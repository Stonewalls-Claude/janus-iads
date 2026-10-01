-- Janus IADS - bench 06 (Phase 4 gate): both coalitions at once, blue doctrine, naval, AWACS, AAA, preset spawning,
-- GCI weapons control and commit requests.
-- Gate (DESIGN 9): a blue bench plus both sides running together with no Janus errors; batteries spawned from presets
-- stand on ground flat enough to fire and fire; a ship and an AWACS work as network nodes; flak-trap guns hold until
-- the trap closes; weapons tight / hold work through JANUS.gci.weaponsControl; the GCI interface answers under load.
-- Load order in JANUS_BENCH_06.miz: THIS file (sets JANUS_SETTINGS, places command posts and AWACS) -> janus.lua.
-- Every SAM, EW, gun and ship group is spawned by JANUS.spawnBattery at t = 3 s, after Janus has started, so the
-- spawns also test pick-up at S_EVENT_BIRTH.
-- Records to dcs.log with the tag "JANUS_BENCH"; Janus's own lines carry "JANUS [spawn]" / "[wta]" / "[aaa]" / "[arm]".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace) and JANUS_SETTINGS (the documented settings table).
--
-- RED (SOVIET_PVO_1985 with flak traps on; anchor C = +170 km N, +90 km E):
--   CMD Bunker North (static), A-50 "Mainstay AEW" orbiting 60 km behind (no role word: picked up by type),
--   presets: EW-SOVIET, SA-10 (+ AAA-ZU23 beside it), SA-6 East with its gun ring, SA-2 West with its gun ring
--   (S-60 + ZU-23: the flak trap), SA-11 South; 12 more SA-6 / SA-8 / SA-15 / SA-3 batteries spread far behind (load).
-- BLUE (NATO_COLDWAR: datalink, weapons TIGHT; anchor B = -150 km N, +60 km E):
--   CMD South (MLRS FDDM), E-3A "Magic AEW" orbiting (callsign-first name), presets EW-NATO, PATRIOT, HAWK (2 deg
--   limit: lands on flat ground), NASAMS, AAA-VULCAN, CSG-USN at sea off Latakia; 12 more HAWK / NASAMS / ROLAND /
--   RAPIER / AVENGER batteries far behind (load).
-- Air: as bench 05 (blue bait + SEAD at the red SAMs, red bait + Su-34 Kh-31P at the Patriot / Hawk) plus red
--   Su-24M bait at the carrier group (ships as WTA shooters).
-- GCI calls (as GCI would make them): commitRequests and weapons state every 60 s for both sides; at t = 420 blue
--   "hold" (ground control), at t = 540 blue "free", at t = 780 blue back to "tight".
-- Recorded: SHOT / HIT / DEAD, each ARM's end, the spawn results (place, worst slope), every 30 s each radar node's
--   EMCON / ARM state and each gun group's fire state; at the end Janus's statistics and per-side node counts.

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.6.0"

JANUS_SETTINGS = { CHECK_MODE = true, BLUE_DOCTRINE = "NATO_COLDWAR",
  RED_DOCTRINE = { base = "SOVIET_PVO_1985", aaa = { mode = "trap" } } }

local TAG = "JANUS_BENCH"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_cos, math_sin, math_atan2 = math.cos, math.sin, math.atan2
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

-- ------------------------------------------------------------------ anchor
local AP
for _, ab in ipairs(world.getAirbases() or {}) do
  local n = ab:getName() or ""
  if n:find("Assad") or n:find("Latakia") then AP = ab:getPoint(); break end
end
if not AP then env_error(TAG .. " no anchor airbase (Syria map?)"); return end
local x0, z0 = AP.x, AP.z

local RED_C, BLUE_C = country.id.RUSSIA, country.id.USA
local POS = {}
local Cx, Cz = x0 + 170000, z0 + 90000
local Bx, Bz = x0 - 150000, z0 + 60000

-- ------------------------------------------------------------------ command posts (before Janus starts)
local function static(side, name, typ, shape, x, z)
  local ok = safeCall("spawn " .. name, coalition.addStaticObject, side,
    { name = name, type = typ, category = "Fortifications", shape_name = shape, x = x, y = z, heading = 0 })
  POS[name] = { x, z }
  log(string_format("SPAWN static %s at %.0f/%.0f %s", name, x - x0, z - z0, ok and "ok" or "FAILED"))
end
static(RED_C, "CMD Bunker North", ".Command Center", "ComCenter", Cx, Cz)
local ok = safeCall("spawn CMD South", coalition.addGroup, BLUE_C, Group.Category.GROUND, { name = "CMD South", task = "Ground Nothing",
  units = { { name = "CMD South-1", type = "MLRS FDDM", skill = "Excellent", x = Bx, y = Bz, heading = 0 } },
  route = { points = { { x = Bx, y = Bz, type = "Turning Point", action = "Off Road", speed = 0,
    task = { id = "ComboTask", params = { tasks = {} } } } } } })
log("SPAWN CMD South " .. (ok and "ok" or "FAILED"))

-- ------------------------------------------------------------------ aircraft
local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local O = AI.Option.Air
-- AWACS: racetrack orbit between two points, invisible to AI so the bench is not decided by fighters chasing it
local function awacs(side, name, acType, fuel, p1, p2, alt)
  local h = math_atan2(p2[2] - p1[2], p2[1] - p1[1])
  local tasks = { { id = "AWACS", enabled = true, auto = true, number = 1, params = {} },
    { id = "Orbit", enabled = true, auto = false, number = 2, params = { pattern = "Race-Track", altitude = alt, speed = 200 } } }
  local okA = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.AIRPLANE, { name = name, task = "AWACS",
    units = { { name = name .. "-1", type = acType, skill = "Excellent", x = p1[1], y = p1[2], alt = alt, alt_type = "BARO",
      speed = 200, heading = h, payload = { pylons = {}, fuel = fuel, chaff = 0, flare = 0, gun = 0 }, callsign = { 1, 1, 1 },
      onboard_num = "001" } },
    route = { points = { wp(p1[1], p1[2], alt, 200, tasks), wp(p2[1], p2[2], alt, 200) } } })
  log(string_format("SPAWN %s (%s) %s", name, acType, okA and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("awacs options " .. name, function()
      local g = Group.getByName(name)
      if g then g:getController():setCommand({ id = "SetInvisible", params = { value = true } }) end
    end)
    return nil
  end, nil, timer_getTime() + 2)
end
awacs(RED_C, "Mainstay AEW", "A-50", 70000, { Cx + 60000, Cz - 20000 }, { Cx + 60000, Cz + 60000 }, 9000)
awacs(BLUE_C, "Magic AEW", "E-3A", 60000, { Bx - 60000, Bz - 20000 }, { Bx - 60000, Bz + 60000 }, 9000)

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
  local okS = safeCall("spawn " .. name, coalition.addGroup, side, Group.Category.AIRPLANE,
    { name = name, task = armed and "SEAD" or "CAP", units = units, route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s, %s) %s", name, count, acType, armed and "SEAD" or "bait", okS and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      c:setOption(O.id.ROE, armed and O.val.ROE.WEAPON_FREE or O.val.ROE.WEAPON_HOLD)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
    end)
    return nil
  end, nil, timer_getTime() + 3)
end

-- ------------------------------------------------------------------ preset spawning (after Janus has started)
local SPAWNED, spawnOk, spawnFail = {}, 0, 0
local function battery(preset, x, z, opts)
  opts = opts or {}
  local name, info = JANUS.spawnBattery(preset, { x = x, z = z }, opts)
  if name then
    spawnOk = spawnOk + 1
    SPAWNED[#SPAWNED + 1] = name
    POS[opts.key or name] = { info.x, info.z }
    log(string_format("PRESET %s -> %s at %.0f/%.0f (%.0f m from asked) worst slope %.2f limit %.1f%s", preset, name,
      info.x - x0, info.z - z0, math.sqrt((info.x - x) ^ 2 + (info.z - z) ^ 2), info.slope, info.limit,
      info.aaa and (" guns " .. info.aaa) or ""))
    if info.aaa then SPAWNED[#SPAWNED + 1] = info.aaa end
  else
    spawnFail = spawnFail + 1
    log(string_format("PRESET %s FAILED: %s", preset, tostring(info)))
  end
  return name
end

at(3, "preset spawning, both sides", function()
  if not JANUS.spawnBattery then env_error(TAG .. " JANUS.spawnBattery missing"); return end
  -- red
  battery("EW-SOVIET", Cx, Cz + 30000, { label = "East", tier = "VET", key = "EW East" })
  battery("SA-10", Cx - 15000, Cz, { label = "Centre", tier = "VET", key = "SA-10" })
  battery("AAA-ZU23", POS["SA-10"][1] + 1500, POS["SA-10"][2] + 1500, { label = "Centre Guns", search = 3000 })
  battery("SA-6", Cx - 20000, Cz + 40000, { label = "East", aaa = true, key = "SA-6" })
  battery("SA-2", Cx - 20000, Cz - 30000, { label = "West", aaa = true, tier = "GRN", key = "SA-2" })
  battery("SA-11", Cx - 40000, Cz + 10000, { label = "South", key = "SA-11" })
  local redLoad = { "SA-6", "SA-8", "SA-15", "SA-3" }
  for i = 1, 12 do
    battery(redLoad[(i - 1) % 4 + 1], Cx + 40000 + math.floor((i - 1) / 4) * 25000, Cz - 40000 + ((i - 1) % 4) * 30000,
      { label = "Red Rear " .. i })
  end
  -- blue
  battery("EW-NATO", Bx, Bz + 15000, { coalition = 2, label = "South", key = "EW South" })
  battery("PATRIOT", Bx, Bz + 40000, { coalition = 2, label = "Bravo", tier = "VET", key = "Patriot" })
  battery("HAWK", Bx + 20000, Bz + 60000, { coalition = 2, label = "Charlie", key = "Hawk" })
  battery("NASAMS", Bx + 30000, Bz + 30000, { coalition = 2, label = "Delta", key = "NASAMS" })
  battery("AAA-VULCAN", POS["Hawk"] and POS["Hawk"][1] + 1500 or Bx, POS["Hawk"] and POS["Hawk"][2] or Bz, { coalition = 2, label = "Charlie Guns", search = 3000 })
  battery("CSG-USN", x0 - 30000, z0 - 50000, { coalition = 2, label = "Ike", search = 40000, key = "CSG", tags = "[net:CSG]" })
  local blueLoad = { "HAWK", "NASAMS", "ROLAND", "RAPIER", "AVENGER" }
  for i = 1, 12 do
    battery(blueLoad[(i - 1) % 5 + 1], Bx - 40000 - math.floor((i - 1) / 4) * 25000, Bz - 30000 + ((i - 1) % 4) * 30000,
      { coalition = 2, label = "Blue Rear " .. i })
  end
  log(string_format("PRESETS spawned %d, failed %d", spawnOk, spawnFail))
end)

-- ------------------------------------------------------------------ air waves (positions from the spawns)
local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local KH31P = "{X-31P}"
local HARMS = { [3] = { CLSID = AGM88C }, [4] = { CLSID = AGM88C }, [6] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }
local KH31 = { [3] = { CLSID = KH31P }, [4] = { CLSID = KH31P }, [8] = { CLSID = KH31P }, [9] = { CLSID = KH31P } }
local function p(key, dflt) return POS[key] or dflt end
local tri = function(dx)
  local s10 = p("SA-10", { Cx - 15000, Cz })
  return { { s10[1] - 130000 + dx, s10[2] - 40000 }, { s10[1] - 20000 + dx, s10[2] + 15000 },
           { s10[1] + 40000, s10[2] + 90000 }, { s10[1] + 60000, s10[2] + 160000 } }
end
local sead = function(dx)
  local s10 = p("SA-10", { Cx - 15000, Cz })
  return { { s10[1] - 150000 + dx, s10[2] - 50000 }, { s10[1] - 60000 + dx, s10[2] - 10000 }, { s10[1] - 150000 + dx, s10[2] - 50000 } }
end
local lowSa2 = function()   -- low and close past the SA-2's gun ring: the flak trap
  local s2 = p("SA-2", { Cx - 20000, Cz - 30000 })
  return { { s2[1] - 80000, s2[2] - 10000 }, { s2[1] + 1500, s2[2] + 500 }, { s2[1] + 80000, s2[2] + 10000 } }
end
local overlap = function()
  local pat = p("Patriot", { Bx, Bz + 40000 })
  return { { pat[1] + 150000, pat[2] + 120000 }, { pat[1] + 10000, pat[2] + 15000 }, { pat[1] - 120000, pat[2] - 40000 } }
end
local redSead = function()
  local pat = p("Patriot", { Bx, Bz + 40000 })
  return { { pat[1] + 170000, pat[2] + 110000 }, { pat[1] + 60000, pat[2] + 40000 }, { pat[1] + 170000, pat[2] + 110000 } }
end
local atShips = function()
  local c = p("CSG", { x0 - 30000, z0 - 50000 })
  return { { c[1] + 120000, c[2] + 60000 }, { c[1] + 5000, c[2] + 3000 }, { c[1] - 100000, c[2] - 40000 } }
end
at(60, "blue bait 1: 2x F-16C through the red triangle", function() air(BLUE_C, "Blue Bait 1", "F-16C_50", 3249, 2, tri(0), 18000 * FT) end)
at(90, "red bait 1: 2x Su-24M over the Patriot / Hawk (weapons tight: identified?)", function()
  air(RED_C, "Red Bait 1", "Su-24M", 9000, 2, overlap(), 15000 * FT) end)
at(150, "blue SEAD 1: 2x F-16C 4x AGM-88C", function() air(BLUE_C, "Blue SEAD 1", "F-16C_50", 3249, 2, sead(0), 22000 * FT, HARMS, true) end)
at(180, "red SEAD 1: 1x Su-34 4x Kh-31P", function() air(RED_C, "Red SEAD 1", "Su-34", 9800, 1, redSead(), 23000 * FT, KH31, true) end)
at(300, "blue low pass past the SA-2 gun ring (flak trap)", function() air(BLUE_C, "Blue Low 1", "F-16C_50", 3249, 2, lowSa2(), 600) end)
at(420, "GCI: blue weapons HOLD", function() log("GCI weaponsControl blue hold -> " .. tostring(JANUS.gci.weaponsControl(2, "hold"))) end)
at(450, "red bait 2 over the Patriot / Hawk (during weapons hold)", function()
  air(RED_C, "Red Bait 2", "Su-24M", 9000, 2, overlap(), 15000 * FT) end)
at(540, "GCI: blue weapons FREE", function() log("GCI weaponsControl blue free -> " .. tostring(JANUS.gci.weaponsControl(2, "free"))) end)
at(600, "red bait 3: 2x Su-24M at the carrier group", function() air(RED_C, "Red Bait Ships", "Su-24M", 9000, 2, atShips(), 3000) end)
at(630, "blue SEAD 2", function() air(BLUE_C, "Blue SEAD 2", "F-16C_50", 3249, 2, sead(10000), 22000 * FT, HARMS, true) end)
at(660, "red SEAD 2", function() air(RED_C, "Red SEAD 2", "Su-34", 9800, 1, redSead(), 23000 * FT, KH31, true) end)
at(780, "GCI: blue weapons back to TIGHT", function() log("GCI weaponsControl blue tight -> " .. tostring(JANUS.gci.weaponsControl(2, "tight"))) end)

-- ------------------------------------------------------------------ recording
local arms, armSeq = {}, 0
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
    local sh = e.initiator
    local grp = ""
    if sh then
      local okG, g = pcall(function() return sh:getGroup():getName() end)
      if okG then grp = " group=" .. tostring(g) end
    end
    log(string_format("SHOT%s shooter=%s (%s)%s weapon=%s target=%s (%s)", id, safeName(sh), safeType(sh), grp,
      safeType(w), safeName(tgt), safeType(tgt)))
  elseif e.id == world.event.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
    log(string_format("HIT shooter=%s weapon=%s target=%s (%s)", safeType(e.initiator), safeType(e.weapon), safeName(e.target),
      safeType(e.target)))
  elseif e.id == world.event.S_EVENT_DEAD and safeCat(e.initiator) == Object.Category.UNIT then
    log(string_format("DEAD %s (%s)", safeName(e.initiator), safeType(e.initiator)))
  end
end)
world.addEventHandler(handler)

local function radarPoints()
  local out = {}
  for _, n in ipairs(JANUS.net and JANUS.net.list or {}) do
    if n.hasRadar and n.alive and n.pos then out[#out + 1] = { name = n.name, p = n.pos } end
  end
  return out
end
timer_schedule(function(_, t)
  safeCall("arms", function()
    local radars
    for i = #arms, 1, -1 do
      local a = arms[i]
      local okE, ex = pcall(function() return a.w:isExist() end)
      if okE and ex then
        radars = radars or radarPoints()
        local q = a.w:getPoint()
        for _, r in ipairs(radars) do
          local dx, dz = q.x - r.p.x, q.z - r.p.z
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
end, nil, timer_getTime() + 5)

-- every 30 s: radar EMCON / ARM state and gun fire state, per side
timer_schedule(function(_, t)
  safeCall("summary", function()
    if not (JANUS.net and JANUS.net.list) then return end
    local radars, guns = {}, {}
    for _, n in ipairs(JANUS.net.list) do
      if n.kind == "AAA" then
        guns[#guns + 1] = string_format("%s:%s", n.name, (not n.alive) and "dead"
          or (n.aaa and (n.aaa.open == false and "HOLD" or "open")) or "free")
      elseif n.hasRadar and not n.name:find("Rear") then
        local st = (not (n.alive and n.working)) and "dead" or (n.emcon.on and "ON" or "off")
        local s, a = n.arm, ""
        if s then
          if s.dark then a = string_format(" DARK(%.0fs)", s.dark.untilT - (JANUS.now() or 0))
          elseif s.mode then a = " " .. s.mode end
        end
        radars[#radars + 1] = string_format("%s:%s%s%s", n.name, st, a, n.linked and "" or " UNLINKED")
      end
    end
    log("RADARS " .. table.concat(radars, " | "))
    log("GUNS " .. table.concat(guns, " | "))
  end)
  return t + 30
end, nil, timer_getTime() + 30)

-- every 60 s: what GCI would read
timer_schedule(function(_, t)
  safeCall("gci", function()
    local G = JANUS.gci
    if not G then return end
    for _, coa in ipairs({ 1, 2 }) do
      local req = G.commitRequests(coa)
      local parts = {}
      for i = 1, math.min(5, #req) do
        parts[i] = string_format("#%s %s (%s)", tostring(req[i].num), tostring(req[i].typeName or req[i].class), tostring(req[i].reason))
      end
      local w = {}
      for net, st in pairs(G.weapons(coa)) do w[#w + 1] = net .. "=" .. st end
      local nTr = 0
      for _ in pairs(G.tracks(coa) or {}) do nTr = nTr + 1 end
      log(string_format("GCI %s: %d tracks, weapons %s, %d commit requests %s", coa == 1 and "red" or "blue", nTr,
        table.concat(w, ","), #req, table.concat(parts, " ")))
    end
  end)
  return t + 60
end, nil, timer_getTime() + 60)

at(1200, "END: bench 06 complete at 20 min", function()
  local count = { {}, {} }
  for _, n in ipairs(JANUS.net and JANUS.net.list or {}) do
    local c = count[n.site.coalition] or {}
    c[n.kind] = (c[n.kind] or 0) + 1
  end
  for coa = 1, 2 do
    local parts = {}
    for k, v in pairs(count[coa]) do parts[#parts + 1] = k .. " " .. v end
    table.sort(parts)
    log(string_format("NODES %s: %s", coa == 1 and "red" or "blue", table.concat(parts, ", ")))
  end
  log(string_format("PRESETS spawned %d, failed %d", spawnOk, spawnFail))
  if JANUS.arm then
    JANUS.arm.summary()
    local st = JANUS.arm.stats
    log(string_format("ARM STATS launched %d, hits %d (on dark radars %d), seen to die short %d", st.launched, st.hits,
      st.hitsDark, st.seenDie))
  end
  log("BENCH 06 COMPLETE")
end)

log(string_format("bench %s loaded (red at %.0f/%.0f, blue at %.0f/%.0f from anchor); janus.lua loads next",
  B.VERSION, Cx - x0, Cz - z0, Bx - x0, Bz - z0))
