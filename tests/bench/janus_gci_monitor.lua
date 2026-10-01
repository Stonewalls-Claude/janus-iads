-- Janus IADS - JANUS.gci monitor for benches (Phase 2.5). Loaded AFTER janus.lua. Plays the part of a GCI script:
-- looks JANUS.gci up itself, checks the version, calls through pcall, subscribes once per Janus instance, and logs
-- what a GCI would see every 60 s (tag "JANUS_GCIMON"). It never changes anything in Janus.
-- Lua 5.1, sanitized. Lives in the shared namespace (JANUS.gcimon) so the one-global rule holds.

JANUS = JANUS or {}
JANUS.gcimon = JANUS.gcimon or {}
local MON = JANUS.gcimon

local TAG = "JANUS_GCIMON"
local env_info, env_error = env.info, env.error
local timer_getTime, timer_schedule = timer.getTime, timer.scheduleFunction
local string_format = string.format
local T0 = timer_getTime()
local function log(msg) env_info(string_format("%s %.2f %s", TAG, timer_getTime() - T0, msg)) end

local function api()
  local g = JANUS and JANUS.gci
  if not g then return nil, "no JANUS.gci" end
  if g.version ~= 1 then return nil, "unknown version " .. tostring(g.version) end
  return g
end

local function call(fn, ...)
  local args, n = { ... }, select("#", ...)
  local ok, res = pcall(function() return fn(unpack(args, 1, n)) end)
  if not ok then
    if not MON.warned then MON.warned = true; env_error(TAG .. " JANUS.gci error, falling back: " .. tostring(res)) end
    return nil
  end
  return res
end

local function onEvent(ev)
  log(string_format("EVENT %s %s [%s] coalition %d: %s (%s)", ev.event, ev.name, ev.kind, ev.coalition, ev.state,
    tostring(ev.reason)))
end

local function subscribe(g)
  if MON.instance == g.instance then return end
  MON.instance = g.instance
  for _, e in ipairs({ "nodeLost", "nodeRestored", "nodeDegraded", "authorityChanged" }) do
    call(g.on, e, onEvent, "janus-gci-monitor")
  end
  log(string_format("subscribed to JANUS.gci v%d instance %d", g.version, g.instance))
end

local function report(_, t)
  local g, why = api()
  if not g then
    log("fallback: " .. why)
    return t + 60
  end
  subscribe(g)
  for _, coal in ipairs({ 1, 2 }) do
    local side = coal == 1 and "red" or "blue"
    local heads = call(g.radarHeads, coal) or {}
    local hs = {}
    for _, h in ipairs(heads) do hs[#hs + 1] = h.name .. (h.airborne and "(air)" or "") end
    local cns = call(g.commandNodes, coal) or {}
    local cs = {}
    for _, c in ipairs(cns) do
      cs[#cs + 1] = string_format("%s:%s%s radio %s ctl %s", c.name, c.kind,
        c.inCommand and "/in command" or (c.alive and (c.active and "/unlinked" or "/standby") or "/dead"), c.radio, c.fighterControl)
    end
    local tracks = call(g.tracks, coal) or {}
    local ts = {}
    for _, tr in ipairs(tracks) do ts[#ts + 1] = string_format("T%d %s", tr.num, tr.typeKnown and tr.typeName or tr.class) end
    local zones = call(g.samZones, coal) or {}
    local zs = {}
    for _, z in ipairs(zones) do zs[#zs + 1] = string_format("%s %.0f km%s", z.name, z.r / 1000, z.emitting and " HOT" or "") end
    log(string_format("%s HEADS %s", side, table.concat(hs, ", ")))
    log(string_format("%s COMMAND %s", side, table.concat(cs, " | ")))
    log(string_format("%s TRACKS %s", side, table.concat(ts, "; ")))
    log(string_format("%s ZONES %s", side, table.concat(zs, "; ")))
    -- control reach at each track: can a ground controller talk a fighter onto it?
    local reach = {}
    for _, tr in ipairs(tracks) do
      local c = call(g.controlState, coal, { x = tr.x, z = tr.z })
      reach[#reach + 1] = string_format("T%d %s", tr.num, c and c.ground and (c.via .. "/" .. c.radio) or "none")
    end
    if #reach > 0 then log(string_format("%s CONTROL %s", side, table.concat(reach, "; "))) end
  end
  return t + 60
end

timer_schedule(function(_, t)
  local ok, res = pcall(report, nil, t)
  if not ok then env_error(TAG .. " monitor error: " .. tostring(res)); return t + 60 end
  return res
end, nil, timer_getTime() + 5)
log("JANUS.gci monitor loaded")
