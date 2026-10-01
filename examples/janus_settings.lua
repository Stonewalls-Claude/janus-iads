-- Janus IADS settings. Optional. Load this with DO SCRIPT FILE *before* janus.lua (same MISSION START trigger).
-- Change the value after the = sign. Text values go between quotes. true/false have no quotes.
-- Delete any line you don't need; Janus uses its default for it.

JANUS_SETTINGS = {

  -- Start automatically one second after loading? (false = a scripter calls JANUS.start() later)
  AUTOSTART = true,

  -- Show the setup report on screen at mission start and draw the network on the F10 map?
  -- Turn this on while you build the mission, off when you publish it.
  CHECK_MODE = false,

  -- How much Janus writes to dcs.log: 0 errors only, 1 + warnings, 2 + info (default), 3 + debug
  LOG_LEVEL = 2,

  -- Doctrine for each side. Shipped profiles:
  --   "SOVIET_PVO_1985"     command post decides, SAMs dark until cued, slow to act alone
  --   "RUSSIA_MODERN"       quicker crews, EW radars take turns, sites under Tor/Pantsir cover stay up against HARMs
  --   "NATO_COLDWAR"        datalinked picture, weapons tight (only fires at identified aircraft)
  --   "US_MODERN"           fastest reactions, datalink picture, weapons tight
  --   "NVA_VIETNAM_1965_72" short radar bursts, slow voice links, several SA-2 sites on one strike package
  --   "US_VIETNAM_1965_72"  Hawk batteries with radars always on
  --   "GENERIC_THIRD_WORLD" radars always on, every site fires at what it sees, slow everything
  RED_DOCTRINE = "SOVIET_PVO_1985",
  BLUE_DOCTRINE = "US_MODERN",
  -- To change one thing in a profile, write it like this instead (example: flak traps for the guns):
  -- RED_DOCTRINE = { base = "NVA_VIETNAM_1965_72", aaa = { mode = "trap" } },
  -- BLUE_DOCTRINE = { base = "US_MODERN", wta = { weapons = "free" } },   -- blue SAMs fire without identification

  -- Statistics in dcs.log: each site's radar time, shots, kills and losses (every STATS_EVERY seconds and at the end)
  STATS = false,
  STATS_EVERY = 600,

  -- "INCOMING! <airbase> - take cover" for the side owning a C-RAM site (or a site tagged [warn]) when bombs, rockets
  -- or air-to-ground missiles come within BASE_WARNING_RANGE metres of it
  BASE_WARNING = false,
  BASE_WARNING_RANGE = 12000,
  BASE_WARNING_SOUND = "",       -- a sound file packed in the mission, e.g. "siren.ogg" ("" = message only); the
                                 -- Mission Editor packs a file once a trigger action uses it (see docs/RECIPES.md)

  -- The words at the start of group names. Only change these if your mission already uses others.
  -- ROLE_WORDS = { SAM = "SAM", EW = "EW", CMD = "CMD", PD = "PD", AAA = "AAA",
  --               COMMS = "COMMS", POWER = "POWER", SHIP = "SHIP", AWACS = "AWACS" },
}
