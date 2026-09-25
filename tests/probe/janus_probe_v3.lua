-- Janus IADS - Phase 0 probe v3 (JANUS_PROBE_V3.miz). One file, no dependencies; janus.lua is loaded AFTER it
-- in the same mission so its setup report runs against the groups spawned here.
-- Records to dcs.log with the tag "JANUS_PROBE". Lua 5.1, sanitized, one global (JANUS).
--
-- Questions (DESIGN 4.5A/4.5B/Phase 1):
--   A  EMCON: how long after ALARM_STATE RED / GREEN and enableEmission(true/false) does each system's radar come
--      up or go down, both as seen by unit:getRadar() and by an enemy RWR (an unarmed blue observer)?  (north, R2)
--   B  Cueing: does a launcher-only group fire using a radar in ANOTHER group? SA-10 and SA-6 split into radar and
--      launcher groups, SA-11 complete group as control, two unarmed C-130 targets.                       (north-east, R3)
--   C  ARM memory: does a Shrike / a HARM keep guiding after its target radar goes dark 5 s after launch?
--      Blue F-4E 2x AGM-45A vs an SA-2, blue F-16C 2x AGM-88C vs an SA-6; targets on weapons hold.         (north, R4/R5)
--   D  Patriot vs ARM / AShM: red Su-34 Kh-31P, Su-24M Kh-58U and Tu-22M3 Kh-22 with AttackUnit on the Patriot
--      radar (run 2's SEAD/EngageTargets tasks never launched).                                            (south, B1)
--   E  First-track range: distance from each listening radar to each weapon when it first appears in
--      getDetectedTargets (tunes the ARM awareness filter).
-- Layout rules: no air-to-air weapons on any aircraft; red sites + blue attackers in the north, blue site + red
-- attackers in the south, ~250 km apart. Anchor: Bassel Al-Assad / Latakia. x north, z east, metres.

JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.4.0"

local TAG = "JANUS_PROBE"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_rad, math_cos, math_sin, math_atan2, math_sqrt = math.rad, math.cos, math.sin, math.atan2, math.sqrt
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
  if obj == nil then return -1 end
  local ok, c = pcall(function() return Object.getCategory(obj) end)
  return ok and c or -1
end
local function safePoint(obj)
  if obj == nil then return nil end
  local ok, p = pcall(function() return obj:getPoint() end)
  return ok and p or nil
end
local function dist(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
  return math_sqrt(dx * dx + dy * dy + dz * dz)
end

-- every N seconds, returns the next time (for timer.scheduleFunction)
local function every(tag, interval, first, fn)
  timer_schedule(function()
    safeCall(tag, fn)
    return timer_getTime() + interval
  end, nil, timer_getTime() + first)
end
local function at(t, tag, fn)
  timer_schedule(function() log("STEP " .. tag); safeCall(tag, fn); return nil end, nil, T0 + t)
end

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

-- move a point east in 5 km steps until it is on land (the north of the map has sea and coast)
local function onLand(x, z)
  for _ = 1, 20 do
    local okS, st = pcall(land.getSurfaceType, { x = x, y = z })
    if okS and st == land.SurfaceType.LAND then return x, z end
    z = z + 5000
  end
  return x, z
end

-- ------------------------------------------------------------------ spawn helpers
local function ground(ctry, name, cx, cz, list)
  local units = {}
  for i = 1, #list do
    local u = list[i]
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent",
      x = cx + u[2], y = cz + u[3], heading = math_rad(u[4] or 270) }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, ctry, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } } })
  log(string_format("SPAWN %s (%d units) %s", name, #units, ok and "ok" or "FAILED"))
end

local function wp(x, z, alt, altType, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = altType,
    speed = speed, speed_locked = true, ETA = 0, ETA_locked = false,
    task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end

local PLANE = Group.Category.AIRPLANE
local function air(ctry, name, typ, count, task, pylons, fuel, route, alt, altType, speed, tasks1, roe)
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
  local ok = safeCall("spawn " .. name, coalition.addGroup, ctry, PLANE,
    { name = name, task = task, units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s) %s", name, count, typ, ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g or not g:isExist() then return end
      local c = g:getController()
      local O = AI.Option.Air
      c:setOption(O.id.ROE, roe or O.val.ROE.WEAPON_FREE)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
      c:setOption(O.id.RTB_ON_OUT_OF_AMMO, false)
    end)
    return nil
  end, nil, timer_getTime() + 2)
end

local function groundOptions(name, alarm, roe)
  local g = Group.getByName(name)
  if not g or not g:isExist() then return end
  local c = g:getController()
  local O = AI.Option.Ground
  if alarm then c:setOption(O.id.ALARM_STATE, alarm) end
  if roe then c:setOption(O.id.ROE, roe) end
end

local function unitId(name)
  local u = Unit.getByName(name)
  return u and u:isExist() and u:getID() or nil
end

local function attackUnitTask(unitName)
  local id = unitId(unitName)
  if not id then log("no target unit " .. unitName); return {} end
  return { { id = "AttackUnit", params = { unitId = id, expend = "All", attackQtyLimit = false, groupAttack = true } } }
end

local function seadTask()
  return { { id = "EngageTargets", enabled = true, auto = false, number = 1,
             params = { targetTypes = { "Air Defence" }, priority = 0 } } }
end

local GA = AI.Option.Ground.val
local RED_ALARM, GREEN_ALARM = GA.ALARM_STATE.RED, GA.ALARM_STATE.GREEN
local HOLD, FREE = GA.ROE.WEAPON_HOLD, GA.ROE.OPEN_FIRE

-- ------------------------------------------------------------------ positions
local R2x, R2z = onLand(x0 + 150000, z0 + 60000)    -- EMCON test sites
local R3x, R3z = onLand(x0 + 120000, z0 + 150000)   -- cueing test sites (inland)
local R4x, R4z = onLand(x0 + 175000, z0 + 15000)    -- Shrike target (SA-2)
local R5x, R5z = onLand(x0 + 200000, z0 + 35000)    -- HARM target (SA-6)
local B1x, B1z = x0 - 60000, z0 + 30000              -- Patriot (south)

-- ------------------------------------------------------------------ A: EMCON test groups (weapons hold, start GREEN)
local EMCON = {
  { "SAM EMCON SA-10", { { "S-300PS 54K6 cp", 0, 0 }, { "S-300PS 64H6E sr", 300, 200 }, { "S-300PS 40B6M tr", -200, 150 },
                         { "S-300PS 5P85C ln", 450, 500 }, { "S-300PS 5P85C ln", -450, 500 } } },
  { "SAM EMCON SA-11", { { "SA-11 Buk CC 9S470M1", 0, 0 }, { "SA-11 Buk SR 9S18M1", 250, 0 },
                         { "SA-11 Buk LN 9A310M1", 0, 300 }, { "SA-11 Buk LN 9A310M1", 0, -300 } } },
  { "SAM EMCON SA-6",  { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 300, 200 }, { "Kub 2P25 ln", -300, 200 } } },
  { "SAM EMCON SA-2",  { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 }, { "S_75M_Volhov", -400, 400 } } },
  { "SAM EMCON SA-5",  { { "RPC_5N62V", 0, 0 }, { "P14_SR", 600, 0 }, { "S-200_Launcher", 400, 400 }, { "S-200_Launcher", -400, 400 } } },
  { "SAM EMCON SA-15", { { "Tor 9A331", 0, 0 } } },
  { "SAM EMCON Pantsir", { { "CHAP_PantsirS1", 0, 0 } } },
}
for i = 1, #EMCON do
  ground(RED, EMCON[i][1], R2x + (i - 1) * 3000, R2z, EMCON[i][2])
end
timer_schedule(function()
  for i = 1, #EMCON do safeCall("emcon init", groundOptions, EMCON[i][1], GREEN_ALARM, HOLD) end
  log("EMCON groups set GREEN, weapons hold")
  return nil
end, nil, timer_getTime() + 2)

-- ------------------------------------------------------------------ B: cueing test groups (weapons free, RED)
ground(RED, "SAM CUE SA-10 Radars", R3x, R3z, { { "S-300PS 54K6 cp", 0, 0 }, { "S-300PS 64H6E sr", 300, 200 }, { "S-300PS 40B6M tr", -200, 150 } })
ground(RED, "SAM CUE SA-10 Launchers", R3x + 400, R3z + 600, { { "S-300PS 5P85C ln", 0, 0 }, { "S-300PS 5P85C ln", 300, 0 } })
ground(RED, "SAM CUE SA-6 Radar", R3x - 30000, R3z, { { "Kub 1S91 str", 0, 0 } })
ground(RED, "SAM CUE SA-6 Launchers", R3x - 30000 + 300, R3z + 300, { { "Kub 2P25 ln", 0, 0 }, { "Kub 2P25 ln", 300, 0 } })
ground(RED, "SAM CUE SA-11 Control", R3x - 30000, R3z + 40000, { { "SA-11 Buk CC 9S470M1", 0, 0 }, { "SA-11 Buk SR 9S18M1", 250, 0 }, { "SA-11 Buk LN 9A310M1", 0, 300 } })
local CUE = { "SAM CUE SA-10 Radars", "SAM CUE SA-10 Launchers", "SAM CUE SA-6 Radar", "SAM CUE SA-6 Launchers", "SAM CUE SA-11 Control" }
timer_schedule(function()
  for i = 1, #CUE do safeCall("cue init", groundOptions, CUE[i], RED_ALARM, FREE) end
  log("CUE groups set RED, weapons free")
  return nil
end, nil, timer_getTime() + 2)

-- ------------------------------------------------------------------ C: ARM memory targets (RED, weapons hold) + EW listeners
ground(RED, "SAM ARMTEST SA-2", R4x, R4z, { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 300, 0 }, { "S_75M_Volhov", 400, 400 } })
ground(RED, "SAM ARMTEST SA-6", R5x, R5z, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 300, 200 } })
ground(RED, "EW Probe 55G6", R4x + 15000, R4z + 40000, { { "55G6 EWR", 0, 0 } })
ground(RED, "EW Probe 1L13", R5x + 10000, R5z + 30000, { { "1L13 EWR", 0, 0 } })
timer_schedule(function()
  for _, n in ipairs({ "SAM ARMTEST SA-2", "SAM ARMTEST SA-6", "EW Probe 55G6", "EW Probe 1L13" }) do
    safeCall("armtest init", groundOptions, n, RED_ALARM, HOLD)
  end
  log("ARMTEST targets and EW listeners set RED, weapons hold")
  return nil
end, nil, timer_getTime() + 2)

-- ------------------------------------------------------------------ D: Patriot (south)
ground(BLUE, "SAM Patriot Probe", B1x, B1z, {
  { "Patriot str", 0, 0 }, { "Patriot ECS", 100, 0 }, { "Patriot EPP", 150, 50 }, { "Patriot AMG", 150, -50 },
  { "Patriot ln", 400, 400 }, { "Patriot ln", 400, -400 }, { "Patriot ln", -400, 400 }, { "Patriot ln", -400, -400 } })

-- ------------------------------------------------------------------ event recording
P.stats = {}
local function bump(k, field)
  local r = P.stats[k]
  if not r then r = { shots = 0, hitsOnWeapons = 0, hitsOnUnits = 0 }; P.stats[k] = r end
  r[field] = r[field] + 1
end

local ARM_GROUPS = { ["Shrike Probe"] = true, ["HARM Memory Probe"] = true }
P.inFlight = {}   -- ARM memory test: weapon -> { target unit, target group, t0, last distance }

local handler = {}
function handler:onEvent(e)
  safeCall("event", function()
    if e.id == world.event.S_EVENT_SHOT then
      local w = e.weapon
      local target = w and w.getTarget and w:getTarget() or nil
      bump(safeType(e.initiator), "shots")
      log(string_format("SHOT shooter=%s (%s) weapon=%s target=%s targetType=%s targetCat=%d",
        safeName(e.initiator), safeType(e.initiator), safeType(w), safeName(target), safeType(target), safeCat(target)))
      -- C: ARM memory test - switch the targeted radar off 5 s after launch and follow the missile
      local okG, grp = pcall(function() return e.initiator:getGroup():getName() end)
      if okG and ARM_GROUPS[grp] and w and target then
        local okT, tgtGroup = pcall(function() return target:getGroup():getName() end)
        P.inFlight[w] = { target = target, targetName = safeName(target), group = okT and tgtGroup or "?",
                          t0 = now(), last = nil, weapon = safeType(w) }
        timer_schedule(function()
          safeCall("armtest off", function()
            local g = okT and Group.getByName(tgtGroup)
            if g and g:isExist() then
              g:enableEmission(false)
              log(string_format("ARMTEST %s emission OFF 5 s after %s launch", tgtGroup, safeType(w)))
            end
          end)
          return nil
        end, nil, timer_getTime() + 5)
      end
    elseif e.id == world.event.S_EVENT_HIT then
      local tgt = e.target
      local shooter = safeType(e.initiator)
      if safeCat(tgt) == Object.Category.WEAPON then
        bump(shooter, "hitsOnWeapons")
        log(string_format("HIT-WEAPON shooter=%s weapon=%s (a weapon: %s)", shooter, safeType(e.weapon), safeType(tgt)))
      elseif safeCat(tgt) == Object.Category.UNIT then
        bump(shooter, "hitsOnUnits")
        log(string_format("HIT shooter=%s weapon=%s target=%s (%s)", shooter, safeType(e.weapon), safeName(tgt), safeType(tgt)))
      end
    elseif e.id == world.event.S_EVENT_DEAD then
      if safeCat(e.initiator) == Object.Category.UNIT then
        log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
      end
    end
  end)
end
world.addEventHandler(handler)

-- C: follow ARMs in flight once a second; when one disappears, log its last distance to the target
every("armtest follow", 1, 1, function()
  for w, r in pairs(P.inFlight) do
    local okE, alive = pcall(function() return w:isExist() end)
    if okE and alive then
      local wp1, tp = safePoint(w), safePoint(r.target)
      if wp1 and tp then r.last = dist(wp1, tp) end
    else
      local tgtAlive = false
      pcall(function() tgtAlive = r.target:isExist() and r.target:getLife() > 1 end)
      log(string_format("ARMTEST END weapon=%s target=%s group=%s flight=%.1fs lastDist=%s targetAlive=%s",
        r.weapon, r.targetName, r.group, now() - r.t0, r.last and string_format("%.0fm", r.last) or "?", tostring(tgtAlive)))
      P.inFlight[w] = nil
    end
  end
end)

-- ------------------------------------------------------------------ A: EMCON sequence + monitor
local OBS = "Observer RWR Probe"
local STEPS = {
  { 0,   "ALARM RED",       function(_, n) groundOptions(n, RED_ALARM, nil) end },
  { 60,  "EMISSION OFF",    function(g) g:enableEmission(false) end },
  { 120, "EMISSION ON",     function(g) g:enableEmission(true) end },
  { 180, "ALARM GREEN",     function(_, n) groundOptions(n, GREEN_ALARM, nil) end },
  { 240, "ALARM RED again", function(_, n) groundOptions(n, RED_ALARM, nil) end },
}
local EMCON_START, STAGGER = 90, 15
P.emcon = {}
for i = 1, #EMCON do
  local name = EMCON[i][1]
  local st = { radar = false, rwr = false, step = "init", stepT = 0 }
  P.emcon[name] = st
  for s = 1, #STEPS do
    local t = EMCON_START + (i - 1) * STAGGER + STEPS[s][1]
    local label, fn = STEPS[s][2], STEPS[s][3]
    timer_schedule(function()
      safeCall("emcon step", function()
        local g = Group.getByName(name)
        if g and g:isExist() then
          fn(g, name)
          st.step, st.stepT = label, now()
          log(string_format("EMCON %s STEP %s (radar=%s rwr=%s)", name, label, tostring(st.radar), tostring(st.rwr)))
        end
      end)
      return nil
    end, nil, T0 + t)
  end
end

every("emcon monitor", 1, 60, function()
  local t = now()
  if t > EMCON_START + #EMCON * STAGGER + 320 then return end
  local rwrSeen = {}
  local og = Group.getByName(OBS)
  if og and og:isExist() then
    local c = og:getController()
    local dets = c and c:getDetectedTargets(Controller.Detection.RWR) or {}
    for j = 1, #dets do
      local o = dets[j].object
      if o and safeCat(o) == Object.Category.UNIT then
        local okg, gn = pcall(function() return o:getGroup():getName() end)
        if okg then rwrSeen[gn] = true end
      end
    end
  end
  for name, st in pairs(P.emcon) do
    local g = Group.getByName(name)
    local radar = false
    if g and g:isExist() then
      local us = g:getUnits() or {}
      for k = 1, #us do
        local okR, on = pcall(function() return us[k]:getRadar() end)
        if okR and on then radar = true end
      end
    end
    local rwr = rwrSeen[name] == true
    if radar ~= st.radar or rwr ~= st.rwr then
      log(string_format("EMCON %s radar=%s rwr=%s  %.0fs after STEP %s", name, tostring(radar), tostring(rwr), t - st.stepT, st.step))
      st.radar, st.rwr = radar, rwr
    end
  end
end)

-- ------------------------------------------------------------------ E: first-track range per listener and weapon
local LISTENERS = { "SAM Patriot Probe", "SAM ARMTEST SA-2", "SAM ARMTEST SA-6", "EW Probe 55G6", "EW Probe 1L13" }
local firstSeen = {}
every("track sweep", 2, 10, function()
  for i = 1, #LISTENERS do
    local g = Group.getByName(LISTENERS[i])
    if g and g:isExist() then
      local u1 = g:getUnit(1)
      local c = g:getController()
      local dets = c and c:getDetectedTargets() or {}
      for j = 1, #dets do
        local o = dets[j].object
        if o and safeCat(o) == Object.Category.WEAPON then
          local key = LISTENERS[i] .. tostring(o)
          if not firstSeen[key] then
            firstSeen[key] = true
            local op, up = safePoint(o), safePoint(u1)
            log(string_format("TRACK-WEAPON by=%s weapon=%s range=%s", LISTENERS[i], safeType(o),
              (op and up) and string_format("%.0fm", dist(op, up)) or "?"))
          end
        end
      end
    end
  end
end)

-- ------------------------------------------------------------------ weapons (CLSIDs from the DCS datamine)
local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local AGM45A = "{AGM_45A}"
local KH58U = "{FE382A68-8620-4AC0-BDF5-709BFE3977D7}"
local KH31P = "{X-31P}"
local KH22 = "{12429ECF-03F0-4DF6-BCBD-5D38B6343DE1}"
local AO = AI.Option.Air.val

-- A: unarmed observer with an RWR, orbiting west of the EMCON sites over the sea
at(20, "A observer: unarmed F-16C RWR orbit west of R2", function()
  air(BLUE, OBS, "F-16C_50", 1, "CAP", {}, 3249,
    { { R2x - 20000, R2z - 90000 }, { R2x + 20000, R2z - 90000 }, { R2x - 20000, R2z - 90000 },
      { R2x + 20000, R2z - 90000 }, { R2x - 20000, R2z - 90000 }, { R2x + 20000, R2z - 90000 } },
    25000 * FT, "BARO", 200, nil, AO.ROE.WEAPON_HOLD)
end)

-- B: two unarmed C-130 targets through the cueing area
at(150, "B targets: C-130 over SA-10 split pair and over SA-6 split pair + SA-11 control", function()
  air(BLUE, "Cue Target North", "C-130", 1, "Transport", {}, 20830,
    { { R3x + 10000, R3z - 60000 }, { R3x + 10000, R3z + 60000 } }, 20000 * FT, "BARO", 150, nil, AO.ROE.WEAPON_HOLD)
  air(BLUE, "Cue Target South", "C-130", 1, "Transport", {}, 20830,
    { { R3x - 30000, R3z - 50000 }, { R3x - 30000, R3z + 60000 } }, 15000 * FT, "BARO", 150, nil, AO.ROE.WEAPON_HOLD)
end)

-- C: ARM memory shooters from the west (sea)
at(600, "C ARM memory: blue F-4E 2x AGM-45A vs SA-2; blue F-16C 2x AGM-88C vs SA-6", function()
  air(BLUE, "Shrike Probe", "F-4E", 1, "SEAD", { [2] = { CLSID = AGM45A }, [8] = { CLSID = AGM45A } }, 4864,
    { { R4x, R4z - 110000 }, { R4x, R4z - 15000 }, { R4x - 20000, R4z - 110000 } }, 18000 * FT, "BARO", 230, seadTask())
  air(BLUE, "HARM Memory Probe", "F-16C_50", 1, "SEAD", { [3] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }, 3249,
    { { R5x, R5z - 120000 }, { R5x, R5z - 30000 }, { R5x + 20000, R5z - 120000 } }, 22000 * FT, "BARO", 240, seadTask())
end)

-- D: red ARMs / AShM at the Patriot radar, forced with AttackUnit
at(600, "D Patriot: red Su-34 4x Kh-31P AttackUnit Patriot str", function()
  air(RED, "Fullback ARM Probe", "Su-34", 1, "SEAD",
    { [3] = { CLSID = KH31P }, [4] = { CLSID = KH31P }, [8] = { CLSID = KH31P }, [9] = { CLSID = KH31P } }, 9800,
    { { B1x, B1z + 160000 }, { B1x, B1z + 40000 }, { B1x + 20000, B1z + 160000 } }, 20000 * FT, "BARO", 250,
    attackUnitTask("SAM Patriot Probe-1"))
end)
at(840, "D Patriot: red Su-24M 2x Kh-58U AttackUnit Patriot str", function()
  air(RED, "Fencer ARM Probe", "Su-24M", 1, "SEAD", { [2] = { CLSID = KH58U }, [7] = { CLSID = KH58U } }, 11700,
    { { B1x + 10000, B1z + 150000 }, { B1x + 10000, B1z + 40000 }, { B1x + 30000, B1z + 150000 } }, 18000 * FT, "BARO", 250,
    attackUnitTask("SAM Patriot Probe-1"))
end)
at(1080, "D Patriot: red Tu-22M3 3x Kh-22 AttackUnit Patriot str", function()
  air(RED, "Backfire ARM Probe", "Tu-22M3", 1, "Antiship Strike",
    { [1] = { CLSID = KH22 }, [3] = { CLSID = KH22 }, [5] = { CLSID = KH22 } }, 50000,
    { { B1x + 30000, B1z + 220000 }, { B1x + 30000, B1z + 80000 }, { B1x + 50000, B1z + 220000 } }, 30000 * FT, "BARO", 260,
    attackUnitTask("SAM Patriot Probe-1"))
end)

-- summary every 60 s, end at 30 min
every("summary", 60, 60, function()
  local parts = {}
  for shooter, s in pairs(P.stats) do
    parts[#parts + 1] = string_format("%s: shots=%d hitsOnWeapons=%d hitsOnUnits=%d", shooter, s.shots, s.hitsOnWeapons, s.hitsOnUnits)
  end
  table.sort(parts)
  log("SUMMARY " .. table.concat(parts, " | "))
end)
at(1800, "END: probe v3 complete at 30 min", function() end)

log(string_format("probe %s loaded on Syria (v3: EMCON R2 %.0f/%.0f, cueing R3 %.0f/%.0f, ARM memory R4/R5, Patriot B1); janus.lua loads next",
  P.VERSION, R2x - x0, R2z - z0, R3x - x0, R3z - z0))
