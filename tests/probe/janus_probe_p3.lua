-- Janus IADS - probe run 7 (JANUS_PROBE_P3.miz). Plain DCS, NO janus.lua. Records to dcs.log as "JANUS_PROBE".
-- Lua 5.1, sanitized, one global (JANUS).
--
-- Part A  LEVEL LADDER, round 2 (run 6 left these open):
--           SA-5 (S-200, 255 km reach - never used in a Janus bench yet): flat control, 2.5-3.5, 4.5-6.5, >= 10 deg.
--             SA-5 targets start 100 km out at 25,000 ft and each SA-5 window lasts 460 s.
--           SA-3 and SA-10 between their run-6 "fires" (5 deg) and "mute" (12 deg): band 6.5-9.5 deg.
--         One site at a time is weapons free for its window while 2 unarmed Su-24M fly straight over it from the north.
-- Part C  STATICS: .Command Center (run 6 never blasted it) and Shelter (survived 3000 kg) hit with rising
--         explosions up to 9 x 3000 kg; events vs a 2 s poll as in run 6.
-- Part B of run 6 (identification) is not repeated.

JANUS = JANUS or {}
JANUS.probe = JANUS.probe or {}
local P = JANUS.probe
P.VERSION = "0.8.0-p3"

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
local function safeCatEx(o)
  if o == nil then return "nil" end
  local ok, c = pcall(function() return o:getCategoryEx() end)
  return ok and tostring(c) or "none"
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

-- ------------------------------------------------------------------ part A: level ladder
local BLUE, RED = country.id.USA, country.id.RUSSIA
local O_G = AI.Option.Ground
local LAYOUT = {
  SA2 = { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 150, 0 }, { "S_75M_Volhov", 0, 220 }, { "S_75M_Volhov", 190, -110 },
          { "S_75M_Volhov", -190, -110 } },
  HAWK = { { "Hawk sr", 0, 0 }, { "Hawk tr", 120, 90 }, { "Hawk pcp", -120, 90 }, { "Hawk ln", 0, 220 },
           { "Hawk ln", 190, -110 }, { "Hawk ln", -190, -110 } },
  SA3 = { { "snr s-125 tr", 0, 0 }, { "p-19 s-125 sr", 150, 0 }, { "5p73 s-125 ln", 0, 200 }, { "5p73 s-125 ln", 170, -100 },
          { "5p73 s-125 ln", -170, -100 } },
  SA6 = { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 0, 200 }, { "Kub 2P25 ln", 170, -100 }, { "Kub 2P25 ln", -170, -100 } },
  SA11 = { { "SA-11 Buk SR 9S18M1", 0, 0 }, { "SA-11 Buk CC 9S470M1", 120, 0 }, { "SA-11 Buk LN 9A310M1", 0, 200 },
           { "SA-11 Buk LN 9A310M1", 170, -100 }, { "SA-11 Buk LN 9A310M1", -170, -100 } },
  SA10 = { { "S-300PS 40B6M tr", 0, 0 }, { "S-300PS 64H6E sr", 150, 100 }, { "S-300PS 54K6 cp", -150, 100 },
           { "S-300PS 5P85C ln", 0, 230 }, { "S-300PS 5P85C ln", 200, -120 }, { "S-300PS 5P85C ln", -200, -120 } },
  SA5 = { { "RPC_5N62V", 0, 0 }, { "RLS_19J6", 300, 0 }, { "S-200_Launcher", 0, 150 }, { "S-200_Launcher", 130, 75 },
          { "S-200_Launcher", 130, -75 }, { "S-200_Launcher", 0, -150 }, { "S-200_Launcher", -130, -75 }, { "S-200_Launcher", -130, 75 } },
  PATRIOT = { { "Patriot str", 0, 0 }, { "Patriot ECS", 120, 90 }, { "Patriot EPP", -120, 90 }, { "Patriot cp", 0, -150 },
              { "Patriot ln", 0, 230 }, { "Patriot ln", 200, -120 } },
}
-- region centres (terrain): L = Alawite hills east of the anchor (moderate slopes), N = Nur mountains (steep)
local REGION = { L = { x0 + 10000, z0 + 30000 }, N = { x0 + 100000, z0 + 60000 } }
local LADDER = {
  { id = "M01", sys = "SA5",  lo = 0,   hi = 1.2, reg = "L", win = 460, start = 100000, alt = 25000 },
  { id = "M02", sys = "SA5",  lo = 2.5, hi = 3.5, reg = "L", win = 460, start = 100000, alt = 25000 },
  { id = "M03", sys = "SA5",  lo = 4.5, hi = 6.5, reg = "L", win = 460, start = 100000, alt = 25000 },
  { id = "M04", sys = "SA5",  lo = 10,  hi = 45,  reg = "N", win = 460, start = 100000, alt = 25000 },
  { id = "M05", sys = "SA3",  lo = 6.5, hi = 9.5, reg = "L", reg2 = "N" },
  { id = "M06", sys = "SA10", lo = 6.5, hi = 9.5, reg = "L", reg2 = "N" },
}
local WINDOW_START, WINDOW_LEN = 120, 190
local shotsBy = {}        -- group name -> shots fired

local function setGroundOptions(name, roe)
  local g = Group.getByName(name)
  if not (g and g:isExist()) then return end
  local c = g:getController()
  c:setOption(O_G.id.ALARM_STATE, O_G.val.ALARM_STATE.RED)
  c:setOption(O_G.id.ROE, roe)
end

local function spawnLadderSite(s)
  local layout = LAYOUT[s.sys]
  local r = REGION[s.reg]
  local cx, cz, lo, hi, hit = findBand(r[1], r[2], layout, s.lo, s.hi, 6000)
  if not hit and s.reg2 then
    local r2 = REGION[s.reg2]
    local cx2, cz2, lo2, hi2, hit2 = findBand(r2[1], r2[2], layout, s.lo, s.hi, 6000)
    if hit2 then cx, cz, lo, hi, hit = cx2, cz2, lo2, hi2, hit2 end
  end
  used[#used + 1] = { cx, cz }
  s.x, s.z = cx, cz
  s.name = string_format("PROBE %s %s %g-%g", s.id, s.sys, s.lo, s.hi)
  local units = {}
  for i, u in ipairs(layout) do
    local ux, uz = cx + u[2], cz + u[3]
    units[i] = { name = s.name .. "-" .. i, type = u[1], skill = "Excellent", x = ux, y = uz, heading = 0 }
    log(string_format("UNIT %s %s slope %.2f deg height %.0f m", units[i].name, u[1], slope(ux, uz), hgt(ux, uz)))
  end
  local ok = safeCall("spawn " .. s.name, coalition.addGroup, BLUE, Group.Category.GROUND,
    { name = s.name, task = "Ground Nothing", units = units })
  log(string_format("SPAWN %s at %.0f/%.0f unit slopes %.2f-%.2f deg band %g-%g %s %s", s.name, cx - x0, cz - z0,
    lo, hi, s.lo, s.hi, hit and "IN-BAND" or "BAND-MISS", ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. s.name, setGroundOptions, s.name, O_G.val.ROE.WEAPON_HOLD)
    return nil
  end, nil, timer_getTime() + 2)
end
-- one site per second so the terrain searches never stall the server
for i, s in ipairs(LADDER) do
  at(i, "ladder spawn " .. s.id, function() spawnLadderSite(s) end)
end

local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local function passive(name)
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
-- n unarmed jets of `acType` flying a straight line from (sx, sz) to (ex, ez)
local function jets(coa, cty, name, acType, n, sx, sz, ex, ez, alt, speed)
  local hdg = math.atan2(ez - sz, ex - sx)
  local units = {}
  for i = 1, n do
    units[i] = { name = name .. "-" .. i, type = acType, skill = "High",
      x = sx - (i - 1) * 2000 * math_cos(hdg), y = sz - (i - 1) * 2000 * math_sin(hdg) + (i - 1) * 1500,
      alt = alt, alt_type = "BARO", speed = speed, heading = hdg,
      payload = { pylons = {}, fuel = 9000, chaff = 0, flare = 0, gun = 0 }, callsign = { 1, 1, i }, onboard_num = "0" .. i }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, cty,
    Group.Category.AIRPLANE, { name = name, task = "CAP", units = units,
      route = { points = { wp(sx, sz, alt, speed), wp(ex, ez, alt, speed) } } })
  log(string_format("SPAWN %s (%dx %s, %.0f ft, coalition %d) %s", name, n, acType, alt / FT, coa, ok and "ok" or "FAILED"))
  passive(name)
end

local function openWindow(s)
  if not s.name then log("WINDOW " .. s.id .. " skipped: site never spawned"); return end
  s.shots0 = shotsBy[s.name] or 0
  setGroundOptions(s.name, O_G.val.ROE.OPEN_FIRE)
  log(string_format("WINDOW OPEN %s", s.name))
  -- targets start 35 km north (SA-5: 100 km), pass overhead, end 40 km south
  local start = s.start or 35000
  jets(coalition.side.RED, RED, "PROBE TGT " .. s.id, "Su-24M", 2, s.x + start, s.z, s.x - 40000, s.z, (s.alt or 15000) * FT, 220)
end
local function closeWindow(s)
  if not s.name then return end
  setGroundOptions(s.name, O_G.val.ROE.WEAPON_HOLD)
  local fired = (shotsBy[s.name] or 0) - (s.shots0 or 0)
  log(string_format("WINDOW END %s shots=%d verdict=%s", s.name, fired, fired > 0 and "FIRES" or "MUTE"))
  local g = Group.getByName("PROBE TGT " .. s.id)
  if g and g:isExist() then g:destroy() end
end
local tw = WINDOW_START
for _, s in ipairs(LADDER) do
  s.win = s.win or WINDOW_LEN
  s.t0 = tw
  at(tw, "window " .. s.id, function() openWindow(s) end)
  at(tw + s.win - 5, "window end " .. s.id, function() closeWindow(s) end)
  tw = tw + s.win
end

-- ------------------------------------------------------------------ flat spots for parts B and C
local function flatSpot(x, z, minSep)
  local one = { { "x", 0, 0 }, { "x", 300, 0 }, { "x", -300, 0 }, { "x", 0, 300 }, { "x", 0, -300 } }
  local cx, cz, lo, hi = findBand(x, z, one, 0, 1.5, minSep)
  used[#used + 1] = { cx, cz }
  return cx, cz, lo, hi
end

local EWC = { x0 - 150000, z0 + 170000 }   -- flat desert used for the statics (run 6)

-- ------------------------------------------------------------------ part C: statics
-- static command posts, radios and power (type, category, shape as the DCS static list gives them) + two command
-- vehicles as controls. Placed on flat ground 25 km south of the EW cluster, 250 m apart.
local STATICS = {
  { ".Command Center", "Fortifications", "ComCenter" },
  { "Shelter", "Fortifications", "ukrytie" },
}
local CMD_VEHICLES = {}
local watched = {}        -- { name, kind = "static"|"unit", x, z, alive, life }
local watchedByName = {}
local sx0, sz0
at(8, "statics", function()
  sx0, sz0 = flatSpot(EWC[1] - 25000, EWC[2], 3000)
  for i, s in ipairs(STATICS) do
    local name = string_format("PROBE ST %d %s", i, s[1])
    local x, z = sx0 + (i - 1) * 250, sz0
    local ok = safeCall("spawn " .. name, coalition.addStaticObject, BLUE,
      { name = name, type = s[1], category = s[2], shape_name = s[3], x = x, y = z, heading = 0 })
    log(string_format("SPAWN %s (%s, %s) slope %.2f %s", name, s[1], s[2], slope(x, z), ok and "ok" or "FAILED"))
    local w = { name = name, kind = "static", x = x, z = z }
    watched[#watched + 1] = w; watchedByName[name] = w
  end
  for i, t in ipairs(CMD_VEHICLES) do
    local name = string_format("PROBE CV %d %s", i, t)
    local x, z = sx0 + (i - 1) * 250, sz0 + 400
    local ok = safeCall("spawn " .. name, coalition.addGroup, BLUE, Group.Category.GROUND,
      { name = name, task = "Ground Nothing", units = { { name = name .. "-1", type = t, skill = "Excellent", x = x, y = z, heading = 0 } } })
    log(string_format("SPAWN %s %s", name, ok and "ok" or "FAILED"))
    local w = { name = name .. "-1", kind = "unit", x = x, z = z }
    watched[#watched + 1] = w; watchedByName[w.name] = w
  end
end)

local function objOf(w)
  if w.kind == "static" then return StaticObject.getByName(w.name) end
  return Unit.getByName(w.name)
end
local function lifeOf(o)
  local ok, l = pcall(function() return o:getLife() end)
  return ok and l or -1
end
local function exists(o)
  if not o then return false end
  local ok, e = pcall(function() return o:isExist() end)
  return ok and e and true or false
end
-- what the static API sees: coalition.getStaticObjects, category, getCategoryEx, desc life
at(15, "static API", function()
  local list = coalition.getStaticObjects(coalition.side.BLUE) or {}
  local n = 0
  for _, o in ipairs(list) do
    local name = safeName(o)
    if name:find("^PROBE ST") then
      n = n + 1
      local ok, desc = pcall(function() return o:getDesc() end)
      log(string_format("STATIC %s type=%s category=%d categoryEx=%s life=%.1f descLife=%s coalition=%s", name, safeType(o),
        safeCat(o), safeCatEx(o), lifeOf(o), ok and desc and tostring(desc.life) or "?", tostring(o:getCoalition())))
    end
  end
  log(string_format("STATIC coalition.getStaticObjects(BLUE) lists %d probe statics of %d spawned", n, #STATICS))
  for _, w in ipairs(watched) do
    local o = objOf(w)
    w.alive, w.life = exists(o), o and lifeOf(o) or -1
    log(string_format("STATIC getByName %s found=%s exist=%s life=%.1f", w.name, tostring(o ~= nil), tostring(w.alive), w.life))
  end
end)

-- explosions of rising power at each object until it dies (objects staggered 30 s apart, steps 20 s apart)
local POWER = { 20, 60, 150, 400, 1000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000, 3000 }
local function blast(w, step)
  local o = objOf(w)
  if step > #POWER or not exists(o) or lifeOf(o) <= 0 then
    log(string_format("BLAST %s done after %d step(s): exist=%s life=%.1f", w.name, step - 1, tostring(exists(o)),
      o and lifeOf(o) or -1))
    return
  end
  local p = { x = w.x, y = hgt(w.x, w.z) + 2, z = w.z }
  trigger.action.explosion(p, POWER[step])
  log(string_format("BLAST %s step %d power %d", w.name, step, POWER[step]))
  timer_schedule(function()
    safeCall("blast after " .. w.name, function()
      local o2 = objOf(w)
      log(string_format("BLAST %s after power %d: exist=%s life=%.1f", w.name, POWER[step], tostring(exists(o2)),
        o2 and lifeOf(o2) or -1))
    end)
    return nil
  end, nil, timer_getTime() + 3)
  timer_schedule(function() safeCall("blast " .. w.name, blast, w, step + 1); return nil end, nil, timer_getTime() + 20)
end
at(200, "static blasts", function()
  for i, w in ipairs(watched) do
    timer_schedule(function() safeCall("blast " .. w.name, blast, w, 1); return nil end, nil, timer_getTime() + 1 + (i - 1) * 30)  -- run 6: a timer at exactly 'now' never ran
  end
end)

-- 2 s poll: log every change of exist / life for the watched objects (compared with the events below)
local function poll(_, t)
  safeCall("poll", function()
    for _, w in ipairs(watched) do
      local o = objOf(w)
      local e, l = exists(o), o and lifeOf(o) or -1
      if w.alive ~= nil and (e ~= w.alive or math.abs(l - (w.life or l)) > 0.01) then
        log(string_format("POLL %s exist %s->%s life %.1f->%.1f found=%s", w.name, tostring(w.alive), tostring(e),
          w.life or -1, l, tostring(o ~= nil)))
      end
      w.alive, w.life = e, l
    end
  end)
  return t + 2
end
timer_schedule(poll, nil, T0 + 20)

-- ------------------------------------------------------------------ events
local EVNAME = {}
for k, v in pairs(world.event) do EVNAME[v] = k end
local function probeObject(o)
  if o == nil then return false end
  local n = safeName(o)
  return n:find("^PROBE ST") ~= nil or n:find("^PROBE CV") ~= nil or watchedByName[n] ~= nil
end
local function wrapHandler(fn)
  return function(...)
    local args, n = { ... }, select("#", ...)
    safeCall("handler", function() return fn(unpack(args, 1, n)) end)
  end
end
local handler = {}
handler.onEvent = wrapHandler(function(_, e)
  if e.id == world.event.S_EVENT_SHOT then
    local w = e.weapon
    local tgt = w and w.getTarget and w:getTarget() or nil
    local g = groupOf(e.initiator)
    shotsBy[g] = (shotsBy[g] or 0) + 1
    log(string_format("SHOT group=%s shooter=%s (%s) weapon=%s target=%s", g, safeName(e.initiator),
      safeType(e.initiator), safeType(w), safeName(tgt)))
    return
  end
  -- every event about a probe static or command vehicle, whatever its id
  if probeObject(e.initiator) or probeObject(e.target) then
    log(string_format("EVENT %s(%d) initiator=%s cat=%d catEx=%s target=%s cat=%d", EVNAME[e.id] or "?", e.id,
      safeName(e.initiator), safeCat(e.initiator), safeCatEx(e.initiator), safeName(e.target), safeCat(e.target)))
    return
  end
  if e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
    log(string_format("HIT shooter=%s weapon=%s target=%s", safeType(e.initiator), safeType(e.weapon), safeName(e.target)))
  elseif e.id == world.event.S_EVENT_DEAD and safeCat(e.initiator) == Object.Category.UNIT then
    log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
  end
end)
world.addEventHandler(handler)

-- status of the open ladder site every 30 s: detections, radars on / tracking, nearest target
local function status(_, t)
  safeCall("status", function()
    local tm = now()
    for _, s in ipairs(LADDER) do
      local ws = s.t0
      if s.name and tm >= ws and tm < ws + s.win then
        local g = Group.getByName(s.name)
        if g and g:isExist() then
          local dets = g:getController():getDetectedTargets() or {}
          local radars = {}
          for _, u in ipairs(g:getUnits() or {}) do
            local ok, on, tracked = pcall(u.getRadar, u)
            if ok and on then radars[#radars + 1] = safeType(u) .. (tracked and "*" or "") end
          end
          local best
          local tg = Group.getByName("PROBE TGT " .. s.id)
          if tg and tg:isExist() then
            for _, u in ipairs(tg:getUnits() or {}) do
              local p = u:getPoint()
              local d = dist(p.x, p.z, s.x, s.z) / 1852
              if not best or d < best then best = d end
            end
          end
          log(string_format("STATUS %s detected=%d radars=[%s] nearestTgt=%s nm", s.id, #dets, table.concat(radars, ","),
            best and string_format("%.1f", best) or "-"))
        end
      end
    end
  end)
  return t + 30
end
timer_schedule(status, nil, T0 + WINDOW_START + 10)

local ENDT = tw + 120
at(ENDT, string_format("END: probe run 7 complete at %d min", math.floor(ENDT / 60 + 0.5)), function() end)
log(string_format("probe run 7 %s loaded: %d ladder sites, %d statics, end t=%d s", P.VERSION, #LADDER, #STATICS, ENDT))
