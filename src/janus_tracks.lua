-- Janus IADS - track picture, Phase 1 (DESIGN 4.2, first part): aircraft seen by the network's emitting radars.
-- Budgeted round-robin polling of Controller:getDetectedTargets(); weapons are ignored here (the ARM awareness
-- model of DESIGN 4.5A handles them in Phase 3, because DCS's own weapon detection is far too generous).

JANUS = JANUS or {}
local M = JANUS

local T = {}
M.tracks = T

local pairs, ipairs = pairs, ipairs

T.POLL_INTERVAL = 5     -- a sensor is polled at most this often
T.BUDGET = 6            -- sensors polled per 1-s tick (spread the cost)
T.TTL = 20              -- a track not refreshed for this long is dropped
T.cursor = 1
T.stats = { polls = 0 }

local AIR = { [0] = true, [1] = true }   -- Unit.Category AIRPLANE, HELICOPTER

local function isSensor(n)
  return n.alive and n.working and n.powered and n.hasRadar and n.emcon.on ~= false
end
T.isSensor = isSensor

local function store(picture, obj, pos, now, node)
  local id = obj.getID and obj:getID() or tostring(obj)
  local tr = picture[id]
  if not tr then
    tr = { id = id, obj = obj, first = now, sensors = {} }
    picture[id] = tr
  end
  tr.pos, tr.t = pos, now
  tr.sensors[node.name] = now
  return tr
end

function T.poll(node, now)
  node.lastPoll = now
  local g = node.site.group
  if not (g and g:isExist()) then return 0 end
  local c = g:getController()
  if not c then return 0 end
  local dets = c:getDetectedTargets() or {}
  local coa = node.net.coalition
  local n = 0
  node.localTracks = node.localTracks or {}
  for i = 1, #dets do
    local obj = dets[i].object
    if obj and obj.isExist and obj:isExist() and Object.getCategory(obj) == Object.Category.UNIT then
      local ocoa = obj:getCoalition()
      local desc = obj:getDesc()
      if ocoa ~= coa and ocoa ~= 0 and desc and AIR[desc.category] then
        local pos = obj:getPoint()
        store(node.localTracks, obj, pos, now, node)
        if node.linked then
          node.net.tracks = node.net.tracks or {}
          store(node.net.tracks, obj, pos, now, node)
        end
        n = n + 1
      end
    end
  end
  T.stats.polls = T.stats.polls + 1
  return n
end

local function expire(picture, now)
  for id, tr in pairs(picture) do
    if now - tr.t > T.TTL or not (tr.obj and tr.obj:isExist()) then picture[id] = nil end
  end
end

function T.tick()
  local now = M.now()
  local list = M.net.list
  local count = #list
  if count == 0 then return end
  local polled, looked = 0, 0
  while polled < T.BUDGET and looked < count do
    if T.cursor > count then T.cursor = 1 end
    local n = list[T.cursor]
    T.cursor = T.cursor + 1
    looked = looked + 1
    if isSensor(n) and now - (n.lastPoll or -1e9) >= T.POLL_INTERVAL then
      M.safe("tracks.poll", T.poll, n, now)
      polled = polled + 1
    end
  end
  for _, net in pairs(M.net.networks) do
    if net.tracks then expire(net.tracks, now) end
  end
  for _, n in ipairs(list) do
    if n.localTracks then expire(n.localTracks, now) end
  end
end

-- Closest track inside `range` of the node: the network picture if the node is linked, plus its own radar.
function T.nearest(node, range)
  if not node.pos then return nil end
  local r2 = range * range
  local best, bestD
  local function scan(picture)
    if not picture then return end
    for _, tr in pairs(picture) do
      local dx, dz = tr.pos.x - node.pos.x, tr.pos.z - node.pos.z
      local d2 = dx * dx + dz * dz
      if d2 <= r2 and (not bestD or d2 < bestD) then best, bestD = tr, d2 end
    end
  end
  if node.linked then scan(node.net.tracks) end
  scan(node.localTracks)
  return best, bestD and math.sqrt(bestD)
end

function T.start()
  M.every("tracks.tick", 1, T.tick, 1)
end
