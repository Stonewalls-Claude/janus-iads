-- Janus IADS settings. Optional. Load this with DO SCRIPT FILE *before* janus.lua.
-- Change the value after the = sign. Text values go between quotes. true/false have no quotes.
-- Delete any line you don't need; Janus uses its default for it.

JANUS_SETTINGS = {

  -- Start automatically one second after loading? (false = a scripter calls JANUS.start() later)
  AUTOSTART = true,

  -- Show the setup report on screen at mission start (and, from Phase 1, draw F10 map marks)?
  -- Turn this on while you build the mission, off when you publish it.
  CHECK_MODE = false,

  -- How much Janus writes to dcs.log: 0 errors only, 1 + warnings, 2 + info (default), 3 + debug
  LOG_LEVEL = 2,

  -- Doctrine for each side. Shipped profiles (Phase 4): "SOVIET_PVO_1985", "RUSSIA_MODERN",
  -- "NATO_COLDWAR", "US_MODERN", "NVA_VIETNAM_1965_72", "US_VIETNAM_1965_72", "GENERIC_THIRD_WORLD"
  RED_DOCTRINE = "SOVIET_PVO_1985",
  BLUE_DOCTRINE = "US_MODERN",

  -- The words at the start of group names. Only change these if your mission already uses others.
  -- ROLE_WORDS = { SAM = "SAM", EW = "EW", CMD = "CMD", PD = "PD", AAA = "AAA",
  --               COMMS = "COMMS", POWER = "POWER", SHIP = "SHIP", AWACS = "AWACS" },
}
