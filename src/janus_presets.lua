-- Janus IADS - battery presets: how real batteries are built, mapped to DCS unit types.
-- Lua 5.1. Hand-written data; validated by tools/check_presets.py against src/janus_units.lua
-- (every `type` below must exist in DCS and carry the role the preset says it does).
--
-- Fields per preset:
--   name, era, nations         : for doctrine-profile filters and the setup report
--   units = { {role, type, count, missiles=, ring=, spacing=, note=}, ... }
--       role    : Janus role the unit fills in this battery (see docs/UNIT_DATA_REPORT.md)
--       count   : typical number in one battery / fire unit ("min-max" as {min,max})
--       missiles: ready missiles per launcher in DCS (from GT_t.LN_t ammo_capacity where known)
--       ring    : launchers placed on a ring of this radius (m) around the fire-control radar
--       spacing : typical separation (m) between like units
--   essential = { role, ... }  : roles without which the site cannot fire (setup report warns)
--   aaa_ring = { ... }         : optional gun ring the spawner can add
--   approx = true              : sources disagree or the figure is an estimate
--   requires = { "DLC name" }  : paid DCS content the units need (e.g. "WWII Assets Pack"). Missions using such a
--                                preset only load for players/servers that own the DLC; Janus says so in the setup
--                                report. Free asset packs in CoreMods (Currenthill, China, Cold War...) need no entry
--   sources = { "url or citation", ... }
--
-- Real-world figures are approximate by nature: unit tables changed by year, army and export
-- customer. Each preset cites its sources; where they disagree the preset says so.

JANUS = JANUS or {}
JANUS.Presets = {

  -- ===================================================================== Soviet / Russian
  ["SA-2"] = {
    name = "SA-2 Guideline (S-75 Dvina/Volkhov) battalion fire unit", era = "Early Cold War",
    nations = { "USSR", "Vietnam", "Egypt", "Syria", "Iraq", "China" },
    units = {
      { role = "TR", type = "SNR_75V",        count = 1, note = "Fan Song fire-control radar at the site centre" },
      { role = "LN", type = "S_75M_Volhov",   count = 6, missiles = 1, ring = 70, note = "six launchers in a hexagon, the classic 'Star of David'" },
      { role = "SR", type = "p-19 s-125 sr",  count = 1, spacing = 300, note = "DCS has no P-12 Spoon Rest; P-19 Flat Face is the stand-in. The Fan Song's DCS data depends on it" },
      { role = "TR", type = "RD_75",          count = 1, note = "RD-75 Amazonka rangefinder, optional (DCS: SA-2 counter-ECM unit)" },
      { role = "AUX", type = "S_75_ZIL",      count = { 2, 6 }, note = "ZIL-131 transloaders, cosmetic in DCS" },
    },
    essential = { "TR", "LN" },
    aaa_ring = { { type = "ZU-23 Emplacement", count = 4, ring = 400 }, { type = "S-60_Type59_Artillery", count = 2, ring = 600 } },
    approx = true,
    sources = {
      "https://en.wikipedia.org/wiki/S-75_Dvina  (battalion: 1 fire-control radar, 6 launchers, 'Star of David' layout)",
      "https://www.globalsecurity.org/military/world/russia/sa-2-site.htm  (site layout, 60-100 m launcher ring)",
    },
  },

  ["SA-2-VIETNAM"] = {
    name = "SA-2 Guideline, North Vietnamese pattern (1965-72)", era = "Early Cold War",
    nations = { "Vietnam" },
    units = {
      { role = "TR", type = "SNR_75V",        count = 1, note = "Fan Song; emits for seconds only, shut down on Shrike launch" },
      { role = "LN", type = "S_75M_Volhov",   count = 6, missiles = 1, ring = 70 },
      { role = "SR", type = "p-19 s-125 sr",  count = { 0, 1 }, spacing = 2000, note = "acquisition radar sited away from the launchers; the site is often cued by regiment-level radar instead" },
    },
    essential = { "TR", "LN" },
    aaa_ring = { { type = "ZU-23 Emplacement", count = 6, ring = 300 }, { type = "S-60_Type59_Artillery", count = 6, ring = 800 }, { type = "SON_9", count = 1 } },
    approx = true,
    sources = {
      "https://en.wikipedia.org/wiki/Operation_Rolling_Thunder  (SA-2 belt, AAA-heavy defence, dummy sites)",
      "https://en.wikipedia.org/wiki/S-75_Dvina#Vietnam_War",
      "https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/195928/  (Wild Weasel vs SA-2 sites)",
    },
  },

  ["SA-3"] = {
    name = "SA-3 Goa (S-125 Neva/Pechora) battery", era = "Mid Cold War",
    nations = { "USSR", "Syria", "Egypt", "Libya", "Yugoslavia" },
    units = {
      { role = "TR", type = "snr s-125 tr",   count = 1, note = "Low Blow fire-control radar" },
      { role = "SR", type = "p-19 s-125 sr",  count = 1, spacing = 200, note = "Flat Face acquisition" },
      { role = "LN", type = "5p73 s-125 ln",  count = 4, missiles = 4, ring = 60, note = "5P73 quad launchers" },
    },
    essential = { "TR", "LN" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/S-125_Neva/Pechora  (battery: 1 SNR-125, 4 launchers, P-15/P-19 acquisition)" },
  },

  ["SA-5"] = {
    name = "SA-5 Gammon (S-200 Angara/Vega) fire channel", era = "Mid Cold War",
    nations = { "USSR", "Syria", "Libya", "Iran", "Ukraine" },
    units = {
      { role = "TR", type = "RPC_5N62V",      count = 1, note = "Square Pair illuminator" },
      { role = "LN", type = "S-200_Launcher", count = 6, missiles = 1, ring = 150 },
      { role = "SR", type = "P14_SR",         count = 1, spacing = 1000, note = "P-14 Tall King acquisition (or RLS_19J6 Tin Shield)" },
    },
    essential = { "TR", "LN" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/S-200_(missile)  (fire channel: one 5N62 + six launchers)" },
  },

  ["SA-6"] = {
    name = "SA-6 Gainful (2K12 Kub) battery", era = "Late Cold War",
    nations = { "USSR", "Syria", "Egypt", "Iraq", "Yugoslavia", "Libya" },
    units = {
      { role = "STR", type = "Kub 1S91 str",  count = 1, note = "Straight Flush search/track/illuminate" },
      { role = "LN",  type = "Kub 2P25 ln",   count = 4, missiles = 3, ring = 200, note = "2P25 TELs" },
      { role = "AUX", type = "ATZ-10",        count = { 0, 2 }, note = "reload/fuel trucks, cosmetic" },
    },
    essential = { "STR", "LN" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/2K12_Kub  (battery: 1 1S91 + 4 2P25; regiment adds a 1S12 Long Track, absent from DCS)" },
  },

  ["SA-8"] = {
    name = "SA-8 Gecko (9K33 Osa) battery", era = "Mid Cold War",
    nations = { "USSR", "Syria", "Iraq", "Libya", "Algeria" },
    units = {
      { role = "SHORAD", type = "Osa 9A33 ln",   count = 4, missiles = 6, spacing = 300, note = "self-contained TELARs" },
      { role = "SR",     type = "Dog Ear radar", count = 1, note = "PPRU-1 / Sborka battery command post as cueing radar" },
    },
    essential = { "SHORAD" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/9K33_Osa  (battery of four TELARs)" },
  },

  ["SA-9"] = {
    name = "SA-9 Gaskin (9K31 Strela-1) platoon", era = "Mid Cold War", nations = { "USSR", "Syria", "Egypt" },
    units = {
      { role = "SHORAD", type = "Strela-1 9P31",  count = 4, missiles = 4, spacing = 200 },
      { role = "SR",     type = "Dog Ear radar",  count = { 0, 1 } },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/9K31_Strela-1" },
  },

  ["SA-13"] = {
    name = "SA-13 Gopher (9K35 Strela-10) platoon", era = "Late Cold War", nations = { "USSR", "Russia", "Syria" },
    units = {
      { role = "SHORAD", type = "Strela-10M3",    count = 4, missiles = 4, spacing = 200 },
      { role = "SR",     type = "Dog Ear radar",  count = { 0, 1 } },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/9K35_Strela-10" },
  },

  ["SA-10"] = {
    name = "SA-10 Grumble (S-300PS) battalion", era = "Late Cold War",
    nations = { "USSR", "Russia", "Ukraine", "Syria", "Iran", "China" },
    units = {
      { role = "C2", type = "S-300PS 54K6 cp",        count = 1, note = "54K6 command post" },
      { role = "TR", type = "S-300PS 40B6M tr",        count = 1, note = "30N6 Flap Lid on 40V6M mast (or 5H63C 30H6_tr truck-mounted)" },
      { role = "SR", type = "S-300PS 64H6E sr",        count = 1, spacing = 500, note = "64N6 Big Bird (regiment-level; 40B6MD Clam Shell is the low-altitude alternative)" },
      { role = "SR", type = "S-300PS 40B6MD sr",       count = { 0, 1 }, note = "5N66M Clam Shell low-altitude detector" },
      { role = "LN", type = "S-300PS 5P85C ln",        count = 4, missiles = 4, ring = 250, note = "5P85S master TELs" },
      { role = "LN", type = "S-300PS 5P85D ln",        count = 8, missiles = 4, ring = 350, note = "5P85D slave TELs" },
      { role = "POWER", type = "generator_5i57",       count = { 0, 2 } },
    },
    essential = { "TR", "LN" },
    approx = true,
    sources = {
      "https://en.wikipedia.org/wiki/S-300_missile_system  (S-300PS battalion: 5N63S, up to 12 TELs 5P85S/D, 54K6 CP)",
      "https://www.ausairpower.net/APA-Grumble-Gargoyle.html  (battery/battalion composition, 40V6M mast)",
    },
  },

  ["SA-11"] = {
    name = "SA-11 Gadfly (9K37 Buk-M1) battery", era = "Late Cold War",
    nations = { "USSR", "Russia", "Ukraine", "Syria", "Georgia" },
    units = {
      { role = "C2",    type = "SA-11 Buk CC 9S470M1",  count = 1, note = "9S470M1 command post" },
      { role = "SR",    type = "SA-11 Buk SR 9S18M1",   count = 1, spacing = 300, note = "Snow Drift" },
      { role = "TELAR", type = "SA-11 Buk LN 9A310M1",  count = 6, missiles = 4, spacing = 250, note = "battery of two firing sections; each TELAR has its own Fire Dome radar" },
    },
    essential = { "TELAR" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/Buk_missile_system  (battery: 1 CP, 1 Snow Drift, up to 6 TELAR + loader-launchers, absent from DCS)" },
  },

  ["SA-15"] = {
    name = "SA-15 Gauntlet (9K330 Tor) battery", era = "Late Cold War", nations = { "USSR", "Russia", "China", "Iran" },
    units = {
      { role = "SHORAD", type = "Tor 9A331",     count = 4, missiles = 8, spacing = 300, note = "self-contained; used by Janus as point defence" },
      { role = "SR",     type = "Dog Ear radar", count = { 0, 1 }, note = "battery command post stand-in (Ranzhir absent from DCS)" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Tor_missile_system  (battery of four TLARs)" },
  },

  ["SA-19"] = {
    name = "SA-19 Grison (2K22 Tunguska) battery", era = "Late Cold War", nations = { "USSR", "Russia" },
    units = {
      { role = "SHORAD", type = "2S6 Tunguska", count = { 4, 6 }, missiles = 8, spacing = 300 },
      { role = "SR",     type = "Dog Ear radar", count = { 0, 1 } },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/2K22_Tunguska" },
  },

  ["TOR-M2"] = {
    name = "SA-15 Gauntlet (Tor-M2) battery", era = "Modern", nations = { "Russia", "Belarus" },
    units = {
      { role = "SHORAD", type = "CHAP_TorM2", count = 4, missiles = 16, spacing = 300, note = "Currenthill pack unit (free, in CoreMods)" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Tor_missile_system#Tor-M2" },
  },

  ["PANTSIR"] = {
    name = "SA-22 Greyhound (Pantsir-S1) battery", era = "Modern", nations = { "Russia", "Syria" },
    units = {
      { role = "SHORAD", type = "CHAP_PantsirS1", count = { 4, 6 }, missiles = 12, spacing = 300, note = "Currenthill pack unit (free, in CoreMods)" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Pantsir_missile_system" },
  },

  -- ===================================================================== NATO / US
  ["IRIS-T-SLM"] = {
    name = "IRIS-T SLM fire unit", era = "Modern", nations = { "Germany", "Ukraine", "Egypt", "Sweden" },
    units = {
      { role = "C2",  type = "CHAP_IRISTSLM_CP",  count = 1, note = "tactical operations centre; Currenthill pack (free, in CoreMods)" },
      { role = "STR", type = "CHAP_IRISTSLM_STR", count = 1, note = "TRML-4D radar" },
      { role = "LN",  type = "CHAP_IRISTSLM_LN",  count = 3, missiles = 8, ring = 400 },
    },
    essential = { "STR", "LN" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/IRIS-T_SLM  (fire unit: TOC, TRML-4D, 3 launchers x 8 missiles)" },
  },

  ["PATRIOT"] = {
    name = "MIM-104 Patriot battery", era = "Late Cold War / Modern",
    nations = { "USA", "Germany", "Netherlands", "Israel", "Saudi Arabia", "Japan", "Poland" },
    units = {
      { role = "STR",   type = "Patriot str",  count = 1, note = "AN/MPQ-53/65 radar set" },
      { role = "C2",    type = "Patriot ECS",  count = 1, note = "Engagement Control Station" },
      { role = "C2",    type = "Patriot EPP",  count = 1, note = "Electric Power Plant (Janus treats it as the battery's POWER node)" },
      { role = "C2",    type = "Patriot AMG",  count = 1, note = "Antenna Mast Group (comms relay)" },
      { role = "C2",    type = "Patriot cp",   count = { 0, 1 }, note = "ICC, battalion-level; one per 4-6 batteries" },
      { role = "LN",    type = "Patriot ln",   count = { 4, 8 }, missiles = 4, ring = 300, note = "M901 launching stations, PAC-2 (4 per launcher)" },
    },
    essential = { "STR", "LN" },
    approx = true,
    sources = {
      "https://en.wikipedia.org/wiki/MIM-104_Patriot  (battery: radar set, ECS, EPP, AMG, up to 8 launchers; ICC at battalion)",
      "https://www.army.mil/  (Patriot fire unit description; figures vary by configuration)",
    },
  },

  ["HAWK"] = {
    name = "MIM-23 I-Hawk (Phase III) battery", era = "Late Cold War",
    nations = { "USA", "Germany", "Israel", "Iran", "Spain", "Greece", "Turkey", "Taiwan", "Japan" },
    units = {
      { role = "C2", type = "Hawk pcp",  count = 1, note = "Platoon Command Post" },
      { role = "SR", type = "Hawk sr",   count = 1, note = "AN/MPQ-50 PAR pulse acquisition radar" },
      { role = "SR", type = "Hawk cwar", count = 1, spacing = 100, note = "AN/MPQ-55 CWAR low-altitude acquisition" },
      { role = "TR", type = "Hawk tr",   count = 2, spacing = 150, note = "AN/MPQ-46 HPIR illuminators, one per firing section" },
      { role = "LN", type = "Hawk ln",   count = 6, missiles = 3, ring = 120, note = "M192 launchers, 3 missiles each; 3 per HPIR" },
    },
    essential = { "TR", "LN" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/MIM-23_Hawk  (I-Hawk battery: PCP, PAR, CWAR, 2 HPIR, 6 launchers)" },
  },

  ["NASAMS"] = {
    name = "NASAMS fire unit", era = "Modern",
    nations = { "Norway", "USA", "Netherlands", "Finland", "Spain", "Ukraine" },
    units = {
      { role = "C2", type = "NASAMS_Command_Post",  count = 1, note = "Fire Distribution Center" },
      { role = "SR", type = "NASAMS_Radar_MPQ64F1", count = 1, note = "AN/MPQ-64F1 Sentinel" },
      { role = "LN", type = "NASAMS_LN_C",          count = 3, missiles = 6, ring = 400, note = "AIM-120C canisters (LN_B for AIM-120B)" },
    },
    essential = { "C2", "SR", "LN" },
    approx = true,
    sources = { "https://en.wikipedia.org/wiki/NASAMS  (fire unit: 1 FDC, 1 Sentinel, 3 launchers x 6 missiles; battery = 3 fire units)" },
  },

  ["RAPIER"] = {
    name = "Rapier FSA fire unit", era = "Late Cold War", nations = { "UK", "Iran", "Turkey", "Oman" },
    units = {
      { role = "SHORAD", type = "rapier_fsa_launcher",             count = 1, missiles = 4 },
      { role = "SR",     type = "rapier_fsa_optical_tracker_unit", count = 1, spacing = 50 },
      { role = "TR",     type = "rapier_fsa_blindfire_radar",      count = { 0, 1 }, spacing = 50, note = "Blindfire DN181 for night/all-weather" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Rapier_(missile)  (fire unit: launcher + optical tracker, Blindfire optional)" },
  },

  ["ROLAND"] = {
    name = "Roland battery", era = "Late Cold War", nations = { "Germany", "France", "USA", "Iraq" },
    units = {
      { role = "SHORAD", type = "Roland ADS",   count = 4, missiles = 8, spacing = 300 },
      { role = "SR",     type = "Roland Radar", count = 1, note = "battery search radar" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Roland_(missile)" },
  },

  ["HQ-7"] = {
    name = "HQ-7B (FM-90) battery", era = "Modern", nations = { "China", "Pakistan", "Iran" },
    units = {
      { role = "C2",     type = "HQ-7_STR_SP", count = 1, note = "search unit; acts as C2 and search radar" },
      { role = "SHORAD", type = "HQ-7_LN_SP",  count = 3, missiles = 4, ring = 300, note = "each launch unit carries its own tracking radar" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/HQ-7  (battery: 1 search unit + 3 launch units)" },
  },

  ["AVENGER"] = {
    name = "Avenger platoon", era = "Modern", nations = { "USA" },
    units = {
      { role = "SHORAD", type = "M1097 Avenger", count = 4, missiles = 8, spacing = 300 },
      { role = "SR",     type = "NASAMS_Radar_MPQ64F1", count = { 0, 1 }, note = "Sentinel radar cueing, as in a US SHORAD battery" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/AN/TWQ-1_Avenger" },
  },

  ["CHAPARRAL"] = {
    name = "Chaparral battery", era = "Mid Cold War", nations = { "USA", "Israel", "Taiwan" },
    units = {
      { role = "SHORAD", type = "M48 Chaparral", count = 4, missiles = 4, spacing = 300 },
      { role = "AAA",    type = "Vulcan",        count = { 0, 4 }, note = "Chaparral/Vulcan battalions paired the two" },
    },
    essential = { "SHORAD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/MIM-72_Chaparral" },
  },

  ["C-RAM"] = {
    name = "C-RAM LPWS section", era = "Modern", nations = { "USA", "UK" },
    units = {
      { role = "CRAM", type = "HEMTT_C-RAM_Phalanx", count = { 2, 4 }, spacing = 400, note = "Land-based Phalanx Weapon System around the protected base; the DCS unit has its own radar. In DCS its engagement of rockets/missiles/bombs is measured by the Phase 0 probe mission" },
    },
    essential = { "CRAM" }, approx = true,
    sources = {
      "https://en.wikipedia.org/wiki/Counter_Rocket,_Artillery,_and_Mortar  (LPWS deployed in sections of several mounts around a base)",
      "https://en.wikipedia.org/wiki/Phalanx_CIWS#Land-based_variant",
    },
  },

  -- ===================================================================== AAA (Vietnam and general)
  ["AAA-100MM"] = {
    name = "KS-19 100 mm battery with Fire Can", era = "Early Cold War", nations = { "USSR", "Vietnam", "China", "Egypt" },
    units = {
      { role = "AAA",    type = "KS-19", count = 6, ring = 60, note = "six guns around the director; DCS links KS-19 to SON-9 by depends_on" },
      { role = "AAA_FC", type = "SON_9", count = 1, note = "SON-9 Fire Can gun-laying radar (ARM-targetable)" },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/KS-19  (batteries of 6 guns with SON-9 / PUAZO director)" },
  },

  ["AAA-57MM"] = {
    name = "S-60 57 mm battery with Fire Can", era = "Early Cold War", nations = { "USSR", "Vietnam", "China", "Syria", "Egypt" },
    units = {
      { role = "AAA",    type = "S-60_Type59_Artillery", count = 6, ring = 50 },
      { role = "AAA_FC", type = "SON_9", count = 1 },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/AZP_S-60  (battery: 6 guns + SON-9 radar + PUAZO-6 director)" },
  },

  ["AAA-ZU23"] = {
    name = "ZU-23 light AAA section", era = "Mid Cold War", nations = { "USSR", "Vietnam", "Syria", "Iraq" },
    units = {
      { role = "AAA", type = "ZU-23 Emplacement", count = { 2, 6 }, spacing = 80 },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/ZU-23-2" },
  },

  ["AAA-SHILKA"] = {
    name = "ZSU-23-4 Shilka platoon", era = "Mid Cold War", nations = { "USSR", "Syria", "Egypt", "Iraq" },
    units = { { role = "AAA", type = "ZSU-23-4 Shilka", count = 4, spacing = 200, note = "radar-directed; Gun Dish is ARM-targetable" } },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/ZSU-23-4_Shilka" },
  },

  ["AAA-GEPARD"] = {
    name = "Gepard platoon", era = "Late Cold War", nations = { "Germany", "Netherlands", "Belgium" },
    units = { { role = "AAA", type = "Gepard", count = 4, spacing = 200 } },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Flakpanzer_Gepard" },
  },

  ["AAA-VULCAN"] = {
    name = "M163 Vulcan platoon", era = "Mid Cold War", nations = { "USA", "Israel" },
    units = { { role = "AAA", type = "Vulcan", count = 4, spacing = 200 } },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/M163_VADS" },
  },

  -- ===================================================================== WWII (DCS: WWII Assets Pack DLC)
  ["FLAK-88"] = {
    name = "Heavy Flak battery, 8.8 cm Flak 18/36/37 (WWII)", era = "WWII", nations = { "Germany" },
    requires = { "WWII Assets Pack" },
    units = {
      { role = "AAA",    type = "flak18",              count = 4, ring = 60, note = "4-gun heavy battery (6 later in the war)" },
      { role = "AAA_FC", type = "KDO_Mod40",           count = 1, note = "Kommandogerät 40 director" },
      { role = "AAA",    type = "Flakscheinwerfer_37", count = { 0, 2 }, ring = 300, note = "searchlights for night defence" },
      { role = "POWER",  type = "Maschinensatz_33",    count = { 0, 1 } },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/8.8_cm_Flak_18/36/37/41  (batteries of 4-6 guns with a Kommandogerät director)" },
  },

  ["FLAK-LIGHT"] = {
    name = "Light Flak platoon, 2 cm Flak 38 / 3.7 cm (WWII)", era = "WWII", nations = { "Germany" },
    requires = { "WWII Assets Pack" },
    units = {
      { role = "AAA", type = "flak38", count = { 3, 4 }, spacing = 60 },
      { role = "AAA", type = "flak36", count = { 0, 2 }, spacing = 80, note = "3.7 cm Flak 36" },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/2_cm_Flak_30/38/Flakvierling" },
  },

  ["AAA-US-WWII"] = {
    name = "US automatic-weapons AAA section (WWII)", era = "WWII", nations = { "USA", "UK" },
    requires = { "WWII Assets Pack" },
    units = {
      { role = "AAA", type = "M45_Quadmount", count = { 2, 4 }, spacing = 60, note = "M45 quad .50 cal" },
      { role = "AAA", type = "M1_37mm",       count = { 0, 2 }, spacing = 80 },
      { role = "AAA", type = "bofors40",      count = { 0, 2 }, spacing = 80, note = "Bofors 40 mm (core unit)" },
    },
    essential = { "AAA" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/M45_Quadmount" },
  },

  ["EW-WWII-GERMAN"] = {
    name = "German radar site, Freya + Würzburg (WWII)", era = "WWII", nations = { "Germany" },
    requires = { "WWII Assets Pack" },
    units = {
      { role = "EWR", type = "FuMG-401", count = 1, note = "Freya LZ early warning" },
      { role = "EWR", type = "FuSe-65",  count = { 1, 2 }, spacing = 200, note = "Würzburg-Riese tracking" },
      { role = "POWER", type = "Maschinensatz_33", count = { 0, 1 } },
    },
    essential = { "EWR" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Freya_radar", "https://en.wikipedia.org/wiki/W%C3%BCrzburg_radar" },
  },

  -- ===================================================================== Early warning / C2 nodes
  ["EW-SOVIET"] = {
    name = "Soviet radiotechnical post", era = "Late Cold War", nations = { "USSR", "Russia" },
    units = {
      { role = "EWR", type = "55G6 EWR", count = 1, note = "Tall Rack, or 1L13 Box Spring" },
      { role = "C2_GENERIC", type = "SKP-11", count = { 0, 1 } },
      { role = "POWER", type = "generator_5i57", count = { 0, 1 } },
    },
    essential = { "EWR" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Soviet_Air_Defence_Forces" },
  },

  ["EW-NATO"] = {
    name = "NATO long-range radar site", era = "Late Cold War / Modern", nations = { "USA", "NATO" },
    units = {
      { role = "EWR", type = "FPS-117", count = 1, note = "AN/FPS-117 (Dome variant for fixed sites)" },
      { role = "EWR", type = "FPS-117 ECS", count = { 0, 1 }, note = "ECS shelter" },
    },
    essential = { "EWR" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/AN/FPS-117" },
  },

  -- ===================================================================== Naval (per the StonewallC carrier standard)
  ["CSG-USN"] = {
    name = "US Navy carrier strike group escort", era = "Modern", nations = { "USA" },
    units = {
      { role = "NAVAL_AD", type = "CVN_73",               count = 1, note = "any Supercarrier hull: CVN_71/72/73/75" },
      { role = "NAVAL_AD", type = "TICONDEROG",           count = 1, spacing = 3000, note = "Ticonderoga CG, air-defence commander" },
      { role = "NAVAL_AD", type = "USS_Arleigh_Burke_IIa", count = 2, spacing = 3000 },
      { role = "NAVAL_AD", type = "PERRY",                count = 1, spacing = 1500, note = "plane guard" },
    },
    essential = { "NAVAL_AD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Carrier_strike_group  (typical CSG: 1 CG, 2-3 DDG/FFG)" },
  },

  ["SAG-RU"] = {
    name = "Russian surface action group", era = "Modern", nations = { "Russia" },
    units = {
      { role = "NAVAL_AD", type = "MOSCOW",     count = 1, note = "Slava-class cruiser, SA-N-6" },
      { role = "NAVAL_AD", type = "NEUSTRASH",  count = 1, spacing = 3000 },
      { role = "NAVAL_AD", type = "REZKY",      count = 1, spacing = 3000 },
      { role = "NAVAL_AD", type = "MOLNIYA",    count = 2, spacing = 2000 },
    },
    essential = { "NAVAL_AD" }, approx = true,
    sources = { "https://en.wikipedia.org/wiki/Slava-class_cruiser" },
  },
}
