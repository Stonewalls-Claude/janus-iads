-- Janus IADS - check-mode view (DESIGN 4.8 "Debug view", 5.0.1): F10 map drawing of every node, its link to
-- command and its state. Only runs when CHECK_MODE = true in the settings. Redrawn when the network changes.

JANUS = JANUS or {}
local M = JANUS
local S = M.settings

local D = {}
M.debugview = D
D.ids = {}
D.nextId = 910000

local ipairs = ipairs
local COLOR = {
  linked = { 0.1, 0.8, 0.1, 1 }, autonomous = { 1, 0.6, 0, 1 }, unlinked = { 1, 1, 0, 1 },
  offline = { 0.5, 0.5, 0.5, 1 }, link = { 0.3, 0.6, 1, 0.8 },
}
local NOFILL = { 0, 0, 0, 0 }

local function newId()
  D.nextId = D.nextId + 1
  D.ids[#D.ids + 1] = D.nextId
  return D.nextId
end

function D.clear()
  for _, id in ipairs(D.ids) do pcall(trigger.action.removeMark, id) end
  D.ids = {}
end

local function stateOf(n)
  if not (n.alive and n.working and n.powered) then return "offline" end
  if n.autonomous then return "autonomous" end
  if not n.linked then return "unlinked" end
  return "linked"
end

function D.draw()
  if not S.CHECK_MODE then return end
  local A = trigger.action
  if not (A.circleToAll and A.lineToAll and A.textToAll) then return end
  D.clear()
  for _, n in ipairs(M.net.list) do
    if n.pos then
      local st = stateOf(n)
      local r = (n.kind == "EW") and math.min(n.detectionRange, 150000) or n.engageRange
      if r and r > 0 then
        A.circleToAll(-1, newId(), n.pos, r, COLOR[st], NOFILL, 2, true)
      end
      A.textToAll(-1, newId(), n.pos, COLOR[st], NOFILL, 12, true,
        string.format("%s [%s %s] %s", n.name, n.kind, n.tier, st))
      if n.parent and n.parent.pos and n.parent ~= n then
        A.lineToAll(-1, newId(), n.pos, n.parent.pos, COLOR.link, 3, true)
      end
    end
  end
end

function D.start()
  if not S.CHECK_MODE then return end
  M.net.onTopology = D.draw
  D.draw()
  M.every("debugview.redraw", 30, D.draw, 30)
end
