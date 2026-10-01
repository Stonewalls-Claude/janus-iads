-- Janus IADS - threat evaluation and weapon-target assignment (DESIGN 4.3).
-- Every `interval` seconds, per network with wta.enabled: rank the network's tracks by threat, estimate each linked
-- battery's kill probability (Pk) against each track, and assign shooters: the best battery first, more (up to the
-- doctrine's maxShooters) until the combined Pk reaches pkGoal. Point defence bids at a discount. An assigned shooter
-- keeps its target until another is better by handoffMargin, or it can no longer engage (handoff). EMCON then cues
-- only assigned batteries on a WTA network; everyone else stays dark. Unlinked / autonomous batteries fight alone.
--
-- Pk model (an estimate for choosing shooters, not a simulation - DCS flies the missiles):
--   envelope   engagement range from the launchers, minimum range and altitude band from the tracking radar's DCS
--              data (probe runs 0-6); outside it Pk = 0
--   range      full inside 70 % of maximum range, falling to 40 % at the edge
--   aspect     a target flying across the site, or away from it beyond half range, is harder
--   speed      very fast targets (> 600 m/s) harder
--   crew tier  GRN 0.8, REG 1.0, VET 1.1, ACE 1.2
--   ammo       a battery with no missiles left does not bid
-- Pk is judged now and `lead` seconds ahead (the radar must be up and locked when the target arrives).

JANUS = JANUS or {}
local M = JANUS

local W = {}
M.wta = W

local string_format = string.format
local math_sqrt, math_min, math_max, math_abs = math.sqrt, math.min, math.max, math.abs
local pairs, ipairs = pairs, ipairs

W.INTERVAL = 2           -- mutate: ok tuning; any interval gives the same assignments
W.AMMO_INTERVAL = 10     -- mutate: ok tuning; tests force the refresh
local BASE_PK = { LR = 0.75, MR = 0.7, SR = 0.6,
                  NONE = 0.5 }   -- mutate: ok only for a shooter the DB gives no range class (none today)
local TIER_PK = { GRN = 0.8, REG = 1.0, VET = 1.1, ACE = 1.2 }
local TRACKER = { TR = true, STR = true, TELAR = true }
TRACKER.SHORAD, TRACKER.CRAM, TRACKER.NAVAL_AD, TRACKER.AAA_FC = true, true, true, true  -- mutate: ok only mod / ship / AAA units carry an envelope for these roles (Phase 4)
local LAUNCHER = { LN = true, TELAR = true, SHORAD = true }
LAUNCHER.CRAM, LAUNCHER.NAVAL_AD = true, true   -- mutate: ok C-RAM and ships join WTA in Phase 3-4
local DEFENDED = { C2 = true, BATTERY = true, PD = true, EW = true }
-- What DCS really does, where it differs from the unit data (bench 04, probe run 4):
-- the Hawk only launches once its TR locks at ~13-15 nm, so its useful reach is ~25 km, not the 45 km in the data;
-- the Patriot engaged two targets 3 s apart although its data lists one channel.
W.DCS_REACH = { ["Hawk ln"] = 25000 }
W.DCS_CHANNELS = { ["Patriot str"] = 2 }

-- Engagement envelope of a battery (cached): R, minimum range, altitude band, target channels.
function W.envelope(n)
  if n.env then return n.env end
  local R = n.engageRange or 0   -- mutate: ok every node has an engageRange
  local rMin, aMin, aMax, ch = 0, 30, 20000, 1
  local found = false
  for _, u in ipairs(n.site.units) do
    local cap = W.DCS_REACH[u.rec.type]
    if cap and cap < R then R = cap end
    if W.DCS_CHANNELS[u.rec.type] then ch = math_max(ch, W.DCS_CHANNELS[u.rec.type]) end
  end
  for _, u in ipairs(n.site.units) do
    local e = u.rec.envelope
    if e and TRACKER[u.rec.role] then
      rMin = math_max(rMin, e.rangeMin or 0)   -- mutate: ok a missing rangeMin falls back to 5 % below
      if not found then aMin, aMax = e.altMin or aMin, e.altMax or aMax end  -- mutate: ok the first tracker's band; batteries have one tracker type
      ch = math_max(ch, e.channels or 1)   -- mutate: ok every tracker envelope in the DB lists channels
      found = true   -- mutate: ok one tracker type per battery today
    end
  end
  if rMin <= 0 then rMin = R * 0.05 end   -- no tracker data: 5 % of range  -- mutate: ok (<= 1 m is the same)
  n.env = { R = R, rMin = rMin, aMin = aMin, aMax = aMax, channels = ch, base = BASE_PK[n.rangeClass] or BASE_PK.NONE }
  return n.env
end

-- Pk of battery n against a target at position p with velocity v (both vec3).
local function pkAt(n, env, p, v)
  local dx, dz = p.x - n.pos.x, p.z - n.pos.z
  local h = p.y - (n.pos.y or 0)   -- mutate: ok DCS points always carry y
  if h < env.aMin * 0.5 or h > env.aMax then return 0 end
  local d2 = dx * dx + dz * dz
  local slant = math_sqrt(d2 + h * h)
  if slant > env.R or slant < env.rMin then return 0 end
  local frac = slant / env.R
  local pk = env.base
  if frac > 0.7 then pk = pk * (1 - (frac - 0.7) / 0.3 * 0.6) end
  if v then
    local speed = math_sqrt(v.x * v.x + v.z * v.z)
    if speed > 1 then          -- mutate: ok guard against a zero velocity; 1 or 2 m/s makes no difference
      local d = math_sqrt(d2)
      if d > 1 then            -- mutate: ok guard against a target exactly overhead
        local radial = (v.x * dx + v.z * dz) / (d * speed)     -- +1 flying straight away, -1 straight at the site
        pk = pk * (1 - 0.3 * (1 - math_abs(radial)))          -- crossing targets are harder
        if radial > 0.3 and frac > 0.5 then pk = pk * 0.6 end -- a receding target far out is a poor shot
      end
      if speed > 600 then pk = pk * 0.7 end
    end
  end
  return pk
end

function W.pk(n, tr, lead)
  if not (n.pos and tr.pos) or (n.engageRange or 0) <= 0 then return 0 end   -- mutate: ok ranges are whole metres
  if n.ammo == 0 then return 0 end
  local env = W.envelope(n)
  local best = pkAt(n, env, tr.pos, tr.vel)
  if lead and lead > 0 and tr.vel then   -- mutate: ok a lead of 0 predicts the same point
    local p = { x = tr.pos.x + tr.vel.x * lead, y = tr.pos.y + tr.vel.y * lead, z = tr.pos.z + tr.vel.z * lead }
    best = math_max(best, pkAt(n, env, p, tr.vel))
  end
  return math_min(0.95, best * (TIER_PK[n.tier] or 1))   -- mutate: ok cap only reachable with custom Pk tables
end

-- Threat of a track to the network: time until it reaches the nearest defended node (closure), low altitude and
-- identified type raise it. Higher = more urgent.
function W.threat(tr, net)
  if not tr.pos then return 0 end
  local bestT
  local v = tr.vel
  for _, n in ipairs(net.nodes) do
    if DEFENDED[n.kind] and n.alive and n.pos then
      local dx, dz = n.pos.x - tr.pos.x, n.pos.z - tr.pos.z
      local d = math_sqrt(dx * dx + dz * dz)
      local closing = 50                                   -- a track that is not closing is still a threat, slowly
      if v and d > 1 then   -- mutate: ok guard against a target on top of the node
        closing = math_max(50, (v.x * dx + v.z * dz) / d)
      end
      local t = d / closing
      if not bestT or t < bestT then bestT = t end
    end
  end
  if not bestT then return 0 end
  local score = 1000 / (bestT + 30)
  if tr.pos.y < 1500 then score = score * 1.2 end          -- low flyers: little warning, strike profile
  if tr.class == "helicopter" then score = score * 0.7 end
  return score
end

local function combined(list)
  local miss = 1
  for i = 1, #list do miss = miss * (1 - list[i].pk) end
  return 1 - miss
end

-- Launcher ammunition (Unit:getAmmo), refreshed slowly. nil = unknown (counted as available).
local function refreshAmmo(n)
  local g = n.site.group
  if not (g and g:isExist()) then return end   -- mutate: ok the loop below checks every unit again
  local total, known = 0, false
  for _, u in ipairs(n.site.units) do
    if LAUNCHER[u.rec.role] and u.unit.getAmmo and u.unit:isExist() then   -- mutate: ok defensive: DCS units always have getAmmo
      local ok, ammo = pcall(u.unit.getAmmo, u.unit)
      if ok then
        known = true
        for _, a in ipairs(ammo or {}) do
          local d = a.desc
          if d and d.category == 1 then total = total + (a.count or 0) end   -- Weapon.Category.MISSILE  -- mutate: ok DCS always gives count
        end
      end
    end
  end
  if known then
    if n.ammo ~= 0 and total == 0 then M.info("wta", string_format("%s %s out of missiles", n.net.key, n.name)) end
    n.ammo = total
  end
end

local function shooterOK(n)
  return (n.kind == "BATTERY" or n.kind == "PD") and n.alive and n.working and n.powered and n.linked
    and not n.autonomous and (n.engageRange or 0) > 0 and n.pos ~= nil   -- mutate: ok W.pk rejects these too
    and not (M.arm and M.arm.isDark(n))           -- dark against an ARM: someone else takes the target
end

function W.assign(net)
  local w = net.doctrine.wta or {}
  local prev = net.assign or {}
  if not w.enabled or not net.tracks then
    net.wtaActive = w.enabled and true or false
    net.assign = {}
    for _, n in ipairs(net.nodes) do n.assigned = nil end
    return
  end
  net.wtaActive = true
  local shooters = {}
  for _, n in ipairs(net.nodes) do
    if shooterOK(n) then shooters[#shooters + 1] = n end
    n.assigned = nil
  end
  local tracks = M.tracks.list(net.tracks)
  for _, tr in ipairs(tracks) do tr.threat = W.threat(tr, net) end
  table.sort(tracks, function(a, b)
    if a.threat ~= b.threat then return a.threat > b.threat end
    return a.num < b.num
  end)
  local load, out = {}, {}
  -- channels a shooter is still using on targets it already had (and that are still tracked) are kept for them, so
  -- a shooter is never pulled off a target it is guiding because another target became more urgent (bench 04:
  -- Patriot / Hawk swapped two Su-24s every 2 s)
  local held = {}
  for id, list in pairs(prev) do
    if net.tracks[id] then
      for _, c in ipairs(list) do held[c.node] = (held[c.node] or 0) + 1 end
    end
  end
  local goal, maxN = w.pkGoal or 0.7, w.maxShooters or 1   -- mutate: ok defaults for custom tables; every profile sets them
  local minPk, margin, disc, lead = w.minPk or 0.15, w.handoffMargin or 0.15, w.pdDiscount or 0.5, w.lead or 0  -- mutate: ok defaults for custom tables
  for _, tr in ipairs(tracks) do
    local bids = {}
    local v = tr.vel
    local reachExtra = v and lead * math_sqrt(v.x * v.x + v.z * v.z) or 0   -- mutate: ok 1 m of slack
    for _, n in ipairs(shooters) do
      local env = W.envelope(n)
      -- cheap reject before the Pk model: farther than range + lead travel (squared, horizontal)
      local dx, dz = tr.pos.x - n.pos.x, tr.pos.z - n.pos.z
      local reach = env.R + reachExtra
      local mine = false
      for _, old in ipairs(prev[tr.id] or {}) do if old.node == n then mine = true end end
      local reserved = (held[n] or 0) - (mine and 1 or 0)   -- mutate: ok a larger discount for its own target changes nothing: it is settled next
      if (load[n] or 0) + reserved < env.channels and dx * dx + dz * dz <= reach * reach then
        local pk = W.pk(n, tr, lead)
        if pk >= minPk then
          bids[#bids + 1] = { node = n, pk = pk, bid = n.kind == "PD" and pk * disc or pk }
        end
      end
    end
    table.sort(bids, function(a, b)
      if a.bid ~= b.bid then return a.bid > b.bid end
      return a.node.name < b.node.name
    end)
    local chosen = {}
    local had = prev[tr.id] or {}
    local bestBid = bids[1] and bids[1].bid or 0   -- mutate: ok with no bids the loop below never runs
    -- hysteresis: shooters already on this target stay while they are within handoffMargin of the best bid
    for _, b in ipairs(bids) do
      if #chosen < maxN then
        for _, old in ipairs(had) do
          if old.node == b.node and b.bid >= bestBid - margin then chosen[#chosen + 1] = b end
        end
      end
    end
    for _, b in ipairs(bids) do
      if #chosen >= maxN or (#chosen > 0 and combined(chosen) >= goal) then break end
      local dup = false
      for _, c in ipairs(chosen) do if c.node == b.node then dup = true end end
      if not dup then chosen[#chosen + 1] = b end
    end
    for _, old in ipairs(had) do held[old.node] = (held[old.node] or 0) - 1 end   -- this target is settled  -- mutate: ok held is always set for a tracked target's shooters
    if #chosen > 0 then
      out[tr.id] = chosen
      for _, c in ipairs(chosen) do
        load[c.node] = (load[c.node] or 0) + 1
        c.node.assigned = c.node.assigned or {}
        c.node.assigned[#c.node.assigned + 1] = tr
      end
    end
    -- log what changed for this target
    local label = M.tracks.label(tr)
    for _, c in ipairs(chosen) do
      local isNew = true
      for _, old in ipairs(had) do if old.node == c.node then isNew = false end end
      if isNew then
        local from
        for _, old in ipairs(had) do
          local still = false
          for _, c2 in ipairs(chosen) do if c2.node == old.node then still = true end end
          if not still then from = old.node end
        end
        if from then
          M.info("wta", string_format("%s %s handed from %s to %s (Pk %.2f)", net.key, label, from.name, c.node.name, c.pk))
        else
          M.info("wta", string_format("%s %s assigned to %s (Pk %.2f)", net.key, label, c.node.name, c.pk))
        end
      end
    end
    if #chosen == 0 and #had > 0 and net.tracks[tr.id] then
      M.info("wta", string_format("%s %s: no shooter can engage (was %s)", net.key, label, had[1].node.name))
    end
  end
  net.assign = out
end

function W.tick()
  local now = M.now()
  W.ammoAt = W.ammoAt or -1e9
  if now - W.ammoAt >= W.AMMO_INTERVAL then
    W.ammoAt = now
    for _, n in ipairs(M.net.list) do
      if (n.kind == "BATTERY" or n.kind == "PD") and n.alive then M.safe("wta.ammo", refreshAmmo, n) end  -- mutate: ok saves work only
    end
  end
  for _, net in pairs(M.net.networks) do W.assign(net) end
end

-- The target a WTA network wants this node to engage (closest assigned), or nil.
function W.targetFor(n)
  local list = n.assigned
  if not (list and n.pos) then return nil end
  local best, bestD
  for _, tr in ipairs(list) do
    if tr.pos then
      local dx, dz = tr.pos.x - n.pos.x, tr.pos.z - n.pos.z
      local d = dx * dx + dz * dz
      if not bestD or d < bestD then best, bestD = tr, d end
    end
  end
  return best, bestD and math_sqrt(bestD)   -- mutate: ok best is nil exactly when bestD is
end

function W.start()
  W.tick()
  M.every("wta.tick", W.INTERVAL, W.tick, 1)   -- mutate: ok first-tick offset
end
