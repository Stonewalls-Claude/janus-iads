-- Janus IADS - ground-control interface JANUS.gci (DESIGN 4.10, Phase 2.5 core). Read-only, optional.
-- Janus never calls or names a consumer: a GCI script looks this table up itself, checks `version`, calls through
-- pcall and falls back to its own mode if Janus is missing, the wrong version, or errors (DESIGN 4.10, decision 10).
--
--   JANUS.gci.version                 interface version (integer); bumped on any breaking change
--   JANUS.gci.instance                a number that changes every time Janus starts (re-subscribe when it changes)
--   JANUS.gci.on(event, fn, key)      subscribe; same event + key replaces; returns a handle.  JANUS.gci.off(handle)
--        events: "nodeLost", "nodeRestored", "nodeDegraded", "authorityChanged"
--        fn(ev), ev = { event, name, kind, coalition, state, reason, net, t }
--   JANUS.gci.tracks(coal [, nodeName])   the coalition's fused air picture, or the picture one command node sees
--   JANUS.gci.commandNodes(coal)      command posts (ground / airborne) with state, authority, radio and radio reach
--   JANUS.gci.radarHeads(coal)        working, powered, emitting, linked radars feeding the picture
--   JANUS.gci.controlState(coal, point [, postName])   can a ground controller reach this point, through which post
--                                     (postName: only through that post)
--   JANUS.gci.samZones(coal)          every working battery's engagement zone, with an `emitting` flag
-- Every function returns plain tables built from Janus's own state (copies, never Janus's internals) and never
-- errors for a coalition with no network. Coalitions: 1 red, 2 blue.

JANUS = JANUS or {}
local M = JANUS

local G = {}
M.gci = G

local pairs, ipairs = pairs, ipairs
local math_sqrt = math.sqrt

G.version = 1
G.instance = math.floor((timer and timer.getAbsTime and timer.getAbsTime() or 0) * 1000) + math.random(1, 999999)  -- mutate: ok any new number will do

-- ------------------------------------------------------------------ events
local EVENTS = { nodeLost = true, nodeRestored = true, nodeDegraded = true, authorityChanged = true }
local subs = { nodeLost = {}, nodeRestored = {}, nodeDegraded = {}, authorityChanged = {} }
local nextHandle = 0   -- mutate: ok handles are opaque

function G.on(event, fn, key)
  if not EVENTS[event] or type(fn) ~= "function" then return nil end
  local list = subs[event]
  if key ~= nil then
    for _, s in ipairs(list) do
      if s.key == key then s.fn = fn; return s.handle end    -- same key: replace, never pile up
    end
  end
  nextHandle = nextHandle + 1   -- mutate: ok handles are opaque
  list[#list + 1] = { fn = fn, key = key, handle = nextHandle }
  return nextHandle
end

function G.off(handle)
  for _, list in pairs(subs) do
    for i = #list, 1, -1 do
      if list[i].handle == handle then table.remove(list, i); return true end
    end
  end
  return false
end

local function emit(event, node, state, reason)
  local list = subs[event]
  if #list == 0 then return end
  local ev = { event = event, name = node.name, kind = node.kind, coalition = node.net.coalition, state = state,
               reason = reason, net = node.net.key, t = M.now() }
  for i = 1, #list do M.safe("gci.subscriber", list[i].fn, ev) end
end
G._emit = emit

-- ------------------------------------------------------------------ helpers
local function up(n) return n.alive and n.working and n.powered end

local function netsOf(coal)
  local out = {}
  if not (M.net and M.net.networks) then return out end   -- mutate: ok both exist once the network module loads
  for _, net in pairs(M.net.networks) do
    if net.coalition == coal then out[#out + 1] = net end
  end
  table.sort(out, function(a, b) return a.key < b.key end)   -- mutate: ok stable order only
  return out
end

local function copyTrack(tr)
  local p, v = tr.pos, tr.vel
  local holders = {}
  for name in pairs(tr.sensors or {}) do holders[#holders + 1] = name end
  table.sort(holders)
  return { id = tr.id, num = tr.num, x = p.x, y = p.y, z = p.z,
           vx = v and v.x or 0, vy = v and v.y or 0, vz = v and v.z or 0,
           class = tr.class, typeKnown = tr.typeKnown == true, typeName = tr.typeKnown and tr.typeName or nil,
           lastSeen = tr.t, holders = holders }
end

local function addPicture(out, seen, picture)
  for _, tr in pairs(picture or {}) do
    if tr.pos and not seen[tr.id] then
      seen[tr.id] = true
      out[#out + 1] = copyTrack(tr)
    end
  end
end

-- ------------------------------------------------------------------ tracks
-- nodeName given: what that command node sees - its network's picture while it is up and linked, else nothing
-- (a dead or unpowered post sees nothing; an unlinked airborne node keeps its own radar picture).
function G.tracks(coal, nodeName)
  local out, seen = {}, {}
  if nodeName then
    local n = M.net and M.net.nodes[nodeName]
    if not (n and n.net.coalition == coal and up(n)) then return out end
    if n.linked then addPicture(out, seen, n.net.tracks) end
    addPicture(out, seen, n.localTracks)
  else
    for _, net in ipairs(netsOf(coal)) do addPicture(out, seen, net.tracks) end
  end
  table.sort(out, function(a, b) return a.num < b.num end)
  return out
end

-- ------------------------------------------------------------------ command nodes
-- how far a command node's air-ground radio reaches now (m): agReach with its radio up (or none modelled), the backup
-- set's range on backup, 0 with none; an airborne node always has its own radios
local function radioReach(n, d)
  if n.airborne then return d.agReach or 300000 end   -- mutate: ok every profile sets agReach
  local state = n.agState or "own"
  if state == "ok" or state == "own" then return d.agReach or 300000 end   -- mutate: ok every profile sets agReach
  if state == "backup" then return d.agBackup and d.agBackup.range or 0 end   -- mutate: ok every profile sets agBackup.range
  return 0
end
G._radioReach = radioReach

local function commandKind(n)
  if n.kind == "C2" then return "ground" end
  if n.kind == "EW" and n.airborne then return "airborne" end
  return nil
end

function G.commandNodes(coal)
  local out = {}
  for _, net in ipairs(netsOf(coal)) do
    local d = net.doctrine
    for _, n in ipairs(net.nodes) do
      local ck = commandKind(n)
      if ck then
        local seats = tonumber(n.site.tags.seats or "")
        out[#out + 1] = {
          name = n.name, kind = ck, net = net.key, tier = n.tier,
          x = n.pos and n.pos.x, y = n.pos and n.pos.y, z = n.pos and n.pos.z,   -- mutate: ok nodes always have a position
          alive = n.alive == true, powered = n.powered == true, working = n.working == true,
          linked = n.linked == true, active = n.active ~= false,
          inCommand = up(n) and n.active ~= false,
          parent = n.parent and n.parent.name or nil,
          alternate = n.altNode and n.altNode.name or nil, alternateFor = n.altFor and n.altFor.name or nil,
          radio = ck == "ground" and (n.agState or "own") or "own",
          reach = radioReach(n, d),
          seats = seats,
          fighterControl = d.fighterControl or "ground",
          awacsTakeover = d.awacsTakeover == true,
        }
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ radar heads
function G.radarHeads(coal)
  local out = {}
  for _, net in ipairs(netsOf(coal)) do
    for _, n in ipairs(net.nodes) do
      if n.kind == "EW" and up(n) and n.pos and n.emcon.on ~= false and n.linked then
        local r = n.detectionRange > 0 and n.detectionRange or 100000   -- mutate: ok every EW type in the DB has a range
        out[#out + 1] = { name = n.name, x = n.pos.x, y = n.pos.y, z = n.pos.z, r2 = r * r,
                          airborne = n.airborne == true, net = net.key }
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ control state
-- A ground controller reaches `point` ({x, z}) when a command post in command has a working radar picture there
-- (a linked radar head covers it) and its air-ground radio reaches it: agReach with the radio up (or none modelled),
-- agBackup.range on the backup set, nothing with none. Returns { ground, via, radio, reach }.
function G.controlState(coal, point, postName)
  local res = { ground = false }
  if not (point and point.x and point.z) then return res end
  local heads = G.radarHeads(coal)
  local covered = false
  for _, h in ipairs(heads) do
    local dx, dz = h.x - point.x, h.z - point.z
    if dx * dx + dz * dz <= h.r2 then covered = true; break end
  end
  if not covered then return res end
  local bestD
  for _, net in ipairs(netsOf(coal)) do
    local d = net.doctrine
    for _, n in ipairs(net.nodes) do
      if n.kind == "C2" and up(n) and n.active ~= false and n.pos and (postName == nil or n.name == postName) then
        local state = n.agState or "own"
        local reach = radioReach(n, d)
        local dx, dz = n.pos.x - point.x, n.pos.z - point.z
        local dd = dx * dx + dz * dz
        if reach > 0 and dd <= reach * reach and (not bestD or dd < bestD) then   -- mutate: ok reach is whole metres
          bestD = dd
          res = { ground = true, via = n.name, radio = state, reach = reach, dist = math_sqrt(dd) }
        end
      end
    end
  end
  return res
end

-- ------------------------------------------------------------------ SAM zones
function G.samZones(coal)
  local out = {}
  for _, net in ipairs(netsOf(coal)) do
    for _, n in ipairs(net.nodes) do
      if (n.kind == "BATTERY" or n.kind == "PD") and up(n) and n.pos and (n.engageRange or 0) > 0 then  -- mutate: ok ranges are whole metres
        local env = M.wta and M.wta.envelope(n) or { R = n.engageRange, rMin = 0, aMin = 0, aMax = 20000 }  -- mutate: ok WTA is always built in
        out[#out + 1] = { name = n.name, kind = n.kind, net = net.key, x = n.pos.x, z = n.pos.z,
                          r = env.R, rMin = env.rMin, altMin = env.aMin, altMax = env.aMax,
                          emitting = n.emcon.on == true, linked = n.linked == true, tier = n.tier }
      end
    end
  end
  return out
end

-- ------------------------------------------------------------------ wiring (network callbacks -> events)
function G.start()
  local on = M.net.on
  on("nodeLost", function(n) emit("nodeLost", n, "lost", "destroyed") end)
  on("restored", function(n, why) emit("nodeRestored", n, "up", why) end)
  on("degraded", function(n, why) emit("nodeDegraded", n, "degraded", why) end)
  on("radio", function(n, state)
    if state == "ok" then emit("nodeRestored", n, "up", "radio ok")
    else emit("nodeDegraded", n, "degraded", "radio " .. state) end
  end)
  on("takeover", function(alt, main) emit("authorityChanged", alt, "in command", "took over from " .. main.name) end)
  on("standdown", function(alt, main) emit("authorityChanged", alt, "standby", main.name .. " back in command") end)
  M.info("gci", string.format("ground-control interface v%d ready (instance %d)", G.version, G.instance))
end
