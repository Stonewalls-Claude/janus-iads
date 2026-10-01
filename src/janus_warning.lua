-- Janus IADS - base warning (DESIGN 4.8, Phase 5; off unless BASE_WARNING = true). A site with C-RAM, or any site
-- tagged [warn], is a protected place. When an enemy bomb, rocket, shell or air-to-ground missile comes within
-- BASE_WARNING_RANGE of it, Janus tells that side "INCOMING" (text, plus BASE_WARNING_SOUND if set), once per
-- BASE_WARNING_COOLDOWN seconds per place. The place is named after the nearest airbase within 15 km, else the site.
-- Air-to-air and surface-to-air missiles are ignored (they are after aircraft, not the base).

JANUS = JANUS or {}
local M = JANUS
local S = M.settings

local BW = {}
M.warning = BW

local string_format = string.format
local ipairs = ipairs

BW.NAME_RANGE = 15000
BW.weapons = {}      -- { w, coalition }
BW.lastWarn = {}     -- [siteName] = time

local function protected(n)
  if n.site.tags.warn then return true end
  for _, u in ipairs(n.site.units or {}) do
    if u.rec and u.rec.role == "CRAM" then return true end
  end
  return false
end

local function placeName(n)
  if n.placeName then return n.placeName end
  local best, bestD
  for _, ab in ipairs(world.getAirbases() or {}) do
    local okP, p = pcall(ab.getPoint, ab)
    if okP and p then   -- mutate: ok defensive: DCS airbases always have a point
      local dx, dz = p.x - n.pos.x, p.z - n.pos.z
      local d = dx * dx + dz * dz
      if d <= BW.NAME_RANGE * BW.NAME_RANGE and (not bestD or d < bestD) then
        local okN, name = pcall(ab.getName, ab)
        if okN then best, bestD = name, d end
      end
    end
  end
  n.placeName = best or n.site.label or n.name
  return n.placeName
end

-- weapons aimed at aircraft are not the base's business
local function groundWeapon(w)
  local ok, d = pcall(w.getDesc, w)
  if not (ok and d) then return false end   -- mutate: ok defensive: DCS weapons always have a description
  if d.category == Weapon.Category.MISSILE then
    return d.missileCategory ~= Weapon.MissileCategory.AAM and d.missileCategory ~= Weapon.MissileCategory.SAM
  end
  return true
end

function BW.onShot(e)
  local w, u = e.weapon, e.initiator
  if not (w and u) then return end
  local okC, coa = pcall(u.getCoalition, u)
  if okC and groundWeapon(w) then BW.weapons[#BW.weapons + 1] = { w = w, coalition = coa } end
end

function BW.tick()
  local now = M.now()
  local r2 = S.BASE_WARNING_RANGE * S.BASE_WARNING_RANGE
  local sites = {}
  for _, n in ipairs(M.net.list) do
    if n.alive and n.pos and protected(n) then sites[#sites + 1] = n end
  end
  for i = #BW.weapons, 1, -1 do
    local e = BW.weapons[i]
    local okE, ex = pcall(e.w.isExist, e.w)
    if not (okE and ex) then
      table.remove(BW.weapons, i)
    else
      local p = e.w:getPoint()
      for _, n in ipairs(sites) do
        if n.net.coalition ~= e.coalition then
          local dx, dz = p.x - n.pos.x, p.z - n.pos.z
          if dx * dx + dz * dz <= r2 and not (e.warned and e.warned[n.name])
            and now - (BW.lastWarn[n.name] or -1e9) >= S.BASE_WARNING_COOLDOWN then
            e.warned = e.warned or {}
            e.warned[n.name] = true   -- one weapon warns a place once
            BW.lastWarn[n.name] = now
            local place = placeName(n)
            trigger.action.outTextForCoalition(n.net.coalition, string_format("INCOMING! %s - take cover", place), 10)
            if S.BASE_WARNING_SOUND and S.BASE_WARNING_SOUND ~= "" then
              trigger.action.outSoundForCoalition(n.net.coalition, S.BASE_WARNING_SOUND)
            end
            M.info("warning", string_format("%s INCOMING at %s (%s, %s)", n.net.key, place, n.name, tostring(e.w:getTypeName())))
          end
        end
      end
    end
  end
end

function BW.start()
  if not S.BASE_WARNING then return end
  M.on(world.event.S_EVENT_SHOT, "warning.shot", BW.onShot)
  M.every("warning.tick", 1, BW.tick, 1)   -- mutate: ok cadence
end
