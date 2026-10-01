-- Janus IADS - bench 07 (Phase 5 release gate): Janus vs Skynet 3.5.0 on the same scenario (DESIGN 1.5, 7.3).
-- One red network, defended by either IADS, against identical blue waves; repeated runs of each.
-- VARIANT below is set when the .miz is built (tools: build_bench07 in the session scratch, see BENCH_RESULTS):
--   "JANUS"  : this file -> janus.lua (red SOVIET_PVO_1985, blue no IADS)
--   "SKYNET" : mist_4_5_126.lua -> skynet-iads-compiled.lua -> this file (stock Skynet 3.5.0, set up as its docs
--              describe: EW and SAM by prefix, command center, the Tor as point defence of the SA-10, HARM defence on)
-- Records to dcs.log with the tag "JANUS_BENCH" (both variants), and at the end one "SCORE" line:
--   blueLost (blue aircraft destroyed; higher = better defence), redRadarsLost / redLost (red radar / any red ground
--   units destroyed; lower = better), harms (ARMs launched), harmHits (ARMs that hit a red unit), emitMin (radar
--   minutes emitting), usefulMin (radar minutes emitting while a blue aircraft was within 100 km).
--   Score (fixed before the first run, 2026-10-01): 3 x blueLost - 3 x redRadarsLost - 1 x (redLost - redRadarsLost)
--   + 1 x (harms - harmHits). Janus passes the gate if its mean score over the runs beats Skynet's.
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace; also in the Skynet variant, holding only this bench) and,
-- in the Janus variant, JANUS_SETTINGS.

local VARIANT = "JANUS"   -- replaced per .miz

JANUS = JANUS or {}
JANUS.bench = JANUS.bench or {}
local B = JANUS.bench
B.VERSION = "0.7.0"
B.variant = VARIANT

if VARIANT == "JANUS" then
  JANUS_SETTINGS = { RED_DOCTRINE = "SOVIET_PVO_1985", BLUE_DOCTRINE = "US_MODERN" }
end

local TAG = "JANUS_BENCH"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local math_cos, math_sin, math_atan2, math_sqrt = math.cos, math.sin, math.atan2, math.sqrt
local FT = 0.3048
local T0 = timer_getTime()
local END_T = 1500

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
local function safeCoa(o)
  if o == nil then return -1 end
  local ok, c = pcall(function() return o:getCoalition() end)
  return ok and c or -1
end
local function at(t, tag, fn)
  timer_schedule(function() log("STEP " .. tag); safeCall(tag, fn); return nil end, nil, T0 + t)
end

-- ------------------------------------------------------------------ anchor, terrain (bench 05 layout)
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
  return math.deg(math.atan(math_sqrt(gx * gx + gz * gz)))
end
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

-- ------------------------------------------------------------------ red network (same groups for both IADS)
local RED_C, BLUE_C = country.id.RUSSIA, country.id.USA
local POS = {}
local RADAR_UNITS = {}   -- unit names whose radar we time
local function ground(name, x, z, list, flatR, radars)
  local cx, cz, s = findFlat(x, z, flatR or 450)
  local units = {}
  for i = 1, #list do
    local u = list[i]
    units[i] = { name = name .. "-" .. i, type = u[1], skill = "Excellent", x = cx + u[2], y = cz + u[3], heading = 0 }
  end
  for _, i in ipairs(radars or {}) do RADAR_UNITS[#RADAR_UNITS + 1] = name .. "-" .. i end
  local ok = safeCall("spawn " .. name, coalition.addGroup, RED_C, Group.Category.GROUND, {
    name = name, task = "Ground Nothing", units = units,
    route = { points = { { x = cx, y = cz, type = "Turning Point", action = "Off Road", speed = 0,
      task = { id = "ComboTask", params = { tasks = {} } } } } } })
  POS[name] = { cx, cz }
  log(string_format("SPAWN %s (%d units) at %.0f/%.0f flat %.2f deg %s", name, #units, cx - x0, cz - z0, s, ok and "ok" or "FAILED"))
end
local Cx, Cz = x0 + 170000, z0 + 90000
do
  local cx, cz = findFlat(Cx, Cz, 50)
  local ok = safeCall("spawn CMD", coalition.addStaticObject, RED_C,
    { name = "CMD Bunker North", type = ".Command Center", category = "Fortifications", shape_name = "ComCenter",
      x = cx, y = cz, heading = 0 })
  POS["CMD Bunker North"] = { cx, cz }
  log("SPAWN static CMD Bunker North " .. (ok and "ok" or "FAILED"))
end
ground("EW East", Cx, Cz + 30000, { { "55G6 EWR", 0, 0 } }, 50, { 1 })
ground("EW West", Cx + 10000, Cz - 45000, { { "1L13 EWR", 0, 0 } }, 50, { 1 })
ground("SAM SA-10 Centre", Cx - 15000, Cz, { { "S-300PS 40B6M tr", 0, 0 }, { "S-300PS 64H6E sr", 150, 100 },
  { "S-300PS 54K6 cp", -150, 100 }, { "S-300PS 5P85C ln", 0, 230 }, { "S-300PS 5P85C ln", 200, -120 }, { "S-300PS 5P85C ln", -200, -120 } },
  nil, { 1, 2 })
ground("PD Tor Centre", POS["SAM SA-10 Centre"][1] + 2000, POS["SAM SA-10 Centre"][2] + 2000, { { "Tor 9A331", 0, 0 } }, 50, { 1 })
ground("SAM SA-11 South", Cx - 40000, Cz + 10000, { { "SA-11 Buk SR 9S18M1", 0, 0 }, { "SA-11 Buk CC 9S470M1", 120, 0 },
  { "SA-11 Buk LN 9A310M1", 0, 200 }, { "SA-11 Buk LN 9A310M1", 170, -100 }, { "SA-11 Buk LN 9A310M1", -170, -100 } }, nil, { 1, 3, 4, 5 })
ground("SAM SA-6 East", Cx - 20000, Cz + 40000, { { "Kub 1S91 str", 0, 0 }, { "Kub 2P25 ln", 0, 200 },
  { "Kub 2P25 ln", 170, -100 }, { "Kub 2P25 ln", -170, -100 } }, nil, { 1 })
ground("SAM SA-2 West", Cx - 20000, Cz - 30000, { { "SNR_75V", 0, 0 }, { "p-19 s-125 sr", 150, 0 },
  { "S_75M_Volhov", 0, 220 }, { "S_75M_Volhov", 190, -110 }, { "S_75M_Volhov", -190, -110 } }, nil, { 1, 2 })
ground("SAM SA-3 North", Cx + 15000, Cz - 10000, { { "snr s-125 tr", 0, 0 }, { "p-19 s-125 sr", 150, 0 },
  { "5p73 s-125 ln", 0, 120 }, { "5p73 s-125 ln", 120, -80 }, { "5p73 s-125 ln", -120, -80 } }, nil, { 1, 2 })

-- ------------------------------------------------------------------ IADS setup
if VARIANT == "SKYNET" then
  at(2, "Skynet 3.5.0 setup (stock, as documented)", function()
    local SK = rawget(_G, "SkynetIADS")   -- Skynet's own global, loaded before this file in the Skynet variant
    if not SK then env_error(TAG .. " SkynetIADS missing"); return end
    local iads = SK:create("RED")
    iads:addEarlyWarningRadarsByPrefix("EW")
    iads:addSAMSitesByPrefix("SAM")
    iads:addCommandCenter(StaticObject.getByName("CMD Bunker North"))
    local tor = iads:addSAMSite("PD Tor Centre")
    local sa10 = iads:getSAMSiteByGroupName("SAM SA-10 Centre")
    if sa10 and tor then sa10:addPointDefence(tor) end
    iads:activate()
    B.skynet = iads
    log("SKYNET " .. tostring(SK.version) .. " activated")
  end)
end

-- ------------------------------------------------------------------ blue waves (identical in both variants)
local function wp(x, z, alt, speed, tasks)
  return { type = "Turning Point", action = "Turning Point", x = x, y = z, alt = alt, alt_type = "BARO", speed = speed,
    speed_locked = true, ETA = 0, ETA_locked = false, task = { id = "ComboTask", params = { tasks = tasks or {} } } }
end
local O = AI.Option.Air
local function air(name, acType, fuel, count, route, alt, pylons, mode, target)
  local h = math_atan2(route[2][2] - route[1][2], route[2][1] - route[1][1])
  local units, pts = {}, {}
  for i = 1, count do
    units[i] = { name = name .. "-" .. i, type = acType, skill = "Excellent",
      x = route[1][1] - (i - 1) * 1500 * math_cos(h), y = route[1][2] - (i - 1) * 1500 * math_sin(h) + (i - 1) * 800,
      alt = alt, alt_type = "BARO", speed = 220, heading = h,
      payload = { pylons = pylons or {}, fuel = fuel, chaff = 60, flare = 60, gun = 100 }, callsign = { 1, 1, i },
      onboard_num = tostring(500 + i) }
  end
  local tasks1
  if mode == "sead" then
    tasks1 = { { id = "EngageTargets", enabled = true, auto = false, number = 1,
      params = { targetTypes = { "Air Defence" }, priority = 0 } } }
  elseif mode == "strike" then
    local g = Group.getByName(target)
    if g then tasks1 = { { id = "AttackGroup", enabled = true, auto = false, number = 1,
      params = { groupId = g:getID(), expend = "All", attackQtyLimit = false } } } end
  end
  for i = 1, #route do pts[i] = wp(route[i][1], route[i][2], alt, 220, i == 1 and tasks1 or nil) end
  local ok = safeCall("spawn " .. name, coalition.addGroup, BLUE_C, Group.Category.AIRPLANE,
    { name = name, task = mode == "sead" and "SEAD" or (mode == "strike" and "Ground Attack" or "CAP"), units = units,
      route = { points = pts } })
  log(string_format("SPAWN %s (%dx %s, %s%s) %s", name, count, acType, mode, target and (" at " .. target) or "", ok and "ok" or "FAILED"))
  timer_schedule(function()
    safeCall("options " .. name, function()
      local g = Group.getByName(name)
      if not g then return end
      local c = g:getController()
      c:setOption(O.id.ROE, mode == "bait" and O.val.ROE.WEAPON_HOLD or O.val.ROE.WEAPON_FREE)
      c:setOption(O.id.REACTION_ON_THREAT, O.val.REACTION_ON_THREAT.EVADE_FIRE)
      c:setOption(O.id.PROHIBIT_JETT, true)
      local u = g:getUnit(1)
      local okA, ammo = false, nil
      if u then okA, ammo = pcall(function() return u:getAmmo() end) end
      local parts = {}
      for _, a in ipairs(okA and ammo or {}) do
        parts[#parts + 1] = string_format("%s x%d", tostring(a.desc and a.desc.typeName), a.count or 0)
      end
      log(string_format("AMMO %s: %s", name, #parts > 0 and table.concat(parts, ", ") or "none"))
    end)
    return nil
  end, nil, timer_getTime() + 3)
end

local AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
local AGM45A = "{AGM_45A}"
local MK82 = "{BCE4E030-38E9-423E-98ED-24BE3DA87C32}"
local HARMS = { [3] = { CLSID = AGM88C }, [4] = { CLSID = AGM88C }, [6] = { CLSID = AGM88C }, [7] = { CLSID = AGM88C } }
local BOMBS = { [3] = { CLSID = MK82 }, [4] = { CLSID = MK82 }, [6] = { CLSID = MK82 }, [7] = { CLSID = MK82 } }
local s10 = POS["SAM SA-10 Centre"]
local tri = function(dx)
  return { { s10[1] - 130000 + dx, s10[2] - 40000 }, { s10[1] - 20000 + dx, s10[2] + 15000 },
           { s10[1] + 40000, s10[2] + 90000 }, { s10[1] + 60000, s10[2] + 160000 } }
end
local sead = function(dx)
  return { { s10[1] - 150000 + dx, s10[2] - 50000 }, { s10[1] - 60000 + dx, s10[2] - 10000 }, { s10[1] - 150000 + dx, s10[2] - 50000 } }
end
local strike = function(target)
  local p = POS[target]
  return { { p[1] - 140000, p[2] - 40000 }, { p[1] - 10000, p[2] - 3000 }, { p[1] - 140000, p[2] - 40000 } }
end
local sa2 = POS["SAM SA-2 West"]
local shrike = { { sa2[1] - 120000, sa2[2] - 20000 }, { sa2[1] - 30000, sa2[2] - 5000 }, { sa2[1] - 120000, sa2[2] - 20000 } }
at(60, "bait 1: 2x F-16C through the triangle", function() air("Blue Bait 1", "F-16C_50", 3249, 2, tri(0), 18000 * FT, nil, "bait") end)
at(150, "SEAD 1: 2x F-16C 4x AGM-88C", function() air("Blue SEAD 1", "F-16C_50", 3249, 2, sead(0), 22000 * FT, HARMS, "sead") end)
at(300, "Shrike: 1x F-4E 2x AGM-45A at the SA-2", function()
  air("Blue Shrike", "F-4E", 4864, 1, shrike, 18000 * FT, { [2] = { CLSID = AGM45A }, [8] = { CLSID = AGM45A } }, "sead") end)
at(420, "strike 1: 4x F-16C Mk-82 at the SA-6", function() air("Blue Strike 1", "F-16C_50", 3249, 4, strike("SAM SA-6 East"), 20000 * FT, BOMBS, "strike", "SAM SA-6 East") end)
at(540, "bait 2", function() air("Blue Bait 2", "F-16C_50", 3249, 2, tri(-8000), 15000 * FT, nil, "bait") end)
at(630, "SEAD 2", function() air("Blue SEAD 2", "F-16C_50", 3249, 2, sead(10000), 22000 * FT, HARMS, "sead") end)
at(900, "strike 2: 4x F-16C Mk-82 at the SA-11", function() air("Blue Strike 2", "F-16C_50", 3249, 4, strike("SAM SA-11 South"), 20000 * FT, BOMBS, "strike", "SAM SA-11 South") end)
at(960, "SEAD 3 with strike 2", function() air("Blue SEAD 3", "F-16C_50", 3249, 2, sead(-5000), 22000 * FT, HARMS, "sead") end)

-- ------------------------------------------------------------------ recording and score
local S = { blueLost = 0, redLost = 0, redRadarsLost = 0, harms = 0, harmHits = 0, redShots = 0, emitSec = 0, usefulSec = 0 }
local isRadar = {}
for _, n in ipairs(RADAR_UNITS) do isRadar[n] = true end
local deadSeen = {}
local arms = {}
local function wrapHandler(fn)
  return function(...)
    local args, n = { ... }, select("#", ...)
    safeCall("handler", function() return fn(unpack(args, 1, n)) end)
  end
end
local function lost(obj, how)
  local name = safeName(obj)
  if deadSeen[name] then return end
  deadSeen[name] = true
  local coa = safeCoa(obj)
  if coa == 2 then S.blueLost = S.blueLost + 1
  elseif coa == 1 then
    S.redLost = S.redLost + 1
    if isRadar[name] then S.redRadarsLost = S.redRadarsLost + 1 end
  end
  log(string_format("LOST %s %s (%s) side %d%s", how, name, safeType(obj), coa, isRadar[name] and " RADAR" or ""))
end
local handler = {}
handler.onEvent = wrapHandler(function(_, e)
  local E = world.event
  if e.id == E.S_EVENT_SHOT then
    local w = e.weapon
    local okD, desc = pcall(function() return w:getDesc() end)
    local arm = okD and desc and desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE
    if arm then
      S.harms = S.harms + 1
      arms[#arms + 1] = { w = w, id = S.harms, type = safeType(w), shooter = safeName(e.initiator), t0 = now() }
    elseif safeCoa(e.initiator) == 1 then
      S.redShots = S.redShots + 1
    end
    local tgt = w and w.getTarget and w:getTarget() or nil
    log(string_format("SHOT%s shooter=%s (%s) weapon=%s target=%s", arm and (" ARM#" .. S.harms) or "", safeName(e.initiator),
      safeType(e.initiator), safeType(w), safeName(tgt)))
  elseif e.id == E.S_EVENT_HIT and safeCat(e.target) == Object.Category.UNIT then
    local okD, desc = pcall(function() return e.weapon:getDesc() end)
    if okD and desc and desc.guidance == Weapon.GuidanceType.RADAR_PASSIVE and safeCoa(e.target) == 1 then
      S.harmHits = S.harmHits + 1
    end
    log(string_format("HIT weapon=%s target=%s (%s)", safeType(e.weapon), safeName(e.target), safeType(e.target)))
  elseif (e.id == E.S_EVENT_DEAD or e.id == E.S_EVENT_CRASH or e.id == E.S_EVENT_UNIT_LOST)
    and safeCat(e.initiator) == Object.Category.UNIT then
    lost(e.initiator, e.id == E.S_EVENT_CRASH and "crash" or "dead")
  end
end)
world.addEventHandler(handler)

-- every 5 s: which red radars are emitting (Unit.getRadar), and was a blue aircraft within 100 km of it
local POLL = 5
local emitting = {}
timer_schedule(function(_, t)
  safeCall("emit", function()
    local blue = {}
    for _, g in ipairs(coalition.getGroups(2, Group.Category.AIRPLANE) or {}) do
      for _, u in ipairs(g:getUnits() or {}) do
        if u:isExist() then blue[#blue + 1] = u:getPoint() end
      end
    end
    for _, n in ipairs(RADAR_UNITS) do
      local u = Unit.getByName(n)
      if u and u:isExist() then
        local okR, on = pcall(function() return u:getRadar() end)
        on = okR and on and true or false
        if on ~= (emitting[n] or false) then
          emitting[n] = on
          log(string_format("RADAR %s %s", n, on and "ON" or "off"))
        end
        if on then
          S.emitSec = S.emitSec + POLL
          local p = u:getPoint()
          for _, q in ipairs(blue) do
            local dx, dz = q.x - p.x, q.z - p.z
            if dx * dx + dz * dz <= 1e10 then S.usefulSec = S.usefulSec + POLL; break end
          end
        end
      end
    end
  end)
  return t + POLL
end, nil, timer_getTime() + POLL)

-- ARM flights: closest approach to any red radar unit
timer_schedule(function(_, t)
  safeCall("arms", function()
    for i = #arms, 1, -1 do
      local a = arms[i]
      local okE, ex = pcall(function() return a.w:isExist() end)
      if okE and ex then
        local q = a.w:getPoint()
        for _, n in ipairs(RADAR_UNITS) do
          local u = Unit.getByName(n)
          if u and u:isExist() then
            local p = u:getPoint()
            local d = math_sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
            if not a.minD or d < a.minD then a.minD, a.minName = d, n end
          end
        end
      else
        log(string_format("ARM END #%d %s from %s after %.0f s: closest %.0f m to %s", a.id, a.type, a.shooter,
          now() - a.t0, a.minD or -1, tostring(a.minName)))
        table.remove(arms, i)
      end
    end
  end)
  return t + 1
end, nil, timer_getTime() + 5)

at(END_T, "END: bench 07 complete", function()
  local score = 3 * S.blueLost - 3 * S.redRadarsLost - (S.redLost - S.redRadarsLost) + (S.harms - S.harmHits)
  log(string_format("SCORE variant=%s blueLost=%d redRadarsLost=%d redLost=%d harms=%d harmHits=%d redShots=%d emitMin=%.1f usefulMin=%.1f score=%d",
    VARIANT, S.blueLost, S.redRadarsLost, S.redLost, S.harms, S.harmHits, S.redShots, S.emitSec / 60, S.usefulSec / 60, score))
  if VARIANT == "JANUS" and JANUS.arm and JANUS.arm.stats then
    local st = JANUS.arm.stats
    log(string_format("ARM STATS launched %d, hits %d (on dark radars %d)", st.launched, st.hits, st.hitsDark))
  end
  log("BENCH 07 COMPLETE")
end)

log(string_format("bench %s (%s) loaded; red at %.0f/%.0f from anchor; %d radar units timed", B.VERSION, VARIANT,
  Cx - x0, Cz - z0, #RADAR_UNITS))
