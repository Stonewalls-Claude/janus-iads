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

local POLICIES = { always = true, dark = true, cued = true, periodic = true, rotating = true }
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
  if n.autonomous or ((n.kind == "BATTERY" or n.kind == "PD") and not n.covered) then
    return d.autonomous[n.kind] or "periodic"
  end
  return d.emcon[n.kind] or "always"
end

-- A battery is covered when a linked, working EW radar (not held dark) can see its area.
local function updateCoverage(net)
  local ews = {}
  for _, n in ipairs(net.nodes) do
    if n.kind == "EW" and n.alive and n.working and n.powered and n.linked and n.pos
       and string.lower(n.site.tags.emcon or "") ~= "dark" then
      ews[#ews + 1] = n
    end
  end
  for _, n in ipairs(net.nodes) do
    if n.kind == "BATTERY" or n.kind == "PD" then
      local cov = false
      if n.pos and n.linked then
        for _, ew in ipairs(ews) do
          local dx, dz = ew.pos.x - n.pos.x, ew.pos.z - n.pos.z
          local r = ew.detectionRange > 0 and ew.detectionRange or 100000
          if dx * dx + dz * dz <= r * r then cov = true; break end
        end
      end
      if n.covered ~= nil and n.covered ~= cov then
        M.info("emcon", string_format("%s %s %s EW cover", net.key, n.name, cov and "back under" or "lost"))
      end
      n.covered = cov
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
    local tr, dist = M.tracks.nearest(n, reach)
    if tr then
      em.cuedAt = em.cuedAt or now
      em.lastCue = now
      local delay = d.cueDelay[n.tier] or d.cueDelay.REG
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
      if em.on == nil then
        apply(n, want, reason, now)                               -- first decision: no timing rules
      elseif want and not em.on then
        local ready = em.offSince + restartTime(n)
        if now >= ready then apply(n, true, reason, now) end
      elseif not want and em.on then
        local forced = policy == "offline" or policy == "dark"
        if forced or now >= em.onSince + n.net.doctrine.minOn then apply(n, false, reason, now) end
      end
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
  E.tick()
  M.every("emcon.tick", 1, E.tick, 1)
end
