-- Offline stand-in for the DCS Mission Scripting Environment, enough to load janus.lua and drive it.
-- Runs under plain Lua 5.1. Not a simulator: it holds groups/units the test builds, delivers
-- timers and events on demand, and records everything Janus logs or shows.

local F = {}
F.time = 0
F.log = {}          -- every env.info/warning/error line
F.text = {}         -- every trigger.action.outText
F.groups = {}       -- name -> group
F.byCoalition = {}  -- coalition -> category -> { groups }
F.timers = {}       -- { id, fn, arg, at }
F.nextId = 1
F.sees = {}            -- group name -> list of units its controller detects
F.controllerError = {} -- group name -> true: getDetectedTargets raises
F.emissionLog = {}

-- ---------------------------------------------------------------- env / timer / trigger / land
env = {
  info = function(s) F.log[#F.log + 1] = "INFO " .. tostring(s) end,
  warning = function(s) F.log[#F.log + 1] = "WARN " .. tostring(s) end,
  error = function(s) F.log[#F.log + 1] = "ERROR " .. tostring(s) end,
}

timer = {
  getTime = function() return F.time end,
  getAbsTime = function() return F.time + 28800 end,
  scheduleFunction = function(fn, arg, at)
    local id = F.nextId; F.nextId = id + 1
    F.timers[#F.timers + 1] = { id = id, fn = fn, arg = arg, at = at }
    return id
  end,
  removeFunction = function(id)
    for i = #F.timers, 1, -1 do if F.timers[i].id == id then table.remove(F.timers, i) end end
  end,
  setFunctionTime = function(id, at)
    for _, t in ipairs(F.timers) do if t.id == id then t.at = at end end
  end,
}

F.marks = {}
trigger = { action = {
  outText = function(s, secs) F.text[#F.text + 1] = s end,
  outTextForCoalition = function(c, s, secs) F.text[#F.text + 1] = s end,
  markToAll = function() end,
  removeMark = function(id) F.marks[id] = nil end,
  circleToAll = function(c, id) F.marks[id] = "circle" end,
  lineToAll = function(c, id) F.marks[id] = "line" end,
  textToAll = function(c, id, p, col, fill, size, ro, text) F.marks[id] = "text:" .. tostring(text) end,
} }

land = { getHeight = function(p) return 0 end }

-- ---------------------------------------------------------------- enums
coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3, TRAIN = 4 } }
Unit = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND_UNIT = 2, SHIP = 3, STRUCTURE = 4 } }
Object = { Category = { UNIT = 1, WEAPON = 2, STATIC = 3, BASE = 4, SCENERY = 5, Cargo = 6 } }
Object.getCategory = function(o) return o:getCategory() end
AI = { Option = { Ground = { id = { ROE = 0, ALARM_STATE = 9, ENGAGE_AIR_WEAPONS = 20 },
  val = { ROE = { OPEN_FIRE = 2, RETURN_FIRE = 3, WEAPON_HOLD = 4 }, ALARM_STATE = { AUTO = 0, GREEN = 1, RED = 2 } } },
  Air = { id = { ROE = 0 }, val = { ROE = { WEAPON_FREE = 0, WEAPON_HOLD = 4 } } } } }
world = { event = {
  S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_DEAD = 8, S_EVENT_BIRTH = 15,
} }

-- ---------------------------------------------------------------- objects
local UnitMT = {}
UnitMT.__index = UnitMT
function UnitMT:isExist() return self.alive end
function UnitMT:getName() return self.name end
function UnitMT:getTypeName() return self.type end
function UnitMT:getPoint() return { x = self.x, y = self.alt or 0, z = self.z } end
function UnitMT:getDesc()
  local cat = self.group.category
  return { category = (cat == Group.Category.AIRPLANE and 0) or (cat == Group.Category.HELICOPTER and 1)
    or (cat == Group.Category.SHIP and 3) or 2, typeName = self.type }
end
function UnitMT:getPosition() return { p = self:getPoint(), x = { x = 1, y = 0, z = 0 } } end
function UnitMT:getGroup() return self.group end
function UnitMT:getCoalition() return self.group.coalition end
function UnitMT:getLife() return self.alive and 1 or 0 end
function UnitMT:getID() return self.id end
function UnitMT:getCategory() return Object.Category.UNIT end
function UnitMT:getController() return self.group:getController() end
function UnitMT:getObjectName() return self.type end
function UnitMT:getCallsign() return self.name end

local GroupMT = {}
GroupMT.__index = GroupMT
function GroupMT:isExist() return self.alive end
function GroupMT:getName() return self.name end
function GroupMT:getUnits() local out = {}; for _, u in ipairs(self.units) do if u.alive then out[#out + 1] = u end end; return out end
function GroupMT:getUnit(i) return self.units[i] end
function GroupMT:getSize() return #self:getUnits() end
function GroupMT:getCoalition() return self.coalition end
function GroupMT:getCategory() return self.category end
function GroupMT:getID() return self.id end
local ControllerMT = {}
ControllerMT.__index = ControllerMT
function ControllerMT:setOption(id, val) self.options[id] = val end
function ControllerMT:getDetectedTargets()
  if F.controllerError[self.group.name] then error("fake controller failure") end
  local out = {}
  if not self.group:isExist() or self.group.emission == false then return out end
  local seen = F.sees[self.group.name]
  if seen then
    for _, u in ipairs(seen) do if u.alive then out[#out + 1] = { object = u, visible = true, type = true, distance = true } end end
  end
  return out
end
function GroupMT:getController()
  self.controller = self.controller or setmetatable({ options = {}, group = self }, ControllerMT)
  return self.controller
end
function GroupMT:enableEmission(on)
  self.emission = on
  F.emissionLog[#F.emissionLog + 1] = { t = F.time, group = self.name, on = on }
end
function UnitMT:getRadar() return self.group.emission ~= false end

Unit.getByName = function(n) for _, g in pairs(F.groups) do for _, u in ipairs(g.units) do if u.name == n then return u end end end end
Group.getByName = function(n) return F.groups[n] end

coalition.getGroups = function(coa, cat)
  local out = {}
  for _, g in pairs(F.groups) do
    if g.coalition == coa and (cat == nil or g.category == cat) and g.alive then out[#out + 1] = g end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end
coalition.getStaticObjects = function() return {} end

-- ---------------------------------------------------------------- events
local handlers = {}
world.addEventHandler = function(h) handlers[#handlers + 1] = h end
world.removeEventHandler = function(h) for i = #handlers, 1, -1 do if handlers[i] == h then table.remove(handlers, i) end end end
function F.fire(event)
  event.time = event.time or F.time
  for _, h in ipairs(handlers) do h:onEvent(event) end
end

-- ---------------------------------------------------------------- builder / clock
-- F.addGroup{ name=, coalition=, category=, units = { { type=, x=, z=, name= }, ... } }
function F.addGroup(spec)
  local g = setmetatable({ name = spec.name, coalition = spec.coalition or coalition.side.RED,
    category = spec.category or Group.Category.GROUND, units = {}, alive = true, id = F.nextId }, GroupMT)
  F.nextId = F.nextId + 1
  for i, us in ipairs(spec.units or {}) do
    local u = setmetatable({ name = us.name or (spec.name .. "-" .. i), type = us.type, x = us.x or 0, z = us.z or 0,
      alt = us.alt, alive = true, group = g, id = F.nextId }, UnitMT)
    F.nextId = F.nextId + 1
    g.units[#g.units + 1] = u
  end
  F.groups[g.name] = g
  return g
end

function F.kill(unit)
  unit.alive = false
  F.fire({ id = world.event.S_EVENT_DEAD, initiator = unit })
end
function F.killGroup(g)
  for _, u in ipairs(g.units) do if u.alive then F.kill(u) end end
end
function F.move(unit, x, z) unit.x, unit.z = x, z end
function F.emitting(name) local g = F.groups[name]; return g and g.emission ~= false end
-- spawn during the mission: BIRTH for every unit, like DCS

-- Advance the clock, running due timers in order (a timer returning a number is rescheduled).
function F.run(untilTime)
  while true do
    table.sort(F.timers, function(a, b) return a.at < b.at end)
    local t = F.timers[1]
    if not t or t.at > untilTime then break end
    table.remove(F.timers, 1)
    F.time = t.at
    local nextAt = t.fn(t.arg, F.time)
    if type(nextAt) == "number" then
      t.at = nextAt
      F.timers[#F.timers + 1] = t
    end
  end
  F.time = untilTime
end

function F.logContains(pattern)
  for _, l in ipairs(F.log) do if l:find(pattern, 1, true) then return true end end
  return false
end

function F.spawn(spec)
  local g = F.addGroup(spec)
  for _, u in ipairs(g.units) do F.fire({ id = world.event.S_EVENT_BIRTH, initiator = u }) end
  return g
end

function F.reset()
  F.time = 0; F.log = {}; F.text = {}; F.groups = {}; F.timers = {}; handlers = {}
  F.sees = {}; F.controllerError = {}; F.emissionLog = {}; F.marks = {}
  JANUS = nil; JANUS_SETTINGS = nil
end

FAKE = F
return F
