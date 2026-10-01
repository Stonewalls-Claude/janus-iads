-- Janus IADS - bench 05 (Phase 3 gate): ARM defence on a full network, both directions.
-- Gate (DESIGN 9): HARM defence works on the full bench (repeated runs): crews notice ARMs only through the
-- awareness model, targeted radars go dark for the estimated time to impact and come back, point defence stays up
-- and engages, suppression (emitting time lost) and ARM hits are recorded; no Janus errors.
-- Load order in JANUS_BENCH_05.miz: THIS file (spawns everything, sets JANUS_SETTINGS) -> janus.lua.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [arm]" / "[emcon]" / "[wta]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- RED (SOVIET_PVO_1985; anchor C = +170 km N, +90 km E), all SAMs flat:
--   CMD Bunker North (static .Command Center), EW East (55G6) 30 km E,
--   SAM SA-10 Centre 15 km S with PD Tor Centre 2 km away, SAM SA-11 South 40 km S, SAM SA-6 East 20 km S / 40 km E,
--   SAM SA-2 West 20 km S / 30 km W (tier C: learns of ARMs only over the network or by eye).
--   blue bait (2x unarmed F-16C, weapons hold) at t=60 and t=540 through the triangle, so the SAMs come up;
--   blue SEAD (2x F-16C, 4x AGM-88C each, SEAD task) at t=150 and t=630 behind the bait;
--   blue Shrike (1x F-4E, 2x AGM-45A, SEAD task) at t=300 at the SA-2 (smoky motor: the eyes cue).
-- BLUE (US_MODERN; anchor B = -150 km N, +60 km E):
--   CMD South, EW South (FPS-117), SAM Patriot 40 km E, SAM Hawk 60 km E / 20 km N (flat).
--   red bait (2x unarmed Su-24M) at t=90 and t=570; red SEAD (1x Su-34, 4x Kh-31P, SEAD task) at t=180 and t=660
--   (probe run 8: the Su-34 fires Kh-31P at Hawk and Patriot radars from ~85 km).
-- Recorded: every SHOT / HIT / DEAD, every ARM's end (closest approach to a radar of the other side), and every
-- 30 s each radar node's EMCON and ARM state; at the end Janus's own ARM statistics.

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.5.0"

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

-- ------------------------------------------------------------------ anchor, terrain
local AP
for _, ab in ipairs(world.getAirbases() or {}) do
  local n = ab:getName() or ""
  if n:find("Assad") or n:find("Latakia") then AP = ab:getPoint(); break end
end
if not AP then env_error(TAG .. " no anchor airbase (Syria map?)"); return end
local x0, z0 = AP.x, AP.z

local function heightAt(x, z) return land.getHeight({ x = x, y = z }) end
local function slope(x, z)
  local d = 30
  local gx = (heightAt(x + d, z) - heightAt(x - d, z)) / (2 * d)
  local gz = (heightAt(x, z + d) - heightAt(x, z - d)) / (2 * d)
  return math.deg(math.atan(math.sqrt(gx * gx + gz * gz)))
end
-- flattest land spot near (x, z): worst slope over a ring of r metres (runs 4-6: SAMs on flat ground)
local function findFlat(x, z, r)
  local bx, bz, bs
  for ring = 0, 16 do
    local n = ring == 0 and 1 or ring * 6
    for i = 1, n do
      local a = (i / n) * 2 * math.pi
      local cx, cz = x + ring * 1500 * math_cos(a), z + ring * 1500 * math_sin(a)
      local ok, st = pcall(land.getSurfaceType, { x = cx, y = cz })
      if ok and st == land.SurfaceType.LAND then
        local s = slope(cx, cz)
        for k = 0, 7 do
          local b = k * math.pi / 4
          local s2 = slope(cx + r * math_cos(b), cz + r * math_sin(b))
          if s2 > s then s = s2 end
        end
        if not bs or s < bs then bx, bz, bs = cx, cz, s end
        if bs < 0.8 then return bx, bz, bs end
      end
    end
  end
  return bx or x, bz or z, bs or -1
end

-- ------------------------------------------------------------------ spawning
local RED_C, BLUE_C = country.id.RUSSIA, country.id.USA
local POS = {}
local function ground(side, name, x, z, list, flatR)
  local cx, cz, s = findFlat(x, z, flatR or 450)
  local units, worst = {}, 0
  for i = 1, #list do
    local u = list[i]
    local us = slope(cx + u[2], cz + u[3])
    if us > worst then worst = us end
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent", x = cx + u[2], y = cz + u[3], heading = math_rad(0) }
  end
  local ok = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } } })
  POS[name] = { cx, cz }
  log(string_format("SPAWN %s (%d units) at %.0f/%.0f worst slope %.2f deg %s", name, #units, cx - x0, cz - z0, worst,
    ok and "ok" or "FAILED"))
  return s
end
-- static command posts, radios and power (probe run 6 types)
local SHAPE = { [".Command Center"] = "ComCenter", ["Military staff"] = "aviashtab", ["Comms tower M"] = "tele_bash_m",
                ["TV tower"] = "tele_bash", ["GeneratorF"] = "GeneratorF" }
local function static(side, name, typ, x, z)
  local cx, cz = findFlat(x, z, 50)
  local ok = safeCall("spawn " .. name, coalition.addStaticObject, side,
    { name = name, type = typ, category = "Fortifications", shape_name = SHAPE[typ], x = cx, y = cz, heading = 0 })
  POS[name] = { cx, cz }
  log(string_format("SPAWN static %s (%s) at %.0f/%.0f %s", name, typ, cx - x0, cz - z0, ok and "ok" or "FAILED"))
end

-- red
local Cx, Cz = x0 + 170000, z0 + 90000
static(RED_C, "CMD Bunker North", ".Command Center", Cx, Cz)
ground(RED_C, "EW East", Cx, Cz + 30000, { { "55G6 EWR", 0, 0 } }, 50)
ground(RED_C, "SAM SA-10 Centre", Cx - 15000, Cz, { { "S-300PS 40B6M tr", 0, 0 }, { "S-300PS 64H6E sr", 150, 100 },
  { "S-300PS 54K6 cp", -150, 100 }, { "S-300PS 5P85C ln", 0, 230 }, { "S-300PS 5P85C ln", 200, -120 }, { "S-300PS 5P85C ln", -200, -120 } })
ground(RED_C, "PD Tor Centre", POS["SAM SA-10 Centre"][1] + 2000, POS["SAM SA-10 Centre"][2] + 2000, { { "Tor 9A331", 0, 0 } }, 50)
ground(RED_C, "SAM SA-11 South", Cx - 40000, Cz + 10000, { { "SA-11 Buk SR 9S18M1", 0, 0 }, { "SA-11 Buk CC 9S470M1", 120, 0 },
  { "SA-11 Buk LN 9A310M1", 0, 200 }, { "SA-11 Buk LN 9A310M1", 170, -100 }, { "SA-11 Buk LN 9A310M1", -170, -100 } })
ground(RED_C, "SAM SA-6 East", Cx - 20000, Cz + 40000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 0, 200 },
  { "Kub 2P25 ln", 170, -100 }, { "Kub 2P25 ln", -170, -100 } })
ground(RED_C, "SAM SA-2 West", Cx - 20000, Cz - 30000, { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 150, 0 },
  { "S_75M_Volhov", 0, 220 }, { "S_75M_Volhov", 190, -110 }, { "S_75M_Volhov", -190, -110 } })

-- blue
local Bx, Bz = x0 - 150000, z0 + 60000
ground(BLUE_C, "CMD South", Bx, Bz, { { "MLRS FDDM", 0, 0 } }, 50)
ground(BLUE_C, "EW South", Bx, Bz + 15000, { { "FPS-117", 0, 0 } }, 50)
ground(BLUE_C, "SAM Patriot", Bx, Bz + 40000, { { "Patriot str", 0, 0 }, { "Patriot ECS", 120, 90 }, { "Patriot EPP", -120, 90 },
  { "Patriot cp", 0, -150 }, { "Patriot ln", 0, 230 }, { "Patriot ln", 200, -120 } })
ground(BLUE_C, "SAM Hawk", Bx + 20000, Bz + 60000, { { "Hawk sr", 0, 0 }, { "Hawk tr", 120, 90 }, { "Hawk pcp", -120, 90 },
  { "Hawk ln", 0, 220 }, { "Hawk ln", 190, -110 }, { "Hawk ln", -190, -110 } })

-- ------------------------------------------------------------------ aircraft
local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local O = AI.Option.Air
-- armed = true: weapons free, SEAD + EngageTargets "Air Defence"; false: weapons hold (bait)
local function air(side, name, acType, fuel, count, route, alt, pylons, armed)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = acType, skill = "Excellent",
      x = route[1][1] - (i - 1) * 1500 * math_cos(h), y = route[1][2] - (i - 1) * 1500 * math_sin(h) + (i - 1) * 800,
      alt = alt, alt_type = "BARO", speed = 220, heading = h,
      payload = { pylons = pylons or {}, fuel = fuel, chaff = 60, flare = 60, gun = 0 }, callsign = { 1, 1, i },
      onboard_num = tostring(500 + i) }
  end
  local tasks1 = armed and { { id = "EngageTargets", enabled = true, auto = false, number = 1,
    params = { targetTypes = { "Air Defence" }, priority = 0 } } } or nil
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, 220, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.AIRPLANE,
    { name = name, task = armed and "SEAD" or "CAP", units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s, %s) %s", name, count, acType, armed and "SEAD" or "bait", ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      c:setOption(O.id.ROE, armed and O.val.ROE.WEAPON_FREE or O.val.ROE.WEAPON_HOLD)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
      local u = g:getUnit(1)
      local ok2, ammo = false, nil
      if u then ok2, ammo = pcall(function() return u:getAmmo() end) end
      local parts = {}
      for _, a in ipairs(ok2 and ammo or {}) do
        parts[#parts + 1] = string_format("%s x%d", tostring(a.desc and a.desc.typeName), a.count or 0)
      end
      log(string_format("AMMO %s: %s", name, #parts > 0 and table.concat(parts, ", ") or "none"))
    end)
    return nil
  end, nil, timer_getTime() + 3)
end

local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local AGM45A = "{AGM_45A}"
local KH31P = "{X-31P}"
local s10 = POS["SAM SA-10 Centre"]
local tri = function(dx)
  return { { s10[1] - 130000 + dx, s10[2] - 40000 }, { s10[1] - 20000 + dx, s10[2] + 15000 },
           { s10[1] + 40000, s10[2] + 90000 }, { s10[1] + 60000, s10[2] + 160000 } }
end
local sead = function(dx)   -- SEAD F-16s come in from the south-west and turn back after the weapons are gone
  return { { s10[1] - 150000 + dx, s10[2] - 50000 }, { s10[1] - 60000 + dx, s10[2] - 10000 }, { s10[1] - 150000 + dx, s10[2] - 50000 } }
end
local sa2 = POS["SAM SA-2 West"]
local shrike = { { sa2[1] - 120000, sa2[2] - 20000 }, { sa2[1] - 30000, sa2[2] - 5000 }, { sa2[1] - 120000, sa2[2] - 20000 } }
local HARMS = { [3] = { CLSID = AGM88C }, [4] = { CLSID = AGM88C }, [6] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }
at(60, "blue bait 1: 2x F-16C through the red triangle", function() air(BLUE_C, "Blue Bait 1", "F-16C_50", 3249, 2, tri(0), 18000 * FT) end)
at(150, "blue SEAD 1: 2x F-16C 4x AGM-88C", function() air(BLUE_C, "Blue SEAD 1", "F-16C_50", 3249, 2, sead(0), 22000 * FT, HARMS, true) end)
at(300, "blue Shrike: 1x F-4E 2x AGM-45A at the SA-2", function()
  air(BLUE_C, "Blue Shrike", "F-4E", 4864, 1, shrike, 18000 * FT, { [2] = { CLSID = AGM45A }, [8] = { CLSID = AGM45A } }, true)
end)
at(540, "blue bait 2", function() air(BLUE_C, "Blue Bait 2", "F-16C_50", 3249, 2, tri(-8000), 15000 * FT) end)
at(630, "blue SEAD 2", function() air(BLUE_C, "Blue SEAD 2", "F-16C_50", 3249, 2, sead(10000), 22000 * FT, HARMS, true) end)

local pat = POS["SAM Patriot"]
local overlap = function()
  return { { pat[1] + 150000, pat[2] + 120000 }, { pat[1] + 10000, pat[2] + 15000 }, { pat[1] - 120000, pat[2] - 40000 } }
end
local redSead = function()
  return { { pat[1] + 170000, pat[2] + 110000 }, { pat[1] + 60000, pat[2] + 40000 }, { pat[1] + 170000, pat[2] + 110000 } }
end
local KH31 = { [3] = { CLSID = KH31P }, [4] = { CLSID = KH31P }, [8] = { CLSID = KH31P }, [9] = { CLSID = KH31P } }
at(90, "red bait 1: 2x Su-24M over the Patriot / Hawk", function() air(RED_C, "Red Bait 1", "Su-24M", 9000, 2, overlap(), 15000 * FT) end)
at(180, "red SEAD 1: 1x Su-34 4x Kh-31P", function() air(RED_C, "Red SEAD 1", "Su-34", 9800, 1, redSead(), 23000 * FT, KH31, true) end)
at(570, "red bait 2", function() air(RED_C, "Red Bait 2", "Su-24M", 9000, 2, overlap(), 15000 * FT) end)
at(660, "red SEAD 2", function() air(RED_C, "Red SEAD 2", "Su-34", 9800, 1, redSead(), 23000 * FT, KH31, true) end)

-- ------------------------------------------------------------------ recording
local RADAR_GROUPS = { "EW East", "SAM SA-10 Centre", "PD Tor Centre", "SAM SA-11 South", "SAM SA-6 East", "SAM SA-2 West",
  "EW South", "SAM Patriot", "SAM Hawk" }
local arms = {}   -- ground truth ARM flights: { w, id, type, shooter, t0, minD, minName }
local armSeq = 0
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
    local okD, desc = pcall(function() return w:getDesc() end)
    local arm = okD and desc and desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE
    local id = ""
    if arm then
      armSeq = armSeq + 1
      id = " ARM#" .. armSeq
      arms[#arms + 1] = { w = w, id = armSeq, type = safeType(w), shooter = safeName(e.initiator), t0 = now() }
    end
    log(string_format("SHOT%s shooter=%s (%s) weapon=%s target=%s (%s)", id, safeName(e.initiator), safeType(e.initiator),
      safeType(w), safeName(tgt), safeType(tgt)))
  elseif e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
    log(string_format("HIT shooter=%s weapon=%s target=%s (%s)", safeType(e.initiator), safeType(e.weapon), safeName(e.target),
      safeType(e.target)))
  elseif e.id == world.event.S_EVENT_DEAD and safeCat(e.initiator) == Object.Category.UNIT then
    log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
  end
end)
world.addEventHandler(handler)

-- ARM flights every second: closest approach to any radar group's first unit; logged when the weapon is gone
local function radarPoints()
  local out = {}
  for _, name in ipairs(RADAR_GROUPS) do
    local g = Group.getByName(name)
    local u = g and g:isExist() and g:getUnit(1)
    if u and u:isExist() then out[#out + 1] = { name = name, p = u:getPoint() } end
  end
  return out
end
local function trackArms(_, t)
  safeCall("arms", function()
    local radars
    for i = #arms, 1, -1 do
      local a = arms[i]
      local ok, ex = pcall(function() return a.w:isExist() end)
      if ok and ex then
        radars = radars or radarPoints()
        local p = a.w:getPoint()
        a.last = p
        for _, r in ipairs(radars) do
          local dx, dz = p.x - r.p.x, p.z - r.p.z
          local d = math.sqrt(dx * dx + dz * dz)
          if not a.minD or d < a.minD then a.minD, a.minName = d, r.name end
        end
      else
        log(string_format("ARM END #%d %s from %s after %.0f s: closest %.0f m to %s", a.id, a.type, a.shooter, now() - a.t0,
          a.minD or -1, tostring(a.minName)))
        table.remove(arms, i)
      end
    end
  end)
  return t + 1
end
timer_schedule(trackArms, nil, timer_getTime() + 5)

-- every 30 s: each radar node's EMCON and ARM state (read-only)
local function summary(_, t)
  safeCall("summary", function()
    if not (JANUS.net and JANUS.net.list) then return end
    local parts = {}
    for _, n in ipairs(JANUS.net.list) do
      if n.hasRadar then
        local st = (not (n.alive and n.working)) and "dead" or (n.emcon.on and "ON" or "off")
        local s = n.arm
        local a = ""
        if s then
          if s.dark then a = string_format(" DARK(%.0fs)", s.dark.untilT - (JANUS.now() or 0))
          elseif s.mode then a = " " .. s.mode end
          if (s.darkSec or 0) > 0 then a = a .. string_format(" lost %ds", s.darkSec) end
        end
        parts[#parts + 1] = string_format("%s:%s%s", n.name, st, a)
      end
    end
    log("RADARS " .. table.concat(parts, " | "))
  end)
  return t + 30
end
timer_schedule(summary, nil, timer_getTime() + 30)

at(1200, "END: bench 05 complete at 20 min", function()
  if JANUS.arm then
    JANUS.arm.summary()
    local st = JANUS.arm.stats
    log(string_format("ARM STATS launched %d, hits %d (on dark radars %d), seen to die short %d", st.launched, st.hits,
      st.hitsDark, st.seenDie))
  end
end)

log(string_format("bench %s loaded (red at %.0f/%.0f, blue at %.0f/%.0f from anchor); janus.lua loads next",
  B.VERSION, Cx - x0, Cz - z0, Bx - x0, Bz - z0))
