-- Janus IADS - SA-2 probe (JANUS_PROBE_SA2.miz). Why has the SA-2 never launched in benches 01-03?
-- One file, no dependencies, NO janus.lua: plain DCS behaviour first. Records to dcs.log with the tag "JANUS_PROBE".
-- Lua 5.1, sanitized, one global (JANUS).
--
-- Leads (ED forums/changelog): since DCS 2.9.8 SA-2 launchers turn to the intercept azimuth before launch; launchers
-- facing away from the target route reportedly do not engage (2026); the site must be one group with Fan Song and
-- P-19; acquisition is slow. Our benches: 3 launchers facing west, no slope check, Janus emission switching.
-- Seven sites, each with its own pair of unarmed red Su-24M flying straight over it at 20,000 ft from the north:
--   S1 FULL_FACING   flat, Fan Song + P-19 + 6 launchers facing the threat (north)        (baseline)
--   S2 BENCH_WEST    flat, bench layout (Fan Song, P-19, 3 launchers) facing west          (our benches)
--   S3 FULL_AWAY     flat, full site facing directly away from the threat (south)          (heading)
--   S4 BENCH_STEEP   bench layout on the steepest ground found nearby                      (slope)
--   S5 FULL_EMCON    flat, full site facing north, enableEmission(false) at 5 s, (true) at 150 s (Janus cued start)
--   S6 FULL_ALARM    flat, full site facing north, ALARM_STATE RED set by script at 5 s   (Janus sets this)
--   S7 SA3_CONTROL   flat SA-3 (Low Blow + P-19 + 3 launchers) facing north                 (control)
-- Layout: row A (S1-S3) 120 km south of the anchor, row B (S5-S7) 240 km south, 60 km apart; S4 in the Nur
-- mountains. All targets come from the north.

JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.6.0-sa2"

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
local SA2_FULL = { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 250, -150 },
                   { "S_75M_Volhov", 500, 0 }, { "S_75M_Volhov", 250, 430 }, { "S_75M_Volhov", -250, 430 },
                   { "S_75M_Volhov", -500, 0 }, { "S_75M_Volhov", -250, -430 }, { "S_75M_Volhov", 250, -430 } }
local SA2_BENCH = { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 }, { "S_75M_Volhov", -400, 400 },
                    { "S_75M_Volhov", 0, -500 } }
local SA3 = { { "snr s-125 tr", 0, 0 }, { "p-19 s-125 sr", 250, -150 }, { "5p73 s-125 ln", 400, 200 },
              { "5p73 s-125 ln", -400, 200 }, { "5p73 s-125 ln", 0, -400 } }

local SITES = {
  { id = "S1", name = "PROBE S1 FULL_FACING", row = "A", col = 1, units = SA2_FULL,  want = "flat", heading = 0 },
  { id = "S2", name = "PROBE S2 BENCH_WEST",  row = "A", col = 2, units = SA2_BENCH, want = "flat", heading = 270 },
  { id = "S3", name = "PROBE S3 FULL_AWAY",   row = "A", col = 3, units = SA2_FULL,  want = "flat", heading = 180 },
  { id = "S4", name = "PROBE S4 BENCH_STEEP", row = "S", col = 0, units = SA2_BENCH, want = "steep", heading = 270 },
  { id = "S5", name = "PROBE S5 FULL_EMCON",  row = "B", col = 1, units = SA2_FULL,  want = "flat", heading = 0 },
  { id = "S6", name = "PROBE S6 FULL_ALARM",  row = "B", col = 2, units = SA2_FULL,  want = "flat", heading = 0 },
  { id = "S7", name = "PROBE S7 SA3_CONTROL", row = "B", col = 3, units = SA3,       want = "flat", heading = 0 },
}
local ROW_X = { A = x0 - 120000, B = x0 - 240000 }

local function spawnSite(s)
  local wx, wz
  if s.row == "S" then
    wx, wz = x0 + 100000, z0 + 60000          -- Nur (Amanos) mountains: look for a slope
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
    units[i] = { name = s.name .. "-" .. i, type = u[1], skill = "Excellent", x = ux, y = uz, heading = math_rad(s.heading or 0) }
    log(string_format("UNIT %s %s slope %.2f deg height %.0f m", units[i].name, u[1], us, h(ux, uz)))
  end
  local spec = { name = s.name, task = "Ground Nothing", units = units }
  if s.route then
    spec.route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } }
  end
  local ok = safeCall("spawn " .. s.name, coalition.addGroup, BLUE, Group.Category.GROUND, spec)
  log(string_format("SPAWN %s at %.0f/%.0f search-slope %.2f worst-unit-slope %.2f heading %d %s",
    s.name, cx - x0, cz - z0, sl, worst, s.heading or 0, ok and "ok" or "FAILED"))
end
for _, s in ipairs(SITES) do spawnSite(s) end

-- ------------------------------------------------------------------ targets: 2x unarmed Su-24M straight over each site
local function wp(x, z, alt, speed)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = {} } } }
end
local function target(s)
  local dir = -1                                   -- every target comes from the north (the "threat" direction)
  local sx, ex = s.x - dir * 90000, s.x + dir * 70000
  if s.row == "B" then sx = s.x + 60000 end         -- start 60 km from row A, not 30 km
  if s.row == "A" then ex = s.x - 60000 end         -- end 60 km from row B
  local name = "PROBE TGT " .. s.id
  local alt = 20000 * FT
  local units = {}
  for i = 1, 2 do
    units[i] = { name = name .. "-" .. i, type = "Su-24M", skill = "High", x = sx - dir * (i - 1) * 2000, y = s.z + (i - 1) * 1500,
      alt = alt, alt_type = "BARO", speed = 220, heading = (dir > 0) and 0 or math.pi,
      payload = { pylons = {}, fuel = 9000, chaff = 0, flare = 0, gun = 0 }, callsign = { 1, 1, i }, onboard_num = "0" .. i }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, RED, Group.Category.AIRPLANE,
    { name = name, task = "CAP", units = units, route = { points = { wp(sx, s.z, alt, 220), wp(ex, s.z, alt, 220) } } })
  log(string_format("SPAWN %s (2x Su-24M, 20,000 ft) over %s %s", name, s.name, ok and "ok" or "FAILED"))
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

-- ------------------------------------------------------------------ Janus-like handling (S5, S6)
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
at(5, "S5 dark, S6 alarm red", function()
  emission("PROBE S5 FULL_EMCON", false)
  alarmRed("PROBE S6 FULL_ALARM")
end)
at(150, "S5 emission on", function() emission("PROBE S5 FULL_EMCON", true) end)

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
at(1500, "END: SA-2 probe complete at 25 min", function() end)

log(string_format("SA-2 probe %s loaded: 7 sites (6 SA-2, 1 SA-3), 7 unarmed Su-24M pairs", P.VERSION))
