-- Janus IADS - probe run 8 (JANUS_PROBE_P4.miz). Plain DCS, NO janus.lua. Records to dcs.log as "JANUS_PROBE".
-- Lua 5.1, sanitized, one global (JANUS).
--
-- Question: can red AI be made to launch anti-radiation missiles (ARMs), and at which blue radars?
--   Run 1: a Su-34 fired a Kh-31P at a Hawk search radar (SEAD task). Runs 2-3: Su-34 Kh-31P, Su-24M Kh-58U and
--   Tu-22M3 Kh-22 never fired at a Patriot (SEAD + EngageTargets, then AttackUnit). So: is it the Patriot, the
--   missile, the tasking or the altitude?
-- Seven lanes, 70 km apart north-south, blue sites ~80 km inland on flat ground (weapons hold, radars on), red
-- shooters from 130 km east:
--   L1 Hawk     <- Su-24M 2x Kh-58U           SEAD + EngageTargets, 23,000 ft   (does Kh-58U work at all)
--   L2 Patriot  <- Su-34  4x Kh-31P           SEAD + EngageTargets, 23,000 ft   (repeat of run 2, with ammo logs)
--   L3 Patriot  <- Su-34  4x Kh-31P           AttackGroup, weaponType ARM (32768), 23,000 ft
--   L4 Patriot  <- Su-25T 2x Kh-25MPU 2x Kh-58U  SEAD + EngageTargets, 13,000 ft
--   L5 Hawk     <- Su-34  2x Kh-31P           SEAD (control: run 1 fired). The Hawk goes DARK 20 s after the first
--                  ARM launch at it (does DCS Kh-31P still hit a dark radar?); a dark Patriot 6 km behind comes up
--                  weapons free at that launch (does Patriot shoot at an ARM?)
--   L6 NASAMS   <- Su-24M 2x Kh-31P           SEAD + EngageTargets, 20,000 ft
--   L7 Patriot  <- JF-17  2x LD-10            SEAD + EngageTargets, 20,000 ft
-- Logged: every shooter's ammo at spawn and every 15 s, range to its site, whether its controller detects the site
-- radar (isTargetDetected), every SHOT (weapon, target, range), each ARM's flight (1 s) and its end (closest
-- approach to the radar), HIT / DEAD on blue units.
JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.9.0-p4"

local TAG = "JANUS_PROBE"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_deg, math_atan, math_sqrt, math_cos, math_sin, math_pi =
  math.deg, math.atan, math.sqrt, math.cos, math.sin, math.pi
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
  return (ok and g) and safeName(g) or "-"
end
local function at(t, tag, fn)
  timer_schedule(function() log("STEP " .. tag); safeCall(tag, fn); return nil end, nil, T0 + t)
end
local function dist(ax, az, bx, bz)
  local dx, dz = ax - bx, az - bz
  return math_sqrt(dx * dx + dz * dz)
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
local function hgt(x, z) return land.getHeight({ x = x, y = z }) end
-- terrain slope in degrees at a point (central differences over 30 m; same method as Janus's setup check)
local function slope(x, z)
  local d = 30
  local gx = (hgt(x + d, z) - hgt(x - d, z)) / (2 * d)
  local gz = (hgt(x, z + d) - hgt(x, z - d)) / (2 * d)
  return math_deg(math_atan(math_sqrt(gx * gx + gz * gz)))
end

local used = {}           -- spots already taken: { x, z }
local function farFromUsed(x, z, minD)
  for i = 1, #used do
    if dist(x, z, used[i][1], used[i][2]) < minD then return false end
  end
  return true
end
-- every unit position of `layout` at centre (x, z): all on land, slope min / max
local function layoutSlopes(x, z, layout)
  local lo, hi = 99, -1
  for _, u in ipairs(layout) do
    local ux, uz = x + u[2], z + u[3]
    if not isLand(ux, uz) then return nil end
    local s = slope(ux, uz)
    if s < lo then lo = s end
    if s > hi then hi = s end
  end
  return lo, hi
end
-- spiral search around (x, z) for a centre where EVERY unit of the layout sits inside [bandLo, bandHi]
-- returns x, z, lo, hi, hit (false = closest miss)
local function findBand(x, z, layout, bandLo, bandHi, minSep)
  local best, bestErr
  for ring = 0, 70 do
    local rr = ring * 500
    local n = ring == 0 and 1 or ring * 6
    for i = 1, n do
      local a = (i / n) * 2 * math_pi
      local cx, cz = x + rr * math_cos(a), z + rr * math_sin(a)
      if farFromUsed(cx, cz, minSep) then
        local lo, hi = layoutSlopes(cx, cz, layout)
        if lo then
          if lo >= bandLo and hi <= bandHi then return cx, cz, lo, hi, true end
          local err = math.max(bandLo - lo, 0) + math.max(hi - bandHi, 0)
          if not bestErr or err < bestErr then best, bestErr = { cx, cz, lo, hi }, err end
        end
      end
    end
  end
  if best then return best[1], best[2], best[3], best[4], false end
  return x, z, -1, -1, false
end

-- ------------------------------------------------------------------ sites
local BLUE, RED = country.id.USA, country.id.RUSSIA
local O_G, O_A = AI.Option.Ground, AI.Option.Air
local LAYOUT = {
  HAWK = { { "Hawk sr", 0, 0 }, { "Hawk tr", 120, 90 }, { "Hawk pcp", -120, 90 }, { "Hawk ln", 0, 220 },
           { "Hawk ln", 190, -110 }, { "Hawk ln", -190, -110 } },
  PATRIOT = { { "Patriot str", 0, 0 }, { "Patriot ECS", 120, 90 }, { "Patriot EPP", -120, 90 }, { "Patriot cp", 0, -150 },
              { "Patriot ln", 0, 230 }, { "Patriot ln", 200, -120 } },
  NASAMS = { { "NASAMS_Radar_MPQ64F1", 0, 0 }, { "NASAMS_Command_Post", 120, 90 }, { "NASAMS_LN_C", 0, 220 },
             { "NASAMS_LN_C", 190, -110 } },
}
-- weapons (CLSIDs from pydcs weapons_data / planes: the pylon lists differ per aircraft)
local KH58U_SU24 = "{FE382A68-8620-4AC0-BDF5-709BFE3977D7}"
local KH58U_SU25T = "{B5CA9846-776E-4230-B4FD-8BCC9BFB1676}"
local KH31P_SU34 = "{X-31P}"
local KH31P_SU24 = "{D8F2C90B-887B-4B9E-9FE2-996BC9E9AF03}"
local KH25MPU_SU25T = "{752AF1D2-EBCC-4bd7-A1E7-2357F5601C70}"
local LD10 = "DIS_LD-10"
local ARM_FLAG = 32768

local LANES = {
  { id = "L1", site = "HAWK", dx = -210000, ac = "Su-24M", n = 1, alt = 23000, fuel = 11700,
    pylons = { [2] = { CLSID = KH58U_SU24 }, [7] = { CLSID = KH58U_SU24 } }, task = "sead" },
  { id = "L2", site = "PATRIOT", dx = -140000, ac = "Su-34", n = 1, alt = 23000, fuel = 9800,
    pylons = { [3] = { CLSID = KH31P_SU34 }, [4] = { CLSID = KH31P_SU34 }, [8] = { CLSID = KH31P_SU34 }, [9] = { CLSID = KH31P_SU34 } },
    task = "sead" },
  { id = "L3", site = "PATRIOT", dx = -70000, ac = "Su-34", n = 1, alt = 23000, fuel = 9800,
    pylons = { [3] = { CLSID = KH31P_SU34 }, [4] = { CLSID = KH31P_SU34 }, [8] = { CLSID = KH31P_SU34 }, [9] = { CLSID = KH31P_SU34 } },
    task = "attack" },
  { id = "L4", site = "PATRIOT", dx = 0, ac = "Su-25T", n = 1, alt = 13000, fuel = 3790,
    pylons = { [3] = { CLSID = KH25MPU_SU25T }, [9] = { CLSID = KH25MPU_SU25T }, [5] = { CLSID = KH58U_SU25T },
               [7] = { CLSID = KH58U_SU25T } }, task = "sead", speed = 200 },
  { id = "L5", site = "HAWK", dx = 70000, ac = "Su-34", n = 1, alt = 23000, fuel = 9800,
    pylons = { [3] = { CLSID = KH31P_SU34 }, [8] = { CLSID = KH31P_SU34 } }, task = "sead", darkAfter = 20, hidden = true },
  { id = "L6", site = "NASAMS", dx = 140000, ac = "Su-24M", n = 1, alt = 20000, fuel = 11700,
    pylons = { [2] = { CLSID = KH31P_SU24 }, [7] = { CLSID = KH31P_SU24 } }, task = "sead" },
  { id = "L7", site = "PATRIOT", dx = 210000, ac = "JF-17", n = 1, alt = 20000, fuel = 2325,
    pylons = { [2] = { CLSID = LD10 }, [6] = { CLSID = LD10 } }, task = "sead" },
}
local laneByGroup = {}   -- group name (site, hidden Patriot, shooter) -> lane
local INLAND = 80000     -- sites this far east of the anchor
local START = 130000      -- shooters start this far east of their site

local function setGround(name, roe, emit)
  local g = Group.getByName(name)
  if not (g and g:isExist()) then return end
  local c = g:getController()
  c:setOption(O_G.id.ALARM_STATE, O_G.val.ALARM_STATE.RED)
  if roe then c:setOption(O_G.id.ROE, roe) end
  if emit ~= nil then g:enableEmission(emit) end
end

local function spawnSite(name, layout, x, z)
  local units = {}
  for i, u in ipairs(layout) do
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent", x = x + u[2], y = z + u[3], heading = 0 }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, BLUE, Group.Category.GROUND,
    { name = name, task = "Ground Nothing", units = units })
  return ok
end

local function placeLane(L)
  local layout = LAYOUT[L.site]
  local cx, cz, lo, hi, hit = findBand(x0 + L.dx, z0 + INLAND, layout, 0, 2, 20000)
  used[#used + 1] = { cx, cz }
  L.x, L.z = cx, cz
  L.siteName = string_format("PROBE %s %s", L.id, L.site)
  L.radar = L.siteName .. "-1"
  laneByGroup[L.siteName] = L
  local ok = spawnSite(L.siteName, layout, cx, cz)
  log(string_format("SPAWN %s at %.0f/%.0f km slopes %.2f-%.2f %s %s", L.siteName, (cx - x0) / 1000, (cz - z0) / 1000,
    lo, hi, hit and "flat" or "BAND-MISS", ok and "ok" or "FAILED"))
  if L.hidden then
    L.hiddenName = string_format("PROBE %s PATRIOT DARK", L.id)
    laneByGroup[L.hiddenName] = L
    local hx, hz = cx, cz - 6000
    local ok2 = spawnSite(L.hiddenName, LAYOUT.PATRIOT, hx, hz)
    log(string_format("SPAWN %s 6 km west of the Hawk, slope %.2f %s", L.hiddenName, slope(hx, hz), ok2 and "ok" or "FAILED"))
  end
  timer_schedule(function()
    safeCall("options " .. L.siteName, setGround, L.siteName, O_G.val.ROE.WEAPON_HOLD, true)
    if L.hiddenName then safeCall("options " .. L.hiddenName, setGround, L.hiddenName, O_G.val.ROE.WEAPON_HOLD, false) end
    return nil
  end, nil, timer_getTime() + 2)
end
for i, L in ipairs(LANES) do
  at(i, "site " .. L.id, function() placeLane(L) end)
end

-- ------------------------------------------------------------------ shooters
local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local function seadTasks()
  return { { id = "EngageTargets", enabled = true, auto = false, number = 1,
             params = { targetTypes = { "Air Defence" }, priority = 0 } } }
end
local function attackTasks(L)
  local g = Group.getByName(L.siteName)
  if not (g and g:isExist()) then log("no site group for " .. L.id); return {} end
  return { { id = "AttackGroup", enabled = true, auto = false, number = 1,
             params = { groupId = g:getID(), weaponType = ARM_FLAG, expend = "All", attackQtyLimit = false } } }
end

local function ammoText(u)
  local ok, ammo = pcall(function() return u:getAmmo() end)
  if not ok then return "?" end
  if not ammo then return "none" end
  local parts = {}
  for _, a in ipairs(ammo) do
    local d = a.desc or {}
    parts[#parts + 1] = string_format("%s x%d", tostring(d.typeName or d.displayName or "?"), a.count or 0)
  end
  return table.concat(parts, ", ")
end

local function spawnShooter(L)
  if not L.x then log("SHOOTER " .. L.id .. " skipped: no site"); return end
  L.shooter = string_format("PROBE %s %s", L.id, L.ac)
  laneByGroup[L.shooter] = L
  local alt, speed = L.alt * FT, L.speed or 230
  local sx, sz = L.x, L.z + START
  local units = {
    { name = L.shooter .. "-1", type = L.ac, skill = "Excellent", x = sx, y = sz, alt = alt, alt_type = "BARO",
      speed = speed, heading = math.atan2(L.z - sz, L.x - sx),
      payload = { pylons = L.pylons, fuel = L.fuel, chaff = 60, flare = 60, gun = 100 },
      callsign = { 1, 1, 1 }, onboard_num = "0" .. L.id:sub(2) } }
  local tasks = L.task == "attack" and attackTasks(L) or seadTasks()
  local ok = safeCall("spawn " .. L.shooter, coalition.addGroup, RED, Group.Category.AIRPLANE, {
    name = L.shooter, task = "SEAD", units = units,
    route = { points = { wp(sx, sz, alt, speed, tasks), wp(L.x, L.z, alt, speed), wp(L.x, L.z + START, alt, speed) } } })
  log(string_format("SPAWN %s (%s, %s task, %.0f ft, %.0f km east of %s) %s", L.shooter, L.ac, L.task, L.alt, START / 1000,
    L.siteName, ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. L.shooter, function()
      local g = Group.getByName(L.shooter)
      if not (g and g:isExist()) then log("SHOOTER " .. L.shooter .. " missing after spawn"); return end
      local c = g:getController()
      c:setOption(O_A.id.ROE, O_A.val.ROE.WEAPON_FREE)
      c:setOption(O_A.id.REACTION_ON_THREAT, O_A.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O_A.id.PROHIBIT_JETT, true)
      c:setOption(O_A.id.RTB_ON_OUT_OF_AMMO, false)
      local u = g:getUnit(1)
      log(string_format("AMMO %s at spawn: %s", L.shooter, u and ammoText(u) or "no unit"))
    end)
    return nil
  end, nil, timer_getTime() + 3)
end
for i, L in ipairs(LANES) do
  at(40 + i * 15, "shooter " .. L.id, function() spawnShooter(L) end)
end

-- ------------------------------------------------------------------ lane status every 15 s
local function status(_, t)
  safeCall("status", function()
    for _, L in ipairs(LANES) do
      local g = L.shooter and Group.getByName(L.shooter)
      local u = g and g:isExist() and g:getUnit(1)
      if u and u:isExist() and not L.gone then
        local p = u:getPoint()
        local radar = Unit.getByName(L.radar)
        local det = "radar gone"
        if radar and radar:isExist() then
          local okD, d, vis, _, typ, distKnown = pcall(function() return u:getController():isTargetDetected(radar) end)
          det = okD and string_format("detected=%s visible=%s type=%s dist=%s", tostring(d), tostring(vis), tostring(typ),
            tostring(distKnown)) or "isTargetDetected error"
        end
        local okR, on = pcall(function() return radar and radar:getRadar() end)
        log(string_format("STATUS %s shooter %.1f km from site, alt %.0f ft, ammo [%s]; site radar %s; %s", L.id,
          dist(p.x, p.z, L.x, L.z) / 1000, p.y / FT, ammoText(u), okR and (on and "tracking" or "on/idle") or "?", det))
      elseif L.shooter and not L.gone then
        L.gone = true
        log(string_format("STATUS %s shooter gone", L.id))
      end
    end
  end)
  return t + 15
end
timer_schedule(status, nil, T0 + 75)

-- ------------------------------------------------------------------ ARM flights
local flights = {}   -- { w, lane, t0, minD, last, name }
local function trackFlights(_, t)
  safeCall("flights", function()
    for i = #flights, 1, -1 do
      local f = flights[i]
      local okE, ex = pcall(function() return f.w:isExist() end)
      local radar = Unit.getByName(f.lane.radar)
      local rp = f.rp
      if radar and radar:isExist() then rp = radar:getPoint(); f.rp = rp end
      if okE and ex then
        local p = f.w:getPoint()
        f.last = p
        if rp then
          local d = dist(p.x, p.z, rp.x, rp.z)
          if not f.minD or d < f.minD then f.minD = d end
        end
      else
        local lp = f.last
        log(string_format("ARM END %s %s after %.1f s: closest %.0f m to %s, last point %.0f m from it, radar %s", f.lane.id,
          f.name, now() - f.t0, f.minD or -1, f.lane.radar, (lp and rp) and dist(lp.x, lp.z, rp.x, rp.z) or -1,
          (radar and radar:isExist()) and "alive" or "gone"))
        table.remove(flights, i)
      end
    end
  end)
  return t + 1
end
timer_schedule(trackFlights, nil, T0 + 60)

local function onArmLaunch(L)
  if L.firstArm then return end
  L.firstArm = now()
  if L.hiddenName then
    safeCall("hidden up", setGround, L.hiddenName, O_G.val.ROE.OPEN_FIRE, true)
    log(string_format("LANE %s ARM launched: %s radar ON, weapons free", L.id, L.hiddenName))
  end
  if L.darkAfter then
    timer_schedule(function()
      safeCall("dark", function()
        local g = Group.getByName(L.siteName)
        if g and g:isExist() then g:enableEmission(false) end
        log(string_format("LANE %s %s DARK %d s after the first ARM launch", L.id, L.siteName, L.darkAfter))
      end)
      return nil
    end, nil, timer_getTime() + L.darkAfter)
  end
end

-- ------------------------------------------------------------------ events
local function wrapHandler(fn)
  return function(...)
    local args, n = { ... }, select("#", ...)
    safeCall("handler", function() return fn(unpack(args, 1, n)) end)
  end
end
local handler = {}
handler.onEvent = wrapHandler(function(_, e)
  do
    if e.id == world.event.S_EVENT_SHOT then
      local w = e.weapon
      local g = groupOf(e.initiator)
      local L = laneByGroup[g]
      local okT, tgt = pcall(function() return w:getTarget() end)
      tgt = okT and tgt or nil
      local okD, desc = pcall(function() return w:getDesc() end)
      local guid = okD and desc and desc.guidance
      local sp = e.initiator and e.initiator:getPoint()
      local tp = tgt and tgt:getPoint()
      log(string_format("SHOT lane=%s group=%s (%s) weapon=%s guidance=%s target=%s (%s) range=%.1f km alt=%.0f ft",
        L and L.id or "-", g, safeType(e.initiator), safeType(w), tostring(guid), safeName(tgt), safeType(tgt),
        (sp and tp) and dist(sp.x, sp.z, tp.x, tp.z) / 1000 or -1, sp and sp.y / FT or -1))
      if L and g == L.shooter and guid == Weapon.GuidanceType.RADAR_PASSIVE then
        flights[#flights + 1] = { w = w, lane = L, t0 = now(), name = safeType(w) }
        onArmLaunch(L)
      end
    elseif e.id == world.event.S_EVENT_HIT then
      local tg = groupOf(e.target)
      if laneByGroup[tg] or laneByGroup[groupOf(e.initiator)] then
        log(string_format("HIT %s by %s weapon=%s", safeName(e.target), safeName(e.initiator), safeType(e.weapon)))
      end
    elseif e.id == world.event.S_EVENT_DEAD or e.id == world.event.S_EVENT_UNIT_LOST then
      if safeCat(e.initiator) == Object.Category.UNIT and laneByGroup[groupOf(e.initiator)] then
        log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
      end
    end
  end
end)
world.addEventHandler(handler)

local ENDT = 1500
at(ENDT, "END: probe run 8 complete at 25 min", function()
  for _, L in ipairs(LANES) do
    log(string_format("LANE SUMMARY %s %s <- %s: first ARM launch %s", L.id, L.site, L.ac,
      L.firstArm and string_format("t=%.0f", L.firstArm) or "none"))
  end
end)
log(string_format("probe run 8 %s loaded: %d lanes, end t=%d s", P.VERSION, #LANES, ENDT))
