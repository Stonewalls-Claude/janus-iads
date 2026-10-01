-- Janus IADS - emission control (DESIGN 4.4, 4.5B). Every radar group sits at ALARM_STATE RED and Janus switches
-- its emitters with Group:enableEmission(), which DCS applies instantly (probe run 3). Janus adds its own restart
-- time after a radar goes dark and a minimum on-time, so sites cannot flicker or dodge ARMs for free.

JANUS = JANUS or {}
local M = JANUS

local E = {}
M.emcon = E
E.onChange = {}

local string_format = string.format
local pairs, ipairs = pairs, ipairs

E.SHOT_HOLD_MAX = 120   -- a site never stays up longer than this for one missile (lost weapons, odd targets)

local POLICIES = { always = true, dark = true, cued = true, periodic = true, rotating = true }
E.POLICIES = POLICIES
local MANAGED = { EW = true, BATTERY = true, PD = true, AAA = true, NAVAL = true, C2 = true }

local function restartTime(n)
  local d = n.net.doctrine
  local by = d.restartByType
  for _, u in ipairs(n.site.units) do
    if by[u.rec.type] then return by[u.rec.type] end
  end
  return d.restart[n.rangeClass] or d.restart.NONE or 5
end

-- Which policy applies to this node right now.
function E.policyFor(n)
  if not (n.alive and n.working and n.powered) then return "offline" end
  local tag = n.site.tags.emcon
  if tag and POLICIES[string.lower(tag)] then return string.lower(tag) end
  local d = n.net.doctrine
  if n.kind == "BATTERY" or n.kind == "PD" then
    -- a battery that still gets early warning (through the network, or by c2LossCue after losing command)
    -- keeps its linked EMCON policy; without it the crew falls back to searching on its own radar
    if n.covered then return d.emcon[n.kind] or "cued" end  -- mutate: ok fallback only for a custom table missing a kind
    local p = d.autonomous[n.kind] or "periodic"             -- mutate: ok fallback only for a custom table missing a kind
    if p == "periodic" and d.periodicByType then   -- mutate: ok today every override is "always", which a non-periodic policy never needs
      for _, u in ipairs(n.site.units) do
        local alt = d.periodicByType[u.rec.type]
        if alt then return alt end
      end
    end
    return p
  end
  if n.autonomous then return d.autonomous[n.kind] or "always" end  -- mutate: ok fallback only for a custom table missing a kind
  return d.emcon[n.kind] or "always"
end

-- A battery is covered when a working EW radar (not held dark) can see its area and its plots reach the battery:
-- through the network while both are linked, otherwise the doctrine's c2LossCue decides (DESIGN 8A):
-- "datalink"/"voice" = an EW within c2LossCue.range feeds it (voice with a longer delay), "none" = nobody does.
local function ewRange(ew) return ew.detectionRange > 0 and ew.detectionRange or 100000 end  -- mutate: ok default for an EW type with no DB range (none today)

local function updateCoverage(net)
  local ews = {}
  for _, n in ipairs(net.nodes) do
    if n.kind == "EW" and n.alive and n.working and n.powered and n.pos
       and string.lower(n.site.tags.emcon or "") ~= "dark" then
      ews[#ews + 1] = n
    end
  end
  local fb = net.doctrine.c2LossCue or {}
  local fbMode = fb.mode or "none"
  local fbRange = fb.range or 0   -- mutate: ok every profile sets range; custom tables without one get no feed
  for _, n in ipairs(net.nodes) do
    if n.kind == "BATTERY" or n.kind == "PD" or n.kind == "AAA" then   -- guns get plots too (AAA fire discipline)
      local via, feeders = nil, nil
      if n.pos then
        if n.linked then
          for _, ew in ipairs(ews) do
            if ew.linked then
              local r = ewRange(ew)
              local dx, dz = ew.pos.x - n.pos.x, ew.pos.z - n.pos.z
              if dx * dx + dz * dz <= r * r then via = "net"; break end
            end
          end
        end
        if not via and fbMode ~= "none" then
          for _, ew in ipairs(ews) do
            local r = math.min(ewRange(ew), fbRange)
            local dx, dz = ew.pos.x - n.pos.x, ew.pos.z - n.pos.z
            if dx * dx + dz * dz <= r * r then
              feeders = feeders or {}
              feeders[#feeders + 1] = ew
            end
          end
          if feeders then via = fbMode end
        end
      end
      local cov = via ~= nil
      if n.coverVia ~= via and n.covered ~= nil then
        if not cov then
          M.info("emcon", string_format("%s %s lost EW cover", net.key, n.name))
        elseif via == "net" then
          M.info("emcon", string_format("%s %s back under EW cover", net.key, n.name))
        else
          local first = feeders and feeders[1]
          M.info("emcon", string_format("%s %s under %s cover from %s", net.key, n.name, via, first and first.name or "?"))
        end
      end
      n.covered, n.coverVia, n.feeders = cov, via, feeders
      n.feedDelay = feeders and fb.delay and (fb.delay[n.tier] or fb.delay.REG) or 0
    end
  end
  return ews
end

-- Rotating EW: `share` of the available rotating radars are up at once, the set shifting every `period`.
local function rotatingOn(n, now)
  local rot = n.net.doctrine.rotating
  local members = {}
  for _, m in ipairs(n.net.nodes) do
    if m.kind == n.kind and m.alive and m.working and m.powered and E.policyFor(m) == "rotating" then
      members[#members + 1] = m
    end
  end
  local k = #members
  if k <= 1 then return true end
  local up = math.max(1, math.floor(k * rot.share + 0.5))
  local slot = math.floor(now / rot.period)
  for i, m in ipairs(members) do
    if m == n then return ((i - 1 + slot) % k) < up end
  end
  return true
end

-- What the policy wants; returns wantOn, reason.
function E.want(n, policy, now)
  local em = n.emcon
  local d = n.net.doctrine
  if policy == "offline" or policy == "dark" then return false, policy end
  if policy == "always" then return true, "always" end
  if policy == "rotating" then return rotatingOn(n, now), "rotating" end
  local reach = (n.engageRange > 0 and n.engageRange or n.detectionRange) * d.cueFactor
  if policy == "cued" then
    local tr, dist
    local byWta = n.net.wtaActive and n.linked and not n.autonomous and M.wta ~= nil
    if byWta then
      tr, dist = M.wta.targetFor(n)           -- a WTA network cues only the shooters it assigned (DESIGN 4.3)
    else
      tr, dist = M.tracks.nearest(n, reach)
    end
    if tr then
      em.cuedAt = em.cuedAt or now
      em.lastCue = now
      local delay = (d.cueDelay[n.tier] or d.cueDelay.REG) + (n.feedDelay or 0) + (n.linkDelay or 0)  -- mutate: ok coverage always sets feedDelay; tiers always present
      if byWta then
        if now - em.cuedAt >= delay then return true, string_format("assigned %s, %.0f km", M.tracks.label(tr), dist / 1000) end  -- mutate: ok km in the log text
        return em.on == true, "cue pending"
      end
      if now - em.cuedAt >= delay then return true, string_format("cued, track %.0f km", dist / 1000) end
      return em.on == true, "cue pending"
    end
    em.cuedAt = nil
    if em.on and now - em.lastCue <= d.cueHold then return true, "cue hold" end
    return false, "no cue"
  end
  if policy == "periodic" then
    -- engaging something it can see itself keeps it up
    if em.on and n.localTracks then
      local own = M.tracks.nearest({ pos = n.pos, linked = false, localTracks = n.localTracks, net = n.net },
        n.engageRange > 0 and n.engageRange or n.detectionRange)
      if own then return true, "own track" end
    end
    local p = d.periodic
    local cycle = p.on + p.off
    if not em.phase then                                   -- stable per-site stagger from the name
      local h = 0
      for i = 1, #n.name do h = (h * 31 + string.byte(n.name, i)) % 100003 end
      em.phase = h % cycle
    end
    return ((now + em.phase) % cycle) < p.on, "periodic"
  end
  return true, "unknown policy"
end

-- Own missiles still flying at a live target keep the radar up (bench 01: a periodic site must not drop its
-- guidance mid-flight). Bookkeeping from S_EVENT_SHOT; bounded by SHOT_HOLD_MAX.
local function missilesInFlight(n, now)
  local shots = n.emcon.shots
  if not shots then return false end
  for i = #shots, 1, -1 do   -- mutate: ok a step of -2 from index 1 still visits every entry it must
    local s = shots[i]
    local w = s.weapon
    local flying = now - s.t <= E.SHOT_HOLD_MAX and w ~= nil and w.isExist ~= nil and w:isExist()
    if flying and w.getTarget then   -- mutate: ok asking a gone weapon for its target changes nothing
      local ok, tgt = pcall(w.getTarget, w)
      if ok and tgt ~= nil and tgt.isExist and not tgt:isExist() then flying = false end
    end
    if not flying then table.remove(shots, i) end
  end
  return #shots > 0
end
E.missilesInFlight = missilesInFlight

function E.onShot(e)
  local u = e.initiator
  if not (u and e.weapon and u.getGroup and Object.getCategory(u) == Object.Category.UNIT) then return end
  local ok, g = pcall(u.getGroup, u)
  if not (ok and g) then return end
  local n = M.net.nodes[g:getName()]
  if not (n and n.emcon) then return end
  n.emcon.shots = n.emcon.shots or {}
  n.emcon.shots[#n.emcon.shots + 1] = { weapon = e.weapon, t = M.now() }
end

local function apply(n, on, reason, now)
  local g = n.site.group
  if g and g:isExist() and g.enableEmission then
    M.safe("emcon.enable", g.enableEmission, g, on)
  end
  local em = n.emcon
  local first = em.on == nil
  em.on = on
  if on then em.onSince = now
  elseif not first then em.offSince = now end        -- starting dark is not "going dark": no restart penalty
  if not first or on then
    M.info("emcon", string_format("%s %s %s (%s)", n.net.key, n.name, on and "ON" or "OFF", reason))
  end
  for i = 1, #E.onChange do M.safe("emcon.callback", E.onChange[i], n, on, reason) end
end

function E.tick()
  local now = M.now()
  for _, net in pairs(M.net.networks) do updateCoverage(net) end
  for _, n in ipairs(M.net.list) do
    if MANAGED[n.kind] and n.hasRadar then
      local em = n.emcon
      local policy = E.policyFor(n)
      if policy ~= em.policy then
        if em.policy then M.info("emcon", string_format("%s %s policy %s -> %s", n.net.key, n.name, em.policy, policy)) end
        em.policy = policy
      end
      local want, reason = E.want(n, policy, now)
      local armWant, armReason
      if M.arm and policy ~= "offline" then armWant, armReason = M.arm.override(n, now) end   -- mutate: ok an offline node is never covered or engaging, and dark is dark
      if armWant ~= nil then want, reason = armWant, armReason end
      if em.on == nil then
        apply(n, want, reason, now)                               -- first decision: no timing rules
      elseif want and not em.on then
        local ready = em.offSince + restartTime(n)
        if now >= ready then apply(n, true, reason, now) end
      elseif not want and em.on then
        local forced = policy == "offline" or policy == "dark" or armWant == false
        if not forced and missilesInFlight(n, now) then
          if not em.holding then
            em.holding = true
            M.info("emcon", string_format("%s %s held up: own missiles in flight", n.net.key, n.name))
          end
        elseif forced or now >= em.onSince + n.net.doctrine.minOn then
          apply(n, false, reason, now)
        end
      end
      if em.holding and (not em.on or want) then em.holding = nil end
      if em.on then em.emitSec = em.emitSec + 1 end
    end
  end
end

-- Force a policy on a node at runtime (API). policy nil clears the override.
function E.set(name, policy)
  local n = M.net.nodes[name]
  if not n then return false end
  n.site.tags.emcon = policy
  return true
end

function E.start()
  local O = AI.Option.Ground
  for _, n in ipairs(M.net.list) do
    local g = n.site.group
    if g and g:isExist() and (n.hasRadar or n.kind == "AAA") then
      local c = g:getController()
      if c then
        M.safe("emcon.alarm", c.setOption, c, O.id.ALARM_STATE, O.val.ALARM_STATE.RED)
      end
    end
  end
  M.net.onNewNode = function(n)
    local g = n.site.group
    local c = g and g:getController()
    if c then M.safe("emcon.alarm", c.setOption, c, O.id.ALARM_STATE, O.val.ALARM_STATE.RED) end
    M.net.dirty = true
  end
  M.on(world.event.S_EVENT_SHOT, "emcon.shot", E.onShot)
  E.tick()
  M.every("emcon.tick", 1, E.tick, 1)
end
