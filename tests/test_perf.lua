-- Phase 4 load test: both coalitions at GCIMAX load (about 300 nodes and 300 aircraft in one mission), every module
-- running (network, tracks, WTA, EMCON, ARM, AAA, GCI), aircraft moving, ARMs in the air.
-- Budget: 10 ms of Janus per simulated second on the harness (DCS runs Lua at a similar speed; the server frame is 16 ms
-- and Janus's work is spread over its ticks).
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"
local RED, BLUE = coalition.side.RED, coalition.side.BLUE
local AIR = Group.Category.AIRPLANE

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. msg) end
end

F.reset()
-- one side: 4 posts, 12 EW, 80 SAM batteries (2 units), 30 PD, 24 AAA = 150 nodes, spread over a 400 x 160 km box
local function side(coa, z0, sign, kinds)
  local pre = coa == RED and "R" or "B"
  for i = 1, 4 do F.addGroup{ name = "CMD " .. pre .. "C" .. i, coalition = coa, units = { { type = kinds.cmd, x = i * 90000, z = z0 } } } end
  for i = 1, 12 do F.addGroup{ name = "EW " .. pre .. "E" .. i, coalition = coa, units = { { type = kinds.ew, x = i * 33000, z = z0 + sign * 20000 } } } end
  for i = 1, 80 do
    local x, z = (i % 20) * 20000, z0 + sign * (40000 + math.floor(i / 20) * 25000)
    F.addGroup{ name = "SAM " .. pre .. "S" .. i, coalition = coa, units = { { type = kinds.str, x = x, z = z },
      { type = kinds.ln, x = x + 200, z = z } } }
  end
  for i = 1, 30 do
    F.addGroup{ name = "PD " .. pre .. "P" .. i, coalition = coa, units = { { type = kinds.pd, x = (i % 20) * 20000 + 1000, z = z0 + sign * (41000 + (i % 4) * 25000) } } }
  end
  for i = 1, 24 do
    F.addGroup{ name = "AAA " .. pre .. "A" .. i, coalition = coa, units = { { type = kinds.aaa, x = (i % 20) * 20000 - 1000, z = z0 + sign * (39000 + (i % 4) * 25000) } } }
  end
end
side(RED, -10000, -1, { cmd = "SKP-11", ew = "1L13 EWR", str = "Kub 1S91 str", ln = "Kub 2P25 ln", pd = "Tor 9A331", aaa = "ZSU-23-4 Shilka" })
side(BLUE, 10000, 1, { cmd = "MLRS FDDM", ew = "FPS-117", str = "Hawk tr", ln = "Hawk ln", pd = "M1097 Avenger", aaa = "Vulcan" })

-- 150 aircraft a side, flying across the line at 250 m/s, in pairs
local planes = { [RED] = {}, [BLUE] = {} }
for coa, list in pairs(planes) do
  local pre, sign = coa == RED and "Red" or "Blue", coa == RED and -1 or 1
  for i = 1, 75 do
    local g = F.addGroup{ name = pre .. " Flight " .. i, coalition = coa, category = AIR,
      units = { { type = coa == RED and "Su-24M" or "F-16C_50", x = (i % 25) * 16000, z = sign * (60000 + math.floor(i / 25) * 20000), alt = 3000 + (i % 7) * 1000 },
                { type = coa == RED and "Su-24M" or "F-16C_50", x = (i % 25) * 16000 + 500, z = sign * (60000 + math.floor(i / 25) * 20000), alt = 3000 + (i % 7) * 1000 } } }
    for _, u in ipairs(g.units) do list[#list + 1] = u end
  end
end
-- each side's EW sees every enemy aircraft (the harness has no radar horizon: the worst case)
for i = 1, 12 do F.sees["EW RE" .. i] = planes[BLUE]; F.sees["EW BE" .. i] = planes[RED] end

assert(loadfile(JANUS_FILE))()
local J = JANUS
-- aircraft move every second: each side flies toward the other's batteries, then turns back at the far edge
local dir = { [RED] = 250, [BLUE] = -250 }
timer.scheduleFunction(function(_, t)
  for coa, list in pairs(planes) do
    for _, u in ipairs(list) do
      local z = u.z + dir[coa]
      if z > 160000 or z < -160000 then z = u.z end
      F.move(u, u.x, z)
    end
  end
  return t + 1
end, nil, 1)
-- a steady trickle of ARMs: every 20 s a blue HARM and a red Kh-58 at batteries in the front line
local armSeq = 0
timer.scheduleFunction(function(_, t)
  armSeq = armSeq + 1
  local b = planes[BLUE][armSeq % #planes[BLUE] + 1]
  local tgt = J.net.nodes["SAM RS" .. (armSeq % 20 + 1)]
  if b and tgt and tgt.pos then
    local dz = tgt.pos.z - b.z
    F.launch{ shooter = b, type = "AGM_88", x = b.x, y = b.alt or 5000, z = b.z, vx = 0, vz = dz > 0 and 600 or -600,
      guidance = Weapon.GuidanceType.RADAR_PASSIVE, dieAt = t + 60 }
  end
  local r = planes[RED][armSeq % #planes[RED] + 1]
  local tgtB = J.net.nodes["SAM BS" .. (armSeq % 20 + 1)]
  if r and tgtB and tgtB.pos then
    local dz = tgtB.pos.z - r.z
    F.launch{ shooter = r, type = "X_58", x = r.x, y = r.alt or 5000, z = r.z, vx = 0, vz = dz > 0 and 300 or -300,
      guidance = Weapon.GuidanceType.RADAR_PASSIVE, dieAt = t + 90 }
  end
  return t + 20
end, nil, 15)

F.run(15)
check(#J.net.list == 300, "300 nodes picked up (" .. #J.net.list .. ")")
-- machine speed: a fixed Lua workload (tables, sqrt, string keys - what Janus does), so the budget holds on any CPU
local function reference()
  local c0 = os.clock()
  local t, acc = {}, 0
  for i = 1, 1000000 do
    local k = i % 997
    t[k] = (t[k] or 0) + math.sqrt(i)
    acc = acc + t[k] * 0.5
  end
  return (os.clock() - c0) * 1000, acc
end
local refMs = reference()
for _ = 1, 4 do refMs = math.min(refMs, (reference())) end   -- the quickest of five: shared machines are noisy
local t0 = os.clock()
F.run(615)
local cpu = os.clock() - t0
local perSec = cpu / 600 * 1000
print(string.format("  perf: 300 nodes, 300 aircraft, both coalitions, 600 s simulated: %.3f s CPU, %.2f ms per simulated second",
  cpu, perSec))
-- budget, relative to machine speed: the Phase 4 build ran this at 8 ms on the machine the 10 ms budget was set on
-- (25 % headroom); on a second machine the same build took 15.5 ms with the reference at ~100 ms. Budget = the same
-- 25 % over the Phase 4 cost: 0.19 x the reference time (2026-10-01).
local budget = 0.19 * refMs
print(string.format("  perf: reference workload %.0f ms -> budget %.1f ms per simulated second", refMs, budget))
check(perSec < budget, string.format("under the budget (%.2f ms, budget %.1f)", perSec, budget))
local function tracks(key)
  local n = 0
  for _ in pairs(J.net.networks[key].tracks or {}) do n = n + 1 end
  return n
end
check(tracks("red/main") > 100 and tracks("blue/main") > 100, "both pictures full (" .. tracks("red/main") .. " / " .. tracks("blue/main") .. ")")
local reqR, reqB = J.gci.commitRequests(RED), J.gci.commitRequests(BLUE)
check(type(reqR) == "table" and type(reqB) == "table", "commit requests both sides (" .. #reqR .. " / " .. #reqB .. ")")
check(not F.logContains("ERROR JANUS"), "no Janus errors under load")

-- the GCI API under load: one full read of every call per side costs well under a frame
t0 = os.clock()
for _ = 1, 10 do
  for _, coa in ipairs({ RED, BLUE }) do
    J.gci.tracks(coa); J.gci.commitRequests(coa); J.gci.weapons(coa); J.gci.commandNodes(coa); J.gci.radarHeads(coa)
    J.gci.samZones(coa)
  end
end
local api = (os.clock() - t0) / 10 * 1000
print(string.format("  perf: GCI API read (tracks, commitRequests, weapons, command nodes, radar heads, SAM zones; both sides): %.2f ms", api))
check(api < 0.3 * refMs, string.format("a full GCI read of both sides well under a 16 ms frame, scaled to this machine (%.2f ms)", api))

print(string.format("test_perf: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
