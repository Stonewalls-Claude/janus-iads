-- Janus IADS - bench 04 (Phase 2 gate): static command posts / radios / power, the backup link and alternate command
-- post, the track picture with identification, and weapon-target assignment with handoffs. Both coalitions.
-- Gate (DESIGN 9): static nodes degrade the network as designed; track picture, WTA and handoffs work; no Janus errors.
-- Load order in JANUS_BENCH_04.miz: THIS file (spawns everything, sets JANUS_SETTINGS) -> janus.lua.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [net]" / "[emcon]" / "[wta]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- RED (SOVIET_PVO_1985: WTA salvo up to 2 shooters, pkGoal 0.85; anchor C = +170 km N, +90 km E), all SAMs flat:
--   CMD Bunker North [alt:Bunker Reserve]  static .Command Center at C; its air-ground radio COMMS Radio North [ag]
--   (static Comms tower M) 1.5 km away; CMD Bunker Reserve (static Military staff) 35 km SW, standing by.
--   EW East (55G6) 30 km E, powered by POWER Plant East (static GeneratorF) beside it.
--   SAM SA-10 Centre 15 km S, SAM SA-11 South 40 km S, SAM SA-6 East 20 km S / 40 km E, PD Tor Centre by the SA-10:
--   overlapping envelopes, so WTA has a choice and must hand targets on as they fly through.
--   COMMS Relay West (static TV tower) 70 km W; SAM SA-3 West 130 km W, reachable only through that relay.
--   AWACS Mainstay (A-50) orbits 40 km N: it identifies types (probe run 6); EW East never does.
--   t=420 Relay West destroyed -> SA-3 West unlinked (130 km: no backup reach) -> autonomous after 180 s.
--   t=480 POWER Plant East destroyed -> EW East on 300 s reserve -> dark at ~780.
--   t=540 COMMS Radio North destroyed -> air-ground radio "backup".
--   t=600 CMD Bunker North destroyed -> every battery unlinked; CMD Bunker Reserve takes over at ~780 (REG 180 s).
--   blue waves (2x unarmed F-16C, weapons hold): t=60 and t=900 through the SA-10/SA-11/SA-6 triangle,
--   t=240 past SA-3 West, t=660 through the triangle while the command post is gone.
-- BLUE (US_MODERN: one shooter per target; anchor B = -150 km N, +60 km E):
--   CMD South, EW South (FPS-117), SAM Patriot 40 km E, SAM Hawk 60 km E / 20 km N (flat), AWACS Sentry (E-3A).
--   red waves (2x unarmed Su-24M): t=120 and t=720 through the Patriot/Hawk overlap (handoff Patriot <-> Hawk).

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.4.0"

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
static(RED_C, "CMD Bunker North [alt:Bunker Reserve]", ".Command Center", Cx, Cz)
static(RED_C, "COMMS Radio North [ag]", "Comms tower M", Cx, Cz + 1500)
static(RED_C, "CMD Bunker Reserve", "Military staff", Cx - 30000, Cz - 20000)
ground(RED_C, "EW East", Cx, Cz + 30000, { { "55G6 EWR", 0, 0 } }, 50)
static(RED_C, "POWER Plant East", "GeneratorF", POS["EW East"][1] + 400, POS["EW East"][2])
ground(RED_C, "SAM SA-10 Centre", Cx - 15000, Cz, { { "S-300PS 40B6M tr", 0, 0 }, { "S-300PS 64H6E sr", 150, 100 },
  { "S-300PS 54K6 cp", -150, 100 }, { "S-300PS 5P85C ln", 0, 230 }, { "S-300PS 5P85C ln", 200, -120 }, { "S-300PS 5P85C ln", -200, -120 } })
ground(RED_C, "PD Tor Centre", POS["SAM SA-10 Centre"][1] + 2000, POS["SAM SA-10 Centre"][2] + 2000, { { "Tor 9A331", 0, 0 } }, 50)
ground(RED_C, "SAM SA-11 South", Cx - 40000, Cz + 10000, { { "SA-11 Buk SR 9S18M1", 0, 0 }, { "SA-11 Buk CC 9S470M1", 120, 0 },
  { "SA-11 Buk LN 9A310M1", 0, 200 }, { "SA-11 Buk LN 9A310M1", 170, -100 }, { "SA-11 Buk LN 9A310M1", -170, -100 } })
ground(RED_C, "SAM SA-6 East", Cx - 20000, Cz + 40000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 0, 200 },
  { "Kub 2P25 ln", 170, -100 }, { "Kub 2P25 ln", -170, -100 } })
static(RED_C, "COMMS Relay West", "TV tower", Cx, Cz - 70000)
ground(RED_C, "SAM SA-3 West", Cx, Cz - 130000, { { "snr s-125 tr", 0, 0 }, { "p-19 s-125 sr", 150, 0 },
  { "5p73 s-125 ln", 0, 200 }, { "5p73 s-125 ln", 170, -100 }, { "5p73 s-125 ln", -170, -100 } })

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
local function air(side, name, acType, fuel, count, route, alt, task, tasks1)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = acType, skill = "Excellent",
      x = route[1][1] - (i - 1) * 1500 * math_cos(h), y = route[1][2] - (i - 1) * 1500 * math_sin(h) + (i - 1) * 800,
      alt = alt, alt_type = "BARO", speed = 220, heading = h,
      payload = { pylons = {}, fuel = fuel, chaff = 60, flare = 60, gun = 0 }, callsign = { 1, 1, i }, onboard_num = tostring(400 + i) }
  end
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, 220, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.AIRPLANE,
    { name = name, task = task, units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s) %s", name, count, acType, ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      c:setOption(O.id.ROE, O.val.ROE.WEAPON_HOLD)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
    end)
    return nil
  end, nil, timer_getTime() + 2)
end
local function orbit(side, name, acType, x, z)
  local o = { id = "Orbit", params = { pattern = "Circle", point = { x = x, y = z }, altitude = 9000, speed = 180 } }
  air(side, name, acType, 60000, 1, { { x, z }, { x + 20000, z } }, 9000, "AWACS",
    { { enabled = true, auto = false, id = "Orbit", number = 1, params = o.params } })
end
orbit(RED_C, "AWACS Mainstay", "A-50", Cx + 40000, Cz)
orbit(BLUE_C, "AWACS Sentry", "E-3A", Bx - 30000, Bz)

-- blue F-16C through the red triangle (SA-10 / SA-11 / SA-6) from the south-west, out to the north-east
local tri = function(dx)
  local s10 = POS["SAM SA-10 Centre"]
  return { { s10[1] - 130000 + dx, s10[2] - 40000 }, { s10[1] - 20000 + dx, s10[2] + 15000 },
           { s10[1] + 40000, s10[2] + 90000 }, { s10[1] + 60000, s10[2] + 160000 } }
end
local sa3 = POS["SAM SA-3 West"]
local function west() return { { sa3[1] - 60000, sa3[2] + 5000 }, { sa3[1], sa3[2] + 5000 }, { sa3[1] + 80000, sa3[2] + 5000 } } end
local function blue(tag, route, alt) air(BLUE_C, tag, "F-16C_50", 3249, 2, route, alt * FT, "CAP") end
at(60,  "red wave 1: 2x F-16C through the triangle (all linked, WTA)", function() blue("Blue Transit 1", tri(0), 18000) end)
at(240, "red wave 2: 2x F-16C past SA-3 West (linked through the relay)", function() blue("Blue Transit 2", west(), 15000) end)
at(660, "red wave 3: 2x F-16C through the triangle (command post gone)", function() blue("Blue Transit 3", tri(8000), 15000) end)
at(900, "red wave 4: 2x F-16C through the triangle (reserve post in command, EW dark)", function() blue("Blue Transit 4", tri(-8000), 18000) end)
-- red Su-24M through the Patriot/Hawk overlap from the north
local function overlap()
  local p, hk = POS["SAM Patriot"], POS["SAM Hawk"]
  local mx, mz = (p[1] + hk[1]) / 2, (p[2] + hk[2]) / 2
  return { { mx + 120000, mz + 10000 }, { mx, mz }, { mx - 100000, mz - 10000 } }
end
local function red(tag) air(RED_C, tag, "Su-24M", 9000, 2, overlap(), 15000 * FT, "CAP") end
at(120, "blue wave A: 2x Su-24M through the Patriot/Hawk overlap", function() red("Red Transit A") end)
at(720, "blue wave B: 2x Su-24M through the Patriot/Hawk overlap", function() red("Red Transit B") end)

-- ------------------------------------------------------------------ node kills (statics: repeated blasts until dead)
local function blastStatic(name, tries)
  local o = StaticObject.getByName(name)
  local p = POS[name]
  if not (o and o:isExist() and o:getLife() > 0) then log(string_format("DESTROY %s done", name)); return end
  if tries <= 0 then log(string_format("DESTROY %s survived (life %.0f)", name, o:getLife())); return end
  trigger.action.explosion({ x = p[1], y = heightAt(p[1], p[2]) + 2, z = p[2] }, 3000)
  log(string_format("BLAST %s (3000 kg), life before %.0f", name, o:getLife()))
  timer_schedule(function() safeCall("blast " .. name, blastStatic, name, tries - 1); return nil end, nil, timer_getTime() + 15)
end
at(420, "kill COMMS Relay West (static)", function() blastStatic("COMMS Relay West", 4) end)
at(480, "kill POWER Plant East (static)", function() blastStatic("POWER Plant East", 4) end)
at(540, "kill COMMS Radio North [ag] (static)", function() blastStatic("COMMS Radio North [ag]", 4) end)
at(600, "kill CMD Bunker North (static)", function() blastStatic("CMD Bunker North [alt:Bunker Reserve]", 6) end)

-- ------------------------------------------------------------------ recording
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
    log(string_format("SHOT shooter=%s (%s) weapon=%s target=%s", safeName(e.initiator), safeType(e.initiator), safeType(w), safeName(tgt)))
  elseif e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
    log(string_format("HIT shooter=%s weapon=%s target=%s", safeType(e.initiator), safeType(e.weapon), safeName(e.target)))
  elseif e.id == world.event.S_EVENT_DEAD then
    log(string_format("DEAD %s (%s) category %d", safeName(e.initiator), safeType(e.initiator), safeCat(e.initiator)))
  end
end)
world.addEventHandler(handler)

-- every 60 s: Janus node states, emitting seconds, assignments and the track picture (read-only)
local function summary(_, t)
  safeCall("summary", function()
    if not (JANUS.net and JANUS.net.list) then return end
    local parts = {}
    for _, n in ipairs(JANUS.net.list) do
      local st = (not (n.alive and n.working)) and "dead" or (not n.powered and "nopower") or (n.autonomous and "auto")
        or (not n.linked and "unlinked") or (n.kind == "C2" and not n.active and "standby") or "linked"
      local extra = (n.linkVia and ("/" .. n.linkVia) or "") .. (n.agState and ("/radio " .. n.agState) or "")
      local tgt = n.assigned and #n.assigned > 0 and (" ->" .. #n.assigned) or ""
      parts[#parts + 1] = string_format("%s:%s%s:%s:%ds%s", n.name, st, extra, n.emcon.on and "ON" or "off", n.emcon.emitSec or 0, tgt)
    end
    log("NODES " .. table.concat(parts, " | "))
    for key, net in pairs(JANUS.net.networks) do
      local tl = {}
      for _, tr in ipairs(JANUS.tracks.list(net.tracks)) do
        local by = {}
        for _, c in ipairs((net.assign or {})[tr.id] or {}) do by[#by + 1] = c.node.name end
        tl[#tl + 1] = string_format("%s%s", JANUS.tracks.label(tr), #by > 0 and (" by " .. table.concat(by, "+")) or "")
      end
      if #tl > 0 then log(string_format("TRACKS %s: %s", key, table.concat(tl, "; "))) end
    end
  end)
  return t + 60
end
timer_schedule(summary, nil, timer_getTime() + 60)
at(1320, "END: bench 04 complete at 22 min", function() end)

log(string_format("bench %s loaded (red at %.0f/%.0f, blue at %.0f/%.0f from anchor); janus.lua loads next",
  B.VERSION, Cx - x0, Cz - z0, Bx - x0, Bz - z0))
