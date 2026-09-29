-- Janus IADS - Hawk probe (JANUS_PROBE_HAWK.miz). Why did the bench 02 Hawks never fire, and what makes them fire?
-- One file, no dependencies, NO janus.lua: plain DCS behaviour first. Records to dcs.log with the tag "JANUS_PROBE".
-- Lua 5.1, sanitized, one global (JANUS).
--
-- Known DCS Hawk issues (ED forums, 2025-26): launchers do not fire on terrain steeper than ~2 deg (ED: "place the
-- SAM on flat terrain"); a static SAM group given a move order never engages; engagement ~10 nm instead of ~20 nm
-- since 2.9.12; the ED repro battery includes the CWAR. Janus also switches emissions, which the bench Hawks saw.
-- Seven blue sites, each with its own pair of unarmed red Su-24M flying straight over it at 15,000 ft:
--   H1 FLAT_FULL     flat (<1 deg), PCP + SR + CWAR + TR + 3 LN, no route           (baseline)
--   H2 FLAT_NOCWAR   flat, bench 02 set (SR + TR + PCP + 3 LN), no route           (is the CWAR needed?)
--   H3 STEEP_FULL    full set on the steepest ground found nearby (>2 deg wanted)  (slope bug)
--   H4 FLAT_ROUTE    full set + the bench's one-point "Off Road" route              (move-order bug)
--   H5 FLAT_EMCON    full set, enableEmission(false) at 5 s, (true) at 150 s        (Janus cued start)
--   H6 FLAT_CYCLE    full set, ALARM RED + emission cycling 15 on / 60 off to 900 s, then on (Janus periodic)
--   H7 PATRIOT       Patriot battery, flat, near Lake Assad (its 100 km reach clears every Hawk pass)  (control)
-- Layout: row A (H1, H2, H4) 120 km south of the anchor, row B (H5, H6) 240 km south, sites 60 km apart; H3 in the
-- Nur mountains 100 km north. Row A targets come from the north, row B/Patriot targets from the south, so every
-- pass stays > 50 km from the other sites.
-- Logs every SHOT/HIT/DEAD with the shooter's group, and every 30 s per site: detected targets and getRadar().

JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.5.0-hawk"

local TAG = "JANUS_PROBE"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_rad, math_deg, math_atan, math_sqrt = math.rad, math.deg, math.atan, math.sqrt
local FT = 0.3048
local T0 = timer_getTime()

local function now() return timer_getTime() - T0 end
local function log(msg) env_info(string_format("%s %.2f %s", TAG, now(), msg)) end

local function safeCall(tag, fn, ...)
  local args = { ... }
  local n = select("#", ...)
  local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
  if not ok then env_error(string_format("%s %s error: %s", TAG, tag, tostring(err))) end
  return ok, err
end
local function safeName(o)
  if o == nil then return "nil" end
  local ok, n = pcall(function() return o:getName() end)
  return ok and tostring(n) or "?"
end
local function safeType(o)
  if o == nil then return "nil" end
  local ok, n = pcall(function() return o:getTypeName() end)
  return ok and tostring(n) or "?"
end
local function safeCat(o)
  if o == nil then return -1 end
  local ok, c = pcall(function() return Object.getCategory(o) end)
  return ok and c or -1
end
local function groupOf(o)
  if o == nil then return "nil" end
  local ok, g = pcall(function() return o:getGroup() end)
  return (ok and g) and safeName(g) or "?"
end
local function at(t, tag, fn)
  timer_schedule(function() log("STEP " .. tag); safeCall(tag, fn); return nil end, nil, T0 + t)
end

-- ------------------------------------------------------------------ anchor, terrain
local AP
for _, ab in ipairs(world.getAirbases() or {}) do
  local n = ab:getName() or ""
  if n:find("Assad") or n:find("Latakia") then AP = ab:getPoint(); break end
end
if not AP then env_error(TAG .. " no anchor airbase (Syria map?)"); return end
local x0, z0 = AP.x, AP.z

local function isLand(x, z)
  local ok, st = pcall(land.getSurfaceType, { x = x, y = z })
  return ok and st == land.SurfaceType.LAND
end
local function h(x, z) return land.getHeight({ x = x, y = z }) end
-- terrain slope in degrees at a point (central differences over 30 m)
local function slope(x, z)
  local d = 30
  local gx = (h(x + d, z) - h(x - d, z)) / (2 * d)
  local gz = (h(x, z + d) - h(x, z - d)) / (2 * d)
  return math_deg(math_atan(math_sqrt(gx * gx + gz * gz)))
end
-- worst slope over a battery footprint (centre + ring of 8 points at r)
local function footprintSlope(x, z, r)
  local worst = slope(x, z)
  for i = 0, 7 do
    local a = i * math.pi / 4
    local s = slope(x + r * math.cos(a), z + r * math.sin(a))
    if s > worst then worst = s end
  end
  return worst
end
-- search rings around (x, z) for a land spot whose footprint slope is best by `better`
local function findSpot(x, z, want)
  local bestX, bestZ, bestS
  for ring = 0, 12 do
    local rr = ring * 1500
    local n = ring == 0 and 1 or ring * 6
    for i = 1, n do
      local a = (i / n) * 2 * math.pi
      local cx, cz = x + rr * math.cos(a), z + rr * math.sin(a)
      if isLand(cx, cz) then
        local s = want == "steep" and slope(cx, cz) or footprintSlope(cx, cz, 450)
        if not bestS or (want == "steep" and s > bestS) or (want ~= "steep" and s < bestS) then
          bestX, bestZ, bestS = cx, cz, s
        end
        if want ~= "steep" and bestS < 0.8 then return bestX, bestZ, bestS end
      end
    end
  end
  return bestX or x, bestZ or z, bestS or -1
end

-- ------------------------------------------------------------------ sites
local BLUE, RED = country.id.USA, country.id.RUSSIA
local HAWK_FULL = { { "Hawk pcp", 0, 0 }, { "Hawk sr", 150, 100 }, { "Hawk cwar", -150, 100 }, { "Hawk tr", 0, 200 },
                    { "Hawk ln", 350, 350 }, { "Hawk ln", -350, 350 }, { "Hawk ln", 0, -400 } }
local HAWK_BENCH = { { "Hawk sr", 0, 0 }, { "Hawk tr", 300, 200 }, { "Hawk pcp", -200, 150 },
                     { "Hawk ln", 450, 500 }, { "Hawk ln", -450, 500 }, { "Hawk ln", 0, -500 } }
local PATRIOT = { { "Patriot str", 0, 0 }, { "Patriot ECS", 150, 100 }, { "Patriot EPP", -150, 100 }, { "Patriot AMG", 0, 200 },
                  { "Patriot cp", 200, -150 }, { "Patriot ln", 350, 350 }, { "Patriot ln", -350, 350 } }

local SITES = {
  { id = "H1", name = "PROBE H1 FLAT_FULL",   row = "A", col = 1, units = HAWK_FULL,  want = "flat" },
  { id = "H2", name = "PROBE H2 FLAT_NOCWAR", row = "A", col = 2, units = HAWK_BENCH, want = "flat" },
  { id = "H3", name = "PROBE H3 STEEP_FULL",  row = "S", col = 0, units = HAWK_FULL,  want = "steep" },
  { id = "H4", name = "PROBE H4 FLAT_ROUTE",  row = "A", col = 3, units = HAWK_FULL,  want = "flat", route = true },
  { id = "H5", name = "PROBE H5 FLAT_EMCON",  row = "B", col = 1, units = HAWK_FULL,  want = "flat" },
  { id = "H6", name = "PROBE H6 FLAT_CYCLE",  row = "B", col = 2, units = HAWK_FULL,  want = "flat" },
  { id = "H7", name = "PROBE H7 PATRIOT",     row = "P", col = 2, units = PATRIOT,    want = "flat" },
}
local ROW_X = { A = x0 - 120000, B = x0 - 240000 }

local function spawnSite(s)
  local wx, wz
  if s.row == "S" then
    wx, wz = x0 + 100000, z0 + 60000          -- Nur (Amanos) mountains: look for a slope
  elseif s.row == "P" then
    wx, wz = x0 + 60000, z0 + 220000          -- Patriot control near Lake Assad, > 150 km from every Hawk pass
  else
    wx, wz = ROW_X[s.row], z0 + 60000 * s.col
  end
  local cx, cz, sl = findSpot(wx, wz, s.want)
  s.x, s.z = cx, cz
  local units, worst = {}, 0
  for i, u in ipairs(s.units) do
    local ux, uz = cx + u[2], cz + u[3]
    local us = slope(ux, uz)
    if us > worst then worst = us end
    units[i] = { name = s.name .. "-" .. i, type = u[1], skill = "Excellent", x = ux, y = uz, heading = math_rad(0) }
    log(string_format("UNIT %s %s slope %.2f deg height %.0f m", units[i].name, u[1], us, h(ux, uz)))
  end
  local spec = { name = s.name, task = "Ground Nothing", units = units }
  if s.route then
    spec.route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } }
  end
  local ok = safeCall("spawn " .. s.name, coalition.addGroup, BLUE, Group.Category.GROUND, spec)
  log(string_format("SPAWN %s at %.0f/%.0f search-slope %.2f worst-unit-slope %.2f route=%s %s",
    s.name, cx - x0, cz - z0, sl, worst, s.route and "yes" or "no", ok and "ok" or "FAILED"))
end
for _, s in ipairs(SITES) do spawnSite(s) end

-- ------------------------------------------------------------------ targets: 2x unarmed Su-24M straight over each site
local function wp(x, z, alt, speed)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = {} } } }
end
local function target(s)
  local dir = (s.row == "B" or s.row == "P") and 1 or -1  -- rows B/P from the south, row A and steep from the north
  local sx, ex = s.x - dir * 90000, s.x + dir * 70000
  local name = "PROBE TGT " .. s.id
  local alt = 15000 * FT
  local units = {}
  for i = 1, 2 do
    units[i] = { name = name .. "-" .. i, type = "Su-24M", skill = "High", x = sx - dir * (i - 1) * 2000, y = s.z + (i - 1) * 1500,
      alt = alt, alt_type = "BARO", speed = 220, heading = (dir > 0) and 0 or math.pi,
      payload = { pylons = {}, fuel = 9000, chaff = 0, flare = 0, gun = 0 }, callsign = { 1, 1, i }, onboard_num = "0" .. i }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, RED, Group.Category.AIRPLANE,
    { name = name, task = "CAP", units = units, route = { points = { wp(sx, s.z, alt, 220), wp(ex, s.z, alt, 220) } } })
  log(string_format("SPAWN %s (2x Su-24M, 15,000 ft) over %s %s", name, s.name, ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      local O = AI.Option.Air
      c:setOption(O.id.ROE, O.val.ROE.WEAPON_HOLD)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.NO_REACTION)
    end)
    return nil
  end, nil, timer_getTime() + 2)
end
for i, s in ipairs(SITES) do
  at(30 + (i - 1) * 45, "targets for " .. s.id, function() target(s) end)
end

-- ------------------------------------------------------------------ Janus-like emission handling (H5, H6)
local function emission(name, on)
  local g = Group.getByName(name)
  if g and g:isExist() then g:enableEmission(on); log(string_format("EMISSION %s %s", name, on and "ON" or "OFF")) end
end
local function alarmRed(name)
  local g = Group.getByName(name)
  if not (g and g:isExist()) then return end
  local O = AI.Option.Ground
  g:getController():setOption(O.id.ALARM_STATE, O.val.ALARM_STATE.RED)
  log("ALARM RED " .. name)
end
at(5, "H5 dark, H6 alarm red + dark", function()
  emission("PROBE H5 FLAT_EMCON", false)
  alarmRed("PROBE H6 FLAT_CYCLE")
  emission("PROBE H6 FLAT_CYCLE", false)
end)
at(150, "H5 emission on", function() emission("PROBE H5 FLAT_EMCON", true) end)
-- H6: 15 s on / 60 s off like SOVIET_PVO periodic while its targets pass (~580-700 s), then stays on at 900 s
for t = 60, 840, 75 do
  at(t, "H6 on", function() emission("PROBE H6 FLAT_CYCLE", true) end)
  at(t + 15, "H6 off", function() emission("PROBE H6 FLAT_CYCLE", false) end)
end
at(900, "H6 on for good", function() emission("PROBE H6 FLAT_CYCLE", true) end)

-- ------------------------------------------------------------------ recording
-- every DCS event handler is wrapped (house rule); safeCall inside keeps the per-event tag
local function wrapHandler(fn)
  return function(...)
    local args, n = { ... }, select("#", ...)
    safeCall("handler", function() return fn(unpack(args, 1, n)) end)
  end
end
local handler = {}
handler.onEvent = wrapHandler(function(_, e)
  safeCall("event", function()
    if e.id == world.event.S_EVENT_SHOT then
      local w = e.weapon
      local tgt = w and w.getTarget and w:getTarget() or nil
      log(string_format("SHOT group=%s shooter=%s (%s) weapon=%s target=%s", groupOf(e.initiator), safeName(e.initiator),
        safeType(e.initiator), safeType(w), safeName(tgt)))
    elseif e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
      log(string_format("HIT shooter=%s weapon=%s target=%s", safeType(e.initiator), safeType(e.weapon), safeName(e.target)))
    elseif e.id == world.event.S_EVENT_DEAD and safeCat(e.initiator) == Object.Category.UNIT then
      log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
    end
  end)
end)
world.addEventHandler(handler)

-- every 30 s: per site, targets detected by the group and which radars report a track, and the nearest target
local function nearestTarget(s)
  local best
  for _, sx in ipairs(SITES) do
    local g = Group.getByName("PROBE TGT " .. sx.id)
    if g and g:isExist() then
      for _, u in ipairs(g:getUnits() or {}) do
        local p = u:getPoint()
        local dx, dz = p.x - s.x, p.z - s.z
        local d = math_sqrt(dx * dx + dz * dz) / 1852
        if not best or d < best then best = d end
      end
    end
  end
  return best
end
local function status()
  safeCall("status", function()
    for _, s in ipairs(SITES) do
      local g = Group.getByName(s.name)
      if g and g:isExist() then
        local dets = g:getController():getDetectedTargets() or {}
        local radars = {}
        for _, u in ipairs(g:getUnits() or {}) do
          local ok, on, tracked = pcall(u.getRadar, u)
          if ok and on then radars[#radars + 1] = safeType(u) .. (tracked and "*" or "") end
        end
        local nt = nearestTarget(s)
        log(string_format("STATUS %s detected=%d radars=[%s] nearestTgt=%s nm", s.id, #dets, table.concat(radars, ","),
          nt and string_format("%.1f", nt) or "-"))
      else
        log("STATUS " .. s.id .. " gone")
      end
    end
  end)
  return timer_getTime() + 30
end
timer_schedule(status, nil, timer_getTime() + 30)
at(1500, "END: Hawk probe complete at 25 min", function() end)

log(string_format("hawk probe %s loaded: 7 sites (6 Hawk, 1 Patriot), 7 unarmed Su-24M pairs", P.VERSION))
