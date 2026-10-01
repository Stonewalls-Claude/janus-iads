-- JANUS.gci interface contract (DESIGN 4.10, Phase 2.5): version, instance, events with keys (no pile-up), tracks,
-- command nodes, radar heads, control state, SAM zones; safe before start and with no network; Janus never names a
-- consumer. Includes a reference consumer written the way a GCI script must use Janus (pull, version check, pcall,
-- fallback).
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
local function bandit(name, x, z, alt, acType)
  local g = F.addGroup{ name = name, coalition = BLUE, category = AIR,
    units = { { type = acType or "F-16C_50", x = x, z = z, alt = alt or 6000 } } }
  return g.units[1]
end
local function byName(list, name)
  for _, e in ipairs(list) do if e.name == name then return e end end
end

-- ---------------------------------------------------------------- reference consumer (what a GCI script does)
-- Looks JANUS.gci up itself every call, uses it only if it knows the version, never lets a Janus error escape.
local Consumer = { warned = false, mode = nil }
function Consumer.radarHeads(coal)
  local j = rawget(_G, "JANUS")
  local g = j and j.gci
  if not g or g.version ~= 1 then
    Consumer.mode = "own"
    return nil                               -- caller falls back to its own "EW ..." scan
  end
  local ok, res = pcall(g.radarHeads, coal)
  if not ok then
    if not Consumer.warned then Consumer.warned = true end
    Consumer.mode = "own"
    return nil
  end
  Consumer.mode = "janus"
  return res
end
Consumer.handle, Consumer.instance = nil, nil
function Consumer.subscribe(fn)
  local g = rawget(_G, "JANUS") and JANUS.gci
  if not g or g.version ~= 1 then return false end
  if Consumer.instance ~= g.instance then                  -- Janus (re)started: sign up again, once
    Consumer.instance = g.instance
    local ok, h = pcall(g.on, "nodeLost", fn, "reference-consumer")
    Consumer.handle = ok and h or nil
  end
  return true
end

-- ---------------------------------------------------------------- 1. consumer fallback: no Janus, wrong version, errors
do
  F.reset()
  check(Consumer.radarHeads(RED) == nil and Consumer.mode == "own", "no Janus: consumer falls back")
  JANUS = { gci = { version = 99, radarHeads = function() return {} end } }
  check(Consumer.radarHeads(RED) == nil and Consumer.mode == "own", "unknown version: consumer falls back")
  JANUS = { gci = { version = 1, radarHeads = function() error("boom") end } }
  check(Consumer.radarHeads(RED) == nil and Consumer.mode == "own" and Consumer.warned, "Janus error: caught, falls back")
  JANUS = nil
end

-- ---------------------------------------------------------------- 2. safe before start and with no network
do
  F.reset()
  JANUS_SETTINGS = { AUTOSTART = false }
  assert(loadfile(JANUS_FILE))()
  local G = JANUS.gci
  check(G and G.version == 1 and type(G.instance) == "number", "version 1 and an instance number before start")
  local ok = pcall(function()
    assert(#G.tracks(RED) == 0 and #G.commandNodes(RED) == 0 and #G.radarHeads(BLUE) == 0 and #G.samZones(RED) == 0)
    assert(G.controlState(RED, { x = 0, z = 0 }).ground == false)
    assert(#G.tracks(RED, "nobody") == 0)
  end)
  check(ok, "every call returns empty results (no error) before Janus has started")
  F.reset()
  local J = load()
  F.run(3)
  local ok2 = pcall(function()
    assert(#J.gci.tracks(RED) == 0 and #J.gci.commandNodes(BLUE) == 0 and J.gci.controlState(BLUE, { x = 1, z = 1 }).ground == false)
    assert(J.gci.controlState(RED, nil).ground == false)
  end)
  check(ok2, "a coalition with no network: empty results")
  check(Consumer.radarHeads(RED) ~= nil and Consumer.mode == "janus", "consumer uses Janus when it is there")
end

-- ---------------------------------------------------------------- 3. the picture: tracks, radar heads, command nodes, zones
do
  F.reset()
  F.addStatic{ name = "CMD Bunker Hama [alt:Reserve] [seats:3]", x = 0, z = 0 }
  F.addStatic{ name = "COMMS Radio Hama [ag]", x = 2000, z = 0, life = 200 }
  F.addGroup{ name = "CMD Reserve", units = { { type = "SKP-11", x = -30000, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  F.addGroup{ name = "EW Dark [emcon:dark]", units = { { type = "1L13 EWR", x = 25000, z = 5000 } } }
  F.addGroup{ name = "AWACS Mainstay", category = AIR, units = { { type = "A-50", x = 60000, z = 0, alt = 9000 } } }
  F.addGroup{ name = "SAM SA-10 Hama", units = { { type = "S-300PS 40B6M tr", x = 50000, z = 0 }, { type = "S-300PS 5P85C ln", x = 50300, z = 0 } } }
  F.addGroup{ name = "PD Tor", units = { { type = "Tor 9A331", x = 49000, z = 1000 } } }
  F.addGroup{ name = "SAM Radar Only", units = { { type = "Kub 1S91 str", x = 30000, z = 0 } } }
  F.addStatic{ name = "CMD Bunker Far", x = 0, z = 300000 }
  local b = bandit("Viper 1", 200000, 0, 7000)
  local J = load()
  F.noType["EW North"] = true
  F.sees["EW North"] = { b }
  F.sees["AWACS Mainstay"] = { b }
  F.run(12)
  local G = J.gci
  -- tracks
  local tl = G.tracks(RED)
  local t1 = tl[1]
  check(#tl == 1 and t1.num >= 1 and t1.x == 200000 and t1.y == 7000 and t1.class == "fixed-wing", "track: number, position, class")
  check(t1.typeKnown and t1.typeName == "F-16C_50", "identified by the AWACS (type flag)")
  check(type(t1.holders) == "table" and #t1.holders == 2 and t1.lastSeen ~= nil, "holders and last-seen time")
  check(t1.vx == 0 and t1.vz == 0, "velocity fields present (0 until the second plot)")
  check(t1.id == b:getID(), "a track's id is the DCS unit ID (GCI keys on it)")
  t1.x = -1
  check(G.tracks(RED)[1].x == 200000, "results are copies: a consumer cannot change Janus's picture")
  check(#G.tracks(BLUE) == 0, "blue sees nothing")
  check(#G.tracks(RED, "CMD Bunker Hama [alt:Reserve] [seats:3]") == 1, "the command post sees the network picture")
  check(#G.tracks(RED, "CMD Reserve") == 1, "a standby post that is up and linked sees it too")
  check(#G.tracks(BLUE, "CMD Reserve") == 0, "asking with the wrong coalition gives nothing")
  check(#G.tracks(RED, "AWACS Mainstay") == 1, "an airborne node's own plots and the network's are merged, not doubled")
  -- radar heads
  local rh = G.radarHeads(RED)
  local ew, aw = byName(rh, "EW North"), byName(rh, "AWACS Mainstay")
  check(ew and ew.r2 == 400000 * 400000 and not ew.airborne, "EW head with its reach squared")
  check(aw and aw.airborne and aw.y == 9000, "AWACS listed once, as airborne")
  check(byName(rh, "EW Dark [emcon:dark]") == nil, "a dark radar is not a head")
  -- command nodes
  local cn = G.commandNodes(RED)
  local main, res, awc = byName(cn, "CMD Bunker Hama [alt:Reserve] [seats:3]"), byName(cn, "CMD Reserve"), byName(cn, "AWACS Mainstay")
  check(main and main.kind == "ground" and main.inCommand and main.radio == "ok" and main.seats == 3 and main.alternate == "CMD Reserve",
    "main post: ground, in command, radio ok, 3 seats, alternate named")
  check(main.reach == 300000 and awc.reach == 300000, "radio reach: agReach with the radio up, AWACS its own")
  check(res and not res.active and not res.inCommand and res.alternateFor == main.name, "reserve stands by")
  check(awc and awc.kind == "airborne" and awc.parent == main.name, "AWACS is an airborne command node under the post")
  check(main.fighterControl == "ground" and main.awacsTakeover == false, "SOVIET_PVO: ground control, no AWACS takeover")
  check(byName(cn, "EW North") == nil and byName(cn, "SAM SA-10 Hama") == nil, "radars and SAMs are not command nodes")
  -- SAM zones
  local z = byName(G.samZones(RED), "SAM SA-10 Hama")
  check(z and z.name == "SAM SA-10 Hama" and z.r == 120000 and z.rMin == 2000 and z.altMax == 27000 and z.emitting == false,
    "SAM zone with envelope, dark (not cued yet)")
  local tor = byName(G.samZones(RED), "PD Tor")
  check(tor and tor.kind == "PD" and tor.r == 12000, "point defence has a zone too")
  check(byName(G.samZones(RED), "SAM Radar Only") == nil and byName(G.samZones(RED), "EW North") == nil,
    "no zone for a radar-only battery or an EW radar")
  -- control state
  local cs = G.controlState(RED, { x = 100000, z = 0 })
  check(cs.ground and cs.via == main.name and cs.radio == "ok" and cs.reach == 300000, "ground control reaches 100 km out through the main post")
  check(not G.controlState(RED, { x = 900000, z = 0 }).ground, "no radar coverage: no ground control")
  F.killStatic(F.statics["COMMS Radio Hama [ag]"])
  F.run(20)
  local cs2 = G.controlState(RED, { x = 100000, z = 0 })
  check(not cs2.ground or cs2.via ~= main.name, "radio down: the main post's backup set (60 km) no longer reaches 100 km")
  check(G.controlState(RED, { x = 40000, z = 0 }).radio == "backup", "the backup set still reaches 40 km")
  check(byName(G.commandNodes(RED), main.name).reach == 60000, "reach field follows the radio: 60 km on backup")

  -- radio repaired: nodeRestored "radio ok"
  local evs = {}
  G.on("nodeRestored", function(ev) evs[#evs + 1] = ev end, "t")
  F.statics["COMMS Radio Hama [ag]"].alive = true
  J.net.dirty = true
  F.run(30)
  local ro = 0
  for _, ev in ipairs(evs) do if ev.reason == "radio ok" and ev.name == main.name then ro = ro + 1 end end
  check(ro == 1, "radio repaired: one nodeRestored (radio ok) for the post (" .. ro .. ")")
  local far = G.controlState(RED, { x = 0, z = 280000 })
  check(far.ground and far.via == "CMD Bunker Far", "two posts reach the point: the nearest answers")
  local named = G.controlState(RED, { x = 0, z = 280000 }, main.name)
  check(named.ground and named.via == main.name and named.reach == 300000, "controlState for a named post: that post only")
  check(not G.controlState(RED, { x = 0, z = 280000 }, "CMD Reserve").ground, "a standby post named: no control")
  check(not G.controlState(RED, { x = 0, z = 280000 }, "nobody").ground, "an unknown post named: no control")
  -- a command post without power is not in command and sees nothing
  local mn = J.net.nodes[main.name]
  mn.powered = false
  local m2 = byName(G.commandNodes(RED), main.name)
  check(not m2.inCommand and m2.powered == false and m2.alive == true and m2.working == true, "unpowered post: alive, working, not powered, not in command")
  check(#G.tracks(RED, main.name) == 0, "an unpowered post sees nothing")
  mn.powered = true
  mn.working = false
  local m3 = byName(G.commandNodes(RED), main.name)
  check(not m3.inCommand and m3.working == false and m3.powered == true and #G.tracks(RED, main.name) == 0, "a post without its equipment is not in command")
  mn.working = true
  -- two tracks, ordered; velocity after a second plot
  local b2 = bandit("Viper 2", 150000, 20000, 6000)
  F.sees["EW North"] = { b, b2 }
  F.run(40)
  local tl2 = G.tracks(RED)
  check(#tl2 == 2 and tl2[1].num < tl2[2].num, "tracks ordered by number")
  J.net.networks["red/main"].tracks[b.id].vel = { x = -100, y = 5, z = 20 }
  local t1b
  for _, t in ipairs(G.tracks(RED)) do if t.id == b.id then t1b = t end end
  check(t1b and t1b.vx == -100 and t1b.vy == 5 and t1b.vz == 20, "velocity copied")
  J.net.networks["red/main"].tracks[b.id].vel = nil
  for _, t in ipairs(G.tracks(RED)) do if t.id == b.id then t1b = t end end
  check(t1b.vx == 0 and t1b.vy == 0 and t1b.vz == 0, "no velocity yet: zeros")
  -- no radar coverage anywhere: no ground control even inside radio reach
  F.killGroup(F.groups["EW North"])
  F.killGroup(F.groups["AWACS Mainstay"])
  F.run(60)
  check(#G.radarHeads(RED) == 0 and not G.controlState(RED, { x = 10000, z = 0 }).ground, "no radar heads: no ground control")
  local hot = byName(G.samZones(RED), "SAM SA-10 Hama")
  check(hot and hot.linked == true, "zone carries the link state")
  check(not F.logContains("ERROR JANUS"), "block 3: no Janus errors")
end

-- ---------------------------------------------------------------- 4. events: keys replace, off, throwing subscribers, instance
do
  F.reset()
  F.addGroup{ name = "CMD Main [alt:Reserve]", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "CMD Reserve", units = { { type = "SKP-11", x = 0, z = 100000 } } }
  F.addGroup{ name = "COMMS Relay", units = { { type = "ZIL-131 KUNG", x = 70000, z = 0 } } }
  F.addGroup{ name = "SAM SA-6 Far", units = { { type = "Kub 1S91 str", x = 170000, z = 0 }, { type = "Kub 2P25 ln", x = 170300, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  F.addGroup{ name = "POWER Gen", units = { { type = "generator_5i57", x = 20500, z = 0 } } }
  local J = load()
  F.run(3)
  local G = J.gci
  local got, n1, n2, na, nb = {}, 0, 0, 0, 0
  local ha = G.on("nodeLost", function() na = na + 1 end, "a")
  G.on("nodeLost", function() nb = nb + 1 end, "b")
  G.on("nodeLost", function() n1 = n1 + 1 end, "gci")
  G.on("nodeLost", function() n2 = n2 + 1 end, "gci")          -- same key: replaces, never piles up
  G.on("nodeLost", function() error("subscriber bug") end, "bad")
  local h = G.on("nodeLost", function(ev) got[#got + 1] = ev end)
  G.on("nodeDegraded", function(ev) got[#got + 1] = ev end, "log")
  G.on("nodeRestored", function(ev) got[#got + 1] = ev end, "log")
  G.on("authorityChanged", function(ev) got[#got + 1] = ev end, "log")
  check(G.on("noSuchEvent", function() end) == nil and G.on("nodeLost", "not a function") == nil, "bad subscriptions refused")
  F.killGroup(F.groups["COMMS Relay"])
  F.run(10)
  check(n1 == 0 and n2 == 1, "re-subscribing with the same key replaced the callback (fired once)")
  check(na == 1 and nb == 1, "different keys never replace each other")
  check(G.off(ha), "off works on the first subscription too")
  local hs = {}
  for i = 1, 4 do hs[i] = G.on("authorityChanged", function() end, "k" .. i) end
  check(G.off(hs[2]) and G.off(hs[3]) and G.off(hs[4]) and G.off(hs[1]), "off finds a subscription anywhere in the list")
  local lost
  for _, ev in ipairs(got) do if ev.event == "nodeLost" and ev.name == "COMMS Relay" then lost = ev end end
  check(lost and lost.kind == "COMMS" and lost.coalition == RED and lost.state == "lost" and lost.net == "red/main", "nodeLost payload")
  local unl
  for _, ev in ipairs(got) do if ev.event == "nodeDegraded" and ev.name == "SAM SA-6 Far" then unl = ev end end
  check(unl and unl.reason == "unlinked", "the SAM behind the relay: nodeDegraded (unlinked)")
  check(F.logContains("gci.subscriber"), "a throwing subscriber is logged, the others still run")
  check(G.off(h) and not G.off(h), "off removes a subscription once")
  local before = #got
  F.killGroup(F.groups["POWER Gen"])
  F.run(330)
  local pw
  for i = before + 1, #got do if got[i].name == "EW North" and got[i].reason == "no power" then pw = got[i] end end
  check(pw and pw.event == "nodeDegraded", "power exhausted: nodeDegraded (no power)")
  F.revive(F.groups["POWER Gen"])
  J.net.dirty = true
  F.run(340)
  local pr = 0
  for _, ev in ipairs(got) do if ev.event == "nodeRestored" and ev.name == "EW North" and ev.reason == "power" then pr = pr + 1 end end
  check(pr == 1, "power back: one nodeRestored (power)")
  F.revive(F.groups["COMMS Relay"])
  J.net.dirty = true
  F.run(380)
  local lr = 0
  for _, ev in ipairs(got) do if ev.event == "nodeRestored" and ev.name == "SAM SA-6 Far" and ev.reason == "linked" then lr = lr + 1 end end
  check(lr == 1, "relay repaired: one nodeRestored (linked) for the SAM behind it")
  F.killGroup(F.groups["CMD Main [alt:Reserve]"])
  F.run(600)
  local tk
  for _, ev in ipairs(got) do if ev.event == "authorityChanged" and ev.name == "CMD Reserve" then tk = ev end end
  check(tk and tk.state == "in command" and tk.reason:find("took over from CMD Main") ~= nil, "authorityChanged on takeover")
  F.revive(F.groups["CMD Main [alt:Reserve]"])
  J.net.dirty = true
  F.run(610)
  local sd, rs
  for _, ev in ipairs(got) do
    if ev.event == "authorityChanged" and ev.state == "standby" then sd = ev end
    if ev.event == "nodeRestored" and ev.name == "CMD Main [alt:Reserve]" and ev.reason == "repaired" then rs = ev end
  end
  check(sd and sd.name == "CMD Reserve" and rs, "main post repaired: nodeRestored + authorityChanged (standby)")
  F.run(640)
  local nrep = 0
  for _, l in ipairs(F.log) do if l:find("CMD Main [alt:Reserve] back in service", 1, true) then nrep = nrep + 1 end end
  check(nrep == 1, "'back in service' once, not on every pass (" .. nrep .. ")")
  -- instance: a new Janus start gives a new instance; the reference consumer re-subscribes exactly once per instance
  local calls = 0
  check(Consumer.subscribe(function() calls = calls + 1 end), "consumer subscribed")
  local inst = J.gci.instance
  Consumer.subscribe(function() calls = calls + 1 end)
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW X", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  local J2 = load()
  F.run(3)
  check(J2.gci.instance ~= inst, "a new Janus start has a new instance")
  Consumer.subscribe(function() calls = calls + 1 end)
  Consumer.subscribe(function() calls = calls + 1 end)
  F.killGroup(F.groups["EW X"])
  F.run(10)
  check(calls == 1, "reference consumer: one callback per Janus instance (" .. calls .. ")")
  check(not F.logContains("ERROR JANUS [gci"), "no interface errors")
end

-- ---------------------------------------------------------------- 5. doctrine delegation and an airborne node taking over
do
  F.reset()
  F.addGroup{ name = "CMD CRC", coalition = BLUE, units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "AWACS Sentry", coalition = BLUE, category = AIR, units = { { type = "E-3A", x = 50000, z = 0, alt = 9000 } } }
  F.addGroup{ name = "EW South", coalition = BLUE, units = { { type = "FPS-117", x = 10000, z = 0 } } }
  local J = load()
  F.run(3)
  local cn = J.gci.commandNodes(BLUE)
  local crc, aw = byName(cn, "CMD CRC"), byName(cn, "AWACS Sentry")
  check(crc.fighterControl == "aew" and crc.awacsTakeover == true, "US_MODERN: AWACS controls fighters and takes over")
  check(aw.kind == "airborne" and aw.parent == "CMD CRC", "E-3 under the CRC")
  local own = J.gci.controlState(BLUE, { x = 100000, z = 0 })
  check(own.ground and own.radio == "own" and own.reach == 300000, "a post with no radio modelled reaches agReach")
  check(crc.reach == 300000, "reach field without a radio modelled: agReach")
  F.killGroup(F.groups["CMD CRC"])
  F.run(10)
  local aw2 = byName(J.gci.commandNodes(BLUE), "AWACS Sentry")
  check(aw2.alive and not aw2.linked, "CRC gone: the AWACS is up but cut off (consumer applies awacsTakeover)")
  check(#J.gci.tracks(BLUE, "AWACS Sentry") == 0, "and with no radar contacts it sees nothing yet")
end

-- ---------------------------------------------------------------- 5b. reach per doctrine; AWACS recognised by type
do
  F.reset()
  F.addStatic{ name = "CMD Hanoi", x = 0, z = 0 }
  local radio = F.addStatic{ name = "COMMS Radio Hanoi [ag]", x = 2000, z = 0, life = 200 }
  F.addGroup{ name = "EW Hanoi", units = { { type = "P14_SR", x = 10000, z = 0 } } }
  F.addGroup{ name = "Magic AEW ACE", category = AIR, units = { { type = "A-50", x = 50000, z = 0, alt = 9000 } } }
  F.addGroup{ name = "Chevy 1 [skill:VET]", category = AIR, units = { { type = "Su-27", x = 60000, z = 0, alt = 9000 } } }
  local J = load{ RED_DOCTRINE = { base = "NVA_VIETNAM_1965_72", agReach = 150000 } }
  F.run(3)
  local cn = J.gci.commandNodes(RED)
  local post, aew = byName(cn, "CMD Hanoi"), byName(cn, "Magic AEW ACE")
  check(post and post.reach == 150000, "a doctrine's own agReach is the reach")
  check(aew and aew.kind == "airborne" and aew.reach == 150000, "an AWACS named by callsign is recognised by its type")
  check(J.net.nodes["Chevy 1 [skill:VET]"] == nil, "a fighter group without a role word is not")
  F.killStatic(radio)
  F.run(10)
  check(byName(J.gci.commandNodes(RED), "CMD Hanoi").reach == 0, "NVA: no backup set, reach 0 with the radio gone")
  -- picked up after start too
  F.spawn{ name = "Wizard AEW", coalition = RED, category = AIR, units = { { type = "A-50", x = 80000, z = 0, alt = 9000 } } }
  F.run(20)
  check(J.net.nodes["Wizard AEW"] ~= nil and J.net.nodes["Wizard AEW"].airborne, "a callsign-named AWACS spawned later is picked up")
  check(not F.logContains("ERROR JANUS"), "block 5b: no Janus errors")
end

-- ---------------------------------------------------------------- 6. Janus never names a consumer
do
  local names = { "janus_core", "janus_names", "janus_doctrine", "janus_network", "janus_tracks", "janus_wta",
                  "janus_emcon", "janus_arm", "janus_aaa", "janus_gci", "janus_debugview", "janus_setup" }
  local hits = {}
  for _, n in ipairs(names) do
    local fh = io.open("src/" .. n .. ".lua", "r")
    if fh then
      local src = fh:read("*a")
      fh:close()
      for _, pat in ipairs({ "StonewallC", "GCI%.", "_G%.GCI", "\"GCI\"", "setGroundSource" }) do
        if src:find(pat) then hits[#hits + 1] = n .. ":" .. pat end
      end
    else
      hits[#hits + 1] = "missing " .. n
    end
  end
  check(#hits == 0, "no consumer named in src/ (" .. table.concat(hits, ", ") .. ")")
end

print(string.format("test_gci_api: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
