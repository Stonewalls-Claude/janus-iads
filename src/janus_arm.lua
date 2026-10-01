-- Janus IADS - anti-radiation missile (ARM) defence (DESIGN 4.5, 4.5A, 4.5B; Phase 3).
-- Every anti-radiation weapon (Shrike to Kh-31P) is recognised by its passive-radar guidance at launch. Janus knows
-- where the missile really is (ground truth), but no crew does until the awareness model says it noticed:
--   radar    a radar that is emitting holds the missile only well inside its listed range (small, fast target) and
--            only now and then: tier A (Tor, Pantsir) often, tier B (modern SAM radars) sometimes, tier C (SA-2/3/5,
--            old EW radars) rarely; busy crews notice less
--   eyes     optical trackers within ~10 km in daylight (15 km for smoky motors)
--   network  a confirmed ARM is passed to every linked node after the doctrine's netDelay
--   suspicion  an identified SEAD aircraft nose-on inside 60 km can make a crew go dark before any launch
-- A radar sighting is confirmed by `confirmScans` sightings inside `confirmWindow` seconds, two sensors, or eyes.
-- Response ladder per threatened radar (the missile's estimated path points at it), after the crew's reaction time:
--   engage   tier A sites and point defence stay up and fight (DCS's Tor / Pantsir do shoot ARMs, probe run 2)
--   accept   a site tagged [hold] (or doctrine accept) stays up
--   covered  doctrine trustPd and a point-defence site within pdCoverRange: stay up, point defence forced on
--   finish   own missiles in flight and more than finishMargin to impact: stay up to finish the shot
--   dark     radar off for estimated time to impact (error by crew tier) + margin, at least the system's minimum;
--            longer while an identified SEAD aircraft stays nose-on in range (suppression), up to maxDark
--            ("restart" doctrines come back then, "wait" doctrines stay down while the shooter stays)
-- EMCON applies the decision; its restart times (4.5B) still apply when the radar comes back. A dark site is not
-- offered targets by WTA. Point defence near a threatened site is forced up. Scoring: emitting time lost to ARMs
-- (suppression), ARM hits, missiles the network saw die short of a radar.

JANUS = JANUS or {}
local M = JANUS

local A = {}
M.arm = A

local string_format = string.format
local math_sqrt, math_max, math_min, math_deg, math_acos = math.sqrt, math.max, math.min, math.deg, math.acos
local pairs, ipairs = pairs, ipairs

A.INTERVAL = 1
A.rand = math.random
A.SUMMARY_EVERY = 300     -- mutate: ok log cadence
A.LOST = 20               -- mutate: ok a threat nobody has seen for this long is kept only LOST + 300 s
A.CALM = 60               -- mutate: ok tuning; after a maximum-dark restart, suspicion alone cannot send it dark again
A.RECENT = 120           -- mutate: ok tuning; a radar dark for less than this still counts as the emitter a missile was fired at
A.SEE_MAX = 50000        -- no radar holds an ARM farther than this (probe run 3: DCS EW radars "see" HARMs at 100+ km)
A.BEYOND = 10000          -- radars more than this beyond the nearest emitter on a missile's path are not threatened
A.GONE_SEEN = 3           -- mutate: ok tuning; the network learns a missile died if a sensor held it this close to its end

-- Anti-radiation weapons by DCS type name (average speed m/s, maximum range m, smoky motor). Gameplay defaults from
-- open sources, speeds checked in DCS where measured (probe run 8: Kh-31P ~800 m/s, Kh-58U only ~250-300 from a Su-25T at 13,000 ft, LD-10 ~370;
-- benches 01-02: AGM-88 ~550-600). An ARM not listed uses DEFAULT_ARM. The table is tuning data.
-- mutate: ok (the lines below are data; tests cover how speed and smoke are used, not every value)
A.ARMS = {
  AGM_88 = { speed = 600, range = 110000 },                 -- mutate: ok data
  AGM_45 = { speed = 450, range = 40000, smoke = true },    -- mutate: ok data
  AGM_45A = { speed = 450, range = 40000, smoke = true },   -- mutate: ok data
  AGM_78 = { speed = 600, range = 90000, smoke = true },    -- mutate: ok data
  AGM_122 = { speed = 400, range = 16000, smoke = true },   -- mutate: ok data
  ALARM = { speed = 600, range = 90000 },                   -- mutate: ok data
  X_58 = { speed = 300, range = 120000 },                   -- mutate: ok data (DCS Kh-58U from a Su-25T: 240-280 m/s)
  X_31P = { speed = 800, range = 110000 },                  -- mutate: ok data
  X_25MP = { speed = 700, range = 40000, smoke = true },    -- mutate: ok data
  X_28 = { speed = 800, range = 90000, smoke = true },      -- mutate: ok data
  ["LD-10"] = { speed = 400, range = 60000 },               -- mutate: ok data
}
A.DEFAULT_ARM = { speed = 700, range = 80000 }              -- mutate: ok data

-- Aircraft that fly SEAD (suspicion cue): only once the network has identified the type.
A.SEAD_TYPES = {
  ["F-16C_50"] = true, ["FA-18C_hornet"] = true, ["F-4E"] = true, ["F-4E-45MC"] = true, ["Tornado IDS"] = true,  -- mutate: ok data
  ["Tornado GR4"] = true, ["Su-24M"] = true, ["Su-34"] = true, ["Su-25T"] = true, ["JF-17"] = true,           -- mutate: ok data
}

-- Sensor tiers (DESIGN 4.5A). Anything with a radar that is not listed: B for batteries / point defence, C for EW.
A.TIER_A = { ["Tor 9A331"] = true, ["CHAP_PantsirS1"] = true, ["CHAP_TorM2"] = true, ["HQ-17A"] = true }  -- mutate: ok data
A.TIER_C = {
  SNR_75V = true, ["snr s-125 tr"] = true, RPC_5N62V = true, ["p-19 s-125 sr"] = true, ["1L13 EWR"] = true,  -- mutate: ok data
  ["55G6 EWR"] = true, P14_SR = true, RLS_19J6 = true, ["Dog Ear radar"] = true,                          -- mutate: ok data
}
A.MODERN_EW = { ["S-300PS 64H6E sr"] = true, ["S-300PS 40B6MD sr"] = true, ["FPS-117"] = true, ["FPS-117 Dome"] = true }  -- mutate: ok data
-- radar holds an ARM within detectionRange x factor, with chance p per second (x crew, / (1 + tracks held / 10))
A.SEE = { A = { factor = 0.4, p = 0.8 }, B = { factor = 0.35, p = 0.25 }, C = { factor = 0.25, p = 0.03 } }  -- mutate: ok tuning
A.CREW = { GRN = 0.6, REG = 1.0, VET = 1.2, ACE = 1.4 }     -- mutate: ok tuning
A.EYES = { range = 10000, smokeRange = 15000, p = 0.5 }     -- mutate: ok tuning
-- shortest dark time per DCS radar type (4.5B); others use the doctrine's minDark
A.MIN_DARK = { ["S-300PS 40B6M tr"] = 30, ["SA-11 Buk LN 9A310M1"] = 20, RPC_5N62V = 60, SNR_75V = 15,  -- mutate: ok tuning
               ["snr s-125 tr"] = 15 }                        -- mutate: ok tuning

A.flights = {}            -- live enemy ARMs (ground truth)
A.seq = 0
A.stats = { launched = 0, hits = 0, hitsDark = 0, seenDie = 0 }

local function horiz(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return math_sqrt(dx * dx + dz * dz)
end
local function dist3(a, b)
  local dx, dy, dz = a.x - b.x, (a.y or 0) - (b.y or 0), a.z - b.z   -- mutate: ok DCS points always carry y
  return math_sqrt(dx * dx + dy * dy + dz * dz)
end
-- angle (degrees) between the horizontal velocity v and the direction from p to q
local function offAngle(p, v, q)
  local vx, vz = v.x, v.z
  local sp = math_sqrt(vx * vx + vz * vz)
  local dx, dz = q.x - p.x, q.z - p.z
  local d = math_sqrt(dx * dx + dz * dz)
  if sp < 1 or d < 1 then return 0 end   -- mutate: ok degenerate-vector guard
  local c = (vx * dx + vz * dz) / (sp * d)
  if c > 1 then c = 1 elseif c < -1 then c = -1 end   -- mutate: ok rounding guard for acos
  return math_deg(math_acos(c))
end
A._offAngle = offAngle

function A.armData(typeName)
  return A.ARMS[typeName] or A.DEFAULT_ARM
end

function A.sensorTier(n)
  if n.armTier then return n.armTier end
  local tier
  local anyRadar, allC = false, true   -- mutate: ok anyRadar only matters for nodes that have a radar
  for _, u in ipairs(n.site.units) do
    local t = u.rec.type
    if A.TIER_A[t] then tier = "A" end
    if u.rec.radar then
      anyRadar = true
      if not A.TIER_C[t] and not (n.kind == "EW" and not A.MODERN_EW[t]) then allC = false end
    end
  end
  if not tier then tier = (anyRadar and allC or n.airborne) and "C" or "B" end
  n.armTier = tier
  return tier
end

local function hasOptics(n)
  if n.armOptic == nil then
    n.armOptic = false
    for _, u in ipairs(n.site.units) do if u.rec.optic then n.armOptic = true end end
  end
  return n.armOptic
end

local function daylight()
  local t = timer.getAbsTime and timer.getAbsTime() or 43200   -- mutate: ok every DCS build has getAbsTime
  local h = (t % 86400) / 3600   -- mutate: ok any whole number of days gives the same hour
  return h >= 6 and h < 19
end

local function lineOfSight(a, b)
  if not (land and land.isVisible) then return true end   -- mutate: ok every DCS build has land.isVisible
  local ok, vis = pcall(land.isVisible, { x = a.x, y = (a.y or 0) + 10, z = a.z }, b)   -- mutate: ok antenna height
  return not ok or vis
end

local function up(n) return n.alive and n.working and n.powered end

local function state(n)
  local s = n.arm
  if not s then
    s = { darkSec = 0, dark = nil, known = {}, logged = {} }
    n.arm = s
  end
  return s
end

-- ------------------------------------------------------------------ launches (ground truth)
function A.onShot(e)
  local w = e.weapon
  if not (w and e.initiator) then return end   -- mutate: ok defensive: DCS shot events carry both
  local ok, desc = pcall(w.getDesc, w)
  if not (ok and desc and desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE) then return end
  local okC, coa = pcall(e.initiator.getCoalition, e.initiator)
  local okT, typ = pcall(w.getTypeName, w)
  A.seq = A.seq + 1
  local f = { id = "A" .. A.seq, w = w, type = okT and typ or "?", coa = okC and coa or 0, launcher = e.initiator,  -- mutate: ok defensive
              t0 = M.now(), pos = w:getPoint() }
  f.data = A.armData(f.type)
  A.flights[#A.flights + 1] = f
  A.stats.launched = A.stats.launched + 1
  M.debug("arm", string_format("%s launched: %s (crews are not told)", f.id, f.type))   -- mutate: ok debug log
end

-- an ARM hitting a network unit: scored, with the radar's state at the time
function A.onHit(e)
  local w, tgt = e.weapon, e.target
  if not (w and tgt and tgt.getGroup) then return end   -- mutate: ok defensive
  local ok, desc = pcall(w.getDesc, w)
  if not (ok and desc and desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE) then return end
  local okG, g = pcall(tgt.getGroup, tgt)
  local n = okG and g and M.net.nodes[g:getName()]
  if not n then return end
  local on = n.emcon and n.emcon.on
  A.stats.hits = A.stats.hits + 1
  if not on then A.stats.hitsDark = A.stats.hitsDark + 1 end
  local s = state(n)
  s.hits = (s.hits or 0) + 1
  M.info("arm", string_format("%s %s hit by an ARM (%s), radar %s", n.net.key, n.name, tostring(tgt:getName()),
    on and "ON" or "dark"))
end

-- ------------------------------------------------------------------ awareness
local function threatsOf(net)
  net.arms = net.arms or {}
  return net.arms
end

-- a sensor sighting of flight f by node n (eyes = optical)
local function sight(net, f, n, now, eyes)
  local th = threatsOf(net)[f.id]
  if not th then
    th = { f = f, id = f.id, sights = {}, first = now }
    net.arms[f.id] = th
  end
  local s = th.sights[n.name]
  if not s then s = { hits = {} }; th.sights[n.name] = s end
  s.hits[#s.hits + 1] = now
  s.last, s.pos, s.vel, s.linked = now, f.pos, f.vel, n.linked
  if eyes then s.eyes = true end
  th.last, th.pos, th.vel = now, f.pos, f.vel
  if n.linked then th.netLast, th.netPos, th.netVel = now, f.pos, f.vel end
  return th, s
end

local function confirmOwn(s, now, d)
  if s.confirmed then return end
  local window = d.arm.confirmWindow
  local k = 0
  for i = #s.hits, 1, -1 do
    if now - s.hits[i] <= window then k = k + 1 end
  end
  if s.eyes or k >= d.arm.confirmScans then
    s.confirmed = now
    s.how = s.eyes and "eyes" or "radar"
  end
end

-- network confirmation: any linked node confirmed it, or two linked sensors hold it at once
local function confirmNet(net, th, now)
  if th.netConfirmed then return end
  local current, by = 0, nil
  for name, s in pairs(th.sights) do
    if s.linked then
      if s.confirmed then th.netConfirmed, th.netBy, th.netHow = s.confirmed, name, s.how; break end
      if now - s.last <= 1.5 then current = current + 1; by = by or name end   -- 1.5: one scan of slack  -- mutate: ok (1.5 -> 3 only)
    end
  end
  if not th.netConfirmed and current >= 2 then th.netConfirmed, th.netBy, th.netHow = now, by, "2 sensors" end
  if th.netConfirmed then
    M.info("arm", string_format("%s ARM %s confirmed by %s (%s)", net.key, th.id, th.netBy, th.netHow))
  end
end

local function sense(net, f, now)
  local d = net.doctrine
  for _, n in ipairs(net.nodes) do
    if up(n) and n.pos and not n.airborne then
      local dd = dist3(n.pos, f.pos)
      local seen, eyes = false, false
      if n.hasRadar and n.emcon.on then
        local tier = A.sensorTier(n)
        local see = A.SEE[tier]
        if dd <= math_min(n.detectionRange * see.factor, A.SEE_MAX) and lineOfSight(n.pos, f.pos) then
          local load = 0
          for _ in pairs(n.localTracks or {}) do load = load + 1 end
          local p = see.p * (A.CREW[n.tier] or 1) / (1 + load / 10)   -- mutate: ok every tier is in CREW
          seen = A.rand() < p
        end
      end
      local obs = d.arm.observers
      if not seen and (hasOptics(n) or obs) and daylight() then
        local r = f.data.smoke and A.EYES.smokeRange or A.EYES.range
        if obs and not hasOptics(n) then r = f.data.smoke and obs.smokeRange or obs.range end
        if dd <= r and lineOfSight(n.pos, f.pos) then
          eyes = A.rand() < A.EYES.p * (A.CREW[n.tier] or 1)   -- mutate: ok every tier is in CREW
          seen = eyes
        end
      end
      if seen then
        local _, s = sight(net, f, n, now, eyes)
        local before = s.confirmed
        confirmOwn(s, now, d)
        if s.confirmed and not before then
          M.info("arm", string_format("%s %s sees ARM %s at %.0f km (%s)", net.key, n.name, f.id, dd / 1000, s.how))
        end
      end
    end
  end
  local th = net.arms and net.arms[f.id]
  if th then confirmNet(net, th, now) end
end

-- when does node n know of threat th (nil = not yet), and from which picture
local function knowsAt(n, th)
  local s = th.sights[n.name]
  local own = s and s.confirmed
  local viaNet
  if n.linked and th.netConfirmed then
    local d = n.net.doctrine.arm
    viaNet = th.netConfirmed + (th.netBy == n.name and 0 or (d.netDelay[n.tier] or d.netDelay.REG))  -- mutate: ok every tier present
  end
  if own and viaNet then return math_min(own, viaNet) end
  return own or viaNet
end

-- estimated missile position now, from what this node can know
local function estimate(n, th, now)
  local s = th.sights[n.name]
  local t, p, v = nil, nil, nil
  if s and s.confirmed then t, p, v = s.last, s.pos, s.vel end
  -- mutate: ok (next two lines) the newer of the two fixes; on a straight flight both dead-reckon to the same point
  if n.linked and th.netLast and (not t or th.netLast > t) then t, p, v = th.netLast, th.netPos, th.netVel end  -- mutate: ok
  if not (t and p and v) then return nil end   -- mutate: ok defensive
  local dt = now - t
  return { x = p.x + v.x * dt, y = p.y, z = p.z + v.z * dt }, v, t
end

-- the nearest EMITTING radar of n's network in the missile's cone when the threat is first judged: an ARM homes on an
-- emitter, so radars far beyond that one are not its target (bench 05: an SA-6 30 km behind the targeted SA-11 went
-- dark for 4 min). Fixed per threat and network (DCS ARMs do not switch to a new emitter: probe runs 3 and 8), so the
-- sites behind do not all go dark one after the other as the front ones shut down.
local function frontNode(n, th, p, v, now)
  local fr = th.front
  if fr and fr[n.net.key] then return fr[n.net.key] end
  local d = n.net.doctrine.arm
  local best, bestD
  for _, m in ipairs(n.net.nodes) do
    local em = m.emcon
    -- emitting now, or dark for less than A.RECENT s (the missile was launched at what was emitting then)
    if m.hasRadar and m.pos and em and (em.on or now - (em.offSince or -1e9) < A.RECENT) and up(m) then  -- mutate: ok offSince is always set
      local dm = horiz(p, m.pos)
      if (dm <= 2000 or offAngle(p, v, m.pos) <= d.cone) and (not bestD or dm < bestD) then best, bestD = m, dm end  -- mutate: ok 2 km: overhead
    end
  end
  if best then
    th.front = fr or {}
    th.front[n.net.key] = best
  end
  return best
end

-- time to impact of threat th on node n (nil = not aimed at it), from the node's estimate
local function aimedAt(n, th, now)
  local p, v = estimate(n, th, now)
  if not (p and v) then return nil end   -- mutate: ok estimate returns both or neither
  local d = n.net.doctrine.arm
  local dist = horiz(p, n.pos)
  local speed = math_sqrt(v.x * v.x + v.z * v.z)
  if speed < 1 then return nil end   -- mutate: ok degenerate guard
  if dist > 2000 and offAngle(p, v, n.pos) > d.cone then return nil end
  -- beyond the nearest emitter on the path (+ A.BEYOND): not this missile's target
  local front = n.linked and frontNode(n, th, p, v, now)
  if front and front ~= n then
    -- past its target (the front radar is behind it): the missile is ending there, nobody further on is threatened
    if offAngle(p, v, front.pos) > 90 or dist > horiz(p, front.pos) + A.BEYOND then return nil end
  end
  return dist / math_max(speed, th.f.data.speed * 0.5)   -- mutate: ok floor for a slowing missile (tuning)
end

-- ------------------------------------------------------------------ response ladder
local function pdCover(n)
  local d = n.net.doctrine.arm
  local r2 = d.pdCoverRange * d.pdCoverRange
  local out = {}
  for _, m in ipairs(n.net.nodes) do
    if m ~= n and up(m) and m.pos and m.hasRadar and (m.kind == "PD" or A.sensorTier(m) == "A") then
      local dx, dz = m.pos.x - n.pos.x, m.pos.z - n.pos.z
      if dx * dx + dz * dz <= r2 then out[#out + 1] = m end
    end
  end
  return out
end

local function minDark(n)
  for _, u in ipairs(n.site.units) do
    if A.MIN_DARK[u.rec.type] then return A.MIN_DARK[u.rec.type] end
  end
  return n.net.doctrine.arm.minDark
end

-- an identified SEAD aircraft nose-on to n inside shooterRange (what the crew can see on its picture)
local function isSead(tr)
  local v = tr.vel
  return tr.typeKnown and A.SEAD_TYPES[tr.typeName] and v ~= nil and v.x * v.x + v.z * v.z > 2500   -- moving > 50 m/s  -- mutate: ok threshold tuning
end
local function seadNoseOn(n)
  local d = n.net.doctrine.arm
  local best
  local function scan(pic)
    for _, tr in pairs(pic or {}) do
      if isSead(tr) then
        local dist = horiz(tr.pos, n.pos)
        if dist <= d.shooterRange and offAngle(tr.pos, tr.vel, n.pos) <= d.shooterCone then
          if not best or dist < best.dist then best = { tr = tr, dist = dist } end   -- mutate: ok nearest only names the log
        end
      end
    end
  end
  if n.linked then scan(n.net.seads) else scan(n.localTracks) end
  return best
end

local function say(n, key, msg)
  local s = state(n)
  if s.logged[key] then return end
  s.logged[key] = true
  M.info("arm", string_format("%s %s %s", n.net.key, n.name, msg))
end

local function goDark(n, now, untilT, why, th)
  local s = state(n)
  local d = n.net.doctrine.arm
  local dk = s.dark
  if not dk then
    dk = { since = now, untilT = untilT, why = why, th = th }
    s.dark = dk
    s.darkCount = (s.darkCount or 0) + 1
    M.info("arm", string_format("%s %s DARK for %.0f s: %s", n.net.key, n.name, untilT - now, why))
  else
    if untilT > dk.untilT then dk.untilT = untilT end
    if th then dk.th, dk.why = th, why end
  end
  if d.afterMax ~= "wait" and dk.untilT > dk.since + d.maxDark then dk.untilT = dk.since + d.maxDark end
end

local function release(n, why)
  local s = state(n)
  local dk = s.dark
  if not dk then return end
  M.info("arm", string_format("%s %s may emit again: %s (dark %.0f s)", n.net.key, n.name, why, M.now() - dk.since))
  s.dark = nil
  s.logged = {}
end

-- decide for one node against its most urgent known threat
local function respond(n, now)
  local d = n.net.doctrine.arm
  local s = state(n)
  local worst, worstT
  for _, th in pairs(n.net.arms or {}) do
    if not th.over then
      local at = knowsAt(n, th)
      if at and now >= at then
        local tti = aimedAt(n, th, now)
        if tti and (not worstT or tti < worstT) then worst, worstT = th, tti end
      end
    end
  end
  s.threat, s.tti = worst, worstT
  if not worst then s.mode = s.dark and "dark" or nil; s.reactAt = nil; return end   -- mutate: ok mode is informational here
  s.reactAt = s.reactAt or (now + (d.reaction[n.tier] or d.reaction.REG))   -- mutate: ok every tier present
  if now < s.reactAt then return end
  local tier = A.sensorTier(n)
  if (tier == "A" or n.kind == "PD") and d.pdEngage then
    s.mode = "engage"
    say(n, "engage" .. worst.id, string_format("stays up to engage ARM %s (%.0f s out)", worst.id, worstT))
    return
  end
  if n.site.tags.hold or d.accept then
    s.mode = "accept"
    say(n, "accept" .. worst.id, string_format("holds and accepts ARM %s", worst.id))
    return
  end
  local cover = pdCover(n)
  for _, m in ipairs(cover) do state(m).coverUntil = now + 10 end   -- mutate: ok renewed every tick while threatened
  if d.trustPd and #cover > 0 then
    s.mode = "covered"
    say(n, "covered" .. worst.id, string_format("stays up, covered by %s against ARM %s", cover[1].name, worst.id))
    return
  end
  if d.finishShot and M.emcon.missilesInFlight(n, now) and worstT > d.finishMargin then
    s.mode = "finish"
    say(n, "finish" .. worst.id, string_format("stays up to finish its shot (ARM %s %.0f s out)", worst.id, worstT))
    return
  end
  s.mode = "dark"
  local dk = s.dark
  if dk and dk.th == worst then return end   -- already dark for this missile
  local err = (d.predictErr[n.tier] or d.predictErr.REG) * (2 * A.rand() - 1)   -- mutate: ok every tier present
  local darkFor = math_max(worstT * (1 + err) + d.margin, minDark(n))
  goDark(n, now, now + darkFor, string_format("ARM %s inbound, ~%.0f s to impact", worst.id, worstT), worst)
end

-- suspicion cue: an identified SEAD aircraft nose-on can send an emitting radar dark before any launch
local function suspect(n, now)
  local d = n.net.doctrine.arm
  local s = state(n)
  if s.dark or not n.emcon.on or A.sensorTier(n) == "A" or n.kind == "PD" then return end   -- mutate: ok a dark node is off within a tick
  if s.calmUntil and now < s.calmUntil then return end
  if M.emcon.missilesInFlight(n, now) or n.site.tags.hold then return end
  local p = d.suspicion[n.tier] or 0   -- mutate: ok every tier present
  if p <= 0 then return end
  if n.linked and #(n.net.seads or {}) == 0 then return end   -- no identified SEAD aircraft on the picture
  if A.rand() >= p then return end          -- roll before the picture scan (the expensive part)
  local sn = seadNoseOn(n)
  if sn then
    goDark(n, now, now + d.suspectDark, string_format("suspects SEAD %s nose-on at %.0f km", M.tracks.label(sn.tr),
      sn.dist / 1000))   -- mutate: ok log text
  end
end

-- a dark site stays dark while a SEAD aircraft stays nose-on (suppression), within its doctrine's limits
local function hold(n, now)
  local s = state(n)
  local dk = s.dark
  if not dk then return end
  local d = n.net.doctrine.arm
  if now >= dk.untilT - 1 then   -- mutate: ok one tick of slack
    local sn = seadNoseOn(n)
    local capped = d.afterMax ~= "wait" and now >= dk.since + d.maxDark
    if sn and not capped then
      dk.untilT = now + 5   -- mutate: ok extension step (tuning)
      say(n, "suppressed", string_format("stays dark: %s nose-on at %.0f km", M.tracks.label(sn.tr), sn.dist / 1000))  -- mutate: ok log
    elseif capped and now >= dk.untilT then   -- mutate: ok hold only runs from untilT - 1, so both orders release at the cap
      release(n, "maximum dark time reached")
      state(n).calmUntil = now + A.CALM   -- back up for real: no new suspicion for a while (real ARMs still count)
      return
    end
  end
  if now >= dk.untilT then release(n, "threat time passed") end
end

-- another known threat (not `except`, not ended) aimed at n, or nil
function A.otherThreat(n, except, now)
  for _, th in pairs(n.net.arms or {}) do
    if th ~= except and not th.over then
      local at = knowsAt(n, th)
      if at and now >= at and aimedAt(n, th, now) then return th end
    end
  end
  return nil
end

-- ------------------------------------------------------------------ flights: update, end
local function flightEnded(f, now)
  for _, net in pairs(M.net.networks) do
    local th = net.arms and net.arms[f.id]
    if th and not th.over then
      th.over = now
      if th.last and now - th.last <= A.GONE_SEEN then
        -- the network watched it die: short of every radar means shot down (or lost), release sites early
        local nearest
        for _, n in ipairs(net.nodes) do
          if n.pos and n.hasRadar then
            local dd = horiz(n.pos, th.pos)
            if not nearest or dd < nearest then nearest = dd end
          end
        end
        local shotDown = nearest and nearest > 2000   -- mutate: ok a network with an ARM threat has a radar
        if shotDown then A.stats.seenDie = A.stats.seenDie + 1 end
        M.info("arm", string_format("%s ARM %s gone %s", net.key, f.id,
          shotDown and string_format("%.1f km short of any radar (shot down?)", nearest / 1000) or "at a radar"))  -- mutate: ok log
        for _, n in ipairs(net.nodes) do
          local s = n.arm
          if s and s.dark and s.dark.th == th then
            local other = A.otherThreat(n, th, now)
            if other then s.dark.th = other                       -- another missile is still coming: stay dark for it
            else release(n, "ARM " .. f.id .. " gone") end
          end
        end
      end
    end
  end
end

local function updateFlights(now)
  for i = #A.flights, 1, -1 do
    local f = A.flights[i]
    local ok, ex = pcall(f.w.isExist, f.w)
    if ok and ex then
      local p = f.w:getPoint()
      local okV, v = pcall(f.w.getVelocity, f.w)
      if okV and v then f.vel = v   -- mutate: ok defensive
      elseif f.pos then f.vel = { x = p.x - f.pos.x, y = p.y - f.pos.y, z = p.z - f.pos.z } end  -- mutate: ok every DCS weapon has getVelocity
      f.pos = p
    else
      table.remove(A.flights, i)
      flightEnded(f, now)
    end
  end
end

-- threats nobody can still be waiting for are dropped
local function expire(net, now)
  for id, th in pairs(net.arms or {}) do
    local last = th.last or th.first   -- mutate: ok housekeeping
    if th.over and now - th.over > 60 then net.arms[id] = nil   -- mutate: ok an ended threat is skipped anyway
    elseif now - last > A.LOST + 300 then net.arms[id] = nil end   -- mutate: ok a very old unseen threat
  end
end

-- ------------------------------------------------------------------ EMCON / WTA hooks
-- want, reason for EMCON (nil = no ARM decision)
function A.override(n, now)
  local s = n.arm
  if not s then return nil end
  if s.dark and now < s.dark.untilT then return false, "ARM defence: " .. s.dark.why end
  if s.coverUntil and now < s.coverUntil then return true, "ARM cover" end
  if s.mode == "engage" and s.threat then return true, "engaging ARM " .. s.threat.id end
  return nil
end

function A.isDark(n)
  local s = n.arm
  return s ~= nil and s.dark ~= nil and M.now() < s.dark.untilT
end

-- ------------------------------------------------------------------ tick
-- one node's ARM tick: decide, suspect, hold / release, bookkeeping
function A.nodeTick(n, now)
  if n.hasRadar and n.pos and up(n) then
    respond(n, now)
    suspect(n, now)
    hold(n, now)
    local s = n.arm
    if s and s.dark then s.darkSec = s.darkSec + A.INTERVAL end
    if s and s.coverUntil and now >= s.coverUntil then s.coverUntil = nil end
  elseif n.arm and n.arm.dark and not up(n) then
    n.arm.dark = nil                       -- a node that is gone or down keeps no ARM state
  end
end

-- nodes with an ARM state still running (dark, cover, a decision): the only ones worth a look on a quiet network
local function busy(n)   -- mutate: ok (whole function) performance only: a busy node is simply processed
  local s = n.arm
  return s ~= nil and (s.dark ~= nil or s.coverUntil ~= nil or s.mode ~= nil or s.reactAt ~= nil)   -- mutate: ok
end

function A.tick()
  local now = M.now()
  updateFlights(now)
  for _, net in pairs(M.net.networks) do
    local d = net.doctrine.arm
    if d and d.enabled then
      for _, f in ipairs(A.flights) do
        if f.coa ~= net.coalition and f.pos and f.vel then sense(net, f, now) end
      end
      local seads = {}
      for _, tr in pairs(net.tracks or {}) do if isSead(tr) then seads[#seads + 1] = tr end end
      net.seads = seads
      -- quiet network (no ARM known, no SEAD aircraft identified): only nodes still in an ARM state need a look
      local quiet = next(net.arms or {}) == nil and #seads == 0
      for _, n in ipairs(net.nodes) do
        local skip = quiet and not busy(n) and not (n.localTracks and next(n.localTracks) and not n.linked)   -- mutate: ok performance skip
        if not skip then A.nodeTick(n, now) end
      end
      expire(net, now)
    end
  end
end

function A.summary()
  for _, net in pairs(M.net.networks) do
    local sites, sec, count, hits = 0, 0, 0, 0
    for _, n in ipairs(net.nodes) do
      local s = n.arm
      if s and ((s.darkCount or 0) > 0 or (s.hits or 0) > 0) then
        sites = sites + 1
        sec = sec + s.darkSec
        count = count + (s.darkCount or 0)
        hits = hits + (s.hits or 0)
      end
    end
    if sites > 0 then
      M.info("arm", string_format("%s ARM defence: %d site(s) went dark %d time(s), %.0f s of emitting lost, %d ARM hit(s)",
        net.key, sites, count, sec, hits))
    end
  end
end

function A.start()
  M.on(world.event.S_EVENT_SHOT, "arm.shot", A.onShot)
  M.on(world.event.S_EVENT_HIT, "arm.hit", A.onHit)
  M.every("arm.tick", A.INTERVAL, A.tick, 1)   -- mutate: ok first-tick offset
  M.every("arm.summary", A.SUMMARY_EVERY, A.summary, A.SUMMARY_EVERY)
end
