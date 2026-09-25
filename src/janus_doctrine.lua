-- Janus IADS - doctrine profiles (data, not code). Phase 1 fields: network links, power, autonomy, EMCON.
-- Later phases add the ARM response ladder, WTA and ROE fields to the same tables.
-- Mission makers can copy a profile, change values and pass it as RED_DOCTRINE / BLUE_DOCTRINE (a table) in
-- janus_settings.lua, or name one of these profiles.
--
-- Field reference (all distances in metres, all times in seconds):
--   linkRange        a node (EW, battery...) connects to a command post or relay within this distance
--   relayRange       command posts and relays connect to each other within this distance
--   powerRange       a POWER node powers nodes within this distance (or name it with [power:Name])
--   powerReserve     how long a node keeps running after its last power source dies
--   autonomyDelay    per crew tier: how long after losing its link to command a node waits before acting alone
--   cueDelay         per crew tier: reaction time between a network cue and the radar coming up
--   cueFactor        a battery is cued when a network track is inside engagement range x cueFactor
--   cueHold          a cued radar stays up this long after the last track leaves
--   emcon            policy per node kind while linked to command:
--                      "always" (emit all the time), "dark" (never emit), "cued" (emit when the network cues it),
--                      "periodic" (emit on/off on a timer), "rotating" (EW radars take turns)
--   autonomous       policy a node falls back to when it has lost command or has no EW cover
--   periodic         { on = s, off = s } for the "periodic" policy
--   rotating         { share = fraction of EW radars up at once, period = s }
--   restart          per range class, the Janus restart time after a radar goes dark (DESIGN 4.5B; DCS itself
--                    switches instantly, so without this rule a site could dodge every ARM)
--   restartByType    per DCS unit type overrides of restart
--   minOn            once up, a radar stays up at least this long (stops flicker)

JANUS = JANUS or {}
local M = JANUS

local TIER = function(grn, reg, vet, ace) return { GRN = grn, REG = reg, VET = vet, ACE = ace } end

local BASE = {
  linkRange = 120000, relayRange = 80000, powerRange = 8000, powerReserve = 300,
  autonomyDelay = TIER(180, 120, 60, 30),
  cueDelay = TIER(12, 6, 3, 2),
  cueFactor = 1.3, cueHold = 30, minOn = 15,
  emcon = { EW = "always", BATTERY = "cued", PD = "cued", AAA = "always", NAVAL = "always", C2 = "always" },
  autonomous = { EW = "always", BATTERY = "periodic", PD = "periodic", AAA = "always", NAVAL = "always", C2 = "always" },
  periodic = { on = 20, off = 40 },
  rotating = { share = 0.5, period = 120 },
  restart = { LR = 10, MR = 8, SR = 5, NONE = 5 },
  restartByType = { ["RPC_5N62V"] = 25, ["SNR_75V"] = 10, ["snr s-125 tr"] = 10 },
}

local function derive(base, changes)
  local out = {}
  for k, v in pairs(base) do
    if type(v) == "table" then
      local t = {}
      for k2, v2 in pairs(v) do t[k2] = v2 end
      out[k] = t
    else
      out[k] = v
    end
  end
  for k, v in pairs(changes) do
    if type(v) == "table" and type(out[k]) == "table" then
      for k2, v2 in pairs(v) do out[k][k2] = v2 end
    else
      out[k] = v
    end
  end
  return out
end
M.deriveDoctrine = derive

M.Doctrines = {
  -- Centralised control, strict EMCON: EW always up, SAMs dark until the command post cues them, slow to act alone.
  SOVIET_PVO_1985 = derive(BASE, {
    name = "SOVIET_PVO_1985",
    autonomyDelay = TIER(300, 180, 120, 60),
    autonomous = { BATTERY = "periodic", PD = "periodic" },
    periodic = { on = 15, off = 60 },
  }),
  -- Faster autonomy, EW radars rotate to spread their exposure, point defence stays close to always-on.
  RUSSIA_MODERN = derive(BASE, {
    name = "RUSSIA_MODERN",
    autonomyDelay = TIER(120, 60, 30, 20),
    cueDelay = TIER(8, 4, 2, 1),
    emcon = { EW = "rotating", PD = "cued" },
    rotating = { share = 0.5, period = 90 },
    periodic = { on = 20, off = 30 },
  }),
  -- Delegated authority: batteries act on their own sooner; AWACS-led picture.
  NATO_COLDWAR = derive(BASE, {
    name = "NATO_COLDWAR",
    autonomyDelay = TIER(90, 60, 30, 20),
    autonomous = { BATTERY = "periodic", PD = "always" },
  }),
  -- Data-linked picture, fast reactions, point defence always up around protected assets.
  US_MODERN = derive(BASE, {
    name = "US_MODERN",
    autonomyDelay = TIER(60, 30, 20, 10),
    cueDelay = TIER(6, 3, 2, 1),
    emcon = { PD = "always" },
    autonomous = { BATTERY = "periodic", PD = "always" },
    periodic = { on = 30, off = 30 },
  }),
  -- North Vietnam 1965-72: Fan Song emits for seconds only, sites cued by early warning, AAA always ready.
  NVA_VIETNAM_1965_72 = derive(BASE, {
    name = "NVA_VIETNAM_1965_72",
    cueFactor = 1.0, cueHold = 15, minOn = 8,
    autonomyDelay = TIER(240, 150, 90, 60),
    periodic = { on = 10, off = 60 },
  }),
  -- US Vietnam era: Hawk batteries defending airbases, simple procedural control.
  US_VIETNAM_1965_72 = derive(BASE, {
    name = "US_VIETNAM_1965_72",
    emcon = { BATTERY = "always" },
    autonomous = { BATTERY = "always" },
  }),
  -- Poor coordination: radars left on, slow reactions.
  GENERIC_THIRD_WORLD = derive(BASE, {
    name = "GENERIC_THIRD_WORLD",
    cueDelay = TIER(20, 12, 8, 5),
    autonomyDelay = TIER(400, 300, 200, 120),
    emcon = { BATTERY = "always", PD = "always" },
    autonomous = { BATTERY = "always", PD = "always" },
  }),
}

-- Resolve a doctrine setting (profile name or table) to a full profile. Unknown names fall back with a warning.
function M.getDoctrine(nameOrTable, fallback)
  if type(nameOrTable) == "table" then
    local base = M.Doctrines[nameOrTable.base or fallback or "SOVIET_PVO_1985"] or M.Doctrines.SOVIET_PVO_1985
    local d = derive(base, nameOrTable)
    d.name = nameOrTable.name or ("custom:" .. tostring(base.name))
    return d
  end
  local d = M.Doctrines[nameOrTable or ""]
  if d then return d end
  if M.warn then M.warn("doctrine", "unknown doctrine '" .. tostring(nameOrTable) .. "', using " .. tostring(fallback)) end
  return M.Doctrines[fallback or "SOVIET_PVO_1985"] or M.Doctrines.SOVIET_PVO_1985
end
