-- Janus IADS - bench 01 (Phase 1 exit gate): a red network run by janus.lua against blue flights.
-- Load order in JANUS_BENCH_01.miz: THIS file (spawns everything, sets JANUS_SETTINGS) -> janus.lua.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [net]" / "JANUS [emcon]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- Layout: red network in the north of the Syria map (anchor Bassel Al-Assad, x north, z east):
--   CMD North (command post) at C; COMMS Relay West 60 km west of C; POWER Grid West next to EW West;
--   EW West (1L13) 45 km west of C, EW East (55G6) 30 km east of C;
--   SAM SA-10 North 25 km west of C (+ PD Tor North beside it), SAM SA-2 Centre at C + 15 km south,
--   SAM SA-6 Coast 110 km west of C (reachable only through the relay).
-- Blue flights come from the sea in the west; no air-to-air weapons anywhere.
-- Events (explosions on the node's units):
--   t=240  POWER Grid West destroyed  -> EW West on 300 s reserve, then out of power
--   t=420  CMD North destroyed        -> every node unlinked; autonomy after the doctrine delay
--   t=900  COMMS Relay West destroyed -> (already unlinked) checks nothing breaks
-- Waves: t=60 and t=600 two unarmed F-16C through the network at 20,000 ft; t=1080 two F-16C with 2x AGM-88C.

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.1.0"

-- Janus settings for this bench (documented settings table, read by janus.lua when it loads)
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
local RED, BLUE = country.id.RUSSIA, country.id.USA
local function ground(name, cx, cz, list)
  local units = {}
  for i = 1, #list do
    local u = list[i]
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent", x = cx + u[2], y = cz + u[3], heading = math_rad(270) }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, RED, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } } })
  log(string_format("SPAWN %s (%d units) %s", name, #units, ok and "ok" or "FAILED"))
end

local Cx, Cz = onLand(x0 + 170000, z0 + 90000)
local Rx, Rz = onLand(Cx, Cz - 60000)
local SITES = {
  { "CMD North",          Cx, Cz,             { { "SKP-11", 0, 0 } } },
  { "COMMS Relay West",   Rx, Rz,             { { "ZIL-131 KUNG", 0, 0 } } },
  { "EW West",            Cx + 10000, Cz - 45000, { { "1L13 EWR", 0, 0 } } },
  { "POWER Grid West",    Cx + 10000, Cz - 44600, { { "generator_5i57", 0, 0 } } },
  { "EW East",            Cx, Cz + 30000,     { { "55G6 EWR", 0, 0 } } },
  { "SAM SA-10 North",    Cx, Cz - 25000,     { { "S-300PS 54K6 cp", 0, 0 }, { "S-300PS 64H6E sr", 300, 200 }, { "S-300PS 40B6M tr", -200, 150 },
                                                { "S-300PS 5P85C ln", 450, 500 }, { "S-300PS 5P85C ln", -450, 500 }, { "S-300PS 5P85D ln", 700, 250 }, { "S-300PS 5P85D ln", -700, 250 } } },
  { "PD Tor North",       Cx + 1500, Cz - 26000, { { "Tor 9A331", 0, 0 } } },
  { "SAM SA-2 Centre",    Cx - 15000, Cz,     { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 }, { "S_75M_Volhov", -400, 400 }, { "S_75M_Volhov", 0, -500 } } },
  { "SAM SA-6 Coast",     Cx - 10000, Cz - 110000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 300, 200 }, { "Kub 2P25 ln", -300, 200 }, { "Kub 2P25 ln", 0, -350 } } },
}
for _, s in ipairs(SITES) do
  local x, z = s[2], s[3]
  if s[1] == "SAM SA-6 Coast" or s[1] == "EW West" or s[1] == "POWER Grid West" then x, z = onLand(x, z) end
  ground(s[1], x, z, s[4])
end

local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local function air(name, count, pylons, route, alt, task, tasks1, roe)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = "F-16C_50", skill = "High",
      x = route[1][1] - (i - 1) * 1500 * math_cos(h), y = route[1][2] - (i - 1) * 1500 * math_sin(h) + (i - 1) * 800,
      alt = alt, alt_type = "BARO", speed = 230, heading = h,
      payload = { pylons = pylons, fuel = 3249, chaff = 60, flare = 60, gun = 100 }, callsign = { 1, 1, i }, onboard_num = tostring(400 + i) }
  end
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, 230, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, BLUE, Group.Category.AIRPLANE,
    { name = name, task = task, units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx F-16C) %s", name, count, ok and "ok" or "FAILED"))
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
-- route: in from the sea west of SA-6 Coast, east past SA-10 and SA-2 to CMD, then back out west
local function transitRoute(dx)
  return { { Cx + dx, Cz - 220000 }, { Cx + dx, Cz - 110000 }, { Cx + dx, Cz - 25000 }, { Cx + dx - 15000, Cz }, { Cx + dx, Cz - 220000 } }
end
at(60, "wave 1: 2x unarmed F-16C transit at 20,000 ft", function()
  air("Blue Transit 1", 2, {}, transitRoute(5000), 20000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end)
at(600, "wave 2: 2x unarmed F-16C transit (network now without command)", function()
  air("Blue Transit 2", 2, {}, transitRoute(-5000), 20000 * FT, "CAP", nil, O.ROE.WEAPON_HOLD)
end)
at(1080, "wave 3: 2x F-16C SEAD, 2x AGM-88C each", function()
  air("Blue SEAD 3", 2, { [3] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }, transitRoute(0), 22000 * FT, "SEAD",
    { { id = "EngageTargets", enabled = true, auto = false, number = 1, params = { targetTypes = { "Air Defence" }, priority = 0 } } },
    O.ROE.WEAPON_FREE)
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
at(240, "kill POWER Grid West", function() destroyGroup("POWER Grid West") end)
at(420, "kill CMD North", function() destroyGroup("CMD North") end)
at(900, "kill COMMS Relay West", function() destroyGroup("COMMS Relay West") end)

-- ------------------------------------------------------------------ recording
local handler = {}
function handler:onEvent(e)
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
end
world.addEventHandler(handler)

-- every 60 s: Janus node states and emitting seconds (read-only use of the shared namespace)
local function summary()
  safeCall("summary", function()
    if not (JANUS.net and JANUS.net.list) then return end
    local parts = {}
    for _, n in ipairs(JANUS.net.list) do
      local st = (not (n.alive and n.working)) and "dead" or (not n.powered and "nopower") or (n.autonomous and "auto")
        or (not n.linked and "unlinked") or "linked"
      parts[#parts + 1] = string_format("%s:%s:%s:%ds", n.name, st, n.emcon.on and "ON" or "off", n.emcon.emitSec or 0)
    end
    log("NODES " .. table.concat(parts, " | "))
  end)
  return timer_getTime() + 60
end
timer_schedule(summary, nil, timer_getTime() + 60)
at(1800, "END: bench 01 complete at 30 min", function() end)

log(string_format("bench %s loaded (red network at %.0f/%.0f from anchor); janus.lua loads next", B.VERSION, Cx - x0, Cz - z0))
