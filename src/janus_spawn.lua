-- Janus IADS - spawning a battery from its real-world preset (DESIGN 4.9, Phase 4), on ground flat enough to fire.
--
--   JANUS.spawnBattery(preset, point [, opts]) -> group name, info   |   nil, error
--     preset  a key of JANUS.Presets ("SA-6", "PATRIOT", "HAWK", ...)
--     point   { x, z } (or { x, y } with y = map z, as the Mission Editor gives it): where to look for a site
--     opts    coalition 1 red / 2 blue (default 1); country (DCS country id; default Russia / USA); label (name after
--             the role word, default "<preset> <n>"); tier "GRN" / "REG" / "VET" / "ACE" (default REG; sets the DCS
--             skill too); heading (degrees, default 0); full = true (optional units too: trucks, extra launchers);
--             aaa = true (the preset's gun ring as its own "AAA ..." group); search (m, default 5000): how far from
--             `point` to look; maxSlope (degrees): steepest ground accepted, default the probe-measured limit of the
--             battery's units (SLOPE_LIMITS, e.g. Hawk 2, SA-2 3) or 8 for units with none; tags (extra name tags,
--             e.g. "[net:North]")
--   A preset with a unit type this DCS install lacks (paid DLC such as the WWII Assets Pack not owned) is refused.
--   Naval presets (CSG-USN, SAG-RU) spawn as a ship group on open water (no slope test), never with a gun ring.
--   The group is named "<SAM|PD|AAA|EW|SHIP> <label> <tier>" ("<label> #2" etc. if that name is taken) so Janus picks it up like any other (S_EVENT_BIRTH).
--   info = { x, z, slope (worst under any unit), limit, units, aaa = name of the gun group or nil }
-- Layout: the fire-control (or search) radar at the centre, launchers on the preset's ring, units with a spacing
-- off to the side, everything else (command post, power, trucks) behind it.

JANUS = JANUS or {}
local M = JANUS

local SP = {}
M.spawn = SP

local string_format = string.format
local math_cos, math_sin, math_rad, math_pi = math.cos, math.sin, math.rad, math.pi
local ipairs = ipairs

SP.seq = 0
SP.DEFAULT_SLOPE = 8          -- units the probes found no limit for (SA-6 / SA-11 / Patriot fired on 10-26 deg ground)
SP.STEP = 250                 -- spiral search step (m)
local SKILL = { GRN = "Average", REG = "Good", VET = "High", ACE = "Excellent" }
SP.SKILL = SKILL
-- which unit stands at the centre: the first listed unit of the earliest role here
SP.CENTRE_ORDER = { "TR", "STR", "SR", "SHORAD", "CRAM", "AAA_FC", "AAA", "EWR" }
local CENTRE_ROLES = {}
for i, r in ipairs(SP.CENTRE_ORDER) do CENTRE_ROLES[r] = i end

local function countOf(u, full)
  local c = u.count
  if type(c) == "table" then
    return full and c[2] or c[1]     -- the minimum (0 for optional units) unless `full`
  end
  return c or 1   -- mutate: ok every preset unit lists a count
end

-- the Janus role (key of settings ROLE_WORDS) the preset's group gets
local function roleWord(preset)
  local has = {}
  for _, u in ipairs(preset.units) do has[u.role] = true end
  if has.NAVAL_AD then return "SHIP" end
  if has.LN or has.TELAR or has.TR or has.STR then return "SAM" end
  if has.SHORAD or has.CRAM then return "PD" end
  if has.AAA then return "AAA" end
  return "EW"
end
SP.roleWord = roleWord

-- unit offsets (x north, z east) before rotation, from the preset
function SP.layout(preset, full)
  local out = {}
  local centre, cRank
  for i, u in ipairs(preset.units) do
    local r = CENTRE_ROLES[u.role]
    if r and countOf(u, full) > 0 and (not cRank or r < cRank) then centre, cRank = i, r end
  end
  local side, back = 0, 0
  for i, u in ipairs(preset.units) do
    local n = countOf(u, full)
    for k = 1, n do
      local dx, dz
      if i == centre and k == 1 then
        dx, dz = 0, 0
      elseif u.ring then
        local a = 2 * math_pi * (k - 1) / n
        dx, dz = u.ring * math_cos(a), u.ring * math_sin(a)
      elseif u.spacing then
        side = side + 1
        dx, dz = 40 * side, u.spacing * k                       -- off to the east, one spacing apart
      else
        back = back + 1
        dx, dz = -60 - 40 * back, 30 * ((back % 3) - 1)         -- behind the centre (south), staggered
      end
      out[#out + 1] = { type = u.type, dx = dx, dz = dz, role = u.role }
    end
  end
  return out
end

local function rotate(dx, dz, hdg)
  local c, s = math_cos(hdg), math_sin(hdg)
  return dx * c - dz * s, dx * s + dz * c
end

-- worst slope under every unit and whether all of them stand on land, for a centre at (x, z)
local function siteSlope(units, x, z, hdg, surface)
  local worst = 0
  for _, u in ipairs(units) do
    local ox, oz = rotate(u.dx, u.dz, hdg)
    local p = { x = x + ox, z = z + oz }
    if land.getSurfaceType({ x = p.x, y = p.z }) ~= surface then return nil end
    local s = surface == land.SurfaceType.LAND and M.slopeAt(p) or 0
    if s > worst then worst = s end
  end
  return worst
end

function SP.limitFor(units, opts)
  if opts.maxSlope then return opts.maxSlope end
  local lim
  for _, u in ipairs(units) do
    local l = M.SLOPE_LIMITS[u.type]
    if l and (not lim or l < lim) then lim = l end
  end
  return lim or SP.DEFAULT_SLOPE
end

-- spiral out from (x, z) in SP.STEP rings; the first centre whose every unit is on land within the limit
function SP.findSite(units, x, z, hdg, limit, search, surface)
  surface = surface or land.SurfaceType.LAND
  local s0 = siteSlope(units, x, z, hdg, surface)
  if s0 and s0 <= limit then return x, z, s0 end
  for ring = 1, math.floor(search / SP.STEP) do
    local n = ring * 6
    for i = 1, n do
      local a = (i / n) * 2 * math_pi
      local cx, cz = x + ring * SP.STEP * math_cos(a), z + ring * SP.STEP * math_sin(a)
      local s = siteSlope(units, cx, cz, hdg, surface)
      if s and s <= limit then return cx, cz, s end
    end
  end
  return nil
end

-- a one-point route (stand still), as the Mission Editor writes for a parked group
local function route(x, z, naval)
  return { points = { { x = x, y = z, type = "Turning Point", action = naval and "Turning Point" or "Off Road", speed = 0,
    task = { id = "ComboTask", params = { tasks = {} } } } } }
end

local function groupUnits(name, units, x, z, hdg, skill)
  local out = {}
  for i, u in ipairs(units) do
    local ox, oz = rotate(u.dx, u.dz, hdg)
    out[i] = { name = string_format("%s-%d", name, i), type = u.type, skill = skill, x = x + ox, y = z + oz,
               heading = hdg, playerCanDrive = false }
  end
  return out
end

function M.spawnBattery(presetName, point, opts)
  opts = opts or {}
  local preset = M.Presets and M.Presets[presetName]
  if not preset then return nil, "unknown preset " .. tostring(presetName) end
  if not (point and point.x and (point.z or point.y)) then return nil, "no point" end
  -- a type this DCS install does not have (paid DLC not owned): refuse rather than spawn a hole in the battery
  if Unit.getDescByName then
    for _, u in ipairs(preset.units) do
      local okD, desc = pcall(Unit.getDescByName, u.type)
      if not (okD and desc) then
        return nil, string_format("%s: unit type %s is not installed%s", presetName, u.type,
          preset.requires and (" (needs " .. table.concat(preset.requires, ", ") .. ")") or "")
      end
    end
  end
  local coa = opts.coalition or 1
  local ctry = opts.country or (coa == 2 and country.id.USA or country.id.RUSSIA)
  local tier = opts.tier and SKILL[opts.tier] and opts.tier or "REG"
  local hdg = math_rad(opts.heading or 0)
  local units = SP.layout(preset, opts.full)
  local role = roleWord(preset)
  local naval = role == "SHIP"
  local limit = SP.limitFor(units, opts)
  local x, z, s = SP.findSite(units, point.x, point.z or point.y, hdg, limit, opts.search or 5000,
    naval and land.SurfaceType.WATER or land.SurfaceType.LAND)
  if not x then
    if naval then return nil, string_format("%s: no open water within %d m for it", presetName, opts.search or 5000) end
    return nil, string_format("%s: no ground within %d m flat enough (%.1f deg) for it", presetName,
      opts.search or 5000, limit)
  end
  SP.seq = SP.seq + 1
  local label = opts.label or string_format("%s %d", presetName, SP.seq)
  local function nameFor(l)
    return string_format("%s %s %s%s", M.settings.ROLE_WORDS[role], l, tier, opts.tags and (" " .. opts.tags) or "")
  end
  local name = nameFor(label)
  -- DCS replaces an existing group of the same name without a word: never do that to a mission maker's group
  local copy = 1
  while Group.getByName(name) do
    copy = copy + 1
    name = nameFor(string_format("%s #%d", label, copy))
  end
  if copy > 1 then label = string_format("%s #%d", label, copy) end
  local ok, err = pcall(coalition.addGroup, ctry, naval and Group.Category.SHIP or Group.Category.GROUND,
    { name = name, task = "Ground Nothing", units = groupUnits(name, units, x, z, hdg, SKILL[tier]), route = route(x, z, naval) })
  if not ok then return nil, "spawn failed: " .. tostring(err) end
  local info = { x = x, z = z, slope = s, limit = limit, units = #units }
  M.info("spawn", string_format("%s spawned as '%s' (%d units) %.0f m from the point asked, worst slope %.1f deg (limit %.1f)",
    presetName, name, #units, math.sqrt((x - point.x) ^ 2 + (z - (point.z or point.y)) ^ 2), s, limit))
  if opts.aaa and preset.aaa_ring and not naval then
    local guns = {}
    for _, g in ipairs(preset.aaa_ring) do
      local n = g.count or 1   -- mutate: ok every ring entry lists a count
      for k = 1, n do
        local a = 2 * math_pi * (k - 0.5) / n
        local r = g.ring or 100
        guns[#guns + 1] = { type = g.type, dx = r * math_cos(a), dz = r * math_sin(a) }
      end
    end
    local gname = string_format("%s %s guns %s%s", M.settings.ROLE_WORDS.AAA, label, tier, opts.tags and (" " .. opts.tags) or "")
    local okG = pcall(coalition.addGroup, ctry, Group.Category.GROUND,
      { name = gname, task = "Ground Nothing", units = groupUnits(gname, guns, x, z, hdg, SKILL[tier]), route = route(x, z) })
    if okG then info.aaa = gname end
  end
  return name, info
end
