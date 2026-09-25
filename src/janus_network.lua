-- Janus IADS - network model (DESIGN 4.1, 4.6): nodes, networks, command links through relays, power, autonomy.
-- A node is one DCS group (probe run 3: a launcher only fires with a radar in its own group).

JANUS = JANUS or {}
local M = JANUS
local U = M.util
local S = M.settings

local string_format = string.format
local pairs, ipairs = pairs, ipairs

local N = {}
M.net = N
N.nodes = {}          -- name -> node
N.list = {}           -- array of nodes
N.networks = {}       -- key "red/main" -> network
N.dirty = true
N.callbacks = { nodeLost = {}, autonomy = {}, linked = {} }

local ROLE_TO_KIND = { CMD = "C2", COMMS = "COMMS", POWER = "POWER", EW = "EW", AWACS = "EW",
                       SAM = "BATTERY", PD = "PD", AAA = "AAA", SHIP = "NAVAL" }

-- unit roles that keep a node of each kind "working"
local WORKING = {
  C2 = { C2 = true, C2_GENERIC = true, EWR = true },
  COMMS = "any", POWER = "any",
  EW = { EWR = true, SR = true, STR = true, TR = true, AIRBORNE_SENSOR = true, TELAR = true, SHORAD = true },
  BATTERY = { TR = true, STR = true, TELAR = true, SHORAD = true, AAA_FC = true, NAVAL_AD = true },
  PD = { TR = true, STR = true, TELAR = true, SHORAD = true, CRAM = true, AAA = true },
  AAA = { AAA = true, AAA_FC = true, SHORAD = true, MANPADS = true },
  NAVAL = { NAVAL_AD = true, NAVAL = true },
}
local RADAR_ROLES = { EWR = true, SR = true, STR = true, TR = true, TELAR = true, SHORAD = true, CRAM = true,
                      AAA_FC = true, NAVAL_AD = true, AIRBORNE_SENSOR = true }
local SHOOTER_ROLES = { LN = true, TELAR = true, SHORAD = true, CRAM = true, AAA = true, MANPADS = true, NAVAL_AD = true }

local TIERS = { GRN = true, REG = true, VET = true, ACE = true }

function N.on(kind, fn)
  local list = N.callbacks[kind]
  if list then list[#list + 1] = fn end
end
local function fire(kind, ...)
  local list = N.callbacks[kind]
  for i = 1, #list do M.safe("net.callback." .. kind, list[i], ...) end
end

-- ------------------------------------------------------------------ node construction
local function tierOf(site)
  local t = site.tags.skill or site.tags.tier
  if t and TIERS[string.upper(t)] then return string.upper(t) end
  for word in string.gmatch(site.name, "%a+") do
    local w = string.upper(word)
    if TIERS[w] then return w end
  end
  return "REG"
end

local function networkFor(coalition, name)
  local coa = U.coalitionName[coalition] or tostring(coalition)
  local key = coa .. "/" .. name
  local net = N.networks[key]
  if not net then
    local doctrineSetting = (coalition == 1) and S.RED_DOCTRINE or S.BLUE_DOCTRINE
    local fallback = (coalition == 1) and "SOVIET_PVO_1985" or "US_MODERN"
    net = { key = key, name = name, coalition = coalition, coaName = coa,
            doctrine = M.getDoctrine(doctrineSetting, fallback), nodes = {}, hasC2 = false }
    N.networks[key] = net
  end
  return net
end

local function ranges(site)
  local det, eng, rclass = 0, 0, "NONE"
  local order = { NONE = 0, SR = 1, MR = 2, LR = 3 }
  for _, u in ipairs(site.units) do
    local r = u.rec
    if (r.detectionRange or 0) > det then det = r.detectionRange end
    if SHOOTER_ROLES[r.role] and (r.threatRange or 0) > eng then eng = r.threatRange end
    local rc = r.rangeClass or "NONE"
    if order[rc] and order[rc] > order[rclass] then rclass = rc end
  end
  return det, eng, rclass
end

function N.addSite(site)
  if N.nodes[site.name] then return N.nodes[site.name] end
  local kind = ROLE_TO_KIND[site.roleWord] or "BATTERY"
  local net = networkFor(site.coalition, site.tags.net or "main")
  local det, eng, rclass = ranges(site)
  local hasRadar = false
  for _, u in ipairs(site.units) do if RADAR_ROLES[u.rec.role] then hasRadar = true end end
  local node = {
    name = site.name, site = site, kind = kind, net = net, tier = tierOf(site),
    detectionRange = det, engageRange = eng, rangeClass = rclass, hasRadar = hasRadar,
    airborne = site.roleWord == "AWACS",
    alive = true, working = true, powered = true, linked = true, autonomous = false,
    powerSources = nil, reserveUntil = nil, unlinkedSince = nil, parent = nil,
    emcon = { policy = nil, on = nil, offSince = -1e9, onSince = -1e9, cuedAt = nil, lastCue = -1e9, emitSec = 0 },
  }
  N.nodes[site.name] = node
  N.list[#N.list + 1] = node
  net.nodes[#net.nodes + 1] = node
  if kind == "C2" then net.hasC2 = true end
  N.dirty = true
  return node
end

-- ------------------------------------------------------------------ state from DCS
local function nodePos(node)
  local g = node.site.group
  if not (g and g.isExist and g:isExist()) then return node.pos end
  local units = g:getUnits() or {}
  for i = 1, #units do
    if U.alive(units[i]) then
      local p = units[i]:getPoint()
      if p then return p end
    end
  end
  return node.pos
end

local function refreshAlive(node)
  local g = node.site.group
  local alive, working = false, false
  local need = WORKING[node.kind]
  if g and g.isExist and g:isExist() then
    for _, u in ipairs(node.site.units) do
      if U.alive(u.unit) and u.unit:getLife() > 0 then
        alive = true
        if need == "any" or (need and need[u.rec.role]) then working = true end
      end
    end
  end
  if node.alive and not alive then
    M.info("net", string_format("%s %s destroyed", node.net.key, node.name))
    fire("nodeLost", node)
  elseif node.working and alive and not working then
    M.info("net", string_format("%s %s lost its %s equipment (degraded)", node.net.key, node.name, node.kind))
  end
  node.alive, node.working = alive, alive and working
  node.pos = nodePos(node) or node.pos
end

-- ------------------------------------------------------------------ topology
local function dist2(a, b)
  local dx, dz = a.x - b.x, a.z - b.z
  return dx * dx + dz * dz
end

local function findByLabel(net, kind, label)
  if not label then return nil end
  local l = string.lower(U.trim(label))
  for _, n in ipairs(net.nodes) do
    if n.kind == kind and (string.lower(n.name) == l or string.lower(n.site.label) == l) then return n end
  end
  return nil
end

local function assignPower(net)
  local d = net.doctrine
  local r2 = d.powerRange * d.powerRange
  for _, n in ipairs(net.nodes) do
    if n.kind ~= "POWER" and n.pos then
      local src
      if n.site.tags.power then
        src = {}
        for _, lbl in ipairs(M.names.list(n.site.tags.power)) do
          local p = findByLabel(net, "POWER", lbl)
          if p then src[#src + 1] = p end
        end
      else
        for _, p in ipairs(net.nodes) do
          if p.kind == "POWER" and p.pos and dist2(p.pos, n.pos) <= r2 then
            src = src or {}
            src[#src + 1] = p
          end
        end
      end
      n.powerSources = src
    end
  end
end

-- Command reachability: BFS from working, powered C2 nodes through working, powered relays.
local function computeLinks(net, now)
  local d = net.doctrine
  local relay2, link2 = d.relayRange * d.relayRange, d.linkRange * d.linkRange
  local hubs = {}
  for _, n in ipairs(net.nodes) do
    if (n.kind == "C2" or n.kind == "COMMS") and n.working and n.powered and n.pos then hubs[#hubs + 1] = n end
  end
  local reached, queue = {}, {}
  for _, h in ipairs(hubs) do
    if h.kind == "C2" then reached[h] = h; queue[#queue + 1] = h end
  end
  local qi = 1
  while qi <= #queue do
    local a = queue[qi]; qi = qi + 1
    for _, b in ipairs(hubs) do
      if not reached[b] and dist2(a.pos, b.pos) <= relay2 then
        reached[b] = a
        queue[#queue + 1] = b
      end
    end
  end
  for _, n in ipairs(net.nodes) do
    local linked, parent = false, nil
    if not net.hasC2 then
      linked = true                                  -- flat network: no command posts, everyone shares
    elseif reached[n] then
      linked, parent = true, reached[n]
    elseif n.kind ~= "C2" and n.kind ~= "POWER" and n.pos then
      local want = findByLabel(net, "C2", n.site.tags.cmd)
      local viaRelay = findByLabel(net, "COMMS", n.site.tags.relay)
      if want then
        linked, parent = reached[want] ~= nil, want
      elseif viaRelay then
        linked, parent = reached[viaRelay] ~= nil and dist2(viaRelay.pos, n.pos) <= link2, viaRelay
      else
        local best, bestD = nil, link2
        for h in pairs(reached) do
          local dd = dist2(h.pos, n.pos)
          if dd <= bestD then best, bestD = h, dd end
        end
        linked, parent = best ~= nil, best
      end
    end
    n.parent = parent
    if linked then
      if n.autonomous then
        n.autonomous = false
        M.info("net", string_format("%s %s link to command restored", net.key, n.name))
        fire("linked", n)
      end
      n.linked, n.unlinkedSince = true, nil
    else
      if n.linked then
        n.linked, n.unlinkedSince = false, now
        M.info("net", string_format("%s %s lost its link to command", net.key, n.name))
      end
    end
  end
end

local function updatePower(net, now)
  for _, n in ipairs(net.nodes) do
    local src = n.powerSources
    if src and #src > 0 then
      local any = false
      for _, p in ipairs(src) do if p.working then any = true end end
      if any then
        n.reserveUntil = nil
        if not n.powered then M.info("net", string_format("%s %s power restored", net.key, n.name)) end
        n.powered = true
      elseif n.powered then
        if not n.reserveUntil then
          n.reserveUntil = now + net.doctrine.powerReserve
          M.info("net", string_format("%s %s on reserve power for %d s", net.key, n.name, net.doctrine.powerReserve))
        elseif now >= n.reserveUntil then
          n.powered = false
          M.info("net", string_format("%s %s out of power", net.key, n.name))
        end
      end
    else
      n.powered = true
    end
  end
end

local function updateAutonomy(net, now)
  local delays = net.doctrine.autonomyDelay
  for _, n in ipairs(net.nodes) do
    if not n.linked and not n.autonomous and n.unlinkedSince then
      if now - n.unlinkedSince >= (delays[n.tier] or delays.REG) then
        n.autonomous = true
        M.info("net", string_format("%s %s is now autonomous (%s crew)", net.key, n.name, n.tier))
        fire("autonomy", n)
      end
    end
  end
end

-- Full update: cheap enough for every slow tick; topology only when something changed.
function N.update()
  local now = M.now()
  for _, n in ipairs(N.list) do
    if n.alive or N.dirty then refreshAlive(n) end
  end
  for _, net in pairs(N.networks) do
    if N.dirty then assignPower(net) end
    updatePower(net, now)
    computeLinks(net, now)
    updateAutonomy(net, now)
  end
  if N.dirty and N.onTopology then M.safe("net.topology", N.onTopology) end
  N.dirty = false
end

-- ------------------------------------------------------------------ building, events
function N.build()
  for _, site in ipairs(M.sites) do N.addSite(site) end
  for _, n in ipairs(N.list) do n.pos = nodePos(n) end
  N.dirty = true
  N.update()
  local parts = {}
  for _, net in pairs(N.networks) do
    local counts = {}
    for _, n in ipairs(net.nodes) do counts[n.kind] = (counts[n.kind] or 0) + 1 end
    local c = {}
    for _, k in ipairs(U.keys(counts)) do c[#c + 1] = counts[k] .. "x " .. k end
    parts[#parts + 1] = string_format("%s (%s, %s%s)", net.key, U.join(c), net.doctrine.name,
      net.hasC2 and "" or ", no command post: flat network")
  end
  table.sort(parts)
  for _, p in ipairs(parts) do M.info("net", "network " .. p) end
  for _, n in ipairs(N.list) do
    local p = n.parent and (" -> " .. n.parent.name) or ""
    local pw = (n.powerSources and #n.powerSources > 0) and (" power:" .. n.powerSources[1].name) or ""
    M.info("net", string_format("  %s [%s %s]%s%s%s", n.name, n.kind, n.tier, p, pw, n.linked and "" or " (NOT LINKED)"))
  end
end

-- A group spawned after start (Olympus, scripts, late activation) that follows the naming rules.
function N.pickUp(group)
  if not (group and group.isExist and group:isExist()) then return end
  local name = group:getName()
  if N.nodes[name] then return end
  local parsed = M.names.parse(name)
  if not parsed then return end
  local site = M.inspectGroup(group, parsed, group:getCoalition())
  M.sites[#M.sites + 1] = site
  local node = N.addSite(site)
  node.pos = nodePos(node)
  M.info("net", string_format("picked up %s [%s] in %s", name, node.kind, node.net.key))
  if N.onNewNode then M.safe("net.newnode", N.onNewNode, node) end
end

function N.start()
  N.build()
  M.on(world.event.S_EVENT_DEAD, "net.dead", function() N.dirty = true end)
  M.on(world.event.S_EVENT_BIRTH, "net.birth", function(e)
    local u = e.initiator
    if u and u.getGroup and Object.getCategory(u) == Object.Category.UNIT then
      local ok, g = pcall(u.getGroup, u)
      if ok and g then
        -- groups are complete a moment after the first BIRTH; pick them up on the next tick
        timer.scheduleFunction(M.wrap("net.pickup", function() N.pickUp(g) end), nil, M.now() + 1)
      end
    end
  end)
  M.every("net.update", 5, N.update, 2)
end
