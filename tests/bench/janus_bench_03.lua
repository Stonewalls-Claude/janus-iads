-- Janus IADS - bench 03: Hawks under Janus on flat ground (probe run 4 fixes), SA-2/Tor engagements, the
-- missile-in-flight hold, and the setup-report slope warning. No air-to-air weapons anywhere.
-- Load order in JANUS_BENCH_03.miz: THIS file (spawns everything, sets JANUS_SETTINGS) -> janus.lua.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [net]" / "JANUS [emcon]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- RED (SOVIET_PVO_1985; anchor +170 km N, +90 km E = C): CMD North at C; EW East (55G6) 30 km E;
--   SAM SA-2 Centre 15 km S of C and PD Tor North beside it (blue routes fly straight over them);
--   SAM SA-6 Lone 150 km W, [net:West] with no EW: uncovered -> periodic 15/60; blue flies past it and away,
--   so it shoots at a receding target (the missile-in-flight hold case).
--   t=600 CMD North destroyed -> SA-2/Tor on voice cover from EW East.
--   blue waves (unarmed F-16C): t=60 over SA-2/Tor, t=300 past SA-6 Lone, t=720 over SA-2/Tor (no command post).
-- BLUE (US_MODERN; anchor -150 km N, +60 km E = B), every Hawk placed on the flattest ground found (< 2 deg):
--   CMD South at B; EW South (FPS-117) 15 km E; SAM Hawk East 60 km E (cued by the network);
--   SAM Hawk Lone [net:Lone] 110 km S with no EW: uncovered -> Janus keeps it up ("always", periodicByType).
--   SAM Hawk Slope [net:Slope] in the Nur mountains (steep on purpose): the setup report must flag it.
--   t=480 CMD South destroyed -> Hawk East on datalink cover.
--   red waves (unarmed Su-24M): t=120 over Hawk East, t=180 over Hawk Lone, t=660 over Hawk East (datalink).

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.3.0"

JANUS_SETTINGS = { CHECK_MODE = true, RED_DOCTRINE = "SOVIET_PVO_1985", BLUE_DOCTRINE = "US_MODERN" }

local TAG = "JANUS_BENCH"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_rad, math_cos, math_sin, math_atan2 = math.rad, math.cos, math.sin, math.atan2
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

local function at(t, tag, fn)
  timer_schedule(function() log("STEP " .. tag); safeCall(tag, fn); return nil end, nil, T0 + t)
end

-- ------------------------------------------------------------------ anchor + land check
local AP
for _, ab in ipairs(world.getAirbases() or {}) do
  local n = ab:getName() or ""
  if n:find("Assad") or n:find("Latakia") then AP = ab:getPoint(); break end
end
if not AP then env_error(TAG .. " no anchor airbase (Syria map?)"); return end
local x0, z0 = AP.x, AP.z

local function onLand(x, z)
  for _ = 1, 20 do
    local okS, st = pcall(land.getSurfaceType, { x = x, y = z })
    if okS and st == land.SurfaceType.LAND then return x, z end
    z = z + 5000
  end
  return x, z
end

-- ------------------------------------------------------------------ spawning
local RED_C, BLUE_C = country.id.RUSSIA, country.id.USA
local function ground(side, name, cx, cz, list)
  local units = {}
  for i = 1, #list do
    local u = list[i]
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent", x = cx + u[2], y = cz + u[3], heading = math_rad(270) }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } } })
  log(string_format("SPAWN %s (%d units) at %.0f/%.0f %s", name, #units, cx - x0, cz - z0, ok and "ok" or "FAILED"))
  return cx, cz
end

local POS = {}
local function place(side, name, x, z, list)
  x, z = onLand(x, z)
  POS[name] = { x, z }
  ground(side, name, x, z, list)
end
local function km(a, b)
  local p, q = POS[a], POS[b]
  if not (p and q) then return -1 end
  local dx, dz = p[1] - q[1], p[2] - q[2]
  return math.sqrt(dx * dx + dz * dz) / 1000
end

-- red
-- flattest (or steepest) land spot near (x, z): footprint slope over a ring of r metres (probe run 4)
local function heightAt(x, z) return land.getHeight({ x = x, y = z }) end
local function slope(x, z)
  local d = 30
  local gx = (heightAt(x + d, z) - heightAt(x - d, z)) / (2 * d)
  local gz = (heightAt(x, z + d) - heightAt(x, z - d)) / (2 * d)
  return math.deg(math.atan(math.sqrt(gx * gx + gz * gz)))
end
local function footprint(x, z, r)
  local worst = slope(x, z)
  for i = 0, 7 do
    local a = i * math.pi / 4
    local s = slope(x + r * math.cos(a), z + r * math.sin(a))
    if s > worst then worst = s end
  end
  return worst
end
local function findSpot(x, z, steep)
  local bx, bz, bs
  for ring = 0, 12 do
    local n = ring == 0 and 1 or ring * 6
    for i = 1, n do
      local a = (i / n) * 2 * math.pi
      local cx, cz = x + ring * 1500 * math.cos(a), z + ring * 1500 * math.sin(a)
      local ok, st = pcall(land.getSurfaceType, { x = cx, y = cz })
      if ok and st == land.SurfaceType.LAND then
        local s = steep and slope(cx, cz) or footprint(cx, cz, 550)
        if not bs or (steep and s > bs) or (not steep and s < bs) then bx, bz, bs = cx, cz, s end
        if not steep and bs < 0.8 then return bx, bz, bs end
      end
    end
  end
  return bx or x, bz or z, bs or -1
end
local function placeAt(side, name, x, z, list, steep)
  local cx, cz, s = findSpot(x, z, steep)
  local worst = 0
  for _, u in ipairs(list) do
    local us = slope(cx + u[2], cz + u[3])
    if us > worst then worst = us end
  end
  POS[name] = { cx, cz }
  ground(side, name, cx, cz, list)
  log(string_format("SLOPE %s search %.2f deg, worst unit %.2f deg", name, s, worst))
end

-- red
local Cx, Cz = onLand(x0 + 170000, z0 + 90000)
place(RED_C, "CMD North",         Cx, Cz,                 { { "SKP-11", 0, 0 } })
place(RED_C, "EW East",           Cx, Cz + 30000,         { { "55G6 EWR", 0, 0 } })
place(RED_C, "SAM SA-2 Centre",   Cx - 15000, Cz,         { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 }, { "S_75M_Volhov", -400, 400 }, { "S_75M_Volhov", 0, -500 } })
place(RED_C, "PD Tor Centre",     Cx - 14000, Cz + 2000,  { { "Tor 9A331", 0, 0 } })
place(RED_C, "SAM SA-6 Lone [net:West]", Cx - 5000, Cz - 150000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 300, 200 }, { "Kub 2P25 ln", -300, 200 }, { "Kub 2P25 ln", 0, -350 } })
log(string_format("GEOMETRY red: SA-2-EW East %.0f km, Tor-EW East %.0f km, SA-6 Lone-EW East %.0f km (voice range 60 km)",
  km("SAM SA-2 Centre", "EW East"), km("PD Tor Centre", "EW East"), km("SAM SA-6 Lone [net:West]", "EW East")))

-- blue (Hawks on flat ground)
local Bx, Bz = onLand(x0 - 150000, z0 + 60000)
local HAWK = { { "Hawk pcp", 0, 0 }, { "Hawk sr", 150, 100 }, { "Hawk cwar", -150, 100 }, { "Hawk tr", 0, 200 },
               { "Hawk ln", 350, 350 }, { "Hawk ln", -350, 350 }, { "Hawk ln", 0, -400 } }
place(BLUE_C, "CMD South",        Bx, Bz,                  { { "MLRS FDDM", 0, 0 } })
place(BLUE_C, "EW South",         Bx, Bz + 15000,          { { "FPS-117", 0, 0 } })
placeAt(BLUE_C, "SAM Hawk East",  Bx + 10000, Bz + 60000,  HAWK)
placeAt(BLUE_C, "SAM Hawk Lone [net:Lone]", Bx - 110000, Bz + 20000, HAWK)
placeAt(BLUE_C, "SAM Hawk Slope [net:Slope]", x0 + 100000, z0 + 60000, HAWK, true)
log(string_format("GEOMETRY blue: Hawk East-EW %.0f km, Hawk Lone-EW %.0f km (Lone is its own network: no EW)",
  km("SAM Hawk East", "EW South"), km("SAM Hawk Lone [net:Lone]", "EW South")))

-- ------------------------------------------------------------------ aircraft
local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local function air(side, name, acType, fuel, count, pylons, route, alt, task, tasks1, roe)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = acType, skill = "High",
      x = route[1][1] - (i - 1) * 1500 * math_cos(h), y = route[1][2] - (i - 1) * 1500 * math_sin(h) + (i - 1) * 800,
      alt = alt, alt_type = "BARO", speed = 230, heading = h,
      payload = { pylons = pylons, fuel = fuel, chaff = 60, flare = 60, gun = 100 }, callsign = { 1, 1, i }, onboard_num = tostring(400 + i) }
  end
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, 230, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.AIRPLANE,
    { name = name, task = task, units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s) %s", name, count, acType, ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      local O = AI.Option.Air
      c:setOption(O.id.ROE, roe)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
    end)
    return nil
  end, nil, timer_getTime() + 2)
end

local O = AI.Option.Air.val

local sa2, sa6 = POS["SAM SA-2 Centre"], POS["SAM SA-6 Lone [net:West]"]
-- blue F-16C: from the west straight over the SA-2 and Tor, then out east and back north
local function sa2Route(dx)
  return { { sa2[1] + dx, sa2[2] - 100000 }, { sa2[1] + dx, sa2[2] }, { sa2[1] + dx, sa2[2] + 60000 }, { sa2[1] + 80000, sa2[2] + 60000 } }
end
-- past the lone SA-6 at 8 km, then straight away west at speed (a receding shot)
local function sa6Route()
  return { { sa6[1] + 8000, sa6[2] + 90000 }, { sa6[1] + 8000, sa6[2] }, { sa6[1] + 8000, sa6[2] - 120000 } }
end
local function blueTransit(tag, route, alt)
  air(BLUE_C, tag, "F-16C_50", 3249, 2, {}, route, alt * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end
at(60,  "red wave 1: 2x F-16C over SA-2/Tor at 18,000 ft (all linked)", function() blueTransit("Blue Transit 1", sa2Route(0), 18000) end)
at(300, "red wave 2: 2x F-16C past the lone SA-6 and away", function() blueTransit("Blue Transit 2", sa6Route(), 12000) end)
at(720, "red wave 3: 2x F-16C over SA-2/Tor at 12,000 ft (no command post)", function() blueTransit("Blue Transit 3", sa2Route(3000), 12000) end)
-- red Su-24M: straight over a Hawk from the north
local function over(name, len)
  local p = POS[name]
  return { { p[1] + len, p[2] + 1000 }, { p[1], p[2] + 1000 }, { p[1] - len, p[2] + 1000 } }
end
local function redTransit(tag, route)
  air(RED_C, tag, "Su-24M", 9000, 2, {}, route, 15000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end
at(120, "blue wave A: 2x Su-24M over Hawk East (linked)", function() redTransit("Red Transit A", over("SAM Hawk East", 90000)) end)
at(180, "blue wave L: 2x Su-24M over Hawk Lone (no EW: Janus keeps it up)", function() redTransit("Red Transit L", over("SAM Hawk Lone [net:Lone]", 90000)) end)
at(660, "blue wave B: 2x Su-24M over Hawk East (datalink after CMD South loss)", function() redTransit("Red Transit B", over("SAM Hawk East", 90000)) end)

-- ------------------------------------------------------------------ node kills
local function destroyGroup(name)
  local g = Group.getByName(name)
  if not (g and g:isExist()) then log("destroy: " .. name .. " not found"); return end
  for _, u in ipairs(g:getUnits() or {}) do
    local p = u:getPoint()
    trigger.action.explosion(p, 2000)
  end
  log("DESTROY " .. name)
end
at(480, "kill CMD South (blue)", function() destroyGroup("CMD South") end)
at(600, "kill CMD North", function() destroyGroup("CMD North") end)

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
      log(string_format("SHOT shooter=%s (%s) weapon=%s target=%s", safeName(e.initiator), safeType(e.initiator), safeType(w), safeName(tgt)))
    elseif e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
      log(string_format("HIT shooter=%s weapon=%s target=%s", safeType(e.initiator), safeType(e.weapon), safeName(e.target)))
    elseif e.id == world.event.S_EVENT_DEAD and safeCat(e.initiator) == Object.Category.UNIT then
      log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
    end
  end)
end)
world.addEventHandler(handler)

-- every 60 s: Janus node states and emitting seconds (read-only use of the shared namespace)
local function summary(_, t)
  safeCall("summary", function()
    if not (JANUS.net and JANUS.net.list) then return end
    local parts = {}
    for _, n in ipairs(JANUS.net.list) do
      local st = (not (n.alive and n.working)) and "dead" or (not n.powered and "nopower") or (n.autonomous and "auto")
        or (not n.linked and "unlinked") or "linked"
      local cov = n.coverVia and ("/" .. n.coverVia) or ""
      parts[#parts + 1] = string_format("%s:%s%s:%s:%ds", n.name, st, cov, n.emcon.on and "ON" or "off", n.emcon.emitSec or 0)
    end
    log("NODES " .. table.concat(parts, " | "))
  end)
  return t + 60
end
timer_schedule(summary, nil, timer_getTime() + 60)
at(1800, "END: bench 03 complete at 30 min", function() end)

log(string_format("bench %s loaded (red network at %.0f/%.0f, blue at %.0f/%.0f from anchor); janus.lua loads next",
  B.VERSION, Cx - x0, Cz - z0, Bx - x0, Bz - z0))
