-- Janus IADS - track picture (DESIGN 4.2): aircraft seen by the network's emitting radars, fused per network and kept
-- per radar. Budgeted round-robin polling of Controller:getDetectedTargets(). A track has a number, class
-- (fixed-wing / helicopter), position, velocity, the sensors holding it and, once identified, the DCS type name:
-- identified when a sensor reports the detection `type` flag (probe run 6: AWACS, SA-6, SA-11 do; ground EW never)
-- or, on the network picture, after the doctrine's idTime of continuous track. Weapons are ignored here (the ARM
-- awareness model of DESIGN 4.5A handles them in Phase 3, because DCS's own weapon detection is far too generous).

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
T.numbers = {}          -- DCS object id -> track number (stable across pictures)
T.seq = 0
T.CLASS = { [0] = "fixed-wing", [1] = "helicopter" }

local AIR = { [0] = true, [1] = true }   -- Unit.Category AIRPLANE, HELICOPTER

local function isSensor(n)
  return n.alive and n.working and n.powered and n.hasRadar and n.emcon.on ~= false
end
T.isSensor = isSensor

local function identify(tr, obj, by, now)
  local ok, t = pcall(obj.getTypeName, obj)
  if ok and t then   -- mutate: ok getTypeName never returns nil
    tr.typeName, tr.typeKnown, tr.idBy, tr.idAt = t, true, by, now
  end
end

-- det: the detection entry (its `type` flag); dwell: seconds of continuous track that identify it anyway (nil = never)
local function store(picture, obj, pos, now, node, det, class, dwell)
  local id = obj.getID and obj:getID() or tostring(obj)
  local tr = picture[id]
  if not tr then
    local num = T.numbers[id]
    if not num then
      T.seq = T.seq + 1
      num = T.seq
      T.numbers[id] = num
    end
    tr = { id = id, num = num, obj = obj, first = now, sensors = {}, class = class, typeKnown = false }
    picture[id] = tr
  elseif tr.pos and now > tr.t then
    local dt = now - tr.t
    tr.vel = { x = (pos.x - tr.pos.x) / dt, y = (pos.y - tr.pos.y) / dt, z = (pos.z - tr.pos.z) / dt }
  end
  tr.pos, tr.t = pos, now
  tr.sensors[node.name] = now
  if not tr.typeKnown then
    if det and det.type then
      identify(tr, obj, node.name, now)
    elseif dwell and now - tr.first >= dwell then
      identify(tr, obj, "held " .. math.floor(now - tr.first) .. " s", now)
    end
  end
  return tr
end
T.store = store

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
    local det = dets[i]
    local obj = det.object
    -- a detection with neither a visual nor a range fix gives no position worth tracking (run 6: A-50 on the E-3)
    local fix = det.visible ~= false or det.distance ~= false
    if fix and obj and obj.isExist and obj:isExist() and Object.getCategory(obj) == Object.Category.UNIT then  -- mutate: ok defensive checks on DCS detection data
      local ocoa = obj:getCoalition()
      local desc = obj:getDesc()
      if ocoa ~= coa and ocoa ~= 0 and desc and AIR[desc.category] then
        local pos = obj:getPoint()
        local class = T.CLASS[desc.category]
        store(node.localTracks, obj, pos, now, node, det, class, nil)
        if node.linked then
          node.net.tracks = node.net.tracks or {}
          local it = node.net.doctrine.idTime
          store(node.net.tracks, obj, pos, now, node, det, class, it and (it[node.tier] or it.REG))
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

-- Closest track inside `range` of the node: the network picture if the node is linked, the radars feeding it after
-- command loss (node.feeders, set by EMCON coverage), plus its own radar.
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
  if node.feeders then                           -- cut off from command: plots from EW radars (c2LossCue)
    for i = 1, #node.feeders do scan(node.feeders[i].localTracks) end
  end
  scan(node.localTracks)
  return best, bestD and math.sqrt(bestD)
end

-- Plain list of a picture's tracks (for logs and the GCI interface later).
function T.list(picture)
  local out = {}
  for _, tr in pairs(picture or {}) do out[#out + 1] = tr end
  table.sort(out, function(a, b) return a.num < b.num end)
  return out
end

function T.label(tr)
  return string.format("T%d %s", tr.num, tr.typeKnown and tr.typeName or (tr.class or "unknown"))
end

function T.start()
  M.every("tracks.tick", 1, T.tick, 1)
end
