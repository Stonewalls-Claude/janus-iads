-- Janus IADS - bench 02 (Phase 2 fixes, DESIGN 8A): EW feed after command loss per doctrine, relay loss, no log
-- noise for power/relay/command nodes, own-missile hold. Red network (SOVIET_PVO_1985) in the north, blue network
-- (US_MODERN) in the south, ~320 km apart. No air-to-air weapons anywhere.
-- Load order in JANUS_BENCH_02.miz: THIS file (spawns everything, sets JANUS_SETTINGS) -> janus.lua.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [net]" / "JANUS [emcon]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- RED (anchor Bassel Al-Assad +170 km N, +90 km E = C; x north, z east):
--   CMD North at C; COMMS Relay West 60 km W; EW West (1L13) 85 km W + POWER Grid West beside it;
--   EW East (55G6) 30 km E; SAM SA-10 North 25 km W + PD Tor North; SAM SA-2 Centre 15 km S;
--   SAM SA-6 Coast 130 km W, tagged [relay:Relay West] so its only path to command is the relay.
--   Expected (SOVIET voice relay, 60 km, REG +60 s):
--   t=300  relay destroyed  -> SA-6 unlinked, "under voice cover from EW West" (if within 60 km), stays cued
--   t=660  CMD destroyed    -> all unlinked; SA-10/Tor/SA-2 under voice cover from EW East; no CMD/COMMS/POWER noise
--   t=900  POWER destroyed  -> EW West on reserve 300 s, then out; SA-6 loses cover -> periodic
--   waves (blue F-16C): t=60, 420, 840 unarmed transits; t=1260 SEAD 2x AGM-88C each
-- BLUE (anchor -150 km N, +60 km E = B):
--   CMD South at B; EW South (FPS-117) 15 km E; SAM Hawk East 60 km E; SAM Hawk West 20 km S / 20 km W.
--   Expected (US_MODERN datalink, 250 km, REG +5 s):
--   t=480  CMD South destroyed -> Hawks unlinked but "under datalink cover from EW South", stay cued
--   waves (red Su-24M, unarmed): t=120 and t=600 transits over both Hawks

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.2.0"

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
local Cx, Cz = onLand(x0 + 170000, z0 + 90000)
local SA6 = "SAM SA-6 Coast [relay:Relay West]"
place(RED_C, "CMD North",        Cx, Cz,                { { "SKP-11", 0, 0 } })
place(RED_C, "COMMS Relay West", Cx, Cz - 60000,        { { "ZIL-131 KUNG", 0, 0 } })
place(RED_C, "EW West",          Cx + 5000, Cz - 85000, { { "1L13 EWR", 0, 0 } })
place(RED_C, "POWER Grid West",  POS["EW West"][1], POS["EW West"][2] + 400, { { "generator_5i57", 0, 0 } })
place(RED_C, "EW East",          Cx, Cz + 30000,        { { "55G6 EWR", 0, 0 } })
place(RED_C, "SAM SA-10 North",  Cx, Cz - 25000,        { { "S-300PS 54K6 cp", 0, 0 }, { "S-300PS 64H6E sr", 300, 200 }, { "S-300PS 40B6M tr", -200, 150 },
                                                          { "S-300PS 5P85C ln", 450, 500 }, { "S-300PS 5P85C ln", -450, 500 }, { "S-300PS 5P85D ln", 700, 250 }, { "S-300PS 5P85D ln", -700, 250 } })
place(RED_C, "PD Tor North",     Cx + 1500, Cz - 26000, { { "Tor 9A331", 0, 0 } })
place(RED_C, "SAM SA-2 Centre",  Cx - 15000, Cz,        { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 }, { "S_75M_Volhov", -400, 400 }, { "S_75M_Volhov", 0, -500 } })
place(RED_C, SA6,                Cx - 10000, Cz - 130000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 300, 200 }, { "Kub 2P25 ln", -300, 200 }, { "Kub 2P25 ln", 0, -350 } })
log(string_format("GEOMETRY red: SA-6-relay %.0f km, SA-6-EW West %.0f km, SA-6-CMD %.0f km, SA-10-EW East %.0f km, SA-10-EW West %.0f km, SA-2-EW East %.0f km (voice range 60 km, link range 120 km)",
  km(SA6, "COMMS Relay West"), km(SA6, "EW West"), km(SA6, "CMD North"), km("SAM SA-10 North", "EW East"), km("SAM SA-10 North", "EW West"), km("SAM SA-2 Centre", "EW East")))

-- blue
local Bx, Bz = onLand(x0 - 150000, z0 + 60000)
local HAWK = { { "Hawk sr", 0, 0 }, { "Hawk tr", 300, 200 }, { "Hawk pcp", -200, 150 }, { "Hawk ln", 450, 500 }, { "Hawk ln", -450, 500 }, { "Hawk ln", 0, -500 } }
place(BLUE_C, "CMD South",      Bx, Bz,                 { { "MLRS FDDM", 0, 0 } })
place(BLUE_C, "EW South",       Bx, Bz + 15000,         { { "FPS-117", 0, 0 } })
place(BLUE_C, "SAM Hawk East",  Bx + 10000, Bz + 60000, HAWK)
place(BLUE_C, "SAM Hawk West",  Bx - 20000, Bz - 20000, HAWK)
log(string_format("GEOMETRY blue: Hawk East-EW %.0f km, Hawk West-EW %.0f km (datalink range 250 km)",
  km("SAM Hawk East", "EW South"), km("SAM Hawk West", "EW South")))

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
local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local sa6 = POS[SA6]
-- blue route: in from the sea west of the SA-6, east past the SA-10 and SA-2, then back out west
local function transitRoute(dx)
  return { { Cx + dx, sa6[2] - 110000 }, { Cx + dx, sa6[2] }, { Cx + dx, Cz - 25000 }, { Cx + dx - 15000, Cz }, { Cx + dx, sa6[2] - 110000 } }
end
local function blueTransit(tag, dx)
  air(BLUE_C, tag, "F-16C_50", 3249, 2, {}, transitRoute(dx), 20000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end
at(60,   "red wave 1: 2x unarmed F-16C transit (all linked)",                 function() blueTransit("Blue Transit 1", 5000) end)
at(420,  "red wave 2: 2x unarmed F-16C transit (SA-6 cut off from command)",  function() blueTransit("Blue Transit 2", -5000) end)
at(840,  "red wave 3: 2x unarmed F-16C transit (no command post)",            function() blueTransit("Blue Transit 3", 0) end)
at(1260, "red wave 4: 2x F-16C SEAD, 2x AGM-88C each", function()
  air(BLUE_C, "Blue SEAD 4", "F-16C_50", 3249, 2, { [3] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }, transitRoute(0), 22000 * FT, "SEAD",
    { { id = "EngageTargets", enabled = true, auto = false, number = 1, params = { targetTypes = { "Air Defence" }, priority = 0 } } },
    O.ROE.WEAPON_FREE)
end)
-- red route over the blue Hawks: from the north-east, south over Hawk East, west over Hawk West, back north
local function redRoute()
  return { { Bx + 150000, Bz + 60000 }, { Bx + 10000, Bz + 60000 }, { Bx - 20000, Bz - 20000 }, { Bx + 150000, Bz - 20000 } }
end
at(120, "blue wave A: 2x unarmed Su-24M transit (all linked)", function()
  air(RED_C, "Red Transit A", "Su-24M", 9000, 2, {}, redRoute(), 15000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end)
at(600, "blue wave B: 2x unarmed Su-24M transit (no command post, datalink)", function()
  air(RED_C, "Red Transit B", "Su-24M", 9000, 2, {}, redRoute(), 15000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end)

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
at(300, "kill COMMS Relay West", function() destroyGroup("COMMS Relay West") end)
at(480, "kill CMD South (blue)", function() destroyGroup("CMD South") end)
at(660, "kill CMD North", function() destroyGroup("CMD North") end)
at(900, "kill POWER Grid West", function() destroyGroup("POWER Grid West") end)

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
at(1800, "END: bench 02 complete at 30 min", function() end)

log(string_format("bench %s loaded (red network at %.0f/%.0f, blue at %.0f/%.0f from anchor); janus.lua loads next",
  B.VERSION, Cx - x0, Cz - z0, Bx - x0, Bz - z0))
