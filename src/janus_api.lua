-- Janus IADS - the scripter's API (DESIGN 5.2, Phase 5). Optional: nothing here is needed for the zero-code setup.
--
-- Events (your function is called through Janus's error guard; an error in it never stops the IADS):
--   JANUS.subscribe(event, fn [, key]) -> handle      the same event + key replaces the earlier function
--   JANUS.unsubscribe(handle) -> true / false
--     "engage"        { coalition, net, site, from (site handed from, or nil), track, unitId, typeName (nil if not
--                       identified), pk }                       a site was given a target
--     "harmDetected"  { coalition, net, arm, site, how }        the network confirmed an anti-radiation missile
--     "emission"      { coalition, net, site, on, reason }      a site's radar went on or off
--     "nodeLost"      { coalition, net, site, kind }            a site, post, relay or power node was destroyed
--     "nodeRestored"  { coalition, net, site, kind, reason }    repaired, power back, relinked, radio back
--     "nodeDegraded"  { coalition, net, site, kind, reason }    equipment lost, no power, unlinked, radio lost
--   Every event table also carries `event` (its name) and `t` (mission seconds).
-- Runtime changes:
--   JANUS.setEmcon(site, policy)      "always" / "dark" / "cued" / "periodic" / "rotating", or nil for the doctrine's
--   JANUS.setWeapons(coal, state [, net])   "free" / "tight" / "hold" (as JANUS.gci.weaponsControl)
--   JANUS.setHold(site, true/false)   true = the site never goes dark for an ARM (the [hold] tag)
--   JANUS.addGroup(groupName)         take a group spawned by another script now instead of at its birth event
-- Reading:
--   JANUS.site(name) -> { name, kind, coalition, net, tier, alive, working, powered, linked, emitting, emcon, dark,
--                         assigned (track numbers), x, z }  or nil
--   JANUS.siteNames(coal) -> sorted list of site names

JANUS = JANUS or {}
local M = JANUS

local A = {}
M.api = A

local pairs, ipairs, type = pairs, ipairs, type

A.EVENTS = { engage = true, harmDetected = true, emission = true, nodeLost = true, nodeRestored = true, nodeDegraded = true }
local subs = {}
for e in pairs(A.EVENTS) do subs[e] = {} end
local nextHandle = 0   -- mutate: ok handles are opaque

function M.subscribe(event, fn, key)
  if not A.EVENTS[event] or type(fn) ~= "function" then return nil end
  local list = subs[event]
  if key ~= nil then
    for _, s in ipairs(list) do
      if s.key == key then s.fn = fn; return s.handle end
    end
  end
  nextHandle = nextHandle + 1   -- mutate: ok handles are opaque
  list[#list + 1] = { fn = fn, key = key, handle = nextHandle }
  return nextHandle
end

function M.unsubscribe(handle)
  for _, list in pairs(subs) do
    for i = #list, 1, -1 do
      if list[i].handle == handle then table.remove(list, i); return true end
    end
  end
  return false
end

-- modules call this; costs nothing with no subscribers
function M.publish(event, data)
  local list = subs[event]
  if not list or #list == 0 then return end   -- mutate: ok modules only publish known events
  data.event, data.t = event, M.now()
  for i = 1, #list do M.safe("api.subscriber." .. event, list[i].fn, data) end
end

local function nodeEvent(event)
  return function(n, reason)
    M.publish(event, { coalition = n.net.coalition, net = n.net.key, site = n.name, kind = n.kind, reason = reason })
  end
end

-- ------------------------------------------------------------------ runtime changes
function M.setEmcon(name, policy)
  if policy ~= nil and not (M.emcon and M.emcon.POLICIES and M.emcon.POLICIES[policy]) then return false end
  return M.emcon ~= nil and M.emcon.set(name, policy) or false
end

function M.setWeapons(coal, state, net)
  return M.gci and M.gci.weaponsControl(coal, state, net) or 0   -- mutate: ok the gci module is always built in
end

function M.setHold(name, on)
  local n = M.net and M.net.nodes[name]
  if not n then return false end
  n.site.tags.hold = on and "true" or nil
  return true
end

function M.addGroup(groupName)
  local g = Group.getByName(groupName)
  if not (g and g:isExist()) then return false end
  M.net.pickUp(g)
  return M.net.nodes[groupName] ~= nil
end

-- ------------------------------------------------------------------ reading
function M.site(name)
  local n = M.net and M.net.nodes[name]
  if not n then return nil end
  local assigned = {}
  for _, tr in ipairs(n.assigned or {}) do assigned[#assigned + 1] = tr.num end
  local em = n.emcon or {}
  return { name = n.name, kind = n.kind, coalition = n.net.coalition, net = n.net.key, tier = n.tier,
           alive = n.alive == true, working = n.working == true, powered = n.powered == true, linked = n.linked == true,
           emitting = em.on == true, emcon = em.policy, dark = (n.arm and n.arm.dark) ~= nil, assigned = assigned,
           x = n.pos and n.pos.x, z = n.pos and n.pos.z }
end

function M.siteNames(coal)
  local out = {}
  for _, n in ipairs(M.net and M.net.list or {}) do
    if coal == nil or n.net.coalition == coal then out[#out + 1] = n.name end
  end
  table.sort(out)
  return out
end

function A.start()
  local N = M.net
  N.on("nodeLost", nodeEvent("nodeLost"))
  N.on("restored", nodeEvent("nodeRestored"))
  N.on("degraded", nodeEvent("nodeDegraded"))
  if M.emcon and M.emcon.onChange then   -- mutate: ok both exist in every build
    M.emcon.onChange[#M.emcon.onChange + 1] = function(n, on, reason)
      M.publish("emission", { coalition = n.net.coalition, net = n.net.key, site = n.name, on = on, reason = reason })
    end
  end
end
