-- Janus IADS - AAA fire discipline (Phase 4 AAA; the Vietnam / Kari profiles that use flak traps are Phase 6). Guns ("AAA ..." groups) follow the doctrine's
-- `aaa.mode`:
--   "free"  DCS default: the crews fire at whatever they see (every shipped profile today).
--   "trap"  flak trap: the guns hold fire (ROE WEAPON_HOLD) until an enemy aircraft the crew knows of (network
--           picture while linked, EW plots after command loss, the battery's own fire-control radar) is inside
--           trapFactor x the gun's reach and below its ceiling; then they open fire together and keep firing until
--           `hold` s after the last target left. A gun site with no picture at all (unlinked, no EW feed, no radar)
--           fires at will: it would otherwise never fire.
-- Emission of radar-directed guns (SON-9, Shilka) stays with EMCON.

JANUS = JANUS or {}
local M = JANUS

local AA = {}
M.aaa = AA

local string_format = string.format
local pairs, ipairs = pairs, ipairs

AA.INTERVAL = 1   -- mutate: ok cadence

local function up(n) return n.alive and n.working and n.powered end   -- mutate: ok a dead node is never working

-- gun reach and ceiling from the unit data (largest gun in the group)
function AA.reach(n)
  if n.aaaReach then return n.aaaReach, n.aaaCeiling end
  local r, c = 0, 0   -- mutate: ok every gun has a reach above 1 m
  for _, u in ipairs(n.site.units) do
    local rec = u.rec
    if (rec.threatRange or 0) > r then r = rec.threatRange end   -- mutate: ok every gun lists a range
    local e = rec.envelope
    local alt = e and e.altMax or (rec.threatRange or 0)   -- mutate: ok every gun lists a range   -- no envelope: assume it reaches as high as it reaches far
    if alt > c then c = alt end
  end
  n.aaaReach, n.aaaCeiling = r, c
  return r, c
end

-- nearest known enemy aircraft inside the trap (range and ceiling), or nil
local function inTrap(n, d)
  local reach, ceiling = AA.reach(n)
  local r = reach * d.trapFactor
  local r2 = r * r
  local found
  local function scan(pic)
    for _, tr in pairs(pic or {}) do
      local p = tr.pos
      if p then
        local dx, dz = p.x - n.pos.x, p.z - n.pos.z
        if dx * dx + dz * dz <= r2 and (p.y or 0) - (n.pos.y or 0) <= ceiling then found = tr end   -- mutate: ok points carry y
      end
    end
  end
  if n.linked then scan(n.net.tracks) end
  for _, f in ipairs(n.feeders or {}) do scan(f.localTracks) end
  scan(n.localTracks)
  return found
end

local function hasPicture(n)
  return n.linked or (n.feeders ~= nil and #n.feeders > 0) or n.hasRadar
end

local function setRoe(n, open, why)
  local s = n.aaa
  if s.open == open then return end
  s.open = open
  local g = n.site.group
  local c = g and g:isExist() and g:getController()
  if c then
    local O = AI.Option.Ground
    M.safe("aaa.roe", c.setOption, c, O.id.ROE, open and O.val.ROE.OPEN_FIRE or O.val.ROE.WEAPON_HOLD)
  end
  M.info("aaa", string_format("%s %s %s (%s)", n.net.key, n.name, open and "OPEN FIRE" or "holds fire", why))
end

function AA.tick()
  local now = M.now()
  for _, n in ipairs(M.net.list) do
    if n.kind == "AAA" and n.pos then
      local d = n.net.doctrine.aaa
      n.aaa = n.aaa or {}
      local s = n.aaa
      if not (d and d.mode == "trap") then
        if s.open == false then setRoe(n, true, "fire at will") end
      elseif not up(n) then
        s.lastTarget = nil
      elseif not hasPicture(n) then
        setRoe(n, true, "no picture: fire at will")
      else
        local tr = inTrap(n, d)
        if tr then
          s.lastTarget = now
          setRoe(n, true, "flak trap: " .. M.tracks.label(tr))
        elseif s.open == nil or (s.open and now - (s.lastTarget or -1e9) > d.hold) then
          setRoe(n, false, s.open == nil and "flak trap set" or "trap reset")
        end
      end
    end
  end
end

function AA.start()
  AA.tick()
  M.every("aaa.tick", AA.INTERVAL, AA.tick, 1)   -- mutate: ok first-tick offset
end
