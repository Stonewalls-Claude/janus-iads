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


-- ---------------------------------------------------------------- 6. weapons control (free / tight / hold) and commit requests
do
  F.reset()
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = -10000 } } }
  F.addGroup{ name = "EW South", coalition = BLUE, units = { { type = "FPS-117", x = 0, z = 5000 } } }
  F.addGroup{ name = "SAM Patriot", coalition = BLUE, units = { { type = "Patriot str", x = 0, z = 0 },
    { type = "Patriot ln", x = 200, z = 0 } } }
  local function red(name, x, z, acType)
    return F.addGroup{ name = name, coalition = 1, category = AIR, units = { { type = acType or "Su-24M", x = x, z = z, alt = 5000 } } }.units[1]
  end
  local a1 = red("Fencer 1", 60000, 0)
  local far = red("Fencer Far", 300000, 0)
  local J = load()
  F.noType["EW South"] = true                 -- the FPS-117 gives no type: identification by dwell (US REG 40 s)
  F.sees["EW South"] = { a1, far }
  F.run(10)
  local G = J.gci
  local net = J.net.networks["blue/main"]
  check(G.weapons(BLUE)["blue/main"] == "tight", "US_MODERN starts weapons tight")
  check(G.weapons(1)["red/main"] == nil, "a coalition with no network: empty")
  check(not (net.assign or {})[a1:getID()], "unidentified: not engaged")
  check(count("blue/main T1 fixed-wing held: weapons tight (not identified)") == 1, "held logged once")
  local cr = G.commitRequests(BLUE)
  local byId = {}
  for _, c in ipairs(cr) do byId[c.id] = c end
  check(#cr == 2 and byId[a1:getID()].reason == "weapons tight" and byId[far:getID()].reason == "out of reach",
    "commit requests: the unidentified one (weapons tight) and the far one (out of reach)")
  check(cr[1].id == a1:getID() and cr[1].threat > cr[2].threat, "most threatening first")
  check(cr[1].net == "blue/main" and cr[1].x == 60000 and cr[1].typeKnown == false, "a copy of the track with its network")
  cr[1].x = -1
  check(G.commitRequests(BLUE)[1].x == 60000, "copies, not Janus's tracks")
  F.run(60)                                   -- held 40 s: identified
  check((net.assign or {})[a1:getID()] ~= nil, "identified after idTime: engaged")
  check(#G.commitRequests(BLUE) == 1 and G.commitRequests(BLUE)[1].reason == "out of reach", "only the far one is left to fighters")
  -- weapons hold from ground control
  check(G.weaponsControl(BLUE, "hold") == 1, "set weapons hold on the coalition's one network")
  check(count("blue/main weapons HOLD (was tight): ground control") == 1, "logged")
  F.run(64)
  check(not (net.assign or {})[a1:getID()] and G.commitRequests(BLUE)[1].reason == "weapons hold", "hold: nothing engaged")
  check(count("held: weapons hold") == 1, "the held track logged once for the new reason (the far one is out of reach)")
  check(G.weaponsControl(BLUE, "bogus") == 0 and G.weapons(BLUE)["blue/main"] == "hold", "an unknown state changes nothing")
  check(G.weaponsControl(BLUE, "free", "elsewhere") == 0, "an unknown network changes nothing")
  check(G.weaponsControl(BLUE, "free", "main") == 1 and G.weaponsControl(BLUE, "free", "blue/main") == 1, "by name or key")
  check(G.weaponsControl(BLUE, "tight") == 1 and G.weapons(BLUE)["blue/main"] == "tight", "tight is a state too")
  check(G.weaponsControl(BLUE, "free") == 1, "back to free")
  check(count("weapons FREE") == 2, "setting the same state again logs nothing (two real changes to free)")
  F.run(68)
  check((net.assign or {})[a1:getID()] ~= nil, "free again: engaged")
  -- more targets than channels: the rest are "no shooter free"
  local a2, a3 = red("Fencer 2", 50000, 2000), red("Fencer 3", 55000, -2000)
  F.sees["EW South"] = { a1, a2, a3, far }
  F.run(75)
  local reasons = {}
  for _, c in ipairs(G.commitRequests(BLUE)) do reasons[#reasons + 1] = c.reason end
  table.sort(reasons)
  check(table.concat(reasons, ",") == "no shooter free,out of reach", "Patriot's two channels busy: one left as 'no shooter free'")
  check(G.weapons(1)["red/main"] == nil and #G.commitRequests(1) == 0, "red: nothing")
  -- SOVIET starts free
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  J = load()
  F.run(3)
  check(J.gci.weapons(1)["red/main"] == "free", "SOVIET starts weapons free")
  check(J.Doctrines.NATO_COLDWAR.wta.weapons == "tight" and J.Doctrines.RUSSIA_MODERN.wta.weapons == "free", "doctrine start states")
  check(not F.logContains("ERROR JANUS"), "block 6: no Janus errors")
end


-- ---------------------------------------------------------------- 7. ships shoot (WTA), a carrier group as its own network, moving sensors
do
  F.reset()
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "EW Coast", coalition = BLUE, units = { { type = "FPS-117", x = 0, z = 5000 } } }
  F.addGroup{ name = "SAM Patriot", coalition = BLUE, units = { { type = "Patriot str", x = 0, z = 10000 },
    { type = "Patriot ln", x = 200, z = 10000 } } }
  local ship = F.addGroup{ name = "SHIP CG Leyte Gulf", coalition = BLUE, category = Group.Category.SHIP,
    units = { { type = "TICONDEROG", x = 100000, z = 0 } } }
  local bad = F.addGroup{ name = "Fencer 1", coalition = 1, category = AIR, units = { { type = "Su-24M", x = 170000, z = 0, alt = 5000 } } }.units[1]
  local J = load()
  F.sees["EW Coast"] = { bad }                -- the FPS-117 gives the type (no noType): identified, weapons tight is no bar
  F.run(10)
  local net = J.net.networks["blue/main"]
  local sh = J.net.nodes["SHIP CG Leyte Gulf"]
  check(sh.kind == "NAVAL" and sh.linked and J.wta.envelope(sh).R >= 100000, "the cruiser is a linked naval shooter with an envelope")
  local a = (net.assign or {})[bad:getID()]
  check(a and a[1].node == sh, "the ship 70 km from the target gets it, not the Patriot 170 km away")
  check(count("assigned to SHIP CG Leyte Gulf") == 1, "logged")
  -- the ship sails out of link range: unlinked, no longer offered targets, the track left to fighters
  F.move(ship.units[1], 400000, 0)
  F.move(bad, 470000, 0)
  F.run(20)
  check(not sh.linked and not (net.assign or {})[bad:getID()], "out of range of the CRC: unlinked, not a WTA shooter")
  -- a carrier group tagged [net:CSG] is its own flat network (its CIC): linked wherever it sails
  F.reset()
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "SHIP CG Leyte Gulf [net:CSG]", coalition = BLUE, category = Group.Category.SHIP,
    units = { { type = "TICONDEROG", x = 400000, z = 0 } } }
  J = load()
  F.run(5)
  local cg = J.net.nodes["SHIP CG Leyte Gulf [net:CSG]"]
  check(cg.net.key == "blue/CSG" and cg.linked and not cg.net.hasC2, "own flat network: linked 400 km from any post")
  -- a moving AWACS: a battery comes under its cover when it flies close enough
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  local aw = F.addGroup{ name = "AWACS Mainstay", category = AIR, units = { { type = "A-50", x = 0, z = 0, alt = 9000 } } }
  F.addGroup{ name = "SAM SA-6 Far", units = { { type = "Kub 1S91 str", x = 110000, z = 0 }, { type = "Kub 2P25 ln", x = 110300, z = 0 } } }
  J = load()
  F.run(5)
  local sam = J.net.nodes["SAM SA-6 Far"]
  check(not sam.covered, "AWACS 110 km away (its 100 km cover): no cover")
  F.move(aw.units[1], 60000, 0)
  F.run(15)
  check(sam.covered and J.net.nodes["AWACS Mainstay"].pos.x == 60000, "AWACS moved in: position followed, battery covered")
  check(not F.logContains("ERROR JANUS"), "block 7: no Janus errors")
end

-- ---------------------------------------------------------------- 8. spawning a battery from its preset on flat ground
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  local J = load()
  F.run(2)
  local SP = J.spawn
  -- layout: the fire-control radar at the centre, launchers on the ring, optional trucks only with `full`
  local L = SP.layout(J.Presets["SA-2"])
  check(#L == 11 and L[1].type == "SNR_75V" and L[1].dx == 0 and L[1].dz == 0, "SA-2: Fan Song at the centre, 11 units, the two ZILs the minimum")
  local onRing = 0
  for _, u in ipairs(L) do
    if u.type == "S_75M_Volhov" and math.abs(math.sqrt(u.dx * u.dx + u.dz * u.dz) - 70) < 0.01 then onRing = onRing + 1 end
  end
  check(onRing == 6, "six launchers on the 70 m ring")
  check(#SP.layout(J.Presets["SA-2"], true) == 15, "full: six ZIL transloaders")
  local H = SP.layout(J.Presets["HAWK"])
  check(H[1].type == "Hawk pcp" and H[1].dx < -60, "Hawk: the command post goes behind")
  local centre
  for _, u in ipairs(H) do if u.dx == 0 and u.dz == 0 then centre = u end end
  check(centre and centre.type == "Hawk tr", "Hawk: an HPIR at the centre")
  local tr2 = 0
  for _, u in ipairs(H) do if u.type == "Hawk tr" and u.dz == 300 then tr2 = tr2 + 1 end end
  check(tr2 == 1, "the second HPIR one spacing pair (2 x 150 m) to the side")
  check(SP.roleWord(J.Presets["SA-6"]) == "SAM" and SP.roleWord(J.Presets["TOR-M2"]) == "PD"
    and SP.roleWord(J.Presets["AAA-ZU23"]) == "AAA" and SP.roleWord(J.Presets["EW-SOVIET"]) == "EW"
    and SP.roleWord(J.Presets["CSG-USN"]) == "SHIP", "role words per preset")
  -- slope limits: the strictest unit's limit, 8 when none, or the mission maker's
  check(SP.limitFor(H, {}) == 2 and SP.limitFor(L, {}) == 3, "Hawk 2, SA-2 3 (probe limits)")
  check(SP.limitFor(SP.layout(J.Presets["SA-6"]), {}) == 8 and SP.limitFor(H, { maxSlope = 6 }) == 6, "SA-6 8 by default; opts.maxSlope wins")
  -- a 5.7 deg hillside west of x = 3000, flat plateau east of it
  F.heightFn = function(x) return x < 3000 and 0.1 * x or 300 end
  local name, info = J.spawnBattery("SA-6", { x = 0, y = 0 }, { label = "Kub", tier = "VET", tags = "[net:North]" })
  check(name == "SAM Kub VET [net:North]", "named role word, label, tier, tags: " .. tostring(name))
  check(info and info.x == 0 and info.z == 0 and math.abs(info.slope - 5.71) < 0.05 and info.units == 5,
    "SA-6 has no limit: spawned on the 5.7 deg slope where asked (ME point y = map z)")
  local add = F.added[#F.added]
  check(add.country == country.id.RUSSIA and add.category == Group.Category.GROUND and add.data.task == "Ground Nothing"
    and add.data.units[1].skill == "High" and add.data.units[1].type == "Kub 1S91 str", "red Russia ground group, VET = High skill")
  F.run(3)
  local n = J.net.nodes[name]
  check(n and n.kind == "BATTERY" and n.tier == "VET" and n.net.key == "red/North", "picked up at BIRTH: a VET battery on net North")
  local hn, hi = J.spawnBattery("HAWK", { x = 0, z = 0 }, { coalition = 2, label = "Charlie" })
  check(hn == "SAM Charlie REG" and hi.slope <= 2 and hi.x > 3000, "Hawk (2 deg) moved up onto the plateau")
  check(F.added[#F.added].country == country.id.USA and F.added[#F.added].data.units[1].skill == "Good", "blue: USA, REG = Good")
  check(count("HAWK spawned as 'SAM Charlie REG' (11 units)") == 1, "logged")
  local mn, mi = J.spawnBattery("SA-6", { x = 0, z = 0 }, { maxSlope = 1 })
  check(mn and mi.x > 3000 and mi.slope <= 1, "SA-6 with maxSlope 1: moved too")
  -- heading turns the layout: the first launcher (70 m north of the radar) ends up 70 m east at heading 90
  F.heightFn = nil
  local sn = J.spawnBattery("SA-2", { x = 50000, z = 50000 }, { heading = 90, aaa = true, label = "Lima" })
  local d = F.added[#F.added - 1].data
  check(sn == "SAM Lima REG" and #d.units == 11, "SA-2 group")
  check(math.abs(d.units[2].x - 50000) < 0.01 and math.abs(d.units[2].y - 50070) < 0.01, "heading 90: launcher 1 due east")
  local g = F.added[#F.added].data
  check(g.name == "AAA Lima guns REG" and #g.units == 6, "the gun ring as its own AAA group (4 ZU-23 + 2 S-60)")
  local far = 0
  for _, u in ipairs(g.units) do
    local r = math.sqrt((u.x - 50000) ^ 2 + (u.y - 50000) ^ 2)
    if math.abs(r - 600) < 0.01 then far = far + 1 end
  end
  check(far == 2, "the S-60s on the 600 m ring")
  F.run(F.time + 3)
  check(J.net.nodes["SAM Charlie REG"] and J.net.nodes["SAM Charlie REG"].net.key == "blue/main", "the blue Hawk picked up too")
  check(J.net.nodes["AAA Lima guns REG"] and J.net.nodes["AAA Lima guns REG"].kind == "AAA", "guns picked up as an AAA node")
  -- nowhere flat enough: nil and why; nothing spawned
  local before = #F.added
  F.heightFn = function(x) return 0.2 * x end
  local nn, err = J.spawnBattery("HAWK", { x = 0, z = 0 }, { search = 2000 })
  check(nn == nil and err:find("no ground within 2000 m flat enough %(2%.0 deg%)") and #F.added == before, "no flat ground: nil, reason, no spawn")
  F.heightFn = nil
  -- water: ground sites keep off it, ships need it
  F.waterFn = function(x) return x > 2000 end
  local wn, wi = J.spawnBattery("SA-6", { x = 2500, z = 0 })
  check(wn and wi.x <= 2000 - 200, "a ground site on the shore, every launcher on land")
  local shn, shi = J.spawnBattery("SAG-RU", { x = 0, z = 0 }, { label = "Black Sea" })
  check(shn == "SHIP Black Sea REG" and shi.x > 2000 and F.added[#F.added].category == Group.Category.SHIP, "a ship group, out on the water")
  F.waterFn = nil
  local nw, werr = J.spawnBattery("CSG-USN", { x = 0, z = 0 }, { search = 1000 })
  check(nw == nil and werr:find("no open water"), "no water: no ships")
  check(J.spawnBattery("SA-99", { x = 0, z = 0 }) == nil and J.spawnBattery("SA-6") == nil, "unknown preset or no point: nil")
  check(not F.logContains("ERROR JANUS"), "block 8: no Janus errors")
end

-- ---------------------------------------------------------------- 9. spawn details, threat ranking, commit-request dedupe
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "SKP-11", x = 0, z = 0 } } }
  local J = load()
  F.run(2)
  local SP = J.spawn
  local function near(a, b) return math.abs(a - b) < 0.01 end
  -- the full SA-2 layout, unit by unit
  local L = SP.layout(J.Presets["SA-2"], true)
  check(near(L[3].dx, 35) and near(L[3].dz, 60.62), "launcher 2 at 60 deg on the ring")
  check(L[8].type == "p-19 s-125 sr" and L[8].dx == 40 and L[8].dz == 300, "the Flat Face one spacing to the side")
  check(L[9].type == "RD_75" and L[9].dx == -100 and L[9].dz == 0, "the second TR behind")
  check(L[10].dx == -140 and L[10].dz == 30 and L[11].dx == -180 and L[11].dz == -30, "trucks behind, staggered")
  -- the centre: the earliest role in CENTRE_ORDER, whatever order the preset lists them in
  local order = SP.CENTRE_ORDER
  for i = 1, #order - 1 do
    local Lx = SP.layout({ units = { { role = order[i + 1], type = "a", count = 1 }, { role = order[i], type = "b", count = 1 } } })
    check(Lx[2].dx == 0 and Lx[2].dz == 0 and Lx[1].dx < 0, order[i] .. " beats " .. order[i + 1] .. " for the centre")
  end
  check(#SP.layout({ units = { { role = "LN", type = "a", count = { 1, 3 } } } }) == 1, "a {1, 3} count spawns 1 without full")
  check(SP.roleWord({ units = { { role = "TELAR" } } }) == "SAM" and SP.roleWord({ units = { { role = "TR" } } }) == "SAM"
    and SP.roleWord({ units = { { role = "STR" } } }) == "SAM" and SP.roleWord({ units = { { role = "LN" } } }) == "SAM"
    and SP.roleWord({ units = { { role = "CRAM" } } }) == "PD", "role words by role")
  check(SP.limitFor({ { type = "Hawk ln" }, { type = "SNR_75V" } }, {}) == 2 and SP.limitFor({ { type = "SNR_75V" }, { type = "Hawk ln" } }, {}) == 2,
    "the strictest limit, in any order")
  -- the spiral: a steep knob of 100 m radius at the point; one unit; the first ring-1 point (60 deg, 250 m) is taken
  F.heightFn = function(x, z) return (x * x + z * z < 130 * 130) and 0.3 * x or 0 end
  local fx, fz, fs = SP.findSite({ { dx = 0, dz = 0 } }, 0, 0, 0, 1, 1000)
  check(fx and near(fx, 125) and near(fz, 216.51) and fs == 0, "first point of ring 1: " .. tostring(fx) .. "/" .. tostring(fz))
  F.heightFn = nil
  -- defaults: label "<preset> <n>" counted from 1, heading 0, REG for an unknown tier, flat ground slope 0
  local n1, i1 = J.spawnBattery("SA-2", { x = 10000, z = 10000 }, { tier = "XYZ" })
  local d1 = F.added[#F.added].data
  check(n1 == "SAM SA-2 1 REG" and i1.slope == 0 and i1.aaa == nil, "default label, unknown tier -> REG, no guns unless asked")
  check(near(d1.units[2].x, 10070) and near(d1.units[2].y, 10000) and d1.units[2].playerCanDrive == false, "heading 0: launcher 1 due north; not drivable")
  local n2 = J.spawnBattery("SA-6", { x = 20000, z = 10000 }, { aaa = true })
  check(n2 == "SAM SA-6 2 REG" and F.added[#F.added].data.name == n2, "count goes up by one; no gun ring in the SA-6 preset: no guns")
  local _, iv = J.spawnBattery("SA-2-VIETNAM", { x = 30000, z = 10000 }, { aaa = true, label = "Hanoi" })
  local guns = F.added[#F.added].data.units
  check(iv.aaa == "AAA Hanoi guns REG" and #guns == 13, "Vietnam ring: 6 ZU-23, 6 S-60, 1 SON-9")
  check(near(guns[1].x - iv.x, 259.81) and near(guns[1].y - iv.z, 150), "first gun half a step (30 deg) round the 300 m ring")
  check(guns[13].type == "SON_9" and near(math.sqrt((guns[13].x - iv.x) ^ 2 + (guns[13].y - iv.z) ^ 2), 100), "no ring given: 100 m")
  -- default search 5000 m: flat ground 6 km away is not found; the message says so
  F.heightFn = function(x) return x < 6000 and 0.2 * x or 1200 end
  local nf, ef = J.spawnBattery("SA-6", { x = 0, z = 0 })
  check(nf == nil and ef:find("within 5000 m"), "default search radius 5000 m")
  local nh, ih = J.spawnBattery("SA-6", { x = 0, z = 0 }, { search = 8000 })
  local dist = math.sqrt(ih.x * ih.x + ih.z * ih.z)
  check(nh and count(string.format("%.0f m from the point asked", dist)) == 1, "the log gives the distance moved")
  F.heightFn = nil
  F.waterFn = function(x) return x > 6000 end
  local nw, ew = J.spawnBattery("SAG-RU", { x = 0, z = 0 })
  check(nw == nil and ew:find("no open water within 5000 m"), "ships: default search 5000 m too")
  local ns, is = J.spawnBattery("SAG-RU", { x = 0, z = 0 }, { search = 9000, aaa = true })
  check(ns and is.slope == 0 and is.aaa == nil, "ships: slope 0, never a gun ring")
  local rs = F.added[#F.added].data.route.points[1]
  check(rs.action == "Turning Point" and rs.speed == 0 and rs.x == is.x and rs.y == is.z, "ships: a one-point route where they spawned, stopped")
  local rg = F.added[#F.added - 1].data.route.points[1]
  check(rg.action == "Off Road" and rg.speed == 0 and rg.x == ih.x and rg.y == ih.z, "ground: a one-point Off Road route, stopped")
  F.waterFn = nil
  -- a name already in use: never replace that group, number the new one
  local d1n = J.spawnBattery("SA-6", { x = 40000, z = 40000 }, { label = "Twin" })
  local d2n, d2i = J.spawnBattery("SA-2", { x = 45000, z = 40000 }, { label = "Twin", aaa = true })
  local d3n = J.spawnBattery("SA-6", { x = 50000, z = 40000 }, { label = "Twin" })
  check(d1n == "SAM Twin REG" and d2n == "SAM Twin #2 REG" and d3n == "SAM Twin #3 REG", "taken names get #2, #3: " .. tostring(d2n))
  check(d2i.aaa == "AAA Twin #2 guns REG", "the gun ring follows the numbered label")
  local firstAdd
  for _, a in ipairs(F.added) do if a.data.name == "SAM Twin REG" then firstAdd = firstAdd or a end end
  check(F.groups["SAM Twin REG"].units[1].x == firstAdd.data.units[1].x and firstAdd.data.units[1].x < 41000, "the first group untouched")
  -- a preset needing DLC this install lacks is refused, nothing spawned
  local before = #F.added
  F.missingTypes["flak18"] = true
  local nd, ed = J.spawnBattery("FLAK-88", { x = 0, z = 0 })
  check(nd == nil and ed == "FLAK-88: unit type flak18 is not installed (needs WWII Assets Pack)" and #F.added == before,
    "WWII preset without the DLC: refused, " .. tostring(ed))
  F.missingTypes["Kub 2P25 ln"] = true
  local _, ek = J.spawnBattery("SA-6", { x = 0, z = 0 })
  check(ek == "SA-6: unit type Kub 2P25 ln is not installed", "any missing type, no DLC named when none declared")
  F.missingTypes = {}
  check(J.spawnBattery("FLAK-88", { x = 0, z = 0 }) ~= nil, "with the DLC: spawns")
  -- threat ranking against a brute-force reference: nearest-in-time defended node, pruning never changes the answer
  local W = J.wta
  local net = { nodes = {} }
  for i = 1, 40 do
    net.nodes[i] = { kind = (i % 5 == 0) and "AAA" or "BATTERY", alive = i % 7 ~= 0, pos = { x = (i * 7919) % 200000 - 100000, y = 0, z = (i * 104729) % 200000 - 100000 } }
  end
  local function ref(tr)
    local best
    for _, n in ipairs(net.nodes) do
      if n.kind ~= "AAA" and n.alive then
        local dx, dz = n.pos.x - tr.pos.x, n.pos.z - tr.pos.z
        local d = math.sqrt(dx * dx + dz * dz)
        local c = 50
        if tr.vel and d > 1 then c = math.max(50, (tr.vel.x * dx + tr.vel.z * dz) / d) end
        if not best or d / c < best then best = d / c end
      end
    end
    local sc = 1000 / (best + 30)
    if tr.pos.y < 1500 then sc = sc * 1.2 end
    return sc
  end
  local okAll = true
  for k = 1, 60 do
    local tr = { pos = { x = (k * 15485863) % 300000 - 150000, y = (k % 3) * 1000, z = (k * 32452843) % 300000 - 150000 },
      vel = (k % 4 ~= 0) and { x = ((k * 31) % 600) - 300, y = 0, z = ((k * 17) % 600) - 300 } or nil }
    if math.abs(W.threat(tr, net) - ref(tr)) > 1e-9 then okAll = false; print("  threat mismatch for k=" .. k) end
  end
  check(okAll, "W.threat equals the brute-force reference on 60 tracks")
  -- commit requests: one entry per aircraft across networks; none for an aircraft another network engages; sorted
  local G = J.gci
  local function tr(id, num, threat) return { id = id, num = num, threat = threat, pos = { x = 0, y = 0, z = 0 } } end
  local A = { key = "red/A", name = "A", coalition = 1, tracks = {}, unassigned = {}, assign = {} }
  local Bn = { key = "red/B", name = "B", coalition = 1, tracks = {}, unassigned = {}, assign = {} }
  for id, t in pairs({ [1] = tr(1, 5, 3), [2] = tr(2, 2, 3), [3] = tr(3, 1, 1), [4] = tr(4, 9, 9) }) do
    A.tracks[id] = t; A.unassigned[id] = { tr = t, reason = "no shooter free" }
    Bn.tracks[id] = t
  end
  Bn.unassigned[1] = { tr = A.tracks[1], reason = "out of reach" }
  Bn.assign[4] = { { node = {} } }               -- B engages #9: not a commit request even though A has no shooter
  Bn.unassigned[5] = { tr = tr(5, 7, 5), reason = "no shooter free" }   -- not in B's picture any more: dropped
  J.net.networks = { ["red/A"] = A, ["red/B"] = Bn }
  local cr = G.commitRequests(1)
  local nums = {}
  for i, c in ipairs(cr) do nums[i] = c.num end
  check(table.concat(nums, ",") == "2,5,1", "threat first, then number; no duplicates; engaged and stale left out: " .. table.concat(nums, ","))
end

print(string.format("test_phase4: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
