-- Janus IADS - demo layout probe (Phase 5). Not a test of DCS behaviour: it lets JANUS.spawnBattery place every SAM,
-- EW, gun and ship group of the four demo missions on flat ground on the real Syria terrain, then logs every unit's
-- absolute position so tools/build_demos.py can write them into the demo .miz files as ordinary Mission Editor groups
-- (mission makers copy groups from the demos, so they must be ME groups, not script spawns).
-- Load order: janus.lua -> this file. Logs "JANUS_DEMO" lines; ends with "DEMO LAYOUT COMPLETE".
-- Lua 5.1, sanitized. Globals: JANUS (shared namespace).

JANUS = JANUS or {}
local TAG = "JANUS_DEMO"
local string_format = string.format

local function log(msg) env.info(TAG .. " " .. msg) end

local AB = {}
for _, ab in ipairs(world.getAirbases() or {}) do
  local ok, name = pcall(ab.getName, ab)
  local okP, p = pcall(ab.getPoint, ab)
  if ok and okP and name and p then
    AB[name] = p
    log(string_format("AIRBASE %s|%.1f|%.1f|%.1f", name, p.x, p.z, p.y))
  end
end

-- { demo side, preset, anchor airbase, dx (north, m), dz (east, m), opts }
local SITES = {
  { "RED", "EW-SOVIET", "Hama", 40000, 0, { label = "North", tier = "VET" } },
  { "RED", "EW-SOVIET", "Hama", 0, 45000, { label = "East" } },
  { "RED", "SA-10", "Hama", 15000, 0, { label = "SA-10 Hama", tier = "VET" } },
  { "RED", "SA-15", "Hama", 17000, 2500, { label = "Tor Hama", tier = "VET" } },
  { "RED", "SA-6", "Hama", -40000, 10000, { label = "SA-6 Homs" } },
  { "RED", "SA-11", "Hama", -10000, 35000, { label = "SA-11 Salamiyah" } },
  { "RED", "SA-2", "Hama", 0, -30000, { label = "SA-2 Hama West", tier = "GRN", aaa = true } },
  { "RED", "SA-3", "Hama", 5000, -45000, { label = "SA-3 Masyaf" } },
  { "BLUE", "EW-NATO", "Incirlik", 15000, 15000, { label = "FPS-117 Incirlik", coalition = 2 } },
  { "BLUE", "PATRIOT", "Incirlik", 5000, -8000, { label = "Patriot Incirlik", coalition = 2, tier = "VET" } },
  { "BLUE", "HAWK", "Incirlik", -10000, -35000, { label = "Hawk Adana", coalition = 2 } },
  { "BLUE", "NASAMS", "Incirlik", -6000, 6000, { label = "NASAMS Incirlik", coalition = 2 } },
  { "BLUE", "C-RAM", "Incirlik", 0, 1500, { label = "C-RAM Incirlik", coalition = 2, search = 3000 } },
  { "BLUE", "AVENGER", "Incirlik", -1500, 0, { label = "Avenger Incirlik", coalition = 2, search = 3000 } },
  { "NAVAL", "CSG-USN", "Bassel Al-Assad", 0, -60000, { label = "Ike", coalition = 2, search = 40000, tags = "[net:CSG]" } },
  { "NAVAL", "SAG-RU", "Bassel Al-Assad", 60000, -90000, { label = "Moskva", coalition = 1, search = 40000 } },
}

local function dump(side, groupName, coa)
  local g = Group.getByName(groupName)
  if not g then log("MISSING " .. groupName); return end
  local cat = g:getCategory()
  for i, u in ipairs(g:getUnits() or {}) do
    local p = u:getPoint()
    log(string_format("UNIT %s|%d|%d|%s|%d|%s|%.1f|%.1f|%.2f", side, coa, cat, groupName, i, u:getTypeName(), p.x, p.z,
      land.getHeight({ x = p.x, y = p.z })))
  end
end

timer.scheduleFunction(JANUS.wrap("demo.layout", function()
  local ok, err = pcall(function()
    for _, s in ipairs(SITES) do
      local side, preset, anchor, dx, dz, opts = s[1], s[2], s[3], s[4], s[5], s[6]
      local a = AB[anchor]
      if not a then
        log("NO AIRBASE " .. anchor)
      else
        local name, info = JANUS.spawnBattery(preset, { x = a.x + dx, z = a.z + dz }, opts)
        if name then
          log(string_format("SITE %s|%s|%s|%.0f|%.0f|%.2f|%.1f|%s", side, preset, name, info.x, info.z, info.slope, info.limit,
            info.aaa or ""))
          dump(side, name, opts.coalition or 1)
          if info.aaa then dump(side, info.aaa, opts.coalition or 1) end
        else
          log(string_format("FAILED %s|%s|%s", side, preset, tostring(info)))
        end
      end
    end
  end)
  if not ok then env.error(TAG .. " error: " .. tostring(err)) end
  log("DEMO LAYOUT COMPLETE")
  return nil
end), nil, timer.getTime() + 3)
log("demo layout probe loaded")
