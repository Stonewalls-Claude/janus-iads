-- Janus IADS - setup: find the mission's air-defence groups, classify their units against the
-- DCS unit database, check that each site can actually work, and write the setup report.
-- Phase 0: recognition + report + autostart. Phases 1+ build the network on top of JANUS.sites.

JANUS = JANUS or {}
local M = JANUS
local S = M.settings
local U = M.util
local N = M.names
local DB = M.UnitDB or {}

local string_format = string.format

-- What each role word expects to find in the group, and which unit roles count as "the shooter/sensor".
local EXPECT = {
  SAM   = { shooters = { LN = true, TELAR = true, SHORAD = true, MANPADS = true }, sensors = { TR = true, STR = true, TELAR = true, SHORAD = true } },
  PD    = { shooters = { SHORAD = true, TELAR = true, CRAM = true, MANPADS = true }, sensors = { SHORAD = true, TELAR = true, CRAM = true, SR = true } },
  AAA   = { shooters = { AAA = true }, sensors = { AAA_FC = true, AAA = true } },
  EW    = { sensors = { EWR = true, SR = true, STR = true } },
  CMD   = { c2 = { C2 = true, C2_GENERIC = true } },
  SHIP  = { shooters = { NAVAL_AD = true }, sensors = { NAVAL_AD = true } },
  AWACS = { sensors = { AIRBORNE_SENSOR = true } },
  COMMS = {}, POWER = {},
}

M.sites = M.sites or {}
M.report = M.report or {}

local function add(lines, s) lines[#lines + 1] = s end

-- Classify one live DCS unit. Returns the DB record (or a stub for unknown types).
local function classifyUnit(unit)
  local t = unit:getTypeName()
  local rec = DB[t]
  if rec then return rec end
  return { type = t, role = "NONE", name = t, unknown = true }
end
M.classifyUnit = classifyUnit

-- Check the DCS dependency chain: every launcher's `dependsOn` types must be present in the group
-- (Phase 1 extends this to cross-group links through [net:] / [cmd:] tags).
local function checkDependencies(site)
  local present = {}
  for _, u in ipairs(site.units) do present[u.rec.type] = true end
  local problems = {}
  for _, u in ipairs(site.units) do
    local deps = u.rec.dependsOn
    if deps and #deps > 0 and not u.rec.mobileSelfContained then
      local ok = false
      for i = 1, #deps do
        if present[deps[i]] then ok = true; break end
      end
      if not ok then
        problems[#problems + 1] = string_format("%s needs one of: %s", u.rec.name, U.join(deps))
      end
    end
  end
  return problems
end

local function inspectGroup(group, parsed, coa)
  local site = {
    name = parsed.name, label = parsed.label, roleWord = parsed.role, tags = parsed.tags,
    coalition = coa, group = group, units = {}, roles = {}, problems = {}, notes = {},
  }
  local units = group:getUnits() or {}
  for i = 1, #units do
    local unit = units[i]
    if U.alive(unit) then
      local rec = classifyUnit(unit)
      site.units[#site.units + 1] = { unit = unit, rec = rec, name = unit:getName() }
      site.roles[rec.role] = (site.roles[rec.role] or 0) + 1
      if rec.unknown then
        site.notes[#site.notes + 1] = string_format("unit type '%s' is not in the Janus unit database (ignored)", rec.type)
      end
      if rec.dlc and not site.dlc then
        site.dlc = rec.dlc
        site.notes[#site.notes + 1] = string_format("uses '%s', a DCS: %s unit - this mission only loads for players and servers that own that DLC", rec.type, rec.dlc)
      end
    end
  end

  local expect = EXPECT[parsed.role] or {}
  local function hasAny(set)
    if not set then return true end
    for role in pairs(set) do
      if (site.roles[role] or 0) > 0 then return true end
    end
    return false
  end
  if expect.shooters and not hasAny(expect.shooters) then
    site.problems[#site.problems + 1] = "has no launcher or gun: it will never fire"
  end
  if expect.sensors and not hasAny(expect.sensors) then
    site.problems[#site.problems + 1] = "has no radar or sensor of its own: it will never fire"
  end
  if expect.c2 and not hasAny(expect.c2) then
    site.problems[#site.problems + 1] = "has no command-post unit"
  end
  for _, p in ipairs(checkDependencies(site)) do
    site.problems[#site.problems + 1] = p
  end
  return site
end
M.inspectGroup = inspectGroup

-- Scan both coalitions. Returns the list of sites and fills M.report (lines of plain English).
function M.scan()
  M.sites = {}
  local lines = {}
  local unrecognised = {}
  local counts = { red = 0, blue = 0 }

  local cats = { Group.Category.GROUND, Group.Category.SHIP, Group.Category.AIRPLANE }
  for _, coa in ipairs({ coalition.side.RED, coalition.side.BLUE }) do
    local coaName = U.coalitionName[coa]
    for _, cat in ipairs(cats) do
      local groups = coalition.getGroups(coa, cat) or {}
      for i = 1, #groups do
        local group = groups[i]
        if U.alive(group) then
          local name = group:getName()
          local parsed = N.parse(name)
          if parsed then
            local site = inspectGroup(group, parsed, coa)
            M.sites[#M.sites + 1] = site
            counts[coaName] = counts[coaName] + 1
          else
            -- not one of ours: is it air defence that the mission maker forgot to name?
            local units = group:getUnits() or {}
            local adUnits = 0
            for j = 1, #units do
              local rec = U.alive(units[j]) and DB[units[j]:getTypeName()]
              if rec and rec.role ~= "NONE" and rec.role ~= "NAVAL" then adUnits = adUnits + 1 end
            end
            if adUnits > 0 then
              unrecognised[#unrecognised + 1] = { name = name, coalition = coaName, n = adUnits, suggest = N.suggest(name) }
            end
          end
        end
      end
    end
  end

  -- ---- report
  add(lines, string_format("Janus IADS %s setup report (DCS unit data %s)", M.VERSION,
    M.UnitDBMeta and M.UnitDBMeta.dcsVersion or "?"))
  add(lines, string_format("Recognised %d red and %d blue air-defence groups.", counts.red, counts.blue))
  for _, site in ipairs(M.sites) do
    local parts = {}
    for _, role in ipairs(U.keys(site.roles)) do
      parts[#parts + 1] = string_format("%dx %s", site.roles[role], role)
    end
    add(lines, string_format("  [%s] %s -> %s (%s)", U.coalitionName[site.coalition], site.name, site.roleWord, U.join(parts)))
    for _, p in ipairs(site.problems) do
      add(lines, string_format("    PROBLEM: %s %s", site.name, p))
    end
    for _, n in ipairs(site.notes) do
      add(lines, string_format("    note: %s", n))
    end
  end
  if #unrecognised > 0 then
    add(lines, string_format("%d group(s) contain air-defence units but do not start with a role word, so Janus ignores them:", #unrecognised))
    for _, u in ipairs(unrecognised) do
      if u.suggest then
        add(lines, string_format("  [%s] '%s' (%d AD units) - did you mean '%s %s'?", u.coalition, u.name, u.n, u.suggest, u.name))
      else
        add(lines, string_format("  [%s] '%s' (%d AD units)", u.coalition, u.name, u.n))
      end
    end
  end
  local dlcs = {}
  for _, site in ipairs(M.sites) do
    if site.dlc then dlcs[site.dlc] = true end
  end
  for _, d in ipairs(U.keys(dlcs)) do
    add(lines, string_format("This mission uses DCS: %s units: say so in the briefing, players without the DLC cannot join.", d))
  end
  M.report = lines
  M.unrecognised = unrecognised
  return M.sites
end

-- Write the report to dcs.log (and to screen in CHECK_MODE).
function M.printReport()
  for _, line in ipairs(M.report) do M.info("setup", line) end
  if S.CHECK_MODE and trigger and trigger.action and trigger.action.outText then
    trigger.action.outText(U.join(M.report, "\n"), 30)
  end
end

-- Start Janus. opts (optional): { red = "DOCTRINE", blue = "DOCTRINE" }
function M.start(opts)
  if M.started then
    M.warn("setup", "JANUS.start() called twice; ignored")
    return
  end
  opts = opts or {}
  S.RED_DOCTRINE = opts.red or S.RED_DOCTRINE
  S.BLUE_DOCTRINE = opts.blue or S.BLUE_DOCTRINE
  M.started = true
  M.safe("setup.scan", M.scan)
  M.safe("setup.report", M.printReport)
  M.startEvents()
  -- Phase modules, in dependency order. Each is optional so a partial build still runs.
  for _, mod in ipairs({ "net", "tracks", "emcon", "debugview" }) do
    if M[mod] and M[mod].start then M.safe("setup.start." .. mod, M[mod].start) end
  end
  M.startScheduler()
  M.info("setup", string_format("started: red doctrine %s, blue doctrine %s, %d sites",
    tostring(type(S.RED_DOCTRINE) == "table" and "custom" or S.RED_DOCTRINE),
    tostring(type(S.BLUE_DOCTRINE) == "table" and "custom" or S.BLUE_DOCTRINE), #M.sites))
end

-- Autostart (zero-code install): ~1 s after the file loads, unless the settings file says not to.
if S.AUTOSTART and timer and timer.scheduleFunction then
  timer.scheduleFunction(M.wrap("setup.autostart", function() M.start() end), nil, M.now() + S.AUTOSTART_DELAY)
end
