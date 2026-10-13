-- Track type identification gated by sensor class (DESIGN 4.2; AI_BRAIN 4.2 d, owner 2026-10-12).
-- A track gets typeKnown / typeName only from a node that could really classify it: a radar in NCTR_RADARS, an
-- optical sensor within VISUAL_ID_RANGE (5 NM), or a PASSIVE (ELINT) node through the T.passiveId hook. Everything
-- else publishes the class only. The doctrine's idTime declares a track hostile (weapons tight) without naming it.
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"
local RED, BLUE = coalition.side.RED, coalition.side.BLUE
local AIR = Group.Category.AIRPLANE
local NM = 1852

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. msg) end
end
local function load(settings)
  JANUS_SETTINGS = settings
  JANUS = nil
  dofile(JANUS_FILE)
  return JANUS
end
local function node(name) return JANUS.net.nodes[name] end
local function jet(name, coa, acType, x, z)
  return F.addGroup{ name = name, coalition = coa, category = AIR,
    units = { { type = acType, x = x, z = z or 0, alt = 6000 } } }.units[1]
end
local function gciTrack(coa, id)
  for _, t in ipairs(JANUS.gci.tracks(coa)) do if t.id == id then return t end end
  return nil
end
local function noErrors(block) check(not F.logContains("ERROR JANUS"), block .. ": no Janus errors") end

-- ---------------------------------------------------------------- 1. the owner's case: Soviet radars give class only
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW 55G6", units = { { type = "55G6 EWR", x = 0, z = 5000 } } }
  F.addGroup{ name = "SAM S-125 [emcon:always]", units = { { type = "snr s-125 tr", x = 0, z = 0 }, { type = "5p73 s-125 ln", x = 200, z = 0 } } }
  local tomcat = jet("Tomcat 1", BLUE, "F-14B", 20 * NM, 0)
  local J = load()
  F.sees["EW 55G6"] = { tomcat }                 -- both report the DCS type flag (no F.noType)
  F.sees["SAM S-125 [emcon:always]"] = { tomcat }
  F.run(12)
  local t = gciTrack(RED, tomcat:getID())
  check(t and t.class == "fixed-wing", "the F-14 at 20 NM is a fixed-wing track")
  check(t and t.typeKnown == false and t.typeName == nil, "55G6 + S-125: typeKnown = false (no NCTR, no optics)")
  check(not node("EW 55G6").nctr and not node("SAM S-125 [emcon:always]").nctr, "no Soviet radar has NCTR")
  local loc = node("SAM S-125 [emcon:always]").localTracks[tomcat:getID()]
  check(loc and not loc.typeKnown, "the S-125's own picture: class only too")
  F.run(200)
  local tr = J.net.networks["red/main"].tracks[tomcat:getID()]
  check(tr.declared and not tr.typeKnown, "held for minutes: declared hostile, type still unknown")
  check(J.tracks.label(tr):find("fixed%-wing") ~= nil, "label: the class")
  noErrors("block 1")
end

-- ---------------------------------------------------------------- 2. NCTR: a Patriot names the type; settings
do
  F.reset()
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "SAM Patriot", coalition = BLUE, units = { { type = "Patriot str", x = 0, z = 0 },
    { type = "Patriot ln", x = 200, z = 0 } } }
  F.addGroup{ name = "EW Coast", coalition = BLUE, units = { { type = "FPS-117", x = 0, z = 8000 } } }
  local fencer = jet("Fencer 1", RED, "Su-24M", 60000, 0)
  local J = load()
  F.sees["EW Coast"] = { fencer }
  F.run(8)
  check(node("SAM Patriot").nctr and not node("EW Coast").nctr, "Patriot str has NCTR by default, the FPS-117 not")
  check(J.settings.NCTR_RADARS["NASAMS_Radar_MPQ64F1"] == true and J.settings.NCTR_RADARS["Hawk sr"] == nil
    and J.settings.NCTR_RADARS["Hawk tr"] == nil, "default list: Patriot and the NASAMS Sentinel, not the Hawk")
  local tr = J.net.networks["blue/main"].tracks[fencer:getID()]
  check(tr and not tr.typeKnown, "the FPS-117 alone: class only")
  J.setEmcon("SAM Patriot", "always")
  F.sees["SAM Patriot"] = { fencer }
  F.run(16)
  check(tr.typeKnown and tr.typeName == "Su-24M" and tr.idBy == "SAM Patriot (NCTR)", "the Patriot names it (NCTR)")
  check(tr.declared, "a named enemy type is declared hostile at once")
  local t = gciTrack(BLUE, fencer:getID())
  check(t and t.typeKnown == true and t.typeName == "Su-24M", "JANUS.gci v1: typeKnown / typeName as before")
  local loc = node("SAM Patriot").localTracks[fencer:getID()]
  check(loc and loc.typeKnown, "the Patriot's own picture is named too")
  F.spawn{ name = "PD Avenger", coalition = BLUE, units = { { type = "M1097 Avenger", x = 58000, z = 0 } } }
  F.run(30)
  check(node("PD Avenger") and node("PD Avenger").optic and node("PD Avenger").linked, "an Avenger 2 km from it joins the network")
  check(tr.idBy == "SAM Patriot (NCTR)", "the first identification is kept (an optic node near it later changes nothing)")
  -- settings: add an NCTR radar, remove a default one
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW 55G6", units = { { type = "55G6 EWR", x = 0, z = 5000 } } }
  F.addGroup{ name = "SAM Patriot Red", units = { { type = "Patriot str", x = 0, z = 9000 }, { type = "Patriot ln", x = 200, z = 9000 } } }
  local eagle = jet("Eagle 1", BLUE, "F-15C", 60000, 0)
  J = load{ NCTR_RADARS = { ["55G6 EWR"] = true, ["Patriot str"] = false } }
  F.sees["EW 55G6"] = { eagle }
  F.run(8)
  check(node("EW 55G6").nctr and not node("SAM Patriot Red").nctr, "NCTR_RADARS: added and removed by type")
  tr = J.net.networks["red/main"].tracks[eagle:getID()]
  check(tr and tr.typeKnown and tr.typeName == "F-15C", "a radar added to NCTR_RADARS names the type")
  noErrors("block 2")
end

-- ---------------------------------------------------------------- 3. optical: within 5 NM, line of sight, any optic node
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW 55G6", units = { { type = "55G6 EWR", x = 0, z = 5000 } } }
  F.addGroup{ name = "PD Tor [emcon:dark]", units = { { type = "Tor 9A331", x = 40000, z = 0 } } }
  local near = jet("Hornet Near", BLUE, "FA-18C_hornet", 40000 + 4.5 * NM, 0)
  local far = jet("Hornet Far", BLUE, "FA-18C_hornet", 40000 - 6 * NM, 0)
  local slant = jet("Hornet Slant", BLUE, "FA-18C_hornet", 40000 + 3 * NM, 4.5 * NM)   -- 5.4 NM: beyond 5
  local close = jet("Hornet Close", BLUE, "FA-18C_hornet", 3 * NM, 5000)               -- 3 NM from the 55G6
  local J = load()
  F.sees["EW 55G6"] = { near, far, slant, close }
  F.run(12)
  check(node("PD Tor [emcon:dark]").optic and not node("EW 55G6").optic, "optic flag from the unit data")
  local net = J.net.networks["red/main"]
  local tn, tf = net.tracks[near:getID()], net.tracks[far:getID()]
  check(tn and tn.typeKnown and tn.typeName == "FA-18C_hornet" and tn.idBy == "PD Tor [emcon:dark] (optical)",
    "4.5 NM from a dark Tor: named by its optics")
  check(tf and not tf.typeKnown, "6 NM from it: class only")
  check(tn.declared and tn.declBy == tn.idBy and tn.declAt == tn.idAt, "named by optics: declared hostile in the same pass")
  check(not node("EW 55G6").optic and not net.tracks[close:getID()].typeKnown, "3 NM from a radar without optics: class only")
  check(not net.tracks[slant:getID()].typeKnown, "3 NM across and 4.5 NM along (5.4 NM): class only")
  -- the optic node's own radar holding a track inside 5 NM names it at once; behind a hill it does not
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "PD Tor [emcon:always]", units = { { type = "Tor 9A331", x = 0, z = 9000 } } }
  local h1 = jet("Hornet 1", BLUE, "FA-18C_hornet", 3 * NM, 9000)
  J = load()
  F.blockLOS = true
  F.sees["PD Tor [emcon:always]"] = { h1 }
  F.run(12)
  net = J.net.networks["red/main"]
  check(net.tracks[h1:getID()] and not net.tracks[h1:getID()].typeKnown, "no line of sight: no visual identification")
  F.blockLOS = false
  F.run(20)
  check(net.tracks[h1:getID()].typeKnown, "in sight inside 5 NM: named")
  -- an optic node cut off from the network names nothing on the network picture
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW 55G6", units = { { type = "55G6 EWR", x = 0, z = 5000 } } }
  F.addGroup{ name = "PD Tor Lost [emcon:dark]", units = { { type = "Tor 9A331", x = 400000, z = 0 } } }   -- far beyond any link
  local h2 = jet("Hornet 2", BLUE, "FA-18C_hornet", 400000 + 2 * NM, 0)
  J = load()
  F.sees["EW 55G6"] = { h2 }
  F.run(12)
  check(not node("PD Tor Lost [emcon:dark]").linked, "the far Tor is cut off from the network")
  check(not J.net.networks["red/main"].tracks[h2:getID()].typeKnown, "an unlinked optic node does not name network tracks")
  noErrors("block 3")
end

-- ---------------------------------------------------------------- 4. PASSIVE (ELINT): a hook for COMMANDER 5.1
do
  F.reset()
  F.addGroup{ name = "CMD Post", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW 55G6", units = { { type = "55G6 EWR", x = 0, z = 5000 } } }
  local viper = jet("Viper 1", BLUE, "F-16C_50", 80000, 0)
  local J = load()
  F.sees["EW 55G6"] = { viper }
  F.run(2)
  node("EW 55G6").passive = true                 -- as a Kolchuga-class node will set it
  F.run(8)
  local tr = J.net.networks["red/main"].tracks[viper:getID()]
  check(tr and not tr.typeKnown, "a PASSIVE node with no hook names nothing")
  local asked
  J.tracks.passiveId = function(n, t) asked = n.name; return t.class == "fixed-wing" end
  F.run(16)
  check(asked == "EW 55G6" and tr.typeKnown and tr.idBy == "EW 55G6 (ELINT)", "the hook names the emitter type")
  noErrors("block 4")
end

print(string.format("test_tracks_id: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
