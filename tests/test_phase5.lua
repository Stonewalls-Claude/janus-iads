-- Phase 5 tests: the scripter's API (events, runtime changes, reading), the stats module, the base warning.
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
local function count(pattern)
  local n = 0
  for _, l in ipairs(F.log) do if l:find(pattern, 1, true) then n = n + 1 end end
  return n
end
local freshReset = F.reset
F.reset = function()
  if JANUS then check(not F.logContains("ERROR JANUS"), "no Janus errors before a reset (t=" .. F.time .. ")") end
  freshReset()
end

-- ---------------------------------------------------------------- 1. events
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "1L13 EWR", x = 0, z = 5000 } } }
  F.addGroup{ name = "SAM SA-6 A", units = { { type = "Kub 1S91 str", x = 10000, z = 0 }, { type = "Kub 2P25 ln", x = 10200, z = 0 } } }
  local jet = F.addGroup{ name = "Viper", coalition = BLUE, category = AIR, units = { { type = "F-16C_50", x = 30000, z = 0, alt = 4000 } } }.units[1]
  local J = load()
  local got = {}
  local function rec(ev) got[#got + 1] = ev end
  local h1 = J.subscribe("engage", rec, "mine")
  check(J.subscribe("engage", rec, "mine") == h1, "same key: same handle, replaced not added")
  check(J.subscribe("nonsense", rec) == nil and J.subscribe("engage", "x") == nil, "unknown event or no function: nil")
  J.subscribe("emission", rec)
  J.subscribe("nodeLost", rec)
  J.subscribe("nodeDegraded", rec)
  J.subscribe("nodeRestored", rec)
  J.subscribe("harmDetected", rec)
  J.subscribe("engage", function() error("subscriber bug") end, "bad")
  F.sees["EW North"] = { jet }
  F.run(10)
  local byEv = {}
  for _, e in ipairs(got) do byEv[e.event] = byEv[e.event] or {}; table.insert(byEv[e.event], e) end
  local en = byEv.engage and byEv.engage[1]
  check(en and en.site == "SAM SA-6 A" and en.coalition == RED and en.net == "red/main" and en.unitId == jet:getID()
    and en.typeName == "F-16C_50" and en.pk > 0 and en.from == nil and en.t > 0, "engage event: site, track, Pk")
  check(#byEv.engage == 1, "one engage event (the bad subscriber called separately)")
  check(F.logContains("api.subscriber.engage"), "a subscriber's error is caught and logged")
  for i = #F.log, 1, -1 do if F.log[i]:find("api.subscriber.engage", 1, true) then table.remove(F.log, i) end end
  local on
  for _, e in ipairs(byEv.emission or {}) do if e.site == "SAM SA-6 A" and e.on then on = e end end
  check(on and on.reason ~= nil, "emission event when the SA-6 comes up")
  -- lose the EW: nodeLost; unpower nothing; SA-6 cut off by killing the post -> degraded / autonomy
  F.kill(F.groups["EW North"].units[1])
  F.run(20)
  local lostEv
  for _, e in ipairs(byEv.nodeLost or got) do if e.event == "nodeLost" and e.site == "EW North" then lostEv = e end end
  check(lostEv and lostEv.kind == "EW", "nodeLost event")
  -- unsubscribe stops events
  check(J.unsubscribe(h1) and not J.unsubscribe(h1), "unsubscribe once")
  local before = 0
  for _, e in ipairs(got) do if e.event == "engage" then before = before + 1 end end
  J.setWeapons(RED, "hold"); J.setWeapons(RED, "free")
  F.move(jet, 25000, 0)
  F.run(40)
  local after = 0
  for _, e in ipairs(got) do if e.event == "engage" then after = after + 1 end end
  check(after == before, "no engage events after unsubscribe")
end

-- ---------------------------------------------------------------- 1a. nodeDegraded / nodeRestored, assigned list
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "1L13 EWR", x = 0, z = 5000 } } }
  local sam = F.addGroup{ name = "SAM SA-6 A", units = { { type = "Kub 1S91 str", x = 10000, z = 300 }, { type = "Kub 2P25 ln", x = 10200, z = 300 } } }
  local jet = F.addGroup{ name = "Viper", coalition = BLUE, category = AIR, units = { { type = "F-16C_50", x = 30000, z = 0, alt = 4000 } } }.units[1]
  local J = load()
  local got = {}
  J.subscribe("nodeDegraded", function(ev) got[#got + 1] = ev end)
  J.subscribe("nodeRestored", function(ev) got[#got + 1] = ev end)
  F.sees["EW North"] = { jet }
  F.run(10)
  local s = J.site("SAM SA-6 A")
  check(#s.assigned == 1 and s.assigned[1] == 1 and s.z == 300, "site(): the track it is assigned (T1), position")
  F.sees["EW North"] = {}
  for _, u in ipairs(sam.units) do F.move(u, u.x + 300000, u.z) end
  F.run(30)
  check(got[1] and got[1].event == "nodeDegraded" and got[1].site == "SAM SA-6 A" and got[1].reason == "unlinked"
    and got[1].kind == "BATTERY", "moved out of link range: nodeDegraded (unlinked)")
  for _, u in ipairs(sam.units) do F.move(u, u.x - 300000, u.z) end
  F.run(50)
  local r = got[#got]
  check(r and r.event == "nodeRestored" and r.site == "SAM SA-6 A" and r.reason == "linked", "back in range: nodeRestored (linked)")
end

-- ---------------------------------------------------------------- 1b. harmDetected (ARM test block 2 scenario)
do
  F.reset()
  F.rnd = 0
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = -20000 } } }
  F.addGroup{ name = "SAM SA-6 A [emcon:always]", units = { { type = "Kub 1S91 str", x = 0, z = 0 }, { type = "Kub 2P25 ln", x = 300, z = 0 } } }
  local viper = F.addGroup{ name = "Viper 1", coalition = BLUE, category = AIR, units = { { type = "F-16C_50", x = 200000, z = 0, alt = 6000 } } }.units[1]
  local J = load()
  local got = {}
  J.subscribe("harmDetected", function(ev) got[#got + 1] = ev end)
  F.run(3)
  F.launch{ shooter = viper, type = "AGM_88", x = 60000, y = 5000, z = 0, vx = -600, vz = 0 }
  F.run(66)
  check(#got == 1 and got[1].arm == "A1" and got[1].site == "SAM SA-6 A [emcon:always]" and got[1].how == "radar"
    and got[1].coalition == RED and got[1].net == "red/main", "harmDetected once, with the confirming site")
end

-- ---------------------------------------------------------------- 2. runtime changes and reading
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "SAM SA-6 A", units = { { type = "Kub 1S91 str", x = 10000, z = 0 }, { type = "Kub 2P25 ln", x = 10200, z = 0 } } }
  F.addGroup{ name = "SAM Hawk B", coalition = BLUE, units = { { type = "Hawk tr", x = -90000, z = 0 }, { type = "Hawk ln", x = -90200, z = 0 } } }
  local J = load()
  F.run(3)
  check(J.setEmcon("SAM SA-6 A", "always"), "setEmcon: accepted")
  F.run(5)
  check(J.site("SAM SA-6 A").emcon == "always", "setEmcon: policy applied on the next tick")
  check(J.site("SAM SA-6 A").emitting, "always: emitting")
  check(J.setEmcon("SAM SA-6 A", nil), "setEmcon nil: back to the doctrine's")
  F.run(10)
  check(J.site("SAM SA-6 A").emcon ~= "always", "doctrine policy again: " .. tostring(J.site("SAM SA-6 A").emcon))
  check(J.setEmcon("SAM SA-6 A", "sometimes") == false and J.setEmcon("Nobody", "dark") == false, "bad policy or site: false")
  check(J.setHold("SAM SA-6 A", true) and J.net.nodes["SAM SA-6 A"].site.tags.hold == "true", "setHold on")
  check(J.setHold("SAM SA-6 A", false) and J.net.nodes["SAM SA-6 A"].site.tags.hold == nil and not J.setHold("Nobody", true), "setHold off; unknown site false")
  check(J.setWeapons(BLUE, "hold") == 1 and J.gci.weapons(BLUE)["blue/main"] == "hold", "setWeapons")
  local s = J.site("SAM SA-6 A")
  check(s.kind == "BATTERY" and s.coalition == RED and s.net == "red/main" and s.tier == "REG" and s.alive and s.working
    and s.powered and s.linked and s.x == 10000 and #s.assigned == 0 and s.dark == false, "site(): a copy of the state")
  s.alive = false
  check(J.net.nodes["SAM SA-6 A"].alive, "site() returns a copy")
  check(J.site("Nobody") == nil, "unknown site: nil")
  local names = J.siteNames(RED)
  check(#names == 2 and names[1] == "CMD Post" and names[2] == "SAM SA-6 A" and #J.siteNames() == 3, "siteNames per side and all")
  -- a group spawned silently (no BIRTH): addGroup picks it up
  F.addGroup{ name = "SAM SA-6 Late", units = { { type = "Kub 1S91 str", x = 20000, z = 0 }, { type = "Kub 2P25 ln", x = 20200, z = 0 } } }
  check(J.net.nodes["SAM SA-6 Late"] == nil and J.addGroup("SAM SA-6 Late") and J.net.nodes["SAM SA-6 Late"], "addGroup")
  check(J.addGroup("No Such Group") == false, "addGroup of nothing: false")
end

-- ---------------------------------------------------------------- 3. stats
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  local sam = F.addGroup{ name = "SAM SA-6 A", units = { { type = "Kub 1S91 str", x = 10000, z = 0 }, { type = "Kub 2P25 ln", x = 10200, z = 0 },
    { type = "Kub 2P25 ln", x = 10200, z = 200 } } }
  local guns = F.addGroup{ name = "AAA Guns C", units = { { type = "ZU-23 Emplacement", x = 30000, z = 30000 } } }
  local hawk = F.addGroup{ name = "SAM Hawk B", coalition = BLUE, units = { { type = "Hawk tr", x = -90000, z = 0 }, { type = "Hawk ln", x = -90200, z = 0 } } }
  local jet = F.addGroup{ name = "Viper", coalition = BLUE, category = AIR, units = { { type = "F-16C_50", x = 30000, z = 0, alt = 4000 } } }.units[1]
  local J = load{ STATS = true, STATS_EVERY = 60 }
  check(J.setEmcon("SAM SA-6 A", "always") == false, "before Janus has started there are no sites: false")
  F.run(3)
  J.setEmcon("SAM SA-6 A", "always")
  F.launch{ shooter = sam.units[2], type = "SA3M9M", guidance = Weapon.GuidanceType.RADAR_SEMI_ACTIVE, missileCategory = Weapon.MissileCategory.SAM, dieAt = 10 }
  F.fire({ id = world.event.S_EVENT_KILL, initiator = sam.units[2], target = jet })
  F.fire({ id = world.event.S_EVENT_KILL, initiator = jet, target = sam.units[1] })   -- a blue kill: not the site's
  F.fire({ id = world.event.S_EVENT_KILL, initiator = hawk.units[2], target = jet })
  F.fire({ id = world.event.S_EVENT_KILL, initiator = hawk.units[2], target = jet })
  F.fire({ id = world.event.S_EVENT_KILL, initiator = guns.units[1], target = jet })
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = nil, weapon = nil })               -- odd DCS events: ignored
  F.fire({ id = world.event.S_EVENT_KILL, initiator = nil })
  F.run(61)
  F.kill(sam.units[2])
  local st = J.stats()["SAM SA-6 A"]
  check(st and st.shots == 1 and st.kills == 1 and st.lost == 1 and st.coalition == RED and st.kind == "BATTERY", "stats: shots, kills, lost (1 of 3)")
  check(st.emitMin > 0.9 and st.emitMin < 1.1, "stats: emitting minutes " .. tostring(st.emitMin))
  check(count("[stats] red SAM SA-6 A: emitting 1.0 min, 1 shots, 1 kills, 0 units lost") == 1, "per-site line " .. tostring(st.emitMin))
  check(count("[stats] blue SAM Hawk B: emitting 1.0 min, 0 shots, 2 kills, 0 units lost") == 1, "blue site line")
  check(count("[stats] red AAA Guns C: emitting 0.0 min, 0 shots, 1 kills, 0 units lost") == 1, "a site with only one kill is listed")
  check(count("[stats] red total (61 s): emitting 1.0 min, 1 shots, 2 kills, 0 units lost") == 1, "red total")
  check(count("[stats] blue total (61 s): emitting 1.0 min, 0 shots, 2 kills, 0 units lost") == 1, "blue total")
  check(count("CMD Post: emitting") == 0, "a site with nothing to report is left out")
  local cp = J.stats()["CMD Post"]
  check(cp.shots == 0 and cp.kills == 0 and cp.emitMin == 0 and cp.lost == 0, "zeros for a quiet site")
  F.fire({ id = world.event.S_EVENT_MISSION_END })
  check(count("[stats] red total (mission end): emitting 1.0 min, 1 shots, 2 kills, 1 units lost") == 1, "and at mission end, with the loss")
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  J = load()
  F.run(700)
  check(count("[stats]") == 0 and J.stats()["CMD Post"] ~= nil, "STATS off: no report, JANUS.stats() still answers")
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  load{ STATS = true, STATS_EVERY = 0 }
  F.run(700)
  check(count("[stats]") == 0, "STATS_EVERY 0: nothing until the end")
  F.fire({ id = world.event.S_EVENT_MISSION_END })
  check(count("red total (mission end)") == 1, "then the end report")
  -- the default interval: every 600 s
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  load{ STATS = true }
  F.run(590)
  check(count("total (") == 0, "default STATS_EVERY: no report before 600 s")
  F.run(620)
  check(count("red total (") == 1, "default STATS_EVERY: the first report at 600 s")
end

-- ---------------------------------------------------------------- 4a. base warning: the default 30 s cooldown
do
  F.reset()
  F.airbases = { { name = "Incirlik", x = 1000, z = 1000 } }
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = -3000 } } }
  F.addGroup{ name = "PD C-RAM Incirlik", coalition = BLUE, units = { { type = "HEMTT_C-RAM_Phalanx", x = 0, z = 0 } } }
  local su = F.addGroup{ name = "Fencer", coalition = RED, category = AIR, units = { { type = "Su-24M", x = 40000, z = 0, alt = 3000 } } }.units[1]
  load{ BASE_WARNING = true }
  F.run(2)
  local function bomb(t)
    F.launch{ shooter = su, type = "FAB-250", category = Weapon.Category.BOMB, guidance = Weapon.GuidanceType.INS,
      x = 8000, z = 0, vx = -500, vz = 0, dieAt = t + 15 }
  end
  bomb(2)
  F.run(5)
  check(#F.coaText == 1, "first bomb: warned")
  F.run(22)
  bomb(22)
  F.run(26)
  check(#F.coaText == 1, "a second bomb 20 s later: inside the 30 s cooldown")
  F.run(40)
  bomb(40)
  F.run(44)
  check(#F.coaText == 2, "a third bomb 38 s later: warned again")
  check(not F.logContains("ERROR JANUS"), "block 4a: no Janus errors")
end

-- ---------------------------------------------------------------- 4. base warning
do
  F.reset()
  F.airbases = { { name = "Adana", x = 9000, z = 9000 }, { name = "Incirlik", x = 1000, z = 1000 }, { name = "Far Field", x = 82000, z = 0 } }
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = -3000 } } }
  F.addGroup{ name = "PD C-RAM Incirlik", coalition = BLUE, units = { { type = "HEMTT_C-RAM_Phalanx", x = 0, z = 0 } } }
  F.addGroup{ name = "SAM Hawk Far [warn]", coalition = BLUE, units = { { type = "Hawk tr", x = 80000, z = 0 }, { type = "Hawk ln", x = 80200, z = 0 } } }
  F.addGroup{ name = "SAM Hawk Plain", coalition = BLUE, units = { { type = "Hawk tr", x = -80000, z = 0 }, { type = "Hawk ln", x = -80200, z = 0 } } }
  local su = F.addGroup{ name = "Fencer", coalition = RED, category = AIR, units = { { type = "Su-24M", x = 40000, z = 0, alt = 3000 } } }.units[1]
  local J = load{ BASE_WARNING = true, BASE_WARNING_SOUND = "siren.ogg" }
  F.run(2)
  -- a bomb falling toward the C-RAM base: warned once inside 12 km, then cooldown
  F.launch{ shooter = su, type = "FAB-250", category = Weapon.Category.BOMB, guidance = Weapon.GuidanceType.INS,
    x = 20000, z = 0, vx = -500, vz = 0, dieAt = 45 }
  F.run(15)
  check(#F.coaText == 0, "20 km out, 13 s later 13.5 km: nothing yet")
  F.run(20)
  check(#F.coaText == 1 and F.coaText[1].coa == BLUE and F.coaText[1].text == "INCOMING! Incirlik - take cover"
    and F.coaText[1].secs == 10, "INCOMING at the nearest airbase's name, 10 s on screen")
  check(#F.sounds == 1 and F.sounds[1].file == "siren.ogg", "with the sound")
  F.run(40)
  check(#F.coaText == 1, "once per cooldown")
  -- an air-to-air missile near the base: ignored
  F.launch{ shooter = su, type = "R-73", category = Weapon.Category.MISSILE, missileCategory = Weapon.MissileCategory.AAM,
    guidance = Weapon.GuidanceType.IR, x = 5000, z = 0, vx = -300, dieAt = 60 }
  F.launch{ shooter = su, type = "SA-9M33", category = Weapon.Category.MISSILE, missileCategory = Weapon.MissileCategory.SAM,
    guidance = Weapon.GuidanceType.RADAR_SEMI_ACTIVE, x = 4000, z = 0, vx = -300, dieAt = 60 }
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = nil, weapon = nil })
  F.fire({ id = world.event.S_EVENT_SHOT, initiator = nil, weapon = F.weapons[1] })
  F.run(55)
  check(#F.coaText == 1, "air-to-air and surface-to-air missiles: no warning")
  -- a rocket near the [warn]-tagged Hawk (no airbase near): its own name; the untagged Hawk never warns
  F.launch{ shooter = su, type = "S-8", category = Weapon.Category.ROCKET, guidance = Weapon.GuidanceType.INS, x = 70000, z = 0, vx = 500, dieAt = 90 }
  F.launch{ shooter = su, type = "S-8", category = Weapon.Category.ROCKET, guidance = Weapon.GuidanceType.INS, x = -70000, z = 0, vx = -500, dieAt = 90 }
  F.run(70)
  check(#F.coaText == 2 and F.coaText[2].text == "INCOMING! Far Field - take cover", "[warn] site, named after the airbase 2 km away: " .. tostring(F.coaText[2] and F.coaText[2].text))
  -- a blue weapon near a blue base: own side, ignored
  F.launch{ shooter = F.groups["SAM Hawk Plain"].units[2], type = "GBU-12", category = Weapon.Category.BOMB, guidance = Weapon.GuidanceType.LASER, x = 500, z = 0, dieAt = 120 }
  F.run(100)
  check(#F.coaText == 2, "own weapons: no warning; " .. table.concat((function() local t = {} for _, c in ipairs(F.coaText) do t[#t + 1] = c.text end return t end)(), " / "))
  check(count("[warning] blue/main INCOMING at Incirlik (PD C-RAM Incirlik, FAB-250)") == 1, "logged")
  F.run(130)
  check(#J.warning.weapons == 0, "weapons forgotten once they are gone")
  -- off by default
  F.reset()
  F.addGroup{ name = "PD C-RAM Base", coalition = BLUE, units = { { type = "HEMTT_C-RAM_Phalanx", x = 0, z = 0 } } }
  local su2 = F.addGroup{ name = "Fencer", coalition = RED, category = AIR, units = { { type = "Su-24M", x = 40000, z = 0, alt = 3000 } } }.units[1]
  load()
  F.run(2)
  F.launch{ shooter = su2, type = "FAB-250", category = Weapon.Category.BOMB, x = 500, z = 0, dieAt = 30 }
  F.run(10)
  check(#F.coaText == 0, "BASE_WARNING off: nothing")
  -- no sound set: text only; a [warn] site with no airbase near: its label
  F.reset()
  F.airbases = { { name = "Twenty Km", x = 0, z = 20000 } }
  F.addGroup{ name = "SAM Hawk Lone [warn]", coalition = BLUE, units = { { type = "Hawk tr", x = 0, z = 0 }, { type = "Hawk ln", x = 200, z = 0 } } }
  local su3 = F.addGroup{ name = "Fencer", coalition = RED, category = AIR, units = { { type = "Su-24M", x = 40000, z = 0, alt = 3000 } } }.units[1]
  load{ BASE_WARNING = true }
  F.run(2)
  F.launch{ shooter = su3, type = "FAB-250", category = Weapon.Category.BOMB, x = 500, z = 0, dieAt = 30 }
  F.run(10)
  check(#F.coaText == 1 and F.coaText[1].text == "INCOMING! Hawk Lone - take cover" and #F.sounds == 0, "text only; named by its label (the airbase 20 km away is too far)")
  check(not F.logContains("ERROR JANUS"), "block 4: no Janus errors")
end

print(string.format("test_phase5: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
