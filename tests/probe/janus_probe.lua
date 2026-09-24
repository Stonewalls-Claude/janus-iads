-- Janus IADS - Phase 0 probe: what does DCS's own AI actually engage, and how fast?
-- One file, no dependencies. Load with DO SCRIPT FILE at MISSION START in an EMPTY Syria mission
-- (tests/probe/janus_probe.miz). It spawns the whole layout itself, releases one attacker wave every
-- 4 minutes, and writes a timeline to dcs.log tagged "JANUS_PROBE" (tools/probe_report.py summarises it).
-- Nothing here fires or controls a defender: DCS AI does what it does; the probe only records.
-- Lua 5.1, sanitized environment, one global (JANUS).
--
-- Layout (Syria, anchored on Bassel Al-Assad / Latakia; x north, z east, metres):
--   BLUE site B1 (inland east): 2x C-RAM, 2x Avenger, a Hawk search+track radar as ARM bait (no launchers),
--                              4 trucks as the bomb/rocket/artillery target
--   BLUE site B2 (30 km south of B1): full Patriot battery (its radar is the ARM bait for wave 2)
--   RED  site R1 (north-east):   2x Tor, 2x Pantsir, a 1L13 EWR as ARM bait, 4 trucks
--   Waves (all AI):  1  240 s  blue F-16C 4x AGM-88C vs R1        | red Su-24M 2x Kh-58U vs B1
--                    2  480 s  red Su-34 2x Kh-31P vs B2 (Patriot)  | red Tu-22M3 3x Kh-22 vs B1
--                    3  720 s  red Su-34 4x KAB-500Kr vs B1 trucks
--                    4  960 s  red Mi-24P S-8 rockets vs B1 trucks
--                    5 1200 s  red BM-21 Grad battery fires at B1 trucks from 15 km (does C-RAM count rockets?)
--                    6 1440 s  red Su-25T 4x FAB-250 dumb bombs vs B1 trucks
--   Summary lines every 60 s; run for 30 minutes of mission time.

JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.2.0"

local TAG = "JANUS_PROBE"
local env_info = env.info
local env_error = env.error
local timer_getTime = timer.getTime
local timer_schedule = timer.scheduleFunction
local string_format = string.format
local math_rad, math_cos, math_sin, math_atan2 = math.rad, math.cos, math.sin, math.atan2
local FT = 0.3048

local function log(msg) env_info(string_format("%s %.2f %s", TAG, timer_getTime(), msg)) end

local function safeCall(tag, fn, ...)
  local args = { ... }
  local n = select("#", ...)
  local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
  if not ok then env_error(string_format("%s %s error: %s", TAG, tag, tostring(err))) end
  return ok, err
end

local function safeName(obj)
  if obj == nil then return "nil" end
  local ok, n = pcall(function() return obj:getName() end)
  return ok and tostring(n) or "?"
end
local function safeType(obj)
  if obj == nil then return "nil" end
  local ok, n = pcall(function() return obj:getTypeName() end)
  return ok and tostring(n) or "?"
end
local function safeCat(obj)
  if obj == nil then return "nil" end
  local ok, c = pcall(function() return Object.getCategory(obj) end)
  return ok and tostring(c) or "?"
end

-- ------------------------------------------------------------------ recording
P.stats = {}   -- shooterType -> counters
local function bump(k, field)
  local r = P.stats[k]
  if not r then r = { shots = 0, hitsOnWeapons = 0, hitsOnUnits = 0 }; P.stats[k] = r end
  r[field] = r[field] + 1
end

local handler = {}
function handler:onEvent(e)
  safeCall("event", function()
    if e.id == world.event.S_EVENT_SHOT then
      local w = e.weapon
      local target = w and w.getTarget and w:getTarget() or nil
      bump(safeType(e.initiator), "shots")
      log(string_format("SHOT shooter=%s (%s) weapon=%s target=%s targetType=%s targetCat=%s",
        safeName(e.initiator), safeType(e.initiator), safeType(w), safeName(target), safeType(target), safeCat(target)))
    elseif e.id == world.event.S_EVENT_HIT then
      local tgt = e.target
      local shooter = safeType(e.initiator)
      if safeCat(tgt) == tostring(Object.Category.WEAPON) then
        bump(shooter, "hitsOnWeapons")
        log(string_format("HIT-WEAPON shooter=%s weapon=%s hitTarget=%s (a weapon: %s)",
          shooter, safeType(e.weapon), safeName(tgt), safeType(tgt)))
      else
        bump(shooter, "hitsOnUnits")
        log(string_format("HIT shooter=%s weapon=%s target=%s (%s)", shooter, safeType(e.weapon), safeName(tgt), safeType(tgt)))
      end
    elseif e.id == world.event.S_EVENT_DEAD then
      local obj = e.initiator
      if safeCat(obj) == tostring(Object.Category.WEAPON) then
        log(string_format("DEAD-WEAPON %s (%s)", safeName(obj), safeType(obj)))
      else
        log(string_format("DEAD %s (%s)", safeName(obj), safeType(obj)))
      end
    elseif e.id == world.event.S_EVENT_BIRTH then
      log(string_format("BIRTH %s (%s)", safeName(e.initiator), safeType(e.initiator)))
    end
  end)
end
world.addEventHandler(handler)

local function summary()
  safeCall("summary", function()
    local parts = {}
    for shooter, s in pairs(P.stats) do
      parts[#parts + 1] = string_format("%s: shots=%d hitsOnWeapons=%d hitsOnUnits=%d", shooter, s.shots, s.hitsOnWeapons, s.hitsOnUnits)
    end
    table.sort(parts)
    log("SUMMARY " .. table.concat(parts, " | "))
  end)
  return timer_getTime() + 60
end
timer_schedule(summary, nil, timer_getTime() + 60)

-- ------------------------------------------------------------------ anchor
local AP
for _, ab in ipairs(world.getAirbases() or {}) do
  local n = ab:getName() or ""
  if n:find("Assad") or n:find("Latakia") then AP = ab:getPoint(); break end
end
if not AP then
  env_error(TAG .. " no anchor airbase (Bassel Al-Assad): is this the Syria map? Nothing spawned.")
  return
end
local x0, z0 = AP.x, AP.z
local RED, BLUE = country.id.RUSSIA, country.id.USA

-- ------------------------------------------------------------------ spawn helpers
local function ground(ctry, name, cx, cz, list, task)
  local units = {}
  for i = 1, #list do
    local u = list[i]
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent",
      x = cx + u[2], y = cz + u[3], heading = math_rad(u[4] or 270) }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, ctry, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = task and { task } or {} } } } } } })
  log(string_format("SPAWN %s (%d units) %s", name, #units, ok and "ok" or "FAILED"))
end

local function wp(x, z, alt, altType, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = altType,
    speed = speed, speed_locked = true, ETA = 0, ETA_locked = false,
    task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end

-- air(ctry, cat, name, type, count, task, pylons, fuel, route{{x,z},...}, alt m, altType, speed m/s, wp1 tasks)
local function air(ctry, cat, name, typ, count, task, pylons, fuel, route, alt, altType, speed, tasks1)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = typ, skill = "High",
      x = route[1][1] - (i - 1) * 1200 * math_cos(h), y = route[1][2] - (i - 1) * 1200 * math_sin(h) + (i - 1) * 600,
      alt = alt, alt_type = altType, speed = speed, heading = h,
      payload = { pylons = pylons, fuel = fuel, chaff = 60, flare = 60, gun = 100 },
      callsign = { 1, 1, i }, onboard_num = tostring(300 + i) }
  end
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, altType, speed, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, ctry, cat,
    { name = name, task = task, units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s) %s", name, count, typ, ok and "ok" or "FAILED"))
  -- options 2 s after spawn (tasking delay rule)
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g or not g:isExist() then return end
      local c = g:getController()
      local O = AI.Option.Air
      c:setOption(O.id.ROE, O.val.ROE.WEAPON_FREE)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
      c:setOption(O.id.RTB_ON_OUT_OF_AMMO, false)
    end)
    return nil
  end, nil, timer_getTime() + 2)
end

local function groupId(name)
  local g = Group.getByName(name)
  return g and g:isExist() and g:getID() or nil
end

local function attackGroupTask(targetName, weaponType)
  local id = groupId(targetName)
  if not id then log("no target group " .. targetName); return {} end
  local t = { id = "AttackGroup", params = { groupId = id, expend = "All", attackQtyLimit = false } }
  if weaponType then t.params.weaponType = weaponType end
  return { t }
end

local function seadTask()
  return { { id = "EngageTargets", enabled = true, auto = false, number = 1,
             params = { targetTypes = { "Air Defence" }, priority = 0 } } }
end

-- ------------------------------------------------------------------ sites
local B1 = { x = x0 - 15000, z = z0 + 40000 }   -- blue point-defence site
local B2 = { x = x0 - 45000, z = z0 + 40000 }   -- blue Patriot site
local R1 = { x = x0 + 40000, z = z0 + 55000 }   -- red point-defence site

ground(BLUE, "PD C-RAM Probe", B1.x, B1.z, { { "HEMTT_C-RAM_Phalanx", 300, 300 }, { "HEMTT_C-RAM_Phalanx", -300, -300 } })
ground(BLUE, "PD Avenger Probe", B1.x, B1.z, { { "M1097 Avenger", 300, -300 }, { "M1097 Avenger", -300, 300 } })
ground(BLUE, "EW Hawk Bait B1", B1.x, B1.z, { { "Hawk sr", 0, 150 }, { "Hawk tr", 0, -150 } })
ground(BLUE, "Target Trucks B1", B1.x, B1.z, { { "Ural-375", 40, 0 }, { "Ural-375", -40, 0 }, { "Ural-375", 0, 40 }, { "Ural-375", 0, -40 } })
ground(BLUE, "SAM Patriot Probe", B2.x, B2.z, {
  { "Patriot str", 0, 0 }, { "Patriot ECS", 100, 0 }, { "Patriot EPP", 150, 50 }, { "Patriot AMG", 150, -50 },
  { "Patriot ln", 300, 300 }, { "Patriot ln", 300, -300 }, { "Patriot ln", -300, 300 }, { "Patriot ln", -300, -300 } })
ground(RED, "PD Tor Probe", R1.x, R1.z, { { "Tor 9A331", 300, 300 }, { "Tor 9A331", -300, -300 } })
ground(RED, "PD Pantsir Probe", R1.x, R1.z, { { "CHAP_PantsirS1", 300, -300 }, { "CHAP_PantsirS1", -300, 300 } })
ground(RED, "EW Bait R1", R1.x, R1.z, { { "1L13 EWR", 0, 0 } })
ground(RED, "Target Trucks R1", R1.x, R1.z, { { "Ural-375", 40, 0 }, { "Ural-375", -40, 0 }, { "Ural-375", 0, 40 }, { "Ural-375", 0, -40 } })

-- ------------------------------------------------------------------ weapons (CLSIDs from the DCS datamine)
local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local AIM120C = "{40EF17B7-F508-45de-8566-6FFECC0C1AB8}"
local KH58U = "{FE382A68-8620-4AC0-BDF5-709BFE3977D7}"
local KH31P = "{X-31P}"
local KH22 = "{12429ECF-03F0-4DF6-BCBD-5D38B6343DE1}"
local KAB500KR = "{E2C426E3-8B10-4E09-B733-9CDC26520F48}"
local S8_B8V20A = "B_8V20A_CM"
local FAB250 = "{FAB_250_M62}"

-- ------------------------------------------------------------------ waves
local PLANE, HELO = Group.Category.AIRPLANE, Group.Category.HELICOPTER
local function at(t, tag, fn)
  timer_schedule(function() log("WAVE " .. tag); safeCall("wave " .. tag, fn); return nil end, nil, timer_getTime() + t)
end

-- wave 1: ARMs both ways
at(240, "1 ARM: blue F-16C AGM-88C vs R1; red Su-24M Kh-58U vs B1", function()
  air(BLUE, PLANE, "Weasel Probe", "F-16C_50", 2, "SEAD",
    { [1] = { CLSID = AIM120C }, [3] = { CLSID = AGM88C }, [4] = { CLSID = AGM88C }, [6] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C }, [9] = { CLSID = AIM120C } },
    3249, { { x0 - 20000, z0 - 90000 }, { R1.x - 20000, R1.z - 30000 }, { R1.x - 20000, R1.z + 30000 }, { x0 - 20000, z0 - 90000 } },
    25000 * FT, "BARO", 240, seadTask())
  air(RED, PLANE, "Fencer Probe", "Su-24M", 2, "SEAD",
    { [2] = { CLSID = KH58U }, [7] = { CLSID = KH58U } },
    11700, { { B1.x + 20000, B1.z + 140000 }, { B1.x + 20000, B1.z + 30000 }, { B1.x + 20000, B1.z + 140000 } },
    22000 * FT, "BARO", 250, seadTask())
end)

-- wave 2: Kh-31P vs Patriot, Kh-22 vs B1
at(480, "2 ARM/AShM: red Su-34 Kh-31P vs B2 (Patriot); red Tu-22M3 Kh-22 vs B1", function()
  air(RED, PLANE, "Fullback SEAD Probe", "Su-34", 2, "SEAD",
    { [3] = { CLSID = KH31P }, [4] = { CLSID = KH31P }, [8] = { CLSID = KH31P }, [9] = { CLSID = KH31P } },
    9800, { { B2.x - 10000, B2.z + 140000 }, { B2.x - 10000, B2.z + 35000 }, { B2.x - 10000, B2.z + 140000 } },
    22000 * FT, "BARO", 250, seadTask())
  air(RED, PLANE, "Backfire Probe", "Tu-22M3", 1, "Antiship Strike",
    { [1] = { CLSID = KH22 }, [3] = { CLSID = KH22 }, [5] = { CLSID = KH22 } },
    50000, { { B1.x + 40000, B1.z + 200000 }, { B1.x + 40000, B1.z + 60000 }, { B1.x + 40000, B1.z + 200000 } },
    30000 * FT, "BARO", 260, attackGroupTask("Target Trucks B1"))
end)

-- wave 3: guided bombs
at(720, "3 guided bombs: red Su-34 KAB-500Kr vs B1 trucks", function()
  air(RED, PLANE, "Fullback KAB Probe", "Su-34", 2, "Ground Attack",
    { [3] = { CLSID = KAB500KR }, [4] = { CLSID = KAB500KR }, [8] = { CLSID = KAB500KR }, [9] = { CLSID = KAB500KR } },
    9800, { { B1.x + 5000, B1.z + 90000 }, { B1.x, B1.z }, { B1.x - 5000, B1.z + 90000 } },
    16000 * FT, "BARO", 230, attackGroupTask("Target Trucks B1"))
end)

-- wave 4: rockets
at(960, "4 rockets: red Mi-24P S-8 vs B1 trucks", function()
  air(RED, HELO, "Hind Probe", "Mi-24P", 2, "CAS",
    { [2] = { CLSID = S8_B8V20A }, [3] = { CLSID = S8_B8V20A }, [4] = { CLSID = S8_B8V20A }, [5] = { CLSID = S8_B8V20A } },
    1701, { { B1.x + 3000, B1.z + 18000 }, { B1.x, B1.z }, { B1.x + 3000, B1.z + 18000 } },
    100, "RADIO", 60, attackGroupTask("Target Trucks B1"))
end)

-- wave 5: artillery rockets
at(1200, "5 artillery: red BM-21 Grad fires at B1 trucks from 15 km", function()
  local id = groupId("Target Trucks B1")
  local fire = { id = "FireAtPoint", params = { point = { x = B1.x, y = B1.z }, radius = 100, expendQty = 40, expendQtyEnabled = true } }
  ground(RED, "Grad Probe", B1.x + 5000, B1.z + 15000,
    { { "Grad-URAL", 0, 0 }, { "Grad-URAL", 0, 60 }, { "Grad-URAL", 0, 120 } }, fire)
  log("Grad target group id " .. tostring(id))
end)

-- wave 6: dumb bombs
at(1440, "6 dumb bombs: red Su-25T FAB-250 vs B1 trucks", function()
  air(RED, PLANE, "Frogfoot Probe", "Su-25T", 2, "Ground Attack",
    { [2] = { CLSID = FAB250 }, [3] = { CLSID = FAB250 }, [8] = { CLSID = FAB250 }, [9] = { CLSID = FAB250 } },
    3790, { { B1.x + 3000, B1.z + 60000 }, { B1.x, B1.z }, { B1.x - 3000, B1.z + 60000 } },
    6000 * FT, "BARO", 180, attackGroupTask("Target Trucks B1"))
end)

at(1800, "END: probe complete at 30 min", function() summary() end)

log("probe " .. P.VERSION .. " loaded on Syria; sites spawned, 6 waves scheduled (240 s apart from 240 s)")
