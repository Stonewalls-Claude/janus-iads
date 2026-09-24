-- Janus IADS - core: namespace, logging, error budget, safe wrappers, scheduler, events, settings.
-- Lua 5.1, sanitized DCS Mission Scripting Environment. No dependencies.
-- Everything Janus owns lives in the one global table JANUS.

JANUS = JANUS or {}
local M = JANUS

M.VERSION = "0.1.0-phase0"
M.TAG = "JANUS"

-- Cache hot DCS functions as locals (nil-safe so the file loads in the offline harness too).
local env_info = env and env.info
local env_error = env and env.error
local timer_getTime = timer and timer.getTime
local timer_schedule = timer and timer.scheduleFunction
local string_format = string.format
local table_concat = table.concat
local math_floor = math.floor

-- ---------------------------------------------------------------- settings
-- Defaults. Mission makers override them from a plain `janus_settings.lua` loaded BEFORE janus.lua,
-- which only has to set fields on a table called JANUS_SETTINGS (read once here, never written).
M.defaults = {
  AUTOSTART = true,          -- start both coalitions ~1 s after loading; false = you call JANUS.start()
  AUTOSTART_DELAY = 1,       -- seconds
  CHECK_MODE = false,        -- also show the setup report on screen and draw F10 marks
  LOG_LEVEL = 2,             -- 0 errors only, 1 + warnings, 2 + info, 3 + debug
  RED_DOCTRINE = "SOVIET_PVO_1985",
  BLUE_DOCTRINE = "US_MODERN",
  -- Role words at the start of a group name (case-insensitive). Change these if your naming differs.
  ROLE_WORDS = {
    SAM = "SAM", EW = "EW", CMD = "CMD", PD = "PD", AAA = "AAA",
    COMMS = "COMMS", POWER = "POWER", SHIP = "SHIP", AWACS = "AWACS",
  },
}

local function copyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      copyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

M.settings = M.settings or {}
do
  local user = rawget(_G, "JANUS_SETTINGS")
  if type(user) == "table" then
    for k, v in pairs(user) do M.settings[k] = v end
  end
  copyDefaults(M.settings, M.defaults)
end
local S = M.settings

-- ---------------------------------------------------------------- logging
local function now()
  if timer_getTime then return timer_getTime() end
  return 0
end
M.now = now

local function fmtTime(t)
  t = math_floor(t or 0)
  return string_format("%02d:%02d:%02d", math_floor(t / 3600), math_floor(t % 3600 / 60), t % 60)
end
M.fmtTime = fmtTime

local function log(level, tag, msg)
  local line = string_format("%s [%s] %s", M.TAG, tag or "core", msg)
  if level == 0 then
    if env_error then env_error(line) else print("ERROR " .. line) end
  elseif level <= S.LOG_LEVEL then
    if env_info then env_info(line) else print(line) end
  end
end
function M.error(tag, msg) log(0, tag, msg) end
function M.warn(tag, msg) log(1, tag, "WARNING: " .. msg) end
function M.info(tag, msg) log(2, tag, msg) end
function M.debug(tag, msg) log(3, tag, msg) end

-- ---------------------------------------------------------------- error budget + safe wrappers
-- First 5 errors per tag in full, then every 100th, so one broken handler can't flood dcs.log.
local budget = {}
local function report(tag, err)
  local b = budget[tag]
  if not b then b = { n = 0 }; budget[tag] = b end
  b.n = b.n + 1
  if b.n <= 5 or b.n % 100 == 0 then
    M.error(tag, string_format("error #%d: %s", b.n, tostring(err)))
  end
end
M.errorCount = function(tag) local b = budget[tag]; return b and b.n or 0 end

local function traceback(err)
  if debug and debug.traceback then return debug.traceback(tostring(err), 2) end
  return tostring(err)
end

-- M.safe(tag, fn, ...) : call fn(...) now, log any error, return ok, results...
-- Lua 5.1 xpcall takes no extra args, so the arguments are forwarded through a closure.
function M.safe(tag, fn, ...)
  local args = { ... }
  local n = select("#", ...)
  local function run()
    return fn(unpack(args, 1, n))
  end
  local r = { xpcall(run, traceback) }
  if not r[1] then report(tag, r[2]) end
  return unpack(r, 1, #r)
end

-- M.wrap(tag, fn [, retrySec]) : returns a function safe to hand to timer.scheduleFunction or an
-- event handler. For scheduled loops, `retrySec` is what to reschedule after an error so a single
-- bad tick doesn't stop the loop for good.
function M.wrap(tag, fn, retrySec)
  return function(...)
    local args = { ... }
    local n = select("#", ...)
    local function run()
      return fn(unpack(args, 1, n))
    end
    local ok, res = xpcall(run, traceback)
    if ok then return res end
    report(tag, res)
    if retrySec then return now() + retrySec end
    return nil
  end
end

-- ---------------------------------------------------------------- scheduler
-- One budgeted tick drives everything periodic; feature code registers jobs here instead of
-- creating its own timers, so intervals stay staggered and the whole IADS costs one timer.
M.jobs = M.jobs or {}
local jobs = M.jobs

-- M.every(tag, intervalSec, fn [, offsetSec]) : fn() runs every interval; returns the job.
function M.every(tag, interval, fn, offset)
  local job = { tag = tag, interval = interval, fn = M.wrap(tag, fn), next = now() + (offset or interval), on = true }
  jobs[#jobs + 1] = job
  return job
end

local TICK = 0.5   -- scheduler resolution; jobs decide their own (slower) intervals
local function tick()
  local t = now()
  for i = 1, #jobs do
    local job = jobs[i]
    if job.on and t >= job.next then
      job.next = t + job.interval
      local r = job.fn()
      if r == false then job.on = false end
    end
  end
  return t + TICK
end
M._tick = tick

function M.startScheduler()
  if M._schedulerId or not timer_schedule then return end
  M._schedulerId = timer_schedule(M.wrap("core.tick", tick, TICK), nil, now() + TICK)
end

-- ---------------------------------------------------------------- events
-- One DCS event handler; feature code subscribes per event id.
M.listeners = M.listeners or {}
function M.on(eventId, tag, fn)
  local list = M.listeners[eventId]
  if not list then list = {}; M.listeners[eventId] = list end
  list[#list + 1] = M.wrap(tag, fn)
end

local handler = {}
function handler:onEvent(e)
  if not e then return end
  local list = M.listeners[e.id]
  if not list then return end
  for i = 1, #list do list[i](e) end
end
M._eventHandler = handler

function M.startEvents()
  if M._eventsOn or not world or not world.addEventHandler then return end
  world.addEventHandler(handler)
  M._eventsOn = true
end

-- ---------------------------------------------------------------- small utilities
local U = {}
M.util = U

function U.dist2(a, b)             -- squared horizontal distance between two vec3 (x north, z east)
  local dx, dz = a.x - b.x, a.z - b.z
  return dx * dx + dz * dz
end

function U.dist(a, b) return math.sqrt(U.dist2(a, b)) end

function U.trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function U.join(list, sep) return table_concat(list, sep or ", ") end

function U.keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Safe object access: DCS objects can vanish between calls.
function U.alive(obj)
  return obj ~= nil and obj.isExist ~= nil and obj:isExist() == true
end

-- Coalition names
U.coalitionName = { [0] = "neutral", [1] = "red", [2] = "blue" }

M.info("core", "Janus IADS " .. M.VERSION .. " core loaded")
