-- Phase 4 tests: AAA fire discipline (flak traps), ground observers seeing ARMs (doctrine arm.observers), per-doctrine
-- voice reach; US_VIETNAM Hawks always up. (The Vietnam / Kari profiles that switch these on are Phase 6.)
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"
local BLUE = coalition.side.BLUE
local AIR = Group.Category.AIRPLANE
local ROE = AI.Option.Ground.id.ROE
local OPEN, HOLD = AI.Option.Ground.val.ROE.OPEN_FIRE, AI.Option.Ground.val.ROE.WEAPON_HOLD

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
local function roe(name)
  local g = F.groups[name]
  return g and g.controller and g.controller.options[ROE]
end
local function bandit(name, x, z, alt, acType)
  local g = F.addGroup{ name = name, coalition = BLUE, category = AIR,
    units = { { type = acType or "F-4E", x = x, z = z, alt = alt or 1000 } } }
  return g.units[1]
end
-- a doctrine with the Phase 4 capabilities switched on (the shipped profiles keep them off until Phase 6)
local NVA = { RED_DOCTRINE = { base = "NVA_VIETNAM_1965_72", agReach = 150000, aaa = { mode = "trap" },
  arm = { observers = { range = 12000, smokeRange = 20000 } } } }

-- ---------------------------------------------------------------- 1. flak trap: hold, open, reset
do
  F.reset()
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = -10000 } } }
  F.addGroup{ name = "EW Hanoi", units = { { type = "p-19 s-125 sr", x = 0, z = 5000 } } }
  F.addGroup{ name = "AAA S-60 Bridge", units = { { type = "S-60_Type59_Artillery", x = 0, z = 0 },
    { type = "S-60_Type59_Artillery", x = 50, z = 0 } } }
  F.addGroup{ name = "AAA KS-19 Belt", units = { { type = "KS-19", x = 2000, z = 0 }, { type = "SON_9", x = 2050, z = 0 } } }
  local b = bandit("Phantom 1", 30000, 0, 1000)
  local J = load(NVA)
  F.sees["EW Hanoi"] = { b }
  F.run(3)
  check(J.net.networks["red/main"].doctrine.aaa.mode == "trap", "doctrine with flak traps")
  check(roe("AAA S-60 Bridge") == HOLD and roe("AAA KS-19 Belt") == HOLD, "guns start holding fire")
  check(count("AAA S-60 Bridge holds fire (flak trap set)") == 1, "trap set logged")
  local reach, ceiling = J.aaa.reach(J.net.nodes["AAA S-60 Bridge"])
  check(reach == 6000 and ceiling == 6000, "S-60 reach 6 km, ceiling from its reach (no envelope)")
  F.move(b, 5000, 0)                            -- inside KS-19's trap (0.7 x 20 km), outside the S-60's (4.2 km)
  F.run(10)
  check(roe("AAA KS-19 Belt") == OPEN and roe("AAA S-60 Bridge") == HOLD, "only the gun whose trap it entered opens")
  F.move(b, 3000, 0)
  F.run(15)
  check(roe("AAA S-60 Bridge") == OPEN, "inside 4.2 km: the S-60 opens")
  check(count("AAA S-60 Bridge OPEN FIRE (flak trap: T1") == 1, "open fire logged with the track")
  F.move(b, 60000, 0)
  F.run(30)
  check(roe("AAA S-60 Bridge") == OPEN, "keeps firing for `hold` s after the target left")
  F.run(40)
  check(roe("AAA S-60 Bridge") == HOLD and count("AAA S-60 Bridge holds fire (trap reset)") == 1, "trap reset after 20 s")
  -- high overhead: above the ceiling, the guns stay silent
  F.move(b, 1000, 0)
  b.alt = 9000
  F.run(50)
  check(roe("AAA S-60 Bridge") == HOLD, "above the S-60's ceiling: holds fire")
  check(roe("AAA KS-19 Belt") == OPEN, "the KS-19 reaches 9 km up (20 km data): opens")
end

-- ---------------------------------------------------------------- 2. no picture: fire at will; free doctrines; dead guns
do
  F.reset()
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "AAA ZU-23 Lonely", units = { { type = "ZU-23 Emplacement", x = 400000, z = 0 } } }
  F.addGroup{ name = "AAA KS-19 Lonely", units = { { type = "KS-19", x = 400000, z = 30000 }, { type = "SON_9", x = 400050, z = 30000 } } }
  F.addGroup{ name = "AAA Shilka Lonely", units = { { type = "ZSU-23-4 Shilka", x = 400000, z = 60000 } } }
  local J = load(NVA)
  F.run(10)
  local zu, ks = J.net.nodes["AAA ZU-23 Lonely"], J.net.nodes["AAA KS-19 Lonely"]
  check(not zu.linked and roe("AAA ZU-23 Lonely") == OPEN, "an unlinked gun with no radar and no EW feed fires at will")
  check(count("AAA ZU-23 Lonely OPEN FIRE (no picture: fire at will)") == 1, "logged")
  check(not ks.linked and ks.hasRadar and roe("AAA KS-19 Lonely") == HOLD, "a gun with its own fire-control radar (SON-9) keeps the trap")
  check(roe("AAA Shilka Lonely") == OPEN, "a Shilka alone fires at will (Janus does not poll gun radars)")
  -- cut off from command but an EW radar still phones plots in (c2LossCue): the trap holds
  F.reset()
  F.addGroup{ name = "CMD Far", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW Border", units = { { type = "p-19 s-125 sr", x = 400000, z = 10000 } } }
  F.addGroup{ name = "AAA ZU-23 Border", units = { { type = "ZU-23 Emplacement", x = 400000, z = 0 } } }
  J = load(NVA)
  F.run(10)
  local zb = J.net.nodes["AAA ZU-23 Border"]
  check(not zb.linked and zb.feeders and #zb.feeders == 1, "the gun is fed by the EW over voice")
  check(roe("AAA ZU-23 Border") == HOLD, "a gun with an EW feed keeps the trap")
  F.reset()
  F.addGroup{ name = "CMD Moscow", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "AAA ZU-23 Moscow", units = { { type = "ZU-23 Emplacement", x = 1000, z = 0 } } }
  J = load()
  F.run(10)
  check(roe("AAA ZU-23 Moscow") == nil and count("[aaa]") == 0, "SOVIET: guns left to DCS (fire at will), nothing logged")
  -- a trap doctrine switched off at runtime opens the guns
  J.net.networks["red/main"].doctrine.aaa = { mode = "trap", trapFactor = 0.7, hold = 20 }
  F.run(12)
  check(roe("AAA ZU-23 Moscow") == HOLD, "trap set when the doctrine asks for it")
  J.net.networks["red/main"].doctrine.aaa = { mode = "free" }
  F.run(14)
  check(roe("AAA ZU-23 Moscow") == OPEN and count("OPEN FIRE (fire at will)") == 1, "back to fire at will")
  -- a destroyed gun is left alone
  F.reset()
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW Hanoi", units = { { type = "p-19 s-125 sr", x = 0, z = 5000 } } }
  local g = F.addGroup{ name = "AAA S-60 Dead", units = { { type = "S-60_Type59_Artillery", x = 1000, z = 0 } } }
  local b = bandit("Phantom 1", 60000, 0, 800)
  J = load(NVA)
  F.sees["EW Hanoi"] = { b }
  F.run(5)
  check(roe("AAA S-60 Dead") == HOLD, "trap set while alive")
  F.kill(g.units[1])
  F.run(12)                                     -- the network pass marks it destroyed
  F.move(b, 2000, 0)
  F.run(20)
  check(roe("AAA S-60 Dead") == HOLD, "a destroyed gun site does not open")
end

-- ---------------------------------------------------------------- 3. NVA observers see a Shrike far out, a HARM closer
do
  F.reset()
  F.rnd = 0.3
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = -10000 } } }
  F.addGroup{ name = "SAM SA-2 Hanoi [emcon:dark]", units = { { type = "SNR_75V", x = 0, z = 0 }, { type = "S_75M_Volhov", x = 300, z = 0 } } }
  local wild = bandit("Weasel 1", 200000, 0, 5000)
  local J = load(NVA)
  F.run(3)
  F.launch{ shooter = wild, type = "AGM_45", x = 26000, y = 5000, z = 0, vx = -400, vz = 0 }
  F.run(3 + 12)                               -- 21.2 km: outside 20
  check(count("sees ARM") == 0, "outside the spotters' 20 km")
  F.run(3 + 17)
  check(count("SAM SA-2 Hanoi [emcon:dark] sees ARM A1 at 20 km (eyes)") == 1, "a Shrike's smoke seen by spotters at 20 km")
  F.reset()
  F.rnd = 0.3
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = -10000 } } }
  F.addGroup{ name = "SAM SA-2 Hanoi [emcon:dark]", units = { { type = "SNR_75V", x = 0, z = 0 }, { type = "S_75M_Volhov", x = 300, z = 0 } } }
  wild = bandit("Weasel 1", 200000, 0, 5000)
  J = load(NVA)
  F.run(3)
  F.launch{ shooter = wild, type = "AGM_88", x = 20000, y = 5000, z = 0, vx = -400, vz = 0 }
  F.run(3 + 16)                               -- 13.6 km
  check(count("sees ARM") == 0, "a HARM (no smoke) is not seen beyond 12 km")
  F.run(3 + 24)
  check(count("SAM SA-2 Hanoi [emcon:dark] sees ARM A1") == 1, "inside 12 km it is")
  -- other doctrines have no spotters: a dark SA-2 sees nothing
  F.reset()
  F.rnd = 0.3
  F.addGroup{ name = "CMD Moscow", units = { { type = "SKP-11", x = 0, z = -10000 } } }
  F.addGroup{ name = "SAM SA-2 Moscow [emcon:dark]", units = { { type = "SNR_75V", x = 0, z = 0 }, { type = "S_75M_Volhov", x = 300, z = 0 } } }
  wild = bandit("Weasel 1", 200000, 0, 5000)
  J = load()
  F.run(3)
  F.launch{ shooter = wild, type = "AGM_45", x = 20000, y = 5000, z = 0, vx = -400, vz = 0 }
  F.run(3 + 45)
  check(count("sees ARM") == 0, "SOVIET: no spotters")
end

-- ---------------------------------------------------------------- 4. radio reach, Hawks
do
  F.reset()
  F.addGroup{ name = "CMD Hanoi", units = { { type = "SKP-11", x = 0, z = 0 } } }
  local J = load(NVA)
  F.run(3)
  local cn = J.gci.commandNodes(1)
  check(cn[1] and cn[1].reach == 150000, "a doctrine's voice reach (150 km) is the post's reach")
  F.reset()
  F.addGroup{ name = "CMD Da Nang", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "SAM Hawk Da Nang", coalition = BLUE, units = { { type = "Hawk sr", x = 5000, z = 0 },
    { type = "Hawk tr", x = 5100, z = 0 }, { type = "Hawk ln", x = 5200, z = 0 } } }
  J = load{ BLUE_DOCTRINE = "US_VIETNAM_1965_72" }
  F.run(5)
  check(F.emitting("SAM Hawk Da Nang"), "US_VIETNAM: Hawk radars always up (probe run 4)")
  check(J.net.networks["blue/main"].doctrine.aaa.mode == "free", "US guns fire at will")
  check(not F.logContains("ERROR JANUS"), "block 4: no Janus errors")
end


-- ---------------------------------------------------------------- 5. coverage for every shooter kind; unpowered guns; optics keep their own range
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "p-19 s-125 sr", x = 5000, z = 0 } } }
  F.addGroup{ name = "PD Tor", units = { { type = "Tor 9A331", x = 8000, z = 0 } } }
  F.addGroup{ name = "AAA ZU-23 Guard", units = { { type = "ZU-23 Emplacement", x = 9000, z = 0 } } }
  F.addGroup{ name = "SAM SA-6 A", units = { { type = "Kub 1S91 str", x = 10000, z = 0 }, { type = "Kub 2P25 ln", x = 10300, z = 0 } } }
  local J = load(NVA)
  F.run(5)
  local N = J.net.nodes
  check(N["PD Tor"].covered and N["AAA ZU-23 Guard"].covered and N["SAM SA-6 A"].covered, "PD, guns and SAMs are under EW cover")
  check(N["EW North"].covered == nil and N["CMD Post"].covered == nil, "radars and posts are not given cover")
  -- a gun site without power stays silent
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "p-19 s-125 sr", x = 5000, z = 0 } } }
  local pw = F.addGroup{ name = "POWER Gen Guns", units = { { type = "Generator", x = 9500, z = 500 } } }
  F.addGroup{ name = "AAA ZU-23 Guard [power:Gen Guns]", units = { { type = "ZU-23 Emplacement", x = 9000, z = 0 } } }
  local b = bandit("Phantom 1", 60000, 0, 800)
  local d = { base = "NVA_VIETNAM_1965_72", aaa = { mode = "trap" }, powerReserve = 5 }
  J = load{ RED_DOCTRINE = d }
  F.sees["EW North"] = { b }
  F.run(5)
  F.killGroup(pw)
  F.run(20)
  check(J.net.nodes["AAA ZU-23 Guard [power:Gen Guns]"].powered == false, "gun site out of power")
  F.move(b, 9500, 0)
  F.run(30)
  check(roe("AAA ZU-23 Guard [power:Gen Guns]") == HOLD, "an unpowered gun site does not open")
  -- an optical unit keeps its own 10 km eye range when the doctrine also has spotters (12 km)
  F.reset()
  F.rnd = 0.3
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = -10000 } } }
  F.addGroup{ name = "PD Tor Eyes [emcon:dark]", units = { { type = "Tor 9A331", x = 0, z = 0 } } }
  local wild = bandit("Weasel 1", 200000, 0, 5000)
  J = load(NVA)
  F.run(3)
  F.launch{ shooter = wild, type = "AGM_88", x = 20000, y = 5000, z = 0, vx = -400, vz = 0 }
  F.run(3 + 23)                               -- 10.8 km out, 11.9 km slant
  check(count("PD Tor Eyes [emcon:dark] sees") == 0, "the Tor's optics: 10 km, not the spotters' 12")
  F.run(3 + 31)
  check(count("PD Tor Eyes [emcon:dark] sees") == 1, "inside 10 km the Tor sees it")
  check(not F.logContains("ERROR JANUS"), "block 5: no Janus errors")
end

print(string.format("test_phase4: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
