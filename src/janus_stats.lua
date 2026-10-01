-- Janus IADS - stats (DESIGN 4.8, Phase 5; off unless STATS = true). Per site: radar emitting time, shots fired,
-- kills (DCS S_EVENT_KILL credited to one of the site's units), units lost; written to dcs.log every STATS_EVERY
-- seconds and at mission end, the same figures the test benches use.
--   JANUS.stats() -> { [siteName] = { coalition, kind, emitMin, shots, kills, lost } }   (works with STATS off too)

JANUS = JANUS or {}
local M = JANUS
local S = M.settings

local ST = {}
M.statsMod = ST

local string_format = string.format
local ipairs, pairs = ipairs, pairs

ST.counts = {}   -- [siteName] = { shots, kills }

local function nodeOf(unit)
  if not (unit and unit.getGroup) then return nil end
  local ok, g = pcall(unit.getGroup, unit)
  if not (ok and g) then return nil end   -- mutate: ok defensive: a unit always has a group
  local okN, name = pcall(g.getName, g)
  return okN and M.net.nodes[name] or nil
end

local function counts(name)
  local c = ST.counts[name]
  if not c then c = { shots = 0, kills = 0 }; ST.counts[name] = c end
  return c
end

function ST.onShot(e)
  local n = nodeOf(e.initiator)
  if n then local c = counts(n.name); c.shots = c.shots + 1 end
end

function ST.onKill(e)
  local n = nodeOf(e.initiator)
  if n then local c = counts(n.name); c.kills = c.kills + 1 end
end

local function lostUnits(n)
  local lost = 0
  for _, u in ipairs(n.site.units or {}) do
    local ok, ex = pcall(u.unit.isExist, u.unit)
    if not (ok and ex) then lost = lost + 1 end
  end
  return lost
end

function M.stats()
  local out = {}
  for _, n in ipairs(M.net and M.net.list or {}) do
    local c = ST.counts[n.name] or { shots = 0, kills = 0 }
    out[n.name] = { coalition = n.net.coalition, kind = n.kind, emitMin = ((n.emcon and n.emcon.emitSec) or 0) / 60,   -- mutate: ok every node has emcon
                    shots = c.shots, kills = c.kills, lost = lostUnits(n) }
  end
  return out
end

function ST.report(why)
  local all = M.stats()
  local names = {}
  for name in pairs(all) do names[#names + 1] = name end
  table.sort(names)
  local function zero() return { emit = 0, shots = 0, kills = 0, lost = 0 } end
  local tot = { [1] = zero(), [2] = zero() }
  for _, name in ipairs(names) do
    local s = all[name]
    if s.emitMin + s.shots + s.kills + s.lost > 0 then
      M.info("stats", string_format("%s %s: emitting %.1f min, %d shots, %d kills, %d units lost", s.coalition == 1 and "red" or "blue",
        name, s.emitMin, s.shots, s.kills, s.lost))
    end
    local t = tot[s.coalition]
    if t then
      t.emit, t.shots, t.kills, t.lost = t.emit + s.emitMin, t.shots + s.shots, t.kills + s.kills, t.lost + s.lost
    end
  end
  for coa = 1, 2 do
    local t = tot[coa]
    M.info("stats", string_format("%s total (%s): emitting %.1f min, %d shots, %d kills, %d units lost", coa == 1 and "red" or "blue",
      why, t.emit, t.shots, t.kills, t.lost))
  end
end

function ST.start()
  M.on(world.event.S_EVENT_SHOT, "stats.shot", ST.onShot)
  if world.event.S_EVENT_KILL then M.on(world.event.S_EVENT_KILL, "stats.kill", ST.onKill) end
  if not S.STATS then return end
  if world.event.S_EVENT_MISSION_END then
    M.on(world.event.S_EVENT_MISSION_END, "stats.end", function() ST.report("mission end") end)
  end
  if (S.STATS_EVERY or 0) > 0 then   -- mutate: ok the default is always set
    M.every("stats.report", S.STATS_EVERY, function() ST.report(string_format("%.0f s", M.now())) end)
  end
end
