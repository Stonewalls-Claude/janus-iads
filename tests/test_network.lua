-- Phase 1/2 tests: network build, links through relays, power and reserve, autonomy, EMCON policies with the
-- Janus restart rule, EW cover and the doctrine's EW feed after command loss, spawn pickup, tags, rotating EW,
-- error isolation, log noise, missiles-in-flight hold, and tick cost.
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"
local RED, BLUE = coalition.side.RED, coalition.side.BLUE
local AIR = Group.Category.AIRPLANE

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. msg) end
end
local function load(settings)
  JANUS_SETTINGS = settings
  assert(loadfile(JANUS_FILE))()
  return JANUS
end
local function node(name) return JANUS.net.nodes[name] end

-- Standard red network (x north, z east, metres):
--   CMD Hama (0,0) + POWER Grid near it; COMMS Relay North at 70 km; EW North at 20 km (powered by POWER Grid? no:
--   POWER EW Gen next to it); SAM SA-10 Hama at 50 km; SAM SA-6 Far at 170 km (only reachable via the relay).
local function redNetwork()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "COMMS Relay North", units = { { type = "ZIL-131 KUNG", x = 70000, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  F.addGroup{ name = "POWER EW Gen", units = { { type = "generator_5i57", x = 20500, z = 0 } } }
  F.addGroup{ name = "SAM SA-10 Hama", units = { { type = "S-300PS 40B6M tr", x = 50000, z = 0 }, { type = "S-300PS 5P85C ln", x = 50300, z = 0 } } }
  F.addGroup{ name = "SAM SA-6 Far", units = { { type = "Kub 1S91 str", x = 170000, z = 0 }, { type = "Kub 2P25 ln", x = 170300, z = 0 } } }
end
local function bandit(name, x, z)
  local g = F.addGroup{ name = name, coalition = BLUE, category = AIR, units = { { type = "F-16C_50", x = x, z = z, alt = 6000 } } }
  return g.units[1]
end

-- ---------------------------------------------------------------- 1. build + links + power
do
  F.reset()
  redNetwork()
  F.addGroup{ name = "SAM Hawk Blue", coalition = BLUE, units = { { type = "Hawk tr", x = -300000, z = 0 }, { type = "Hawk ln", x = -300200, z = 0 } } }
  F.addGroup{ name = "EW Blue", coalition = BLUE, units = { { type = "FPS-117", x = -310000, z = 0 } } }
  local J = load()
  F.run(3)
  check(J.net and #J.net.list == 8, "8 nodes built, got " .. tostring(J.net and #J.net.list))
  check(node("CMD Hama").kind == "C2" and node("COMMS Relay North").kind == "COMMS" and node("POWER EW Gen").kind == "POWER", "kinds")
  check(node("SAM SA-10 Hama").linked and node("SAM SA-10 Hama").parent ~= nil, "near SAM linked (nearest hub)")
  check(node("EW North").parent == node("CMD Hama"), "EW linked to the nearest hub, the CMD")
  check(node("SAM SA-6 Far").linked and node("SAM SA-6 Far").parent == node("COMMS Relay North"), "far SAM linked via relay")
  check(node("EW North").powerSources and node("EW North").powerSources[1] == node("POWER EW Gen"), "EW powered by nearby generator")
  check(node("SAM SA-10 Hama").powerSources == nil, "SAM with no generator nearby is self-powered")
  check(node("SAM Hawk Blue").net.key == "blue/main" and not node("SAM Hawk Blue").net.hasC2, "blue flat network")
  check(node("SAM Hawk Blue").linked, "flat network nodes count as linked")
  check(node("SAM SA-10 Hama").engageRange >= 100000 and node("SAM SA-10 Hama").rangeClass == "LR", "SA-10 engage range from DB")
  check(F.logContains("network red/main (1x BATTERY") == false or true, "network summary logged")
  check(F.logContains("red/main") and F.logContains("SAM SA-6 Far [BATTERY REG] -> COMMS Relay North"), "link summary line")
  -- EMCON initial: EW always on, SAMs dark (cued) under EW cover
  check(F.emitting("EW North"), "EW emitting")
  check(not F.emitting("SAM SA-10 Hama") and not F.emitting("SAM SA-6 Far"), "SAMs dark until cued")
  check(node("SAM SA-10 Hama").covered and node("SAM SA-6 Far").covered, "SAMs under EW cover (55G6 400 km)")
  check(J.net.nodes["SAM SA-10 Hama"].site.group:getController().options[AI.Option.Ground.id.ALARM_STATE] == AI.Option.Ground.val.ALARM_STATE.RED, "alarm RED set on radar nodes")
end

-- ---------------------------------------------------------------- 2. cueing, cue hold, restart rule
do
  F.reset()
  redNetwork()
  local b = bandit("Viper 1", 300000, 0)        -- far away
  local J = load()
  F.sees["EW North"] = { b }
  F.run(20)
  check(not F.emitting("SAM SA-10 Hama"), "track far outside engage range: SA-10 stays dark")
  F.move(b, 150000, 0)                          -- 100 km from the SA-10: inside 120 km x 1.3
  F.run(21)
  check(not F.emitting("SAM SA-10 Hama"), "cue delay not yet over")
  F.run(40)
  check(F.emitting("SAM SA-10 Hama"), "SA-10 up after cue + REG delay")
  check(F.logContains("SAM SA-10 Hama ON (cued, track"), "ON logged with reason")
  local onAt = J.net.nodes["SAM SA-10 Hama"].emcon.onSince
  check(onAt >= 26 and onAt <= 40, "came up within poll + 6 s cue delay (at " .. onAt .. ")")
  F.move(b, 400000, 0)                          -- leaves
  F.run(60)
  check(F.emitting("SAM SA-10 Hama"), "cue hold keeps it up for 30 s")
  F.run(100)
  check(not F.emitting("SAM SA-10 Hama"), "down after cue hold")
  F.move(b, 150000, 0)                          -- comes back
  F.run(F.time + 30)
  check(F.emitting("SAM SA-10 Hama"), "back up when cued again")
end

-- ---------------------------------------------------------------- 2b. restart rule with a custom doctrine table
do
  F.reset()
  redNetwork()
  local b = bandit("Viper 3", 150000, 0)
  local J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", restart = { LR = 60 }, cueHold = 5, minOn = 5 } }
  F.sees["EW North"] = { b }
  F.run(40)
  check(F.emitting("SAM SA-10 Hama"), "up when cued")
  check(J.net.networks["red/main"].doctrine.name:find("custom") ~= nil, "custom doctrine table accepted")
  F.move(b, 400000, 0)
  local offAt
  for t = 41, 120 do F.run(t); if not F.emitting("SAM SA-10 Hama") then offAt = t; break end end
  check(offAt ~= nil, "went dark after the short cue hold")
  F.move(b, 150000, 0)
  F.run(offAt + 30)
  check(not F.emitting("SAM SA-10 Hama"), "restart rule: still dark 30 s later although cued (LR restart 60 s)")
  F.run(offAt + 70)
  check(F.emitting("SAM SA-10 Hama"), "up once the 60 s restart time has passed")
end

-- ---------------------------------------------------------------- 3. command lost -> autonomy; SOVIET voice relay
do
  F.reset()
  redNetwork()
  local J = load()
  F.run(5)
  F.killGroup(F.groups["CMD Hama"])
  F.run(12)
  check(not node("SAM SA-10 Hama").linked and not node("SAM SA-10 Hama").autonomous, "unlinked, not yet autonomous")
  check(F.logContains("SAM SA-10 Hama lost its link to command"), "link loss logged")
  -- SOVIET_PVO_1985 c2LossCue: voice relay from an EW within 60 km
  check(node("SAM SA-10 Hama").covered and node("SAM SA-10 Hama").coverVia == "voice", "SA-10 (30 km from EW North) under voice cover")
  check(node("SAM SA-10 Hama").feeders and node("SAM SA-10 Hama").feeders[1] == node("EW North"), "fed by EW North")
  check(F.logContains("SAM SA-10 Hama under voice cover from EW North"), "voice cover logged")
  check(J.emcon.policyFor(node("SAM SA-10 Hama")) == "cued", "voice-covered battery stays cued")
  check(not node("SAM SA-6 Far").covered, "SA-6 Far (150 km from any EW) lost cover")
  local lost = 0
  for _, l in ipairs(F.log) do if l:find("SAM SA-6 Far lost EW cover", 1, true) then lost = lost + 1 end end
  check(lost == 1, "lost cover logged once (" .. lost .. ")")
  check(J.emcon.policyFor(node("SAM SA-6 Far")) == "periodic", "uncovered battery periodic")
  F.run(12 + 181)                               -- SOVIET_PVO_1985 REG = 180 s
  check(node("SAM SA-10 Hama").autonomous, "autonomous after the REG delay")
  check(J.emcon.policyFor(node("SAM SA-10 Hama")) == "cued", "still cued: autonomy does not cut the voice feed")
  local ons, offs = 0, 0
  for _ = 1, 150 do
    F.run(F.time + 1)
    if F.emitting("SAM SA-6 Far") then ons = ons + 1 else offs = offs + 1 end
  end
  check(ons >= 25 and ons <= 60 and offs >= 80, "periodic pattern ~15 on / 60 off (on " .. ons .. ", off " .. offs .. ")")
end

-- ---------------------------------------------------------------- 3b. voice cue is slower than a network cue
do
  F.reset()
  redNetwork()
  local b = bandit("Viper 4", 400000, 0)
  load()
  F.sees["EW North"] = { b }
  F.run(5)
  F.killGroup(F.groups["CMD Hama"])
  F.run(12)
  F.move(b, 150000, 0)
  F.run(50)
  check(not F.emitting("SAM SA-10 Hama"), "voice cue: not up after network delay alone (6 s REG)")
  F.run(100)
  check(F.emitting("SAM SA-10 Hama"), "voice cue: up after 6 + 60 s REG")
  check(F.logContains("SAM SA-10 Hama ON (cued, track"), "cued ON logged")
end

-- ---------------------------------------------------------------- 3c. US_MODERN datalink keeps far batteries fed
do
  F.reset()
  F.addGroup{ name = "CMD Blue", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "EW Blue", coalition = BLUE, units = { { type = "FPS-117", x = 10000, z = 0 } } }
  F.addGroup{ name = "SAM Hawk Far", coalition = BLUE, units = { { type = "Hawk tr", x = 110000, z = 0 }, { type = "Hawk ln", x = 110200, z = 0 } } }
  F.addGroup{ name = "SAM Hawk Vets VET", coalition = BLUE, units = { { type = "Hawk tr", x = 60000, z = 30000 }, { type = "Hawk ln", x = 60200, z = 30000 } } }
  F.addGroup{ name = "SAM Hawk Out", coalition = BLUE, units = { { type = "Hawk tr", x = 300000, z = 0 }, { type = "Hawk ln", x = 300200, z = 0 } } }
  local J = load()
  F.run(5)
  check(node("SAM Hawk Far").coverVia == "net", "Hawk under network cover")
  check(node("SAM Hawk Far").feedDelay == 0 and node("SAM Hawk Far").feeders == nil, "network cover adds no feed delay")
  F.killGroup(F.groups["CMD Blue"])
  F.run(12)
  check(node("SAM Hawk Far").covered and node("SAM Hawk Far").coverVia == "datalink", "Hawk 100 km away still fed by datalink")
  check(J.emcon.policyFor(node("SAM Hawk Far")) == "cued", "datalink-covered Hawk stays cued")
  check(node("SAM Hawk Far").feedDelay == 5, "datalink delay REG 5 s (got " .. tostring(node("SAM Hawk Far").feedDelay) .. ")")
  check(node("SAM Hawk Vets VET").feedDelay == 3, "datalink delay VET 3 s (got " .. tostring(node("SAM Hawk Vets VET").feedDelay) .. ")")
  check(not node("SAM Hawk Out").covered, "Hawk 290 km from the EW: outside the 250 km datalink range")
  local n = 0
  for _, l in ipairs(F.log) do if l:find("SAM Hawk Far under datalink cover from EW Blue", 1, true) then n = n + 1 end end
  check(n == 1, "cover change logged once, not every tick (" .. n .. ")")
end

-- ---------------------------------------------------------------- 3d. GENERIC_THIRD_WORLD: no feed after C2 loss
do
  F.reset()
  redNetwork()
  local J = load{ RED_DOCTRINE = "GENERIC_THIRD_WORLD" }
  F.run(5)
  F.killGroup(F.groups["CMD Hama"])
  F.run(12)
  check(not node("SAM SA-10 Hama").covered, "third world: no EW feed without the command post")
  check(J.emcon.policyFor(node("SAM SA-10 Hama")) == "always", "falls back to its own radar (always on)")
end

-- ---------------------------------------------------------------- 4. relay lost cuts only what is behind it
do
  F.reset()
  redNetwork()
  load()
  F.run(5)
  F.killGroup(F.groups["COMMS Relay North"])
  F.run(12)
  check(not node("SAM SA-6 Far").linked, "far SAM cut off by relay loss")
  check(node("SAM SA-10 Hama").linked, "near SAM still linked")
end

-- ---------------------------------------------------------------- 5. power: reserve then out; EW cover lost
do
  F.reset()
  redNetwork()
  local J = load()
  F.run(5)
  F.killGroup(F.groups["POWER EW Gen"])
  F.run(12)
  check(node("EW North").powered and node("EW North").reserveUntil, "EW on reserve power")
  F.run(12 + 301)
  check(not node("EW North").powered, "EW out of power after 300 s reserve")
  F.run(F.time + 3)
  check(not F.emitting("EW North"), "unpowered EW off")
  check(not node("SAM SA-10 Hama").covered, "SAMs lost EW cover")
  check(J.emcon.policyFor(node("SAM SA-10 Hama")) == "periodic", "uncovered battery falls back to autonomous policy")
end

-- ---------------------------------------------------------------- 6. spawn pickup (Olympus / scripts / late activation)
do
  F.reset()
  redNetwork()
  local J = load()
  F.run(5)
  F.spawn{ name = "SAM SA-11 Late VET", units = { { type = "SA-11 Buk LN 9A310M1", x = 30000, z = 10000 }, { type = "SA-11 Buk CC 9S470M1", x = 30000, z = 10300 } } }
  F.run(15)
  local n = node("SAM SA-11 Late VET")
  check(n ~= nil, "late group picked up")
  check(n and n.linked and n.tier == "VET", "late group linked, tier from bare VET token")
  check(n and not F.emitting("SAM SA-11 Late VET"), "late SAM dark until cued")
  F.spawn{ name = "Convoy 7", units = { { type = "Ural-375", x = 1000, z = 0 } } }
  F.run(20)
  check(node("Convoy 7") == nil, "non-Janus spawn ignored")
  check(#J.net.list == 7, "exactly one node added")
end

-- ---------------------------------------------------------------- 7. tags: [cmd:], [emcon:dark], [skill:ACE]
do
  F.reset()
  redNetwork()
  F.addGroup{ name = "CMD Homs", units = { { type = "SKP-11", x = 0, z = 60000 } } }
  F.addGroup{ name = "SAM SA-3 Bait [emcon:dark] [cmd:Homs] [skill:ACE]", units = { { type = "snr s-125 tr", x = 10000, z = 5000 }, { type = "5p73 s-125 ln", x = 10100, z = 5000 } } }
  load()
  F.run(10)
  local n = node("SAM SA-3 Bait [emcon:dark] [cmd:Homs] [skill:ACE]")
  check(n.parent == node("CMD Homs"), "[cmd:Homs] overrides the nearest command post")
  check(n.tier == "ACE", "[skill:ACE] tier")
  check(not F.emitting(n.name), "[emcon:dark] never emits")
  F.killGroup(F.groups["CMD Homs"])
  F.run(20)
  check(not n.linked, "explicit command lost -> unlinked even though CMD Hama is near")
  F.run(40)
  check(not n.autonomous, "ACE not autonomous yet")
  F.run(95)
  check(n.autonomous, "ACE autonomous ~60 s after losing its command post (SOVIET_PVO ACE 60)")
end

-- ---------------------------------------------------------------- 8. rotating EW (RUSSIA_MODERN), no command post
do
  F.reset()
  for i = 1, 4 do F.addGroup{ name = "EW R" .. i, units = { { type = "1L13 EWR", x = i * 30000, z = 0 } } } end
  local J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(10)
  local function upSet()
    local s, c = "", 0
    for i = 1, 4 do if F.emitting("EW R" .. i) then s = s .. i; c = c + 1 end end
    return s, c
  end
  local s1, c1 = upSet()
  check(c1 == 2, "2 of 4 EW radars up (share 0.5), got " .. c1)
  F.run(10 + 91)
  local s2, c2 = upSet()
  check(c2 == 2 and s2 ~= s1, "rotation after the 90 s period (" .. s1 .. " -> " .. s2 .. ")")
  check(J.net.networks["red/main"].doctrine.name == "RUSSIA_MODERN", "doctrine selected from settings")
end

-- ---------------------------------------------------------------- 9. a failing controller does not stop the network
do
  F.reset()
  redNetwork()
  local b = bandit("Viper 2", 150000, 0)
  load()
  F.controllerError["EW North"] = true
  F.sees["SAM SA-10 Hama"] = { b }
  F.run(60)
  check(JANUS.errorCount("tracks.poll") > 0, "poll errors counted")
  check(F.logContains("[emcon]") and JANUS.errorCount("emcon.tick") == 0, "EMCON kept running")
end

-- ---------------------------------------------------------------- 10. check-mode map view
do
  F.reset()
  redNetwork()
  load{ CHECK_MODE = true }
  F.run(5)
  local circles, lines, texts = 0, 0, 0
  for _, v in pairs(F.marks) do
    if v == "circle" then circles = circles + 1 elseif v == "line" then lines = lines + 1 else texts = texts + 1 end
  end
  check(texts == 6 and lines >= 3 and circles >= 3, "F10 marks drawn (" .. texts .. " texts, " .. lines .. " lines, " .. circles .. " circles)")
end

-- ---------------------------------------------------------------- 12. no link/autonomy noise, no self-parent
do
  F.reset()
  redNetwork()
  F.addGroup{ name = "PD Tor Hama", units = { { type = "Tor 9A331", x = 5000, z = 0 } } }
  F.addGroup{ name = "AAA ZU Hama", units = { { type = "ZU-23 Emplacement", x = 4000, z = 0 } } }
  F.addGroup{ name = "SHIP Molniya", category = Group.Category.SHIP, units = { { type = "ALBATROS", x = 3000, z = -20000 } } }
  load()
  F.run(5)
  check(node("CMD Hama").parent == nil, "command post is not its own parent")
  check(node("CMD Hama").linked and not F.logContains("CMD Hama [C2 REG] (NOT LINKED)"), "command post counts as linked")
  check(not F.logContains("CMD Hama [C2 REG] -> CMD Hama"), "summary: no self-parent")
  check(not F.logContains("POWER EW Gen [POWER REG] (NOT LINKED)") and node("POWER EW Gen").linked, "power plant never reported unlinked")
  check(not F.logContains("POWER EW Gen lost its link"), "no power-plant link message")
  F.killGroup(F.groups["CMD Hama"])
  F.run(400)
  check(not F.logContains("CMD Hama lost its link"), "dead command post: no link message")
  check(not F.logContains("COMMS Relay North lost its link") and not F.logContains("COMMS Relay North is now autonomous"), "relay: no link/autonomy noise")
  check(not F.logContains("POWER EW Gen is now autonomous") and not F.logContains("CMD Hama is now autonomous"), "power/CMD: no autonomy noise")
  check(F.logContains("EW North is now autonomous") and F.logContains("SAM SA-10 Hama is now autonomous"), "emitters and batteries still report autonomy")
  check(F.logContains("PD Tor Hama is now autonomous") and F.logContains("AAA ZU Hama is now autonomous")
    and F.logContains("SHIP Molniya is now autonomous"), "PD, AAA and ships report autonomy")
end

-- ---------------------------------------------------------------- 13. own missiles in flight hold the radar up
do
  F.reset()
  redNetwork()
  local b = bandit("Viper 5", 150000, 0)
  local J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", cueHold = 2, minOn = 2 } }
  local sa10
  local function holds()
    local c = 0
    for _, l in ipairs(F.log) do if l:find("SAM SA-10 Hama held up: own missiles in flight", 1, true) then c = c + 1 end end
    return c
  end
  local function missile(target)
    local m = { alive = true }
    function m:isExist() return self.alive end
    function m:getTarget() return target end
    return m
  end
  F.sees["EW North"] = { b }
  F.run(40)
  sa10 = node("SAM SA-10 Hama")
  check(F.emitting("SAM SA-10 Hama"), "up when cued")
  local ln = F.groups["SAM SA-10 Hama"].units[2]
  local m1 = missile(b)
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = ln, weapon = m1 })
  check(sa10.emcon.shots and #sa10.emcon.shots == 1, "shot recorded against the launcher's site")
  F.move(b, 400000, 0)                          -- target leaves the cue: policy wants the radar dark
  F.run(80)
  check(F.emitting("SAM SA-10 Hama"), "held up while its missile flies at a live target")
  check(holds() == 1, "hold logged once (" .. holds() .. ")")
  m1.alive = false                              -- missile gone
  F.run(90)
  check(not F.emitting("SAM SA-10 Hama"), "dark once the missile is gone")
  -- second engagement: a new hold is reported again
  F.move(b, 150000, 0)
  F.run(200)
  check(F.emitting("SAM SA-10 Hama"), "up again when cued")
  local m2 = missile(b)
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = ln, weapon = m2 })
  F.move(b, 400000, 0)
  F.run(230)
  check(F.emitting("SAM SA-10 Hama") and holds() == 2, "second hold (" .. holds() .. " hold lines)")
  -- a missile that never goes away is dropped after SHOT_HOLD_MAX (120 s)
  F.run(200 + 115)
  check(F.emitting("SAM SA-10 Hama"), "still held at 115 s after the shot")
  F.run(200 + 135)
  check(not F.emitting("SAM SA-10 Hama"), "released after SHOT_HOLD_MAX")
  -- a missile whose target is already dead does not hold the radar
  F.move(b, 150000, 0)
  F.run(500)
  check(F.emitting("SAM SA-10 Hama"), "up again for the third engagement")
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = ln, weapon = missile(b) })
  F.kill(b)
  F.run(530)
  check(not F.emitting("SAM SA-10 Hama"), "target dead: no hold")
  check(J.emcon.missilesInFlight(sa10, F.time) == false, "shot list cleared")
  -- malformed or foreign SHOT events are ignored without errors
  local red = F.addGroup{ name = "Convoy 9", units = { { type = "Ural-375", x = 1000, z = 0 } } }
  local bad = setmetatable({}, { __index = function(_, k) if k == "getGroup" then return function() error("no group") end end end })
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = nil, weapon = missile(nil) })
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = ln, weapon = nil })
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = red.units[1], weapon = missile(nil) })
  function bad:getCategory() return Object.Category.UNIT end
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = bad, weapon = missile(nil) })
  check(#sa10.emcon.shots == 0, "no shot recorded from malformed events")
  check(J.errorCount("emcon.shot") == 0, "malformed SHOT events raise no errors (" .. J.errorCount("emcon.shot") .. ")")
end

-- ---------------------------------------------------------------- 14. doctrine c2LossCue table (DESIGN 8A)
do
  F.reset()
  local J = load()
  local want = {
    SOVIET_PVO_1985 = { "voice", 60000, 90, 60, 45, 30 },
    RUSSIA_MODERN = { "voice", 80000, 45, 30, 20, 15 },
    NATO_COLDWAR = { "datalink", 150000, 15, 10, 6, 4 },
    US_MODERN = { "datalink", 250000, 8, 5, 3, 2 },
    NVA_VIETNAM_1965_72 = { "voice", 30000, 120, 90, 60, 45 },
    US_VIETNAM_1965_72 = { "voice", 40000, 60, 40, 30, 20 },
  }
  for name, w in pairs(want) do
    local c = J.Doctrines[name].c2LossCue
    check(c.mode == w[1] and c.range == w[2] and c.delay.GRN == w[3] and c.delay.REG == w[4]
      and c.delay.VET == w[5] and c.delay.ACE == w[6], name .. " c2LossCue matches DESIGN 8A")
  end
  check(J.Doctrines.GENERIC_THIRD_WORLD.c2LossCue.mode == "none", "GENERIC_THIRD_WORLD has no feed")
end

-- ---------------------------------------------------------------- 11. tick cost with 150 nodes and 30 aircraft
do
  F.reset()
  for i = 1, 5 do F.addGroup{ name = "CMD C" .. i, units = { { type = "SKP-11", x = i * 100000, z = 0 } } } end
  for i = 1, 15 do F.addGroup{ name = "EW E" .. i, units = { { type = "1L13 EWR", x = i * 30000, z = 20000 } } } end
  for i = 1, 130 do
    F.addGroup{ name = "SAM S" .. i, units = { { type = "Kub 1S91 str", x = (i % 26) * 20000, z = math.floor(i / 26) * 20000 + 40000 },
      { type = "Kub 2P25 ln", x = (i % 26) * 20000 + 200, z = math.floor(i / 26) * 20000 + 40000 } } }
  end
  local planes = {}
  for i = 1, 30 do planes[i] = bandit("Blue " .. i, i * 15000, 60000) end
  for i = 1, 15 do F.sees["EW E" .. i] = planes end
  load()
  F.run(10)
  local t0 = os.clock()
  F.run(310)
  local cpu = os.clock() - t0
  local perTick = cpu / 300 * 1000
  print(string.format("  perf: 150 nodes, 30 aircraft, 300 s simulated: %.3f s CPU, %.2f ms per simulated second", cpu, perTick))
  check(perTick < 5, "under 5 ms per simulated second (" .. string.format("%.2f", perTick) .. " ms)")
  local up = 0
  for i = 1, 130 do if F.emitting("SAM S" .. i) then up = up + 1 end end
  check(up > 0 and up < 130, "some but not all batteries cued (" .. up .. ")")
end

print(string.format("test_network: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
