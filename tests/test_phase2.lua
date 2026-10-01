-- Phase 2 tests: static command posts / radios / power (DESIGN 4.1A), bare [flag] tags, air-ground radio state,
-- backup link, alternate command post, track picture (class, velocity, identification by type flag and by dwell),
-- threat evaluation and weapon-target assignment (Pk, hysteresis, handoff, salvo, channels, point-defence discount,
-- ammunition) and WTA-driven EMCON.
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
local function near(a, b, eps) return a ~= nil and math.abs(a - b) <= (eps or 0.005) end
local function bandit(name, x, z, alt, acType)
  local g = F.addGroup{ name = name, coalition = BLUE, category = AIR,
    units = { { type = acType or "F-16C_50", x = x, z = z, alt = alt or 6000 } } }
  return g.units[1]
end
local function sa10(name, x, z)
  F.addGroup{ name = name, units = { { type = "S-300PS 40B6M tr", x = x, z = z }, { type = "S-300PS 5P85C ln", x = x + 300, z = z } } }
end
local function sa6(name, x, z)
  F.addGroup{ name = name, units = { { type = "Kub 1S91 str", x = x, z = z }, { type = "Kub 2P25 ln", x = x + 300, z = z } } }
end

-- ---------------------------------------------------------------- 1. names: bare flags
do
  F.reset()
  local J = load()
  local p = J.names.parse("COMMS Radio Hama [ag] [cmd:Hama]")
  check(p and p.role == "COMMS" and p.tags.ag == "true" and p.tags.cmd == "Hama" and p.label == "Radio Hama", "bare [ag] flag + key tag")
  local q = J.names.parse("SAM SA-6 Homs [VET]")
  check(q and q.tags.vet == "true" and q.label == "SA-6 Homs", "bare flag removed from the label")
end

-- ---------------------------------------------------------------- 2. static command post, relay, power
do
  F.reset()
  F.addStatic{ name = "CMD Bunker Hama", type = ".Command Center", x = 0, z = 0, life = 4000 }
  F.addStatic{ name = "COMMS Tower North", type = "Comms tower M", x = 70000, z = 0, life = 200 }
  local gen = F.addStatic{ name = "POWER Plant EW", type = "GeneratorF", x = 20500, z = 0, life = 10 }
  F.addStatic{ name = "SAM Static Wrong", type = "Bunker 1", x = 5000, z = 5000 }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  sa10("SAM SA-10 Hama", 50000, 0)
  sa6("SAM SA-6 Far", 170000, 0)
  local J = load()
  F.run(3)
  local cmd, relay, pw = node("CMD Bunker Hama"), node("COMMS Tower North"), node("POWER Plant EW")
  check(cmd and cmd.kind == "C2" and cmd.static and cmd.working, "static command post is a working C2 node")
  check(relay and relay.kind == "COMMS" and relay.static and pw and pw.kind == "POWER", "static relay and power nodes")
  check(node("SAM SA-6 Far").linked and node("SAM SA-6 Far").parent == relay, "far SAM linked through the static relay")
  check(node("EW North").powerSources and node("EW North").powerSources[1] == pw, "EW powered by the static generator")
  check(node("SAM Static Wrong") == nil, "a static SAM is not a node")
  check(F.logContains("static 'SAM Static Wrong' starts with SAM, but only CMD, COMMS and POWER"), "report explains the wrong static")
  check(F.logContains("static '.Command Center', life 4000"), "report notes the static type and life")
  check(F.logContains("CMD Bunker Hama -> CMD (1x STATIC)") and F.logContains("Recognised 6 red"), "statics counted in the report")
  -- relay destroyed (DCS fires S_EVENT_DEAD for statics): the far SAM loses its link (170 km: no backup reach)
  F.killStatic(F.statics["COMMS Tower North"])
  F.run(10)
  check(not relay.alive and not node("SAM SA-6 Far").linked, "relay destroyed -> far SAM unlinked")
  check(F.logContains("COMMS Tower North destroyed"), "static death logged")
  -- generator destroyed with no event: the network pass still sees it (isExist backstop)
  F.killStatic(gen, true)
  F.run(20)
  check(not pw.alive and node("EW North").reserveUntil ~= nil, "silent static death caught by the network pass; EW on reserve")
  -- command post destroyed
  F.killStatic(F.statics["CMD Bunker Hama"])
  F.run(30)
  check(not cmd.alive and not node("SAM SA-10 Hama").linked, "static command post destroyed -> SAMs unlinked")
  -- a static spawned during the mission is picked up from its BIRTH event
  local late = F.addStatic{ name = "CMD Bunker Homs", x = 30000, z = 0 }
  F.fire({ id = world.event.S_EVENT_BIRTH, initiator = late })
  F.run(40)
  check(node("CMD Bunker Homs") ~= nil and node("CMD Bunker Homs").static, "late static command post picked up")
  check(node("SAM SA-10 Hama").linked and node("SAM SA-10 Hama").parent == node("CMD Bunker Homs"), "SAM relinks to the new post")
  F.fire({ id = world.event.S_EVENT_BIRTH, initiator = F.addStatic{ name = "Warehouse 3", x = 1, z = 1 } })
  F.run(42)
  check(node("Warehouse 3") == nil, "an unnamed static is ignored")
  check(not F.logContains("ERROR JANUS"), "block 2: no Janus errors")
end

-- ---------------------------------------------------------------- 3. air-ground radio
do
  F.reset()
  F.addStatic{ name = "CMD Bunker Hama", x = 0, z = 0 }
  local radio = F.addStatic{ name = "COMMS Radio Hama [ag]", type = "Comms tower M", x = 2000, z = 0, life = 200 }
  F.addStatic{ name = "CMD Bunker Aleppo", x = 0, z = 200000 }
  F.addStatic{ name = "COMMS Tower Mid", x = 60000, z = 0 }
  sa6("SAM SA-6 Mid", 100000, 0)
  local J = load()
  F.run(3)
  local r, c = node("COMMS Radio Hama [ag]"), node("CMD Bunker Hama")
  check(r.agRadio and r.agCP == c and r.linked, "air-ground radio belongs to the post 2 km away")
  check(c.agState == "ok" and node("CMD Bunker Aleppo").agState == "own", "radio up: ok; a post with no radio modelled: own")
  check(node("SAM SA-6 Mid").parent == node("COMMS Tower Mid"), "the air-ground radio is not a relay hub")
  local got
  J.net.on("radio", function(cp, state) got = cp.name .. "=" .. state end)
  F.killStatic(radio)
  F.run(10)
  check(c.agState == "backup" and got == "CMD Bunker Hama=backup", "radio destroyed -> backup set (SOVIET_PVO), callback fired")
  check(F.logContains("CMD Bunker Hama air-ground radio: backup"), "radio state change logged")

  F.reset()
  F.addStatic{ name = "CMD Bunker Hanoi", x = 0, z = 0 }
  local r2 = F.addStatic{ name = "COMMS Radio Hanoi [ag] [cmd:Bunker Hanoi]", x = 9000, z = 0 }
  load{ RED_DOCTRINE = "NVA_VIETNAM_1965_72" }
  F.run(3)
  check(node("COMMS Radio Hanoi [ag] [cmd:Bunker Hanoi]").agCP == node("CMD Bunker Hanoi"), "[cmd:] ties a radio to its post")
  F.killStatic(r2)
  F.run(10)
  check(node("CMD Bunker Hanoi").agState == "none", "NVA: no backup radio -> none")
  check(not F.logContains("ERROR JANUS"), "block 3: no Janus errors")
end

-- ---------------------------------------------------------------- 4. backup link after relay loss, delay on cues
do
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "COMMS Relay North", units = { { type = "ZIL-131 KUNG", x = 70000, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  sa6("SAM SA-6 Far", 140000, 0)
  local b = bandit("Viper 1", 400000, 0, 3000)
  local J = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", linkBackup = { range = 150000 } } }
  F.sees["EW North"] = { b }
  F.run(5)
  local n = node("SAM SA-6 Far")
  check(n.linked and n.linkVia == nil and n.linkDelay == 0, "linked through the relay, no backup")
  F.killGroup(F.groups["COMMS Relay North"])
  F.run(12)
  check(n.linked and n.linkVia == "backup" and n.parent == node("CMD Hama") and n.linkDelay == 40,
    "relay gone -> backup link to CMD Hama, +40 s (SOVIET_PVO REG)")
  check(count("SAM SA-6 Far on the backup link to CMD Hama") == 1, "backup link logged once")
  F.move(b, 150000, 0)                      -- 10 km from the SA-6
  F.run(40)
  check(not F.emitting("SAM SA-6 Far"), "cue delayed by the backup link (6 + 40 s)")
  F.run(80)
  check(F.emitting("SAM SA-6 Far"), "up once cue + backup delay have passed")
  check(not F.logContains("ERROR JANUS"), "block 4: no Janus errors")
end

-- ---------------------------------------------------------------- 5. alternate command post
do
  F.reset()
  F.addGroup{ name = "CMD Main [alt:Reserve]", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "CMD Reserve", units = { { type = "SKP-11", x = 0, z = 100000 } } }
  sa6("SAM SA-6 A", 50000, 0)
  local J = load()
  F.run(3)
  local main, alt, s = node("CMD Main [alt:Reserve]"), node("CMD Reserve"), node("SAM SA-6 A")
  check(main.altNode == alt and alt.altFor == main and not alt.active, "alternate stands by")
  check(s.parent == main, "SAM under the main post")
  local took
  J.net.on("takeover", function(a, m) took = a.name .. "<" .. m.name end)
  F.killGroup(F.groups["CMD Main [alt:Reserve]"])
  F.run(20)
  check(not s.linked, "main post destroyed: the standby post is not in command yet (SAM unlinked)")
  F.run(170)
  check(not alt.active, "alternate not yet in command before 180 s (SOVIET_PVO REG)")
  F.run(200)
  check(alt.active and s.linked and s.parent == alt, "alternate takes over after 180 s; SAM relinked to it")
  check(took == "CMD Reserve<CMD Main [alt:Reserve]" and F.logContains("CMD Reserve takes over command from CMD Main"), "takeover callback + log")
  F.killGroup(F.groups["SAM SA-6 A"])
  F.run(220)
  check(alt.active, "a later death (topology pass) does not put the acting post back on standby")
  check(not F.logContains("ERROR JANUS"), "block 5: no Janus errors")
end

-- ---------------------------------------------------------------- 6. tracks: class, velocity, identification
do
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW Ground", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  local b = bandit("Viper 1", 200000, 0, 7000)
  local J = load()
  F.noType["EW Ground"] = true
  F.sees["EW Ground"] = { b }
  F.run(8)
  local net = J.net.networks["red/main"]
  local tr = net.tracks and net.tracks[b.id]
  check(tr and tr.class == "fixed-wing" and not tr.typeKnown and tr.typeName == nil, "ground EW track: class only")
  check(tr and J.tracks.label(tr):find("fixed%-wing") ~= nil, "label shows the class")
  local loc = node("EW Ground").localTracks[b.id]
  check(loc and loc.num == tr.num, "same track number in the radar's and the network's picture")
  F.move(b, 199000, 0)
  F.run(14)
  check(tr.vel and near(tr.vel.x, -200, 1), "velocity from successive plots (" .. tostring(tr.vel and tr.vel.x) .. ")")
  F.run(80)
  check(not tr.typeKnown, "not identified before the doctrine's idTime (REG 90 s)")
  F.run(110)
  check(tr.typeKnown and tr.typeName == "F-16C_50" and tr.idBy:find("^held") ~= nil, "identified by dwell after 90 s")
  check(not loc.typeKnown, "a radar's own picture never identifies by dwell")
  -- a sensor that reports the type identifies at once
  F.addGroup{ name = "EW Airborne", units = { { type = "55G6 EWR", x = 30000, z = 0 } } }
  local b2 = bandit("Viper 2", 150000, 5000, 7000, "F-15C")
  F.spawn{ name = "EW Late", units = { { type = "55G6 EWR", x = 25000, z = 0 } } }
  F.sees["EW Late"] = { b2 }
  F.run(130)
  local t2 = net.tracks[b2.id]
  check(t2 and t2.typeKnown and t2.typeName == "F-15C" and t2.idBy == "EW Late", "type flag identifies immediately")
  check(J.tracks.label(t2) == "T" .. t2.num .. " F-15C", "label shows the type once known")
  local list = J.tracks.list(net.tracks)
  check(#list == 2 and list[1].num < list[2].num, "track list sorted by number")
  check(not F.logContains("ERROR JANUS"), "block 6: no Janus errors")
end

-- ---------------------------------------------------------------- 7. WTA: Pk, hysteresis, handoff, salvo, channels
do
  F.reset()
  F.addGroup{ name = "CMD Test", units = { { type = "S-300PS 54K6 cp", x = 0, z = -5000 } } }
  sa10("SAM A", 0, 0)
  sa6("SAM B", 110000, 0)
  F.addGroup{ name = "PD Tor", units = { { type = "Tor 9A331", x = 100000, z = 3000 } } }
  local bu = bandit("Target", 300000, 300000, 3000)
  local J = load{ RED_DOCTRINE = { base = "NATO_COLDWAR", wta = { lead = 0 } } }
  F.run(3)
  local W = J.wta
  local net = J.net.networks["red/main"]
  local A, B, T = node("SAM A"), node("SAM B"), node("PD Tor")
  local function track(id, x, z, alt)
    net.tracks = net.tracks or {}
    local tr = net.tracks[id]
    if not tr then
      tr = { id = id, num = id, obj = bu, first = 0, sensors = {}, class = "fixed-wing", typeKnown = false }
      net.tracks[id] = tr
    end
    tr.pos, tr.t, tr.vel = { x = x, y = alt or 3000, z = z }, 1e9, nil
    return tr
  end
  local function shooters(id)
    local out = {}
    for _, c in ipairs((net.assign or {})[id] or {}) do out[#out + 1] = c.node.name end
    table.sort(out)
    return table.concat(out, ",")
  end
  local env = W.envelope(A)
  check(env.R == 120000 and env.rMin == 2000 and env.aMax == 27000 and env.channels == 2, "SA-10 envelope from DCS data")
  check(W.envelope(B).R == 25000 and W.envelope(B).rMin == 1000, "SA-6 envelope")
  local tr = track(1, 60000, 0)
  check(near(W.pk(A, tr, 0), 0.75) and W.pk(B, tr, 0) == 0, "Pk: SA-10 mid-envelope 0.75, SA-6 out of range 0")
  check(W.pk(A, track(99, 60000, 0, 40000), 0) == 0, "above the altitude band: 0")
  net.tracks[99] = nil
  check(W.pk(A, track(98, 1000, 0, 500), 0) == 0, "inside minimum range: 0")
  net.tracks[98] = nil
  W.assign(net)
  check(shooters(1) == "SAM A" and A.assigned and A.assigned[1] == tr, "best shooter assigned")
  check(F.logContains("T1 fixed-wing assigned to SAM A (Pk 0.75)"), "assignment logged")
  track(1, 95000, 0)                      -- SA-6 now slightly better (0.70 vs 0.61): inside the margin
  check(W.pk(B, tr, 0) > W.pk(A, tr, 0), "SA-6 is the better shot at 95 km")
  W.assign(net)
  check(shooters(1) == "SAM A", "hysteresis: SAM A keeps the target within handoffMargin")
  track(1, 105000, 0)                     -- SA-10 near its edge: 0.49 vs 0.70
  W.assign(net)
  check(shooters(1) == "SAM B", "handoff when the new shooter is better by more than the margin")
  check(F.logContains("T1 fixed-wing handed from SAM A to SAM B"), "handoff logged")
  -- point defence bids at a discount
  net.assign = {}
  net.tracks[1] = nil
  local tt = track(2, 100000, 6000, 1000)
  local pkT, pkA = W.pk(T, tt, 0), W.pk(A, tt, 0)
  check(pkT > pkA, "Tor has the better Pk (" .. pkT .. " vs " .. pkA .. ")")
  local savedB = B.alive
  B.alive = false
  W.assign(net)
  check(shooters(2) == "SAM A", "PD bid discounted: the SAM engages, the Tor is saved")
  net.doctrine.wta.pdDiscount = 1
  net.assign = {}
  W.assign(net)
  check(shooters(2) == "PD Tor", "without the discount the Tor would take it")
  net.doctrine.wta.pdDiscount = 0.5
  B.alive = savedB
  -- salvo: pkGoal and maxShooters
  net.assign = {}
  net.tracks[2] = nil
  track(3, 95000, 0)
  net.doctrine.wta.maxShooters, net.doctrine.wta.pkGoal = 2, 0.85
  W.assign(net)
  check(shooters(3) == "SAM A,SAM B", "salvo: second shooter until combined Pk >= 0.85")
  net.assign = {}
  net.doctrine.wta.pkGoal = 0.6
  W.assign(net)
  check(shooters(3) == "SAM B", "one shooter is enough when it alone reaches pkGoal")
  net.doctrine.wta.maxShooters, net.doctrine.wta.pkGoal = 1, 0.7
  -- channels: the SA-6 guides two targets at once; a third goes to the next shooter
  net.assign = {}
  net.tracks[3] = nil
  track(4, 108000, 1000); track(5, 108000, -1000); track(6, 112000, 0)
  W.assign(net)
  local onB = 0
  for _, id in ipairs({ 4, 5, 6 }) do if shooters(id) == "SAM B" then onB = onB + 1 end end
  check(onB == 2 and #(B.assigned or {}) == 2, "SA-6 takes 2 targets (2 channels)")
  check(shooters(4) ~= "" and shooters(5) ~= "" and shooters(6) ~= "", "the third target goes to another shooter")
  -- minPk
  net.assign = {}
  for _, id in ipairs({ 4, 5, 6 }) do net.tracks[id] = nil end
  track(7, 0, 118000)
  net.doctrine.wta.minPk = 0.5
  W.assign(net)
  check(shooters(7) == "", "below minPk nobody is assigned")
  net.doctrine.wta.minPk = 0.15
  -- ammunition: a battery with no missiles does not bid
  for _, u in ipairs(F.groups["SAM A"].units) do u.ammo = 0 end
  W.ammoAt = -1e9
  W.tick()
  check(A.ammo == 0 and W.pk(A, net.tracks[7], 0) == 0, "out of missiles: Pk 0")
  check(F.logContains("SAM A out of missiles"), "out of missiles logged")
  -- threat: the closer, closing track is more urgent
  local near1 = { pos = { x = 10000, y = 3000, z = 0 }, vel = { x = -250, y = 0, z = 0 } }
  local far1 = { pos = { x = 200000, y = 3000, z = 0 }, vel = { x = -250, y = 0, z = 0 } }
  local away = { pos = { x = 20000, y = 3000, z = 0 }, vel = { x = 250, y = 0, z = 0 } }
  check(W.threat(near1, net) > W.threat(far1, net), "a close, closing track is a bigger threat")
  check(W.threat(near1, net) > W.threat(away, net), "closing beats opening")
  local low = { pos = { x = 50000, y = 300, z = 0 } }
  local high = { pos = { x = 50000, y = 9000, z = 0 } }
  check(W.threat(low, net) > W.threat(high, net), "low flyers rank higher")
  check(not F.logContains("ERROR JANUS"), "block 7: no Janus errors")
end

-- ---------------------------------------------------------------- 8. WTA drives EMCON; handoff when a shooter dies
do
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  sa10("SAM SA-10 Hama", 50000, 0)
  sa6("SAM SA-6 Near", 70000, 0)
  local b = bandit("Viper 1", 80000, 0, 6000)
  local J = load{ RED_DOCTRINE = "NATO_COLDWAR" }
  F.sees["EW North"] = { b }
  F.run(40)
  check(F.emitting("SAM SA-10 Hama") and not F.emitting("SAM SA-6 Near"), "only the assigned battery comes up")
  check(J.net.networks["red/main"].wtaActive, "WTA active on a NATO network")
  F.killGroup(F.groups["SAM SA-10 Hama"])
  F.run(80)
  check(F.logContains("handed from SAM SA-10 Hama to SAM SA-6 Near"), "shooter destroyed -> target handed on")
  check(F.emitting("SAM SA-6 Near"), "the new shooter comes up")

  -- no WTA (GENERIC_THIRD_WORLD): every battery in reach is cued as before
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  F.addGroup{ name = "SAM SA-10 Hama [emcon:cued]", units = { { type = "S-300PS 40B6M tr", x = 50000, z = 0 }, { type = "S-300PS 5P85C ln", x = 50300, z = 0 } } }
  F.addGroup{ name = "SAM SA-6 Near [emcon:cued]", units = { { type = "Kub 1S91 str", x = 70000, z = 0 }, { type = "Kub 2P25 ln", x = 70300, z = 0 } } }
  local b2 = bandit("Viper 2", 80000, 0, 6000)
  local J2 = load{ RED_DOCTRINE = "GENERIC_THIRD_WORLD" }
  F.sees["EW North"] = { b2 }
  F.run(60)
  check(not J2.net.networks["red/main"].wtaActive, "WTA off for GENERIC_THIRD_WORLD")
  check(F.emitting("SAM SA-10 Hama [emcon:cued]") and F.emitting("SAM SA-6 Near [emcon:cued]"), "without WTA both batteries are cued")
  check(not F.logContains("ERROR JANUS"), "block 8: no Janus errors")
end

-- ---------------------------------------------------------------- 9. network details: command post kinds, alternate stands down, radio power, backup ends
do
  F.reset()
  F.addGroup{ name = "CMD Gen", units = { { type = "MLRS FDDM", x = 0, z = 0 } } }
  F.addGroup{ name = "CMD Radar", units = { { type = "1L13 EWR", x = 0, z = 300000 } } }
  F.addGroup{ name = "CMD Main [alt:Reserve]", units = { { type = "S-300PS 54K6 cp", x = 0, z = 600000 } } }
  F.addGroup{ name = "CMD Reserve", units = { { type = "SKP-11", x = 0, z = 650000 } } }
  sa6("SAM SA-6 A", 50000, 600000)
  F.addStatic{ name = "CMD Bunker R", x = 300000, z = 0 }
  F.addStatic{ name = "COMMS Radio R [ag]", x = 309000, z = 0 }
  local gen = F.addStatic{ name = "POWER Radio Gen", type = "GeneratorF", x = 316000, z = 0, life = 10 }
  local J = load()
  F.run(3)
  check(node("CMD Gen").working and node("CMD Radar").working, "C2_GENERIC and EWR units can be command posts")
  check(not F.logContains("back in command") and not F.logContains("air-ground radio:"), "no state-change messages at start")
  check(node("COMMS Radio R [ag]").powerSources[1] == node("POWER Radio Gen") and node("CMD Bunker R").powerSources == nil,
    "the radio has its own generator; the post (16 km away) does not")
  F.killStatic(gen)
  F.run(200)
  check(node("CMD Bunker R").agState == "ok", "radio on reserve power: still ok")
  F.run(320)
  check(node("CMD Bunker R").agState == "backup", "radio out of power -> backup")
  -- the main post comes back after the alternate took over: the alternate stands by again
  local main, alt, s = node("CMD Main [alt:Reserve]"), node("CMD Reserve"), node("SAM SA-6 A")
  F.killGroup(F.groups["CMD Main [alt:Reserve]"])
  F.run(520)
  check(alt.active and s.parent == alt, "alternate in command")
  F.revive(F.groups["CMD Main [alt:Reserve]"])
  J.net.dirty = true
  F.run(530)
  check(main.alive and not alt.active and s.parent == main, "main post back: alternate stands by, SAM back under main")
  check(F.logContains("CMD Main [alt:Reserve] back in command, CMD Reserve stands by"), "stand-down logged")
  check(not F.logContains("ERROR JANUS"), "block 9: no Janus errors")

  -- backup link ends when the relay is repaired
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "COMMS Relay North", units = { { type = "ZIL-131 KUNG", x = 70000, z = 0 } } }
  sa6("SAM SA-6 Far", 140000, 0)
  local J2 = load{ RED_DOCTRINE = { base = "SOVIET_PVO_1985", linkBackup = { range = 150000 } } }
  F.run(3)
  F.killGroup(F.groups["COMMS Relay North"])
  F.run(12)
  check(node("SAM SA-6 Far").linkVia == "backup", "on backup")
  F.revive(F.groups["COMMS Relay North"])
  J2.net.dirty = true
  F.run(22)
  check(node("SAM SA-6 Far").linkVia == nil and node("SAM SA-6 Far").linkDelay == 0, "relay repaired: normal link, no delay")
  check(F.logContains("SAM SA-6 Far back on the network link"), "return to the network link logged")
end

-- ---------------------------------------------------------------- 10. tracks: numbering, helicopters, fixes, same-second plots, tier
do
  F.reset()
  F.addGroup{ name = "CMD Hama", units = { { type = "S-300PS 54K6 cp", x = 0, z = 0 } } }
  F.addGroup{ name = "EW One [skill:VET]", units = { { type = "55G6 EWR", x = 20000, z = 0 } } }
  F.addGroup{ name = "EW Two", units = { { type = "55G6 EWR", x = 25000, z = 0 } } }
  F.addGroup{ name = "EW Blind", units = { { type = "55G6 EWR", x = 30000, z = 0 } } }
  local b = bandit("Viper 1", 200000, 0, 7000)
  local h = F.addGroup{ name = "Huey", coalition = BLUE, category = Group.Category.HELICOPTER,
    units = { { type = "UH-1H", x = 150000, z = 0, alt = 300 } } }.units[1]
  local ghost = bandit("Ghost", 180000, 50000, 7000)
  local J = load()
  F.noType["EW One [skill:VET]"] = true
  F.noType["EW Two"] = true
  F.sees["EW One [skill:VET]"] = { b }
  F.sees["EW Two"] = { b, h }
  F.sees["EW Blind"] = { ghost }
  F.detFlags["EW Blind"] = { visible = false, distance = false }
  F.run(8)
  local net = J.net.networks["red/main"]
  local tb, th = net.tracks[b.id], net.tracks[h.id]
  check(tb and tb.num == 1 and th and th.num == 2, "tracks numbered 1, 2 in order of first detection")
  check(th and th.class == "helicopter", "helicopter class")
  check(net.tracks[ghost.id] == nil, "a detection with no visual and no range fix makes no track")
  F.detFlags["EW Blind"] = { visible = false, distance = true }
  F.run(16)
  check(net.tracks[ghost.id] ~= nil, "a range-only detection does make a track")
  F.move(b, 199000, 0)
  F.run(30)
  local v = tb.vel
  check(v and v.x == v.x and math.abs(v.x) < 1000, "velocity stays finite when two radars plot in the same second")
  F.run(65)
  check(not tb.typeKnown or tb.idBy:find("^held") ~= nil, "no type flag: only dwell can identify")
  check(tb.typeKnown and tb.idAt <= 70, "held by a VET radar: identified after 60 s, not 90")
  check(not F.logContains("ERROR JANUS"), "block 10: no Janus errors")
end

-- ---------------------------------------------------------------- 11. WTA details: envelopes, Pk factors, threat, ammo, ordering, logging
do
  F.reset()
  F.addGroup{ name = "CMD Test", units = { { type = "S-300PS 54K6 cp", x = 0, z = -5000 } } }
  sa10("SAM A", 0, 0)
  sa6("SAM B", 110000, 0)
  F.addGroup{ name = "PD Tor", units = { { type = "Tor 9A331", x = 100000, z = 3000 } } }
  F.addGroup{ name = "EW Seven", units = { { type = "1L13 EWR", x = 0, z = 50000 } } }
  F.addGroup{ name = "SAM C", units = { { type = "SA-11 Buk SR 9S18M1", x = 0, z = -200000 },
    { type = "SA-11 Buk LN 9A310M1", x = 200, z = -200000 } } }
  sa6("SAM D2", -100000, -10000)
  sa6("SAM D1", -100000, 10000)
  F.addGroup{ name = "AAA ZU", units = { { type = "HL_ZU-23", x = 0, z = 400000 } } }
  F.addGroup{ name = "SAM R", units = { { type = "Kub 1S91 str", x = 0, z = 20000 } } }
  F.addGroup{ name = "SAM Hawk X", units = { { type = "Hawk tr", x = 0, z = 700000 }, { type = "Hawk ln", x = 200, z = 700000 } } }
  F.addGroup{ name = "SAM Patriot X", units = { { type = "Patriot str", x = 0, z = 800000 }, { type = "Patriot ln", x = 200, z = 800000 } } }
  local bu = bandit("Target", 300000, 300000, 3000)
  local J = load{ RED_DOCTRINE = { base = "NATO_COLDWAR", wta = { lead = 0 } } }
  F.run(3)
  local W = J.wta
  local net = J.net.networks["red/main"]
  check(net.wtaActive and net.tracks == nil, "WTA active on its network even before the first track")
  local A, B, T, C = node("SAM A"), node("SAM B"), node("PD Tor"), node("SAM C")
  local function track(id, x, z, alt, vel, class)
    net.tracks = net.tracks or {}
    local tr = net.tracks[id]
    if not tr then
      tr = { id = id, num = id, obj = bu, first = 0, sensors = {}, typeKnown = false }
      net.tracks[id] = tr
    end
    tr.pos, tr.t, tr.vel, tr.class = { x = x, y = alt or 3000, z = z }, 1e9, vel, class or "fixed-wing"
    return tr
  end
  local function drop(...) for _, id in ipairs({ ... }) do net.tracks[id] = nil end end
  local function shooters(id)
    local out = {}
    for _, c in ipairs((net.assign or {})[id] or {}) do out[#out + 1] = c.node.name end
    table.sort(out)
    return table.concat(out, ",")
  end
  -- envelopes
  local eH, eP = W.envelope(node("SAM Hawk X")), W.envelope(node("SAM Patriot X"))
  check(eH.R == 25000 and eP.channels == 2, "DCS reality: Hawk reach 25 km (launches at 13-15 nm), Patriot 2 channels")
  local eC, eT = W.envelope(C), W.envelope(T)
  check(eC.R == 50000 and eC.rMin == 3000 and eC.aMin == 20 and eC.aMax == 22000 and eC.channels == 2,
    "SA-11 (TELAR) envelope from DCS data")
  check(eT.R == 12000 and eT.rMin == 600 and eT.aMin == 30 and eT.aMax == 20000 and eT.channels == 1 and eT.base == 0.6,
    "Tor without DB envelope: defaults (5 % minimum range, 30-20000 m, 1 channel, SR base 0.6)")
  -- Pk factors (SA-10 at the origin, R 120 km, target at 60 km)
  check(near(W.pk(T, track(20, 105000, 3000, 1000), 0), 0.6), "Tor mid-envelope 0.6")
  local t21 = track(21, 60000, 0, 3000)
  A.tier = "VET"; check(near(W.pk(A, t21, 0), 0.825), "VET x1.1")
  A.tier = "ACE"; check(near(W.pk(A, t21, 0), 0.9), "ACE x1.2")
  A.tier = "GRN"; check(near(W.pk(A, t21, 0), 0.6), "GRN x0.8")
  A.tier = "REG"
  check(W.pk(A, track(22, 60000, 0, 10), 0) == 0 and W.pk(A, track(22, 60000, 0, 20), 0) > 0, "below half the minimum altitude: 0")
  check(near(W.pk(A, track(23, 60000, 0, 3000, { x = 0, y = 0, z = 250 }), 0), 0.525), "crossing target x0.7")
  check(near(W.pk(A, track(23, 60000, 0, 3000, { x = 250, y = 0, z = 0 }), 0), 0.45), "receding beyond half range x0.6")
  check(near(W.pk(A, track(23, 50000, 0, 3000, { x = 250, y = 0, z = 0 }), 0), 0.75), "receding inside half range: no penalty")
  check(near(W.pk(A, track(23, 60000, 0, 3000, { x = 125, y = 0, z = 216.506 }), 0), 0.3825), "half-receding (radial 0.5): x0.85 x0.6")
  check(near(W.pk(A, track(23, 60000, 0, 3000, { x = -700, y = 0, z = 0 }), 0), 0.525), "faster than 600 m/s x0.7")
  check(near(W.pk(A, track(23, 60000, 0, 3000, { x = -500, y = 0, z = 0 }), 0), 0.75), "500 m/s head-on: no penalty")
  check(W.pk(node("EW Seven"), t21, 0) == 0, "a radar with no launchers never bids")
  check(W.pk(A, { pos = nil }, 0) == 0, "a track without a position: 0")
  local inb = track(24, 0, 130000, 3000, { x = 0, y = 0, z = -250 })
  check(W.pk(A, inb, 0) == 0 and near(W.pk(A, inb, 60), 0.362, 0.002), "lead: judged 60 s ahead the target is in range")
  drop(20, 21, 22, 23)
  net.doctrine.wta.lead = 60
  W.assign(net)
  check(shooters(24) == "SAM A", "with lead an inbound target is assigned before it enters the envelope")
  net.doctrine.wta.lead = 0
  drop(24); net.assign = {}
  -- threat
  local st = track(30, 0, -20000, 3000)
  check(near(W.threat(st, net), 1000 / 330, 0.0005), "threat of a stationary track 15 km from the CMD: 1000 / (300 + 30)")
  check(W.threat({}, net) == 0, "a track without a position is no threat")
  check(near(W.threat(track(31, 0, -20000, 3000, { x = 0, y = 0, z = -30 }), net), 1000 / 330, 0.0005), "opening track: floor of 50 m/s")
  local low, hi = W.threat(track(32, 0, -20000, 1400), net), W.threat(track(33, 0, -20000, 1600), net)
  check(near(low, hi * 1.2, 0.0005), "below 1500 m: x1.2")
  check(near(W.threat(track(34, 0, -20000, 3000, nil, "helicopter"), net), 1000 / 330 * 0.7, 0.0005), "helicopter x0.7")
  drop(30, 31, 32, 33, 34)
  local saved = {}
  for _, n in ipairs(net.nodes) do saved[n] = n.alive end
  local far = { pos = { x = 500000, y = 3000, z = 500000 } }
  for _, kind in ipairs({ "C2", "BATTERY", "PD", "EW", "AAA" }) do
    for _, n in ipairs(net.nodes) do n.alive = (n.kind == kind) end
    local th = W.threat(far, net)
    if kind == "AAA" then check(th == 0, "guns are not a defended asset") else check(th > 0, kind .. " is a defended asset") end
  end
  for n, a in pairs(saved) do n.alive = a end
  -- ordering: one channel, two targets: the bigger threat gets it; equal threats: the lower number
  A.alive, B.alive = false, false
  track(40, 96000, 3000, 2000); track(41, 104000, 3000, 1000)
  W.assign(net)
  check(shooters(41) == "PD Tor" and shooters(40) == "", "the only shooter (1 channel) takes the bigger threat (lower)")
  drop(40, 41); net.assign = {}
  track(43, 100000, 8000, 2000); track(42, 100000, 8000, 2000)
  W.assign(net)
  check(shooters(42) == "PD Tor" and shooters(43) == "", "equal threats: the lower track number first")
  drop(42, 43); net.assign = {}
  A.alive, B.alive = true, true
  -- a shooter keeps the target it is guiding when another target becomes the bigger threat (bench 04 ping-pong)
  A.alive, B.alive = false, false
  track(70, 96000, 3000, 1000); track(71, 104000, 3000, 2000)
  W.assign(net)
  check(shooters(70) == "PD Tor" and shooters(71) == "", "Tor (1 channel) on the lower, bigger threat")
  track(70, 96000, 3000, 2000); track(71, 104000, 3000, 1000)   -- now the other one is lower
  W.assign(net)
  check(shooters(70) == "PD Tor" and shooters(71) == "", "Tor keeps the target it is guiding; the new threat waits")
  drop(70)
  W.assign(net)
  check(shooters(71) == "PD Tor", "its target gone, the Tor takes the other one")
  drop(71); net.assign = {}
  A.alive, B.alive = true, true
  -- equal bids: alphabetical
  track(50, -100000, 0, 3000)
  W.assign(net)
  check(shooters(50) == "SAM D1", "equal Pk: the first battery by name (" .. shooters(50) .. " " .. W.pk(node("SAM D1"), net.tracks[50], 0) .. " " .. W.pk(node("SAM D2"), net.tracks[50], 0) .. ")")
  drop(50); net.assign = {}
  -- salvo on top of an existing assignment never doubles a shooter; logs say "assigned", not "handed"
  track(51, 95000, 0, 3000)
  W.assign(net)
  check(shooters(51) == "SAM B", "one shooter")
  W.assign(net); W.assign(net)
  check(count("T51 fixed-wing assigned to SAM B") == 1, "an unchanged assignment is logged once")
  net.doctrine.wta.maxShooters, net.doctrine.wta.pkGoal = 2, 0.99
  W.assign(net)
  check(shooters(51) == "SAM A,SAM B", "salvo adds SAM A beside the kept SAM B (no duplicate)")
  check(count("T51 fixed-wing assigned to SAM A") == 1 and count("handed from SAM B to SAM A") == 0, "added shooter logged as assigned")
  net.doctrine.wta.maxShooters, net.doctrine.wta.pkGoal = 1, 0.7
  track(51, 400000, 0, 3000)
  W.assign(net); W.assign(net)
  check(shooters(51) == "" and count("T51 fixed-wing: no shooter can engage") == 1, "lost target logged once")
  track(52, 95000, 0, 3000)
  W.assign(net)
  track(52, 400000, 0, 3000)
  W.assign(net)
  check(count("T52 fixed-wing: no shooter can engage") == 1, "lost target after a single shooter logged")
  drop(51); net.assign = {}
  -- targetFor: the nearest of several assigned targets
  local n1, n2 = track(60, 30000, 0, 3000), track(61, 80000, 0, 3000)
  A.assigned = { n2, n1 }
  local tgt, d = W.targetFor(A)
  check(tgt == n1 and near(d, 30000, 1), "cue on the nearest assigned target")
  A.assigned = nil
  drop(60, 61)
  -- ammunition by launcher role, missiles only, logged once
  for _, u in ipairs(F.groups["SAM C"].units) do u.ammo = 0 end
  for _, u in ipairs(F.groups["PD Tor"].units) do u.ammo, u.ammoCat = 5, 0 end   -- 5 gun rounds, no missiles
  W.ammoAt = -1e9; W.tick()
  check(C.ammo == 0 and T.ammo == 0 and A.ammo == 4, "TELAR and SHORAD launchers counted; shells are not missiles")
  W.ammoAt = -1e9; W.tick()
  W.ammoAt = -1e9; W.tick()
  check(count("SAM C out of missiles") == 1, "out of missiles logged once")
  check(count("SAM R out of missiles") == 0, "a battery with no launchers is not 'out of missiles'")
  check(count("SAM A out of missiles") == 0, "a battery that still has missiles is never reported")
  check(not F.logContains("ERROR JANUS"), "block 11: no Janus errors")
end

print(string.format("test_phase2: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
