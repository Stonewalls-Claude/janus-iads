-- Phase 3 tests: ARM defence (DESIGN 4.5, 4.5A, 4.5B). Launch recognition, radar / eyes / network awareness with
-- confirmation, the response ladder (engage, accept, covered, finish the shot, dark), dark time from the estimated
-- time to impact, suppression while a SEAD aircraft stays nose-on, maxDark (restart / wait), release when the network
-- sees the missile die, hit scoring, EMCON and WTA hooks, quiet networks.
-- F.rnd sets every random roll: 0 = every chance succeeds, 0.999 = none does, 0.5 = only chances above one half.
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"
local BLUE = coalition.side.BLUE
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
local function count(pattern)
  local n = 0
  for _, l in ipairs(F.log) do if l:find(pattern, 1, true) then n = n + 1 end end
  return n
end
local function firstLine(pattern)
  for _, l in ipairs(F.log) do if l:find(pattern, 1, true) then return l end end
  return nil
end
local function bandit(name, x, z, acType)
  local g = F.addGroup{ name = name, coalition = BLUE, category = AIR,
    units = { { type = acType or "F-16C_50", x = x, z = z, alt = 6000 } } }
  return g.units[1]
end
local function sa6(name, x, z)
  F.addGroup{ name = name, units = { { type = "Kub 1S91 str", x = x, z = z }, { type = "Kub 2P25 ln", x = x + 300, z = z } } }
end
local function sa2(name, x, z)
  F.addGroup{ name = name, units = { { type = "SNR_75V", x = x, z = z }, { type = "S_75M_Volhov", x = x + 300, z = z } } }
end
local function cmd(x, z) F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = x or 0, z = z or -20000 } } } end
-- an ARM flying along -x from (x, z) toward x = 0 at `speed`
local function harm(shooter, x, z, speed, typ, dieAt)
  return F.launch{ shooter = shooter, type = typ or "AGM_88", x = x, y = 5000, z = z or 0, vx = -(speed or 600), vz = 0,
    dieAt = dieAt }
end
local function noErrors(block) check(not F.logContains("ERROR JANUS"), block .. ": no Janus errors") end
-- every scenario ends error-free, also the ones a block resets away
local freshReset = F.reset
F.reset = function()
  if JANUS then check(not F.logContains("ERROR JANUS"), "no Janus errors before a reset (t=" .. F.time .. ")") end
  freshReset()
end

-- ---------------------------------------------------------------- 1. launches: ARMs recognised, others ignored
do
  F.reset()
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  F.launch{ shooter = viper, type = "AIM_120C", guidance = Weapon.GuidanceType.RADAR_ACTIVE, x = 190000, vx = -900 }
  check(#J.arm.flights == 0, "an active-radar missile is not an ARM")
  local w = harm(viper, 190000, 0, 600)
  check(#J.arm.flights == 1 and J.arm.flights[1].type == "AGM_88", "HARM recognised by passive-radar guidance")
  check(J.arm.flights[1].data.speed == 600 and J.arm.flights[1].data.range == 110000, "HARM data from the ARM table")
  check(J.arm.armData("X_99") == J.arm.DEFAULT_ARM, "unknown ARM type uses the default data")
  check(J.arm.stats.launched == 1, "launch counted")
  F.run(10)
  check(J.arm.flights[1].pos.x < 190000 - 4000, "flight position follows the weapon")
  check(count("DARK") == 0 and F.emitting("SAM SA-6 A [emcon:always]"), "nobody reacts to a missile 180 km out")
  w.alive = false
  F.run(12)
  check(#J.arm.flights == 0, "flight removed when the weapon is gone")
  noErrors("block 1")
end

-- ---------------------------------------------------------------- 2. tier B radar: sees late, confirms, goes dark
do
  F.reset()
  F.rnd = 0                                 -- every sighting roll succeeds
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  local n = node("SAM SA-6 A [emcon:always]")
  check(J.arm.sensorTier(n) == "B", "SA-6 is a tier B sensor")
  check(F.emitting("SAM SA-6 A [emcon:always]"), "SA-6 up before the launch")
  harm(viper, 60000, 0, 600)                -- 70 km x 0.35 = 24.5 km: first sighting ~59 s later
  F.run(3 + 55)
  check(count("sees ARM") == 0, "not seen outside 35 % of the radar's range")
  F.run(3 + 63)
  check(count("SAM SA-6 A [emcon:always] sees ARM A1") == 1, "seen and confirmed after 3 sightings inside the range")
  check(count("ARM A1 confirmed by SAM SA-6 A [emcon:always] (radar)") == 1, "network confirmation logged once")
  check(F.emitting("SAM SA-6 A [emcon:always]"), "crew still reacting (SOVIET REG 3 s)")
  F.run(3 + 68)
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "dark after the reaction time")
  local line = firstLine("SAM SA-6 A [emcon:always] DARK for")
  check(line ~= nil and line:find("ARM A1 inbound", 1, true) ~= nil, "dark logged with the threat")
  check(J.arm.isDark(n), "isDark")
  check(n.emcon.policy == "always", "the EMCON policy itself is unchanged")
  -- rnd 0 -> error -15 %: tti ~ (60000 - 600*~66)/600 ~ 32 s x 0.85 + 10 margin ~ 37 s
  local s = n.arm.dark
  check(s.untilT - s.since > 30 and s.untilT - s.since < 45, "dark time = estimated time to impact + margin")
  F.run(3 + 150)
  check(count("SAM SA-6 A [emcon:always] may emit again") == 1, "released once the threat time passed")
  check(F.emitting("SAM SA-6 A [emcon:always]"), "back up (after the restart time)")
  local lost = n.arm.darkSec
  check(lost > 25 and lost < 50, "emitting time lost is counted")
  check(n.arm.mode == nil and n.arm.dark == nil, "no ARM state left once released")
  noErrors("block 2")
end

-- ---------------------------------------------------------------- 3. rolls fail: tier B never notices; LOS blocks
do
  F.reset()
  F.rnd = 0.999
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 30000, 0, 600, nil, 3 + 50)
  F.run(60)
  check(count("sees ARM") == 0 and count("DARK") == 0, "a crew that never notices never reacts")
  check(F.emitting("SAM SA-6 A [emcon:always]"), "stays up, unaware")
  F.reset()
  F.rnd = 0
  F.blockLOS = true
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  load()
  F.run(3)
  harm(viper, 30000, 0, 600, nil, 3 + 50)
  F.run(60)
  check(count("sees ARM") == 0, "no line of sight, no sighting")
  noErrors("block 3")
end

-- ---------------------------------------------------------------- 4. network warning: a Tor sees it, the SA-2 learns
do
  F.reset()
  F.rnd = 0.5                               -- tier A (0.8) sees, tier B (0.25) and C (0.03) do not
  cmd()
  sa2("SAM SA-2 Hanoi [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Hanoi [emcon:always]", units = { { type = "Tor 9A331", x = 5000, z = 1000 } } }
  sa2("SAM SA-2 Other [emcon:always] [net:Other]", 0, 30000)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  local sam, tor = node("SAM SA-2 Hanoi [emcon:always]"), node("PD Tor Hanoi [emcon:always]")
  check(J.arm.sensorTier(sam) == "C" and J.arm.sensorTier(tor) == "A", "SA-2 tier C, Tor tier A")
  harm(viper, 30000, 0, 400, "AGM_45")      -- Shrike, 400 m/s, straight at the SA-2
  F.run(3 + 58)
  check(count("PD Tor Hanoi [emcon:always] sees ARM A1") == 1, "the Tor holds the Shrike")
  check(count("sees ARM A1 at") == 1, "the SA-2 itself never does")
  local conf = firstLine("ARM A1 confirmed by PD Tor Hanoi")
  check(conf ~= nil, "network confirmed by the Tor")
  check(count("SAM SA-2 Hanoi [emcon:always] DARK for") == 1, "the SA-2 goes dark on the network warning")
  check(not F.emitting("SAM SA-2 Hanoi [emcon:always]"), "SA-2 dark")
  check(sam.arm.dark.untilT - sam.arm.dark.since >= 15, "at least the Fan Song's minimum dark time")
  check(F.emitting("PD Tor Hanoi [emcon:always]"), "the Tor stays up")
  check(count("SAM SA-2 Other [emcon:always] [net:Other] DARK") == 0, "another network hears nothing")
  noErrors("block 4")
end

-- ---------------------------------------------------------------- 5. timing: net delay + reaction, eyes
do
  F.reset()
  F.rnd = 0.5
  cmd()
  sa2("SAM SA-2 Hanoi [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Hanoi [emcon:always]", units = { { type = "Tor 9A331", x = 5000, z = 1000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 60000, 0, 600)
  local confAt, darkAt
  for t = 4, 120 do
    F.run(t)
    if not confAt and J.net.networks["red/main"].arms and J.net.networks["red/main"].arms.A1
       and J.net.networks["red/main"].arms.A1.netConfirmed then confAt = t end
    if not darkAt and not F.emitting("SAM SA-2 Hanoi [emcon:always]") then darkAt = t end
  end
  check(confAt ~= nil and darkAt ~= nil, "confirmed and dark")
  -- SOVIET REG: netDelay 5 + reaction 3 (+1 s each for the tick order)
  check(darkAt and confAt and darkAt - confAt >= 8 and darkAt - confAt <= 10, "dark = confirmation + net delay + reaction")
  -- eyes: an optical Tor that is NOT emitting still sees a Shrike (smoke) inside 15 km in daylight
  F.reset()
  F.rnd = 0.3
  cmd()
  F.addGroup{ name = "PD Tor Eyes [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 30000, 0, 400, "AGM_45")      -- inside the 15 km smoke range after 37.5 s
  F.run(3 + 36)
  check(count("sees ARM") == 0, "not yet inside eye range")
  F.run(3 + 45)
  check(firstLine("PD Tor Eyes [emcon:dark] sees ARM A1") ~= nil and firstLine("(eyes)") ~= nil, "seen by eye, confirmed at once")
  noErrors("block 5")
end

-- ---------------------------------------------------------------- 6. ladder: engage, accept [hold], trustPd cover
do
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "PD Tor Target [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  sa6("SAM SA-6 Hold [emcon:always] [hold]", 0, 40000)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 20000, 0, 600)
  F.launch{ shooter = viper, type = "AGM_88", x = 20000, y = 5000, z = 40000, vx = -600, vz = 0 }
  F.run(3 + 30)
  check(count("PD Tor Target [emcon:always] stays up to engage ARM A1") == 1, "tier A engages, logged once")
  check(F.emitting("PD Tor Target [emcon:always]"), "Tor up")
  check(count("SAM SA-6 Hold [emcon:always] [hold] holds and accepts ARM A2") == 1, "[hold] accepts")
  check(F.emitting("SAM SA-6 Hold [emcon:always] [hold]"), "[hold] site stays up")
  check(J.arm.override(node("PD Tor Target [emcon:always]"), F.time) == true, "engage forces the radar on")
  -- RUSSIA_MODERN trusts point defence: an SA-10 with a Tor 8 km away stays up, the Tor is forced on
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM SA-10 Moscow [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 0, z = 0 },
    { type = "S-300PS 5P85C ln", x = 300, z = 0 } } }
  F.addGroup{ name = "PD Tor Guard [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 8000 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(3)
  harm(viper, 50000, 0, 600)
  F.run(3 + 60)
  check(count("SAM SA-10 Moscow [emcon:always] stays up, covered by PD Tor Guard [emcon:dark]") == 1, "covered by point defence")
  check(F.emitting("SAM SA-10 Moscow [emcon:always]"), "SA-10 stays up under cover")
  check(F.emitting("PD Tor Guard [emcon:dark]"), "the covering Tor is forced on (ARM cover)")
  check(count("PD Tor Guard [emcon:dark] ON (ARM cover)") == 1, "cover logged by EMCON")
  -- without trust (SOVIET): the SA-10 goes dark but still forces the Tor up
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM SA-10 Kiev [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 0, z = 0 },
    { type = "S-300PS 5P85C ln", x = 300, z = 0 } } }
  F.addGroup{ name = "PD Tor Guard [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 8000 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 50000, 0, 600)
  F.run(3 + 60)
  check(not F.emitting("SAM SA-10 Kiev [emcon:always]"), "SOVIET: SA-10 dark despite the Tor")
  check(F.emitting("PD Tor Guard [emcon:dark]"), "SOVIET: the Tor is still forced up")
  local sa10 = node("SAM SA-10 Kiev [emcon:always]")
  check(sa10.arm.dark.untilT - sa10.arm.dark.since >= 30, "SA-10 minimum dark time 30 s")
  noErrors("block 6")
end

-- ---------------------------------------------------------------- 7. finish the shot
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  local n = node("SAM SA-6 A [emcon:always]")
  local own = F.launch{ shooter = F.groups["SAM SA-6 A [emcon:always]"].units[2], type = "SA-6 3M9",
    guidance = Weapon.GuidanceType.RADAR_SEMI_ACTIVE, x = 0, z = 0, vx = 800, vz = 0, target = viper }
  check(#J.arm.flights == 0, "own SAM is not an ARM")
  harm(viper, 45000, 0, 600)                -- seen at ~24 km (t ~ 40), reaction 3 s
  F.run(3 + 46)
  check(count("stays up to finish its shot") == 1, "stays up while its own missile flies")
  check(F.emitting("SAM SA-6 A [emcon:always]"), "up")
  F.run(3 + 63)                             -- ARM now < 15 s out
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "dark once the ARM is inside finishMargin")
  own.alive = false
  noErrors("block 7")
end

-- ---------------------------------------------------------------- 8. a missile not aimed at the site
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  F.launch{ shooter = viper, type = "AGM_88", x = 20000, y = 5000, z = -10000, vx = 0, vz = 600 }   -- crossing
  F.run(3 + 30)
  check(count("sees ARM A1") == 1, "crossing ARM seen")
  check(count("DARK") == 0 and F.emitting("SAM SA-6 A [emcon:always]"), "not aimed at the site: no reaction")
  check(J.arm._offAngle({ x = 0, z = 0 }, { x = 1, z = 0 }, { x = 10, z = 10 }) > 44.9, "offAngle 45 deg")
  noErrors("block 8")
end

-- ---------------------------------------------------------------- 9. the network sees it die short: release early
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Near [emcon:always]", units = { { type = "Tor 9A331", x = 12000, z = 3000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 30000, 0, 600, nil, 3 + 30)   -- dies 12 km short (shot down)
  F.run(3 + 25)
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "SA-6 dark")
  F.run(3 + 33)
  check(count("ARM A1 gone 3.1 km short of any radar (shot down?)") == 1, "the network saw it die short (nearest radar the Tor)")
  check(count("SAM SA-6 A [emcon:always] may emit again: ARM A1 gone") == 1, "released early")
  check(J.arm.stats.seenDie == 1, "counted")
  F.run(3 + 50)
  check(F.emitting("SAM SA-6 A [emcon:always]"), "back up after the restart time")
  noErrors("block 9")
end

-- ---------------------------------------------------------------- 10. hits, WTA, quiet network
do
  F.reset()
  F.rnd = 0.999                               -- no suspicion rolls: the EW stays up and the SA-6 gets its target
  cmd()
  sa6("SAM SA-6 A", 0, 0)
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 10000, z = 0 } } }
  local viper = bandit("Viper 1", 18000, 0)
  local J = load()
  F.sees["EW North"] = { viper }
  F.run(10)
  local n = node("SAM SA-6 A")
  local net = J.net.networks["red/main"]
  check(J.wta.targetFor(n) ~= nil, "SA-6 assigned the Viper")
  n.arm = { darkSec = 0, logged = {}, known = {}, dark = { since = F.time, untilT = F.time + 60, why = "test" } }
  J.wta.assign(net)
  check(J.wta.targetFor(n) == nil, "a site dark against an ARM is not assigned targets")
  local w = harm(viper, 20000, 0, 600)
  F.fire({ id = world.event.S_EVENT_HIT, initiator = viper, weapon = w, target = F.groups["SAM SA-6 A"].units[1] })
  check(count("SAM SA-6 A hit by an ARM") == 1 and J.arm.stats.hits == 1, "ARM hit scored")
  check(J.arm.stats.hitsDark == (n.emcon.on and 0 or 1), "hit on a dark radar counted as such")
  F.fire({ id = world.event.S_EVENT_HIT, initiator = viper, target = F.groups["SAM SA-6 A"].units[1],
    weapon = F.launch{ shooter = viper, type = "Mk-82", guidance = Weapon.GuidanceType.INS } })
  check(J.arm.stats.hits == 1, "a bomb hit is not an ARM hit")
  J.arm.summary()
  check(count("ARM defence:") == 1, "summary line")
  noErrors("block 10")
end

-- ---------------------------------------------------------------- 11. suspicion, suppression, maxDark
-- the Viper flies at the SA-6 at 150 m/s (one plot a second, so the track has a velocity)
local function fly(viper, t0, t1, x0, vx, z0, vz)
  for t = t0, t1 do
    F.move(viper, x0 + vx * (t - t0), (z0 or 0) + (vz or 0) * (t - t0))
    F.run(t)
  end
end
do
  F.reset()
  F.rnd = 0                                   -- suspicion rolls succeed
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "EW North", units = { { type = "SA-11 Buk SR 9S18M1", x = 10000, z = 30000 } } }
  local viper = bandit("Viper 1", 42000, 0)
  local J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", arm = { afterMax = "restart", maxDark = 60 } } }
  F.sees["EW North"] = { viper }
  fly(viper, 1, 12, 42000, -150)
  local n = node("SAM SA-6 A [emcon:always]")
  local tr = J.net.networks["red/main"].tracks[viper:getID()]
  check(tr and tr.typeKnown and tr.typeName == "F-16C_50", "Viper identified (type flag)")
  check(firstLine("SAM SA-6 A [emcon:always] DARK for 30 s: suspects SEAD T") ~= nil, "suspects the nose-on SEAD jet")
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "dark on suspicion")
  check(count("EW North DARK") == 0, "a jet not pointing at the EW radar does not scare it")
  local since = n.arm.dark.since
  fly(viper, 13, 50, 42000 - 150 * 12, -150)
  check(count("stays dark: T") == 1, "suppressed while the jet stays nose-on (logged once)")
  check(J.arm.isDark(n), "still dark past the 30 s suspicion time")
  fly(viper, 51, 80, 42000 - 150 * 50, -150)
  check(count("maximum dark time reached") == 1, "restart doctrine: back at maxDark")
  local rel = firstLine("may emit again: maximum dark time reached")
  check(rel ~= nil and n.arm.dark == nil and since ~= nil, "released")
  fly(viper, 81, 120, 42000 - 150 * 80, -150)
  check(n.arm.dark == nil and F.emitting("SAM SA-6 A [emcon:always]"), "after a max-dark restart suspicion is calm for 60 s")
  -- wait doctrine: stays dark past maxDark while the jet stays nose-on, released once it turns away
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "EW North", units = { { type = "SA-11 Buk SR 9S18M1", x = 10000, z = 30000 } } }
  viper = bandit("Viper 1", 55000, 0)
  J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", arm = { afterMax = "wait", maxDark = 60 } } }
  F.sees["EW North"] = { viper }
  fly(viper, 1, 130, 55000, -150)             -- ends ~35 km out, still nose-on
  check(J.arm.isDark(node("SAM SA-6 A [emcon:always]")), "wait doctrine: still dark after maxDark")
  check(count("maximum dark time reached") == 0, "wait doctrine never restarts on the clock")
  fly(viper, 131, 150, 55000 - 150 * 130, 0, 0, 200)   -- turns north: no longer nose-on
  check(not J.arm.isDark(node("SAM SA-6 A [emcon:always]")), "released once the jet is no longer nose-on")
  -- US_MODERN never goes dark on suspicion
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "EW North", units = { { type = "SA-11 Buk SR 9S18M1", x = 10000, z = 30000 } } }
  viper = bandit("Viper 1", 42000, 0)
  J = load{ RED_DOCTRINE = "US_MODERN" }
  F.sees["EW North"] = { viper }
  fly(viper, 1, 30, 42000, -150)
  check(count("suspects SEAD") == 0, "US_MODERN: no suspicion")
  noErrors("block 11")
end

-- ---------------------------------------------------------------- 12. doctrine fields
do
  F.reset()
  local J = load()
  local D = J.Doctrines
  check(D.SOVIET_PVO_1985.arm.afterMax == "wait" and D.SOVIET_PVO_1985.arm.maxDark == 300, "SOVIET waits")
  check(D.RUSSIA_MODERN.arm.trustPd == true, "RUSSIA_MODERN trusts point defence")
  check(D.NVA_VIETNAM_1965_72.arm.maxDark == 60 and D.NVA_VIETNAM_1965_72.arm.afterMax == "restart", "NVA blinks")
  check(D.GENERIC_THIRD_WORLD.arm.confirmScans == 5, "third world slow to confirm")
  check(D.US_MODERN.arm.suspicion.REG == 0, "US never dark on suspicion")
  for name, d in pairs(D) do
    check(d.arm and d.arm.enabled == true and d.arm.reaction.REG and d.arm.netDelay.GRN and d.arm.predictErr.ACE,
      name .. " has the arm fields")
  end
  noErrors("block 12")
end


-- ---------------------------------------------------------------- 13. sensor tiers, who can see at all
do
  F.reset()
  F.rnd = 0.3                                 -- eyes (0.5) succeed, tier B radar (0.25) does not
  cmd()
  F.addGroup{ name = "EW Old", units = { { type = "55G6 EWR", x = 0, z = 50000 } } }
  F.addGroup{ name = "EW Modern", units = { { type = "S-300PS 64H6E sr", x = 0, z = 60000 } } }
  F.addGroup{ name = "EW Blue", coalition = BLUE, units = { { type = "FPS-117", x = 300000, z = 0 } } }
  sa6("SAM SA-6 Dark [emcon:dark]", 0, 0)
  sa2("SAM SA-2 B", 0, 80000)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  check(J.arm.sensorTier(node("EW Old")) == "C", "55G6 EW is tier C")
  check(J.arm.sensorTier(node("EW Modern")) == "B", "64H6E EW is tier B")
  check(J.arm.sensorTier(node("EW Blue")) == "B", "FPS-117 is tier B")
  check(J.arm.sensorTier(node("SAM SA-6 Dark [emcon:dark]")) == "B", "SA-6 is tier B")
  check(J.arm.sensorTier(node("SAM SA-2 B")) == "C", "SA-2 is tier C")
  harm(viper, 20000, 3000, 600)               -- passes 3 km from the dark SA-6
  F.run(3 + 40)
  check(count("SAM SA-6 Dark [emcon:dark] sees") == 0, "a dark radar without optics sees nothing")
  noErrors("block 13a")
  -- night: no eyes; a destroyed Tor neither sees nor covers
  F.reset()
  F.rnd = 0.3
  F.time = 43200                              -- 20:00 local
  cmd()
  F.addGroup{ name = "PD Tor Night [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(43203)
  harm(viper, 20000, 0, 400, "AGM_45")
  F.run(43203 + 45)
  check(count("sees ARM") == 0, "no eyes at night")
  F.reset()
  F.rnd = 0
  cmd()
  local tor = F.addGroup{ name = "PD Tor Dead [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  F.addGroup{ name = "SAM SA-10 Near [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 5000, z = 0 },
    { type = "S-300PS 5P85C ln", x = 5300, z = 0 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(3)
  F.kill(tor.units[1])
  F.run(10)
  harm(viper, 45000, 0, 600)
  F.run(10 + 64)                              -- the ARM is now inside the Tor's eye range
  check(count("PD Tor Dead [emcon:always] sees") == 0, "a destroyed Tor sees nothing")
  check(count("covered by PD Tor Dead") == 0, "a destroyed Tor covers nothing")
  check(not F.emitting("SAM SA-10 Near [emcon:always]"), "SA-10 goes dark: no cover left")
  noErrors("block 13b")
end

-- ---------------------------------------------------------------- 14. confirmation: 3 sightings in the window, 2 sensors
do
  F.reset()
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  -- rolls: see, see, then 12 misses, then see: the first two fall out of the 10 s window
  local seq, i = { 0, 0, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0, 0, 0 }, 0
  J.arm.rand = function() i = i + 1; return seq[i] or 0.9 end
  harm(viper, 23000, 0, 100)                  -- slow, already inside 24.5 km
  F.run(3 + 8)
  local th = J.net.networks["red/main"].arms and J.net.networks["red/main"].arms.A1
  local sname = "SAM SA-6 A [emcon:always]"
  check(th and #th.sights[sname].hits >= 2 and not th.sights[sname].confirmed, "two sightings: not confirmed yet")
  local hitsAtConfirm
  for t = 24, 60 do
    F.run(t)
    if th.sights[sname].confirmed and not hitsAtConfirm then hitsAtConfirm = #th.sights[sname].hits end
  end
  check(hitsAtConfirm == 5, "old sightings drop out of the window: confirmed on the 3rd recent one (5th overall)")
  -- two tier B sensors holding it at once confirm at the first sighting
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  sa6("SAM SA-6 B [emcon:always]", 0, 3000)
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 30000, 1500, 600)
  F.run(3 + 12)
  th = J.net.networks["red/main"].arms.A1
  check(th.netConfirmed and th.netHow == "2 sensors", "two sensors at once confirm")
  check(th.netBy == "SAM SA-6 A [emcon:always]", "the first of the two is named as the confirmer")
  -- an airborne radar never sees an ARM (AWACS)
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "AWACS Mainstay", category = AIR, units = { { type = "A-50", x = 0, z = 0, alt = 9000 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 20000, 0, 600)
  F.run(3 + 30)
  check(count("AWACS Mainstay sees") == 0, "AWACS never sees an ARM")
  -- a busy radar notices less: 12 tracks halve the chance (0.25 -> ~0.11 < 0.2)
  F.reset()
  F.rnd = 0.2
  cmd()
  sa6("SAM SA-6 Busy [emcon:always]", 0, 0)
  local jets = {}
  for k = 1, 12 do jets[k] = bandit("Jet " .. k, 30000 + k * 1000, 20000, "C-130") end
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.sees["SAM SA-6 Busy [emcon:always]"] = jets
  F.run(8)
  harm(viper, 20000, 0, 600)
  F.run(8 + 25)
  check(count("SAM SA-6 Busy [emcon:always] sees") == 0, "12 tracks held: the crew misses the ARM")
  F.reset()
  F.rnd = 0.2
  cmd()
  sa6("SAM SA-6 Idle [emcon:always]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(8)
  harm(viper, 20000, 0, 600)
  F.run(8 + 25)
  check(count("SAM SA-6 Idle [emcon:always] sees") == 1, "same roll, idle crew: sees it")
  noErrors("block 14")
end

-- ---------------------------------------------------------------- 15. two missiles, caps, doctrines
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Near [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 3000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  local n = node("SAM SA-6 A [emcon:always]")
  harm(viper, 20000, 0, 150, "AGM_88")        -- A1: slow, ~130 s out
  F.run(3 + 12)
  local d1 = n.arm.dark and n.arm.dark.untilT
  check(d1 ~= nil and n.arm.dark.th.id == "A1", "dark for A1")
  local w2 = harm(viper, 12000, 0, 400, "AGM_88", 38)   -- A2: faster; the Tor sees it (the SA-6 is dark), dies at t=38
  F.run(3 + 30)
  check(n.arm.dark.th.id == "A2", "the more urgent missile is the one tracked")
  check(n.arm.dark.untilT >= d1, "a shorter estimate never shortens the dark time")
  F.run(3 + 37)
  check(not w2.alive and count("ARM A2 gone") == 1 and count("may emit again: ARM A2 gone") == 0, "A2 died but A1 is still inbound: stays dark")
  check(J.arm.isDark(n), "still dark for A1")
  noErrors("block 15a")
  -- restart doctrine caps the dark time at maxDark; wait doctrine does not
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", arm = { afterMax = "restart", maxDark = 25 } } }
  F.run(3)
  harm(viper, 24000, 0, 200)                  -- ~120 s out
  F.run(3 + 10)
  n = node("SAM SA-6 A [emcon:always]")
  check(n.arm.dark and n.arm.dark.untilT - n.arm.dark.since <= 25.01, "restart doctrine: capped at maxDark")
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", arm = { afterMax = "wait", maxDark = 25 } } }
  F.run(3)
  harm(viper, 24000, 0, 200)
  F.run(3 + 10)
  n = node("SAM SA-6 A [emcon:always]")
  check(n.arm.dark and n.arm.dark.untilT - n.arm.dark.since > 60, "wait doctrine: dark until the missile is due")
  -- a point-defence group that is not tier A still stays up to fight
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "PD Kub Guard [emcon:always]", units = { { type = "Kub 1S91 str", x = 0, z = 0 },
    { type = "Kub 2P25 ln", x = 300, z = 0 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 30000, 0, 600)
  F.run(3 + 30)
  check(count("PD Kub Guard [emcon:always] stays up to engage") == 1, "point defence of any tier engages")
  -- RUSSIA_MODERN: an SA-6 nearby is not point defence: the SA-10 goes dark
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM SA-10 Moscow [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 0, z = 0 },
    { type = "S-300PS 5P85C ln", x = 300, z = 0 } } }
  sa6("SAM SA-6 Beside [emcon:dark]", 0, 8000)
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(3)
  harm(viper, 50000, 0, 600)
  F.run(3 + 60)
  check(count("covered by") == 0 and not F.emitting("SAM SA-10 Moscow [emcon:always]"), "an SA-6 is no cover")
  check(not F.emitting("SAM SA-6 Beside [emcon:dark]"), "and is not forced up")
  noErrors("block 15b")
end

-- ---------------------------------------------------------------- 16. suspicion only on real cues; overrides; switches
do
  local function setup(acType, doctrine, samName)
    F.reset()
    F.rnd = 0
    cmd()
    sa6(samName or "SAM SA-6 A [emcon:always]", 0, 0)
    F.addGroup{ name = "EW North", units = { { type = "SA-11 Buk SR 9S18M1", x = 10000, z = 30000 } } }
    local v = bandit("Viper 1", 42000, 0, acType)
    local J = load{ RED_DOCTRINE = doctrine }
    F.sees["EW North"] = { v }
    return J, v
  end
  local J, v = setup("C-130")
  for t = 1, 20 do F.move(v, 42000 - 150 * (t - 1), 0); F.run(t) end
  check(count("suspects SEAD") == 0, "a transport nose-on is no SEAD cue")
  J, v = setup("F-16C_50")
  F.noType["EW North"] = true                 -- no type flag: identified only after idTime (90 s REG)
  for t = 1, 40 do F.move(v, 42000 - 150 * (t - 1), 0); F.run(t) end
  check(count("suspects SEAD") == 0, "an unidentified jet is no SEAD cue")
  J, v = setup("F-16C_50", nil, "SAM SA-6 A [emcon:always] [hold]")
  for t = 1, 20 do F.move(v, 42000 - 150 * (t - 1), 0); F.run(t) end
  check(count("suspects SEAD") == 0, "a [hold] site never goes dark on suspicion")
  J, v = setup("F-16C_50", { base = "SOVIET_PVO_1985", arm = { enabled = false } })
  for t = 1, 20 do F.move(v, 42000 - 150 * (t - 1), 0); F.run(t) end
  harm(v, 20000, 0, 600)
  F.run(50)
  check(count("[arm]") == 0, "arm.enabled = false: no ARM defence at all")
  -- own-coalition ARMs are not threats
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local su34 = F.addGroup{ name = "Red SEAD", category = AIR, units = { { type = "Su-34", x = 20000, z = 0, alt = 7000 } } }.units[1]
  J = load()
  F.run(3)
  harm(su34, 20000, 0, 600)
  F.run(30)
  check(#J.arm.flights == 1 and count("sees ARM") == 0, "a friendly ARM is not tracked as a threat")
  -- an unseen missile dying tells the network nothing
  F.reset()
  F.rnd = 0.999
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  v = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(v, 30000, 0, 600, nil, 3 + 20)
  F.run(40)
  check(count("gone") == 0, "an unseen missile's end is not logged")
  -- a missile that reaches its radar: "gone at a radar"; a dark node destroyed leaves no ARM state
  F.reset()
  F.rnd = 0
  cmd()
  local g = F.addGroup{ name = "SAM SA-6 A [emcon:always] [hold]", units = { { type = "Kub 1S91 str", x = 0, z = 0 },
    { type = "Kub 2P25 ln", x = 300, z = 0 } } }
  v = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(v, 30000, 0, 600, nil, 3 + 50)
  F.run(3 + 52)
  check(count("ARM A1 gone at a radar") == 1, "impact at the radar logged (the [hold] site watched it come)")
  local n = node("SAM SA-6 A [emcon:always] [hold]")
  n.arm.dark = { since = F.time, untilT = F.time + 100, why = "test" }
  F.kill(g.units[1])
  F.run(3 + 60)
  check(n.arm.dark == nil, "a destroyed node keeps no ARM state")
  noErrors("block 16")
end

-- ---------------------------------------------------------------- 17. overrides, cover expiry, hits, summary
do
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM SA-10 Moscow [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 0, z = 0 },
    { type = "S-300PS 5P85C ln", x = 300, z = 0 } } }
  F.addGroup{ name = "PD Tor Guard [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 8000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(3)
  harm(viper, 50000, 0, 600, nil, 3 + 83)
  F.run(3 + 60)
  local sa10, tor = node("SAM SA-10 Moscow [emcon:always]"), node("PD Tor Guard [emcon:dark]")
  check(sa10.arm.mode == "covered" and J.arm.override(sa10, F.time) == nil, "covered: no forced state for the SA-10")
  check(tor.arm.darkSec == 0, "the Tor never went dark")
  F.run(3 + 130)
  check(not F.emitting("PD Tor Guard [emcon:dark]"), "cover over: the Tor goes back to its own policy (dark)")
  check(tor.arm.coverUntil == nil, "cover cleared")
  -- hits while ON and while dark; summary text
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  local n = node("SAM SA-6 A [emcon:always]")
  local w = harm(viper, 40000, 0, 600)
  F.fire({ id = world.event.S_EVENT_HIT, initiator = viper, weapon = w, target = F.groups["SAM SA-6 A [emcon:always]"].units[2] })
  check(count("hit by an ARM") == 1 and count("radar ON") == 1, "hit on an emitting radar")
  F.run(3 + 45)
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "dark now")
  F.fire({ id = world.event.S_EVENT_HIT, initiator = viper, weapon = w, target = F.groups["SAM SA-6 A [emcon:always]"].units[2] })
  check(J.arm.stats.hits == 2 and J.arm.stats.hitsDark == 1 and n.arm.hits == 2, "hits and hits while dark counted")
  local lost = n.arm.darkSec
  J.arm.summary()
  check(count(string.format("red/main ARM defence: 1 site(s) went dark 1 time(s), %d s of emitting lost, 2 ARM hit(s)", lost)) == 1,
    "summary: sites, times, seconds, hits")
  noErrors("block 17")
end

-- ---------------------------------------------------------------- 18. EMCON: a forced policy beats the own-missile hold
do
  F.reset()
  F.rnd = 0.999
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local viper = bandit("Viper 1", 20000, 0)
  local J = load()
  F.run(3)
  F.launch{ shooter = F.groups["SAM SA-6 A [emcon:always]"].units[2], type = "3M9", guidance = Weapon.GuidanceType.RADAR_SEMI_ACTIVE,
    x = 0, z = 0, vx = 800, vz = 0, target = viper }
  J.emcon.set("SAM SA-6 A [emcon:always]", "dark")
  F.run(5)
  check(not F.emitting("SAM SA-6 A [emcon:always]"), "policy dark: off at once despite its own missile in flight")
  noErrors("block 18")
end


-- ---------------------------------------------------------------- 19. more edges: load, tier-A battery cover, guards
do
  -- one track: 0.25 / 1.1 = 0.227 > 0.22 -> sees; two tracks would not
  F.reset()
  F.rnd = 0.22
  cmd()
  sa6("SAM SA-6 One [emcon:always]", 0, 0)
  local jet = bandit("Jet 1", 30000, 20000, "C-130")
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.sees["SAM SA-6 One [emcon:always]"] = { jet }
  F.run(8)
  harm(viper, 20000, 0, 600)
  F.run(8 + 25)
  check(count("SAM SA-6 One [emcon:always] sees") == 1, "one track held: still sees it (0.227 > 0.22)")
  -- a Tor in a SAM group (tier A battery) covers too
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM SA-10 Moscow [emcon:always]", units = { { type = "S-300PS 40B6M tr", x = 0, z = 0 },
    { type = "S-300PS 5P85C ln", x = 300, z = 0 } } }
  F.addGroup{ name = "SAM Tor Guard [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 12000 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load{ RED_DOCTRINE = "RUSSIA_MODERN" }
  F.run(3)
  harm(viper, 50000, 0, 600)
  F.run(3 + 60)
  check(count("covered by SAM Tor Guard [emcon:dark]") == 1, "a tier A battery covers like point defence")
  check(count("SAM Tor Guard [emcon:dark] ON (ARM cover)") == 1, "and is forced up for it")
  -- Tor and point defence never go dark on suspicion
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "SAM Tor A [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  F.addGroup{ name = "PD Kub B [emcon:always]", units = { { type = "Kub 1S91 str", x = 0, z = 1000 }, { type = "Kub 2P25 ln", x = 300, z = 1000 } } }
  F.addGroup{ name = "EW North", units = { { type = "SA-11 Buk SR 9S18M1", x = 10000, z = 30000 } } }
  viper = bandit("Viper 1", 42000, 0)
  J = load()
  F.sees["EW North"] = { viper }
  for t = 1, 20 do F.move(viper, 42000 - 150 * (t - 1), 0); F.run(t) end
  check(count("SAM Tor A [emcon:always] DARK") == 0 and count("PD Kub B [emcon:always] DARK") == 0,
    "tier A and point defence never go dark on suspicion")
  -- A2 dies; A1 is known but crossing (not aimed): the site is released
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Near [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 3000 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  F.launch{ shooter = viper, type = "AGM_88", x = 15000, y = 5000, z = -15000, vx = 0, vz = 150 }   -- A1 crossing
  F.run(3 + 6)
  check(count("sees ARM A1") == 1 and count("DARK") == 0, "the crossing missile is known, no reaction")
  harm(viper, 12000, 0, 400, "AGM_88", 3 + 25)                                                    -- A2 aimed
  F.run(3 + 30)
  check(count("red/main ARM A2 gone") == 1 and count("may emit again: ARM A2 gone") == 1, "a crossing missile does not keep it dark")
  -- a missile seen, then lost (no line of sight), dying later: the network does not learn of its end
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always] [hold]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 20000, 0, 600, nil, 3 + 20)
  F.run(3 + 8)
  F.blockLOS = true
  F.run(3 + 25)
  check(count("sees ARM A1") == 1 and count("gone") == 0, "lost from sight > 3 s before its end: end unknown")
  -- the end is placed against radars only, not the command post
  F.reset()
  F.rnd = 0
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 10000, z = 0 } } }
  sa6("SAM SA-6 A [emcon:always] [hold]", 0, 0)
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 20000, 0, 600, nil, 3 + 16)     -- dies at x = 10400, beside the command post, 10.4 km from the SA-6
  F.run(3 + 20)
  check(count("ARM A1 gone 11.0 km short of any radar") == 1, "distance to the nearest radar (last seen point), not to the command post")
  noErrors("block 19")
end

-- ---------------------------------------------------------------- 20. summary counts only sites that went dark or were hit
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  local tor = F.addGroup{ name = "PD Tor Near [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 1000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 20000, 0, 600)
  F.run(3 + 25)
  local n = node("SAM SA-6 A [emcon:always]")
  check(node("PD Tor Near [emcon:always]").arm ~= nil, "the Tor has an ARM state (engaging)")
  J.arm.summary()
  check(count(string.format("red/main ARM defence: 1 site(s) went dark 1 time(s), %d s of emitting lost, 0 ARM hit(s)",
    n.arm.darkSec)) == 1, "summary: the engaging Tor is not counted")
  local w = harm(viper, 20000, 0, 600)
  F.fire({ id = world.event.S_EVENT_HIT, initiator = viper, weapon = w, target = tor.units[1] })
  J.arm.summary()
  check(count(string.format("red/main ARM defence: 2 site(s) went dark 1 time(s), %d s of emitting lost, 1 ARM hit(s)",
    n.arm.darkSec)) == 1, "summary: a site only hit counts as a site, with no dark time")
  noErrors("block 20")
end


-- ---------------------------------------------------------------- 21. two missiles die one after the other
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 A [emcon:always]", 0, 0)
  F.addGroup{ name = "PD Tor Near [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 3000 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 12000, 0, 400, "AGM_88", 3 + 10)    -- A1 dies 8 km out
  harm(viper, 12000, 300, 400, "AGM_88", 3 + 14)  -- A2 dies 6.4 km out
  F.run(3 + 12)
  local n = node("SAM SA-6 A [emcon:always]")
  check(J.arm.isDark(n) and count("may emit again") == 0, "first missile gone, the second still coming: dark")
  check(n.arm.dark.th and n.arm.dark.th.id == "A2", "now dark for the second")
  F.run(3 + 16)
  check(count("may emit again: ARM A2 gone") == 1, "both gone: released")
  noErrors("block 21")
end


-- ---------------------------------------------------------------- 22. only radars near the first emitter on the path
do
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 Front [emcon:always]", 0, 0)
  sa6("SAM SA-6 Behind [emcon:always]", -30000, 0)      -- 30 km further along the missile's path, also emitting
  sa6("SAM SA-6 Close [emcon:always]", -8000, 500)      -- 8 km beyond the first: could be the target too
  sa6("SAM SA-6 Mid [emcon:always]", -15000, -500)      -- 15 km beyond: not
  sa6("SAM SA-6 DarkFirst [emcon:dark]", 15000, 800)    -- nearer to the missile but not emitting: not a homing target
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  harm(viper, 26000, 0, 600)
  F.run(3 + 14)
  check(count("SAM SA-6 Front [emcon:always] DARK") == 1, "the first emitter on the path goes dark")
  check(count("SAM SA-6 Close [emcon:always] DARK") == 1, "one within 10 km beyond it too")
  check(count("SAM SA-6 Mid [emcon:always] DARK") == 0, "one 15 km beyond it does not")
  check(count("SAM SA-6 Behind [emcon:always] DARK") == 0, "one 30 km beyond it does not")
  F.run(3 + 60)
  check(count("SAM SA-6 Mid [emcon:always] DARK") == 0 and count("SAM SA-6 Behind [emcon:always] DARK") == 0,
    "no cascade: the sites behind stay up after the front ones shut down")
  noErrors("block 22")
end


-- ---------------------------------------------------------------- 23. bench 05 fixes: recently dark front, 50 km cap
do
  -- the targeted SA-6 went dark just before the crew behind it learned of the missile: still the front
  F.reset()
  F.rnd = 0
  cmd()
  sa6("SAM SA-6 Front", 0, 0)
  F.addGroup{ name = "EW Behind", units = { { type = "55G6 EWR", x = -40000, z = 0 } } }
  local viper = bandit("Viper 1", 200000, 0)
  local J = load()
  F.run(3)
  J.emcon.set("SAM SA-6 Front", "always")
  F.run(10)
  J.emcon.set("SAM SA-6 Front", "dark")      -- the SA-6 shuts down on its own at t=10
  F.run(20)
  harm(viper, 60000, 0, 600)                -- aimed through the SA-6 at the EW 40 km behind
  F.run(20 + 120)
  check(count("EW Behind sees ARM A1") == 1, "the EW radar holds the missile (inside 50 km)")
  check(count("EW Behind DARK") == 0, "a radar 40 km behind a recently-dark target is not threatened")
  -- the 50 km cap: a 64H6E (160 km x 0.35 = 56 km) does not hold an ARM at 53 km
  F.reset()
  F.rnd = 0
  cmd()
  F.addGroup{ name = "EW Big [emcon:always]", units = { { type = "S-300PS 64H6E sr", x = 0, z = 0 } } }
  viper = bandit("Viper 1", 200000, 0)
  J = load()
  F.run(3)
  harm(viper, 58000, 0, 600)
  F.run(3 + 8)                               -- ARM at ~53 km
  check(count("sees ARM") == 0, "no radar holds an ARM beyond 50 km")
  F.run(3 + 18)                              -- ~47 km
  check(count("EW Big [emcon:always] sees ARM A1") == 1, "inside 50 km it can")
  noErrors("block 23")
end

print(string.format("test_arm: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
