-- Janus IADS - doctrine profiles (data, not code). Fields: network links, power, autonomy, EMCON, backup links,
-- air-ground radios, alternate command posts, identification time, weapon-target assignment.
-- Phase 3: the ARM defence fields (`arm`).
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
--   periodicByType   per DCS unit type: the policy used instead of "periodic" for systems that cannot engage in a
--                    short radar window (the Hawk)
--   c2LossCue        how early warning still reaches batteries that have lost their command post (DESIGN 8A):
--                      mode  "datalink" (the picture keeps flowing, e.g. Link 16), "voice" (plots passed by
--                            radio/telephone from a nearby EW radar), or "none" (only the battery's own radar)
--                      range an EW radar within this distance of the battery (and seeing that far) can feed it
--                      delay per crew tier: extra reaction time on top of cueDelay for a cue that comes this way
--   linkBackup       relays gone (DESIGN 4.1A): a node within `range` of a working command post stays linked over the
--                    backup channel (field telephone, HF, a self-healing datalink); `delay` per tier is added to cues
--   agRange          an air-ground radio ("COMMS ... [ag]") belongs to the command post within this distance
--                    (or the one named by [cmd:Name])
--   agBackup         mode "backup" (a short-range backup set) or "none" when all of a post's air-ground radios are down
--   altTakeover      per crew tier: how long an alternate command post ([alt:Name] on the main post) takes to take over
--   idTime           per crew tier: a track held this long by the linked network is identified even when no sensor
--                    reports the aircraft type (probe run 6: ground EW radars never do; AWACS and SA-6/SA-11 do)
--   fighterControl   who controls fighters (for a GCI script reading JANUS.gci, DESIGN 4.10): "ground" (command
--                    posts; AWACS mainly a flying radar) or "aew" (AWACS controllers under the CRC's authority)
--   awacsTakeover    true: an airborne command node takes over as senior controller when its parent post is lost
--   agReach          how far an air-ground radio reaches (m); the backup set reaches agBackup.range
--   wta              weapon-target assignment (DESIGN 4.3): enabled; pkGoal = combined kill probability wanted per
--                    target; maxShooters per target; pdDiscount = weight on point-defence bids; handoffMargin = how much
--                    better a new shooter must be before a target is handed over; minPk = below this nobody is
--                    assigned; lead = seconds ahead a target is judged at (so the radar is up in time)
--   arm              anti-radiation missile defence (DESIGN 4.5, janus_arm.lua):
--                      enabled; confirmScans sightings within confirmWindow s confirm a radar sighting (eyes or two
--                      sensors confirm at once); netDelay per tier: a confirmed ARM reaches linked nodes this late;
--                      reaction per tier: crew reaction before acting; cone: a missile heading within this many
--                      degrees of a radar threatens it; margin: s added to the estimated time to impact;
--                      predictErr per tier: +- fraction error of that estimate; minDark: shortest dark time (per-type
--                      table in janus_arm.lua overrides); maxDark: longest; afterMax "restart" (come back) or "wait"
--                      (stay dark while a SEAD aircraft stays nose-on); pdEngage: point defence / Tor-class sites
--                      stay up and fight; trustPd: a site covered by point defence within pdCoverRange stays up;
--                      finishShot/finishMargin: a site with its own missile in flight stays up while the ARM is
--                      more than finishMargin s away; accept: every site accepts the hit (or tag a site [hold]);
--                      suspicion per tier: chance per second that an identified SEAD aircraft nose-on within
--                      shooterRange (shooterCone degrees) sends an emitting radar dark for suspectDark s;
--                      observers: { range, smokeRange } = ground observers at every site see ARMs by eye in daylight
--                      (NVA spotters; without it only optical units do)
--   aaa              gun fire discipline (janus_aaa.lua): mode "free" (fire at will) or "trap" (flak trap: hold fire
--                    until a known target is inside trapFactor x the gun's reach, keep firing `hold` s after it left)

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
  c2LossCue = { mode = "voice", range = 40000, delay = TIER(60, 40, 30, 20) },
  -- DCS types whose tracking radar cannot acquire, lock and launch inside a short periodic window use this policy
  -- instead of "periodic" (probe run 4: a Hawk cycled 15 s on / 60 s off never fired, even with targets overhead).
  periodicByType = { ["Hawk tr"] = "always" },
  linkBackup = { range = 30000, delay = TIER(40, 25, 15, 10) },
  agRange = 15000,
  agBackup = { mode = "backup", range = 60000 },
  agReach = 300000,
  fighterControl = "ground", awacsTakeover = false,
  altTakeover = TIER(240, 150, 90, 60),
  idTime = TIER(150, 90, 60, 40),
  wta = { enabled = true, pkGoal = 0.7, maxShooters = 1, pdDiscount = 0.5, handoffMargin = 0.15, minPk = 0.15, lead = 40 },
  arm = { enabled = true, confirmScans = 3, confirmWindow = 10, netDelay = TIER(8, 5, 3, 2), reaction = TIER(6, 3, 2, 1),  -- mutate: ok tuning
          cone = 15, margin = 10, predictErr = TIER(0.3, 0.15, 0.1, 0.05), minDark = 20, maxDark = 180,  -- mutate: ok tuning
          afterMax = "restart", pdEngage = true, trustPd = false, pdCoverRange = 15000, finishShot = true,  -- mutate: ok tuning
          finishMargin = 15, accept = false, suspicion = TIER(0.02, 0.01, 0.005, 0), suspectDark = 30,  -- mutate: ok tuning
          shooterRange = 60000, shooterCone = 20 },  -- mutate: ok tuning
  aaa = { mode = "free", trapFactor = 0.7, hold = 20 },  -- mutate: ok tuning
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
    -- regimental CP gone: battalions fight on their own radar, radar companies still phone plots in
    c2LossCue = { mode = "voice", range = 60000, delay = TIER(90, 60, 45, 30) },
    linkBackup = { range = 40000, delay = TIER(60, 40, 25, 15) },
    altTakeover = TIER(300, 180, 120, 90),
    -- salvo doctrine: two battalions on a high-value target until the combined kill probability is high
    wta = { pkGoal = 0.85, maxShooters = 2 },
    -- dark on warning and wait out the SEAD aircraft; a command post orders it, so reactions are not quick
    arm = { afterMax = "wait", maxDark = 300, suspicion = TIER(0.04, 0.02, 0.01, 0.005) },  -- mutate: ok tuning
  }),
  -- Faster autonomy, EW radars rotate to spread their exposure, point defence stays close to always-on.
  RUSSIA_MODERN = derive(BASE, {
    name = "RUSSIA_MODERN",
    autonomyDelay = TIER(120, 60, 30, 20),
    cueDelay = TIER(8, 4, 2, 1),
    emcon = { EW = "rotating", PD = "cued" },
    rotating = { share = 0.5, period = 90 },
    periodic = { on = 20, off = 30 },
    c2LossCue = { mode = "voice", range = 80000, delay = TIER(45, 30, 20, 15) },
    linkBackup = { range = 60000, delay = TIER(30, 20, 12, 8) },
    altTakeover = TIER(150, 90, 60, 45),
    idTime = TIER(90, 60, 40, 30),
    wta = { pkGoal = 0.8, maxShooters = 2, pdDiscount = 0.6 },
    -- layered defence: Pantsir / Tor cover the long-range radars, which stay up under that cover
    arm = { trustPd = true, reaction = TIER(4, 2, 1, 1), netDelay = TIER(5, 3, 2, 1) },  -- mutate: ok tuning
  }),
  -- Delegated authority: batteries act on their own sooner; AWACS-led picture.
  NATO_COLDWAR = derive(BASE, {
    name = "NATO_COLDWAR", fighterControl = "aew", awacsTakeover = true,
    autonomyDelay = TIER(90, 60, 30, 20),
    autonomous = { BATTERY = "periodic", PD = "always" },
    c2LossCue = { mode = "datalink", range = 150000, delay = TIER(15, 10, 6, 4) },
    linkBackup = { range = 80000, delay = TIER(15, 10, 6, 4) },
    altTakeover = TIER(120, 60, 45, 30),
    idTime = TIER(90, 60, 40, 30),     -- IFF + procedural ID
  }),
  -- Data-linked picture, fast reactions, point defence always up around protected assets.
  US_MODERN = derive(BASE, {
    name = "US_MODERN", fighterControl = "aew", awacsTakeover = true,
    autonomyDelay = TIER(60, 30, 20, 10),
    cueDelay = TIER(6, 3, 2, 1),
    emcon = { PD = "always" },
    autonomous = { BATTERY = "periodic", PD = "always" },
    periodic = { on = 30, off = 30 },
    -- Link 16: the picture does not depend on one command post; engagement goes decentralized
    c2LossCue = { mode = "datalink", range = 250000, delay = TIER(8, 5, 3, 2) },
    linkBackup = { range = 150000, delay = TIER(8, 5, 3, 2) },
    altTakeover = TIER(60, 30, 20, 15),
    idTime = TIER(60, 40, 25, 20),     -- IFF, NCTR, fused picture
    arm = { reaction = TIER(4, 2, 1, 1), netDelay = TIER(3, 2, 1, 1), suspicion = TIER(0, 0, 0, 0) },  -- mutate: ok tuning
  }),
  -- North Vietnam 1965-72: Fan Song emits for seconds only, sites cued by early warning, AAA always ready.
  NVA_VIETNAM_1965_72 = derive(BASE, {
    name = "NVA_VIETNAM_1965_72",
    cueFactor = 1.0, cueHold = 15, minOn = 8,
    autonomyDelay = TIER(240, 150, 90, 60),
    periodic = { on = 10, off = 60 },
    c2LossCue = { mode = "voice", range = 30000, delay = TIER(120, 90, 60, 45) },
    linkBackup = { range = 20000, delay = TIER(90, 60, 45, 30) },
    altTakeover = TIER(360, 240, 180, 120),
    agBackup = { mode = "none" },
    wta = { pkGoal = 0.8, maxShooters = 2 },   -- several SA-2 sites fire at one strike package
    -- short "blinks": dark just long enough, back up quickly; observers phone warnings in slowly
    -- (Phase 6 Vietnam tuning to come: flak traps, ground spotters, VHF voice reach)
    arm = { maxDark = 60, margin = 5, minDark = 10, netDelay = TIER(20, 15, 10, 8),  -- mutate: ok tuning
            suspicion = TIER(0.08, 0.05, 0.03, 0.02), suspectDark = 20 },  -- mutate: ok tuning
  }),
  -- US Vietnam era: Hawk batteries defending airbases, simple procedural control.
  US_VIETNAM_1965_72 = derive(BASE, {
    name = "US_VIETNAM_1965_72", fighterControl = "aew",
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
    c2LossCue = { mode = "none" },         -- Iraq 1991: without the centre, sites are on their own
    linkBackup = { range = 0 },
    altTakeover = TIER(600, 400, 300, 200),
    agBackup = { mode = "none" },
    idTime = TIER(240, 180, 120, 90),
    wta = { enabled = false },             -- no central fire control: every site engages what it sees
    arm = { confirmScans = 5, reaction = TIER(15, 10, 6, 4), netDelay = TIER(30, 20, 15, 10),  -- mutate: ok tuning
            suspicion = TIER(0.05, 0.03, 0.02, 0.01) },  -- mutate: ok tuning
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
