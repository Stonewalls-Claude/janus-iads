# Janus battery presets

Generated from `src/janus_presets.lua` by `tools/check_presets.py` (38 presets, all DCS type names verified against `data/units.json`). Real-world compositions are **approximate**: tables of organisation changed by year, army and export customer; each preset lists its sources.

Everything in `CoreMods` is free DCS content, including the Currenthill pack (`CHAP_*`: Pantsir-S1, Tor-M2, IRIS-T SLM, Project 22160). Presets that use paid DLC units say so in a box.

## `AAA-100MM` - KS-19 100 mm battery with Fire Can

Era: Early Cold War · Users: USSR, Vietnam, China, Egypt · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `KS-19` | 6 |  | ring 60 m | six guns around the director; DCS links KS-19 to SON-9 by depends_on |
| AAA_FC | `SON_9` | 1 |  |  | SON-9 Fire Can gun-laying radar (ARM-targetable) |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/KS-19  (batteries of 6 guns with SON-9 / PUAZO director)

## `AAA-57MM` - S-60 57 mm battery with Fire Can

Era: Early Cold War · Users: USSR, Vietnam, China, Syria, Egypt · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `S-60_Type59_Artillery` | 6 |  | ring 50 m |  |
| AAA_FC | `SON_9` | 1 |  |  |  |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/AZP_S-60  (battery: 6 guns + SON-9 radar + PUAZO-6 director)

## `SA-2` - SA-2 Guideline (S-75 Dvina/Volkhov) battalion fire unit

Era: Early Cold War · Users: USSR, Vietnam, Egypt, Syria, Iraq, China · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| TR | `SNR_75V` | 1 |  |  | Fan Song fire-control radar at the site centre |
| LN | `S_75M_Volhov` | 6 | 1 | ring 70 m | six launchers in a hexagon, the classic 'Star of David' |
| SR | `p-19 s-125 sr` | 1 |  | spacing 300 m | DCS has no P-12 Spoon Rest; P-19 Flat Face is the stand-in. The Fan Song's DCS data depends on it |
| TR | `RD_75` | 1 |  |  | RD-75 Amazonka rangefinder, optional (DCS: SA-2 counter-ECM unit) |
| AUX | `S_75_ZIL` | 2-6 |  |  | ZIL-131 transloaders, cosmetic in DCS |

Optional AAA ring: 4× `ZU-23 Emplacement` at 400 m, 2× `S-60_Type59_Artillery` at 600 m

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/S-75_Dvina  (battalion: 1 fire-control radar, 6 launchers, 'Star of David' layout)
- https://www.globalsecurity.org/military/world/russia/sa-2-site.htm  (site layout, 60-100 m launcher ring)

## `SA-2-VIETNAM` - SA-2 Guideline, North Vietnamese pattern (1965-72)

Era: Early Cold War · Users: Vietnam · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| TR | `SNR_75V` | 1 |  |  | Fan Song; emits for seconds only, shut down on Shrike launch |
| LN | `S_75M_Volhov` | 6 | 1 | ring 70 m |  |
| SR | `p-19 s-125 sr` | 0-1 |  | spacing 2000 m | acquisition radar sited away from the launchers; the site is often cued by regiment-level radar instead |

Optional AAA ring: 6× `ZU-23 Emplacement` at 300 m, 6× `S-60_Type59_Artillery` at 800 m, 1× `SON_9`

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/Operation_Rolling_Thunder  (SA-2 belt, AAA-heavy defence, dummy sites)
- https://en.wikipedia.org/wiki/S-75_Dvina#Vietnam_War
- https://www.nationalmuseum.af.mil/Visit/Museum-Exhibits/Fact-Sheets/Display/Article/195928/  (Wild Weasel vs SA-2 sites)

## `AAA-GEPARD` - Gepard platoon

Era: Late Cold War · Users: Germany, Netherlands, Belgium · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `Gepard` | 4 |  | spacing 200 m |  |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/Flakpanzer_Gepard

## `EW-SOVIET` - Soviet radiotechnical post

Era: Late Cold War · Users: USSR, Russia · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| EWR | `55G6 EWR` | 1 |  |  | Tall Rack, or 1L13 Box Spring |
| C2_GENERIC | `SKP-11` | 0-1 |  |  |  |
| POWER | `generator_5i57` | 0-1 |  |  |  |

Essential roles: EWR

Sources:
- https://en.wikipedia.org/wiki/Soviet_Air_Defence_Forces

## `HAWK` - MIM-23 I-Hawk (Phase III) battery

Era: Late Cold War · Users: USA, Germany, Israel, Iran, Spain, Greece, Turkey, Taiwan, Japan · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `Hawk pcp` | 1 |  |  | Platoon Command Post |
| SR | `Hawk sr` | 1 |  |  | AN/MPQ-50 PAR pulse acquisition radar |
| SR | `Hawk cwar` | 1 |  | spacing 100 m | AN/MPQ-55 CWAR low-altitude acquisition |
| TR | `Hawk tr` | 2 |  | spacing 150 m | AN/MPQ-46 HPIR illuminators, one per firing section |
| LN | `Hawk ln` | 6 | 3 | ring 120 m | M192 launchers, 3 missiles each; 3 per HPIR |

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/MIM-23_Hawk  (I-Hawk battery: PCP, PAR, CWAR, 2 HPIR, 6 launchers)

## `RAPIER` - Rapier FSA fire unit

Era: Late Cold War · Users: UK, Iran, Turkey, Oman · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `rapier_fsa_launcher` | 1 | 4 |  |  |
| SR | `rapier_fsa_optical_tracker_unit` | 1 |  | spacing 50 m |  |
| TR | `rapier_fsa_blindfire_radar` | 0-1 |  | spacing 50 m | Blindfire DN181 for night/all-weather |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/Rapier_(missile)  (fire unit: launcher + optical tracker, Blindfire optional)

## `ROLAND` - Roland battery

Era: Late Cold War · Users: Germany, France, USA, Iraq · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `Roland ADS` | 4 | 8 | spacing 300 m |  |
| SR | `Roland Radar` | 1 |  |  | battery search radar |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/Roland_(missile)

## `SA-10` - SA-10 Grumble (S-300PS) battalion

Era: Late Cold War · Users: USSR, Russia, Ukraine, Syria, Iran, China · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `S-300PS 54K6 cp` | 1 |  |  | 54K6 command post |
| TR | `S-300PS 40B6M tr` | 1 |  |  | 30N6 Flap Lid on 40V6M mast (or 5H63C 30H6_tr truck-mounted) |
| SR | `S-300PS 64H6E sr` | 1 |  | spacing 500 m | 64N6 Big Bird (regiment-level; 40B6MD Clam Shell is the low-altitude alternative) |
| SR | `S-300PS 40B6MD sr` | 0-1 |  |  | 5N66M Clam Shell low-altitude detector |
| LN | `S-300PS 5P85C ln` | 4 | 4 | ring 250 m | 5P85S master TELs |
| LN | `S-300PS 5P85D ln` | 8 | 4 | ring 350 m | 5P85D slave TELs |
| POWER | `generator_5i57` | 0-2 |  |  |  |

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/S-300_missile_system  (S-300PS battalion: 5N63S, up to 12 TELs 5P85S/D, 54K6 CP)
- https://www.ausairpower.net/APA-Grumble-Gargoyle.html  (battery/battalion composition, 40V6M mast)

## `SA-11` - SA-11 Gadfly (9K37 Buk-M1) battery

Era: Late Cold War · Users: USSR, Russia, Ukraine, Syria, Georgia · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `SA-11 Buk CC 9S470M1` | 1 |  |  | 9S470M1 command post |
| SR | `SA-11 Buk SR 9S18M1` | 1 |  | spacing 300 m | Snow Drift |
| TELAR | `SA-11 Buk LN 9A310M1` | 6 | 4 | spacing 250 m | battery of two firing sections; each TELAR has its own Fire Dome radar |

Essential roles: TELAR

Sources:
- https://en.wikipedia.org/wiki/Buk_missile_system  (battery: 1 CP, 1 Snow Drift, up to 6 TELAR + loader-launchers, absent from DCS)

## `SA-13` - SA-13 Gopher (9K35 Strela-10) platoon

Era: Late Cold War · Users: USSR, Russia, Syria · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `Strela-10M3` | 4 | 4 | spacing 200 m |  |
| SR | `Dog Ear radar` | 0-1 |  |  |  |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/9K35_Strela-10

## `SA-15` - SA-15 Gauntlet (9K330 Tor) battery

Era: Late Cold War · Users: USSR, Russia, China, Iran · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `Tor 9A331` | 4 | 8 | spacing 300 m | self-contained; used by Janus as point defence |
| SR | `Dog Ear radar` | 0-1 |  |  | battery command post stand-in (Ranzhir absent from DCS) |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/Tor_missile_system  (battery of four TLARs)

## `SA-19` - SA-19 Grison (2K22 Tunguska) battery

Era: Late Cold War · Users: USSR, Russia · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `2S6 Tunguska` | 4-6 | 8 | spacing 300 m |  |
| SR | `Dog Ear radar` | 0-1 |  |  |  |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/2K22_Tunguska

## `SA-6` - SA-6 Gainful (2K12 Kub) battery

Era: Late Cold War · Users: USSR, Syria, Egypt, Iraq, Yugoslavia, Libya · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| STR | `Kub 1S91 str` | 1 |  |  | Straight Flush search/track/illuminate |
| LN | `Kub 2P25 ln` | 4 | 3 | ring 200 m | 2P25 TELs |
| AUX | `ATZ-10` | 0-2 |  |  | reload/fuel trucks, cosmetic |

Essential roles: STR, LN

Sources:
- https://en.wikipedia.org/wiki/2K12_Kub  (battery: 1 1S91 + 4 2P25; regiment adds a 1S12 Long Track, absent from DCS)

## `EW-NATO` - NATO long-range radar site

Era: Late Cold War / Modern · Users: USA, NATO · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| EWR | `FPS-117` | 1 |  |  | AN/FPS-117 (Dome variant for fixed sites) |
| EWR | `FPS-117 ECS` | 0-1 |  |  | ECS shelter |

Essential roles: EWR

Sources:
- https://en.wikipedia.org/wiki/AN/FPS-117

## `PATRIOT` - MIM-104 Patriot battery

Era: Late Cold War / Modern · Users: USA, Germany, Netherlands, Israel, Saudi Arabia, Japan, Poland · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| STR | `Patriot str` | 1 |  |  | AN/MPQ-53/65 radar set |
| C2 | `Patriot ECS` | 1 |  |  | Engagement Control Station |
| C2 | `Patriot EPP` | 1 |  |  | Electric Power Plant (Janus treats it as the battery's POWER node) |
| C2 | `Patriot AMG` | 1 |  |  | Antenna Mast Group (comms relay) |
| C2 | `Patriot cp` | 0-1 |  |  | ICC, battalion-level; one per 4-6 batteries |
| LN | `Patriot ln` | 4-8 | 4 | ring 300 m | M901 launching stations, PAC-2 (4 per launcher) |

Essential roles: STR, LN

Sources:
- https://en.wikipedia.org/wiki/MIM-104_Patriot  (battery: radar set, ECS, EPP, AMG, up to 8 launchers; ICC at battalion)
- https://www.army.mil/  (Patriot fire unit description; figures vary by configuration)

## `AAA-SHILKA` - ZSU-23-4 Shilka platoon

Era: Mid Cold War · Users: USSR, Syria, Egypt, Iraq · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `ZSU-23-4 Shilka` | 4 |  | spacing 200 m | radar-directed; Gun Dish is ARM-targetable |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/ZSU-23-4_Shilka

## `AAA-VULCAN` - M163 Vulcan platoon

Era: Mid Cold War · Users: USA, Israel · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `Vulcan` | 4 |  | spacing 200 m |  |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/M163_VADS

## `AAA-ZU23` - ZU-23 light AAA section

Era: Mid Cold War · Users: USSR, Vietnam, Syria, Iraq · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `ZU-23 Emplacement` | 2-6 |  | spacing 80 m |  |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/ZU-23-2

## `CHAPARRAL` - Chaparral battery

Era: Mid Cold War · Users: USA, Israel, Taiwan · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `M48 Chaparral` | 4 | 4 | spacing 300 m |  |
| AAA | `Vulcan` | 0-4 |  |  | Chaparral/Vulcan battalions paired the two |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/MIM-72_Chaparral

## `SA-3` - SA-3 Goa (S-125 Neva/Pechora) battery

Era: Mid Cold War · Users: USSR, Syria, Egypt, Libya, Yugoslavia · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| TR | `snr s-125 tr` | 1 |  |  | Low Blow fire-control radar |
| SR | `p-19 s-125 sr` | 1 |  | spacing 200 m | Flat Face acquisition |
| LN | `5p73 s-125 ln` | 4 | 4 | ring 60 m | 5P73 quad launchers |

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/S-125_Neva/Pechora  (battery: 1 SNR-125, 4 launchers, P-15/P-19 acquisition)

## `SA-5` - SA-5 Gammon (S-200 Angara/Vega) fire channel

Era: Mid Cold War · Users: USSR, Syria, Libya, Iran, Ukraine · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| TR | `RPC_5N62V` | 1 |  |  | Square Pair illuminator |
| LN | `S-200_Launcher` | 6 | 1 | ring 150 m |  |
| SR | `P14_SR` | 1 |  | spacing 1000 m | P-14 Tall King acquisition (or RLS_19J6 Tin Shield) |

Essential roles: TR, LN

Sources:
- https://en.wikipedia.org/wiki/S-200_(missile)  (fire channel: one 5N62 + six launchers)

## `SA-8` - SA-8 Gecko (9K33 Osa) battery

Era: Mid Cold War · Users: USSR, Syria, Iraq, Libya, Algeria · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `Osa 9A33 ln` | 4 | 6 | spacing 300 m | self-contained TELARs |
| SR | `Dog Ear radar` | 1 |  |  | PPRU-1 / Sborka battery command post as cueing radar |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/9K33_Osa  (battery of four TELARs)

## `SA-9` - SA-9 Gaskin (9K31 Strela-1) platoon

Era: Mid Cold War · Users: USSR, Syria, Egypt · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `Strela-1 9P31` | 4 | 4 | spacing 200 m |  |
| SR | `Dog Ear radar` | 0-1 |  |  |  |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/9K31_Strela-1

## `AVENGER` - Avenger platoon

Era: Modern · Users: USA · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `M1097 Avenger` | 4 | 8 | spacing 300 m |  |
| SR | `NASAMS_Radar_MPQ64F1` | 0-1 |  |  | Sentinel radar cueing, as in a US SHORAD battery |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/AN/TWQ-1_Avenger

## `C-RAM` - C-RAM LPWS section

Era: Modern · Users: USA, UK · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| CRAM | `HEMTT_C-RAM_Phalanx` | 2-4 |  | spacing 400 m | Land-based Phalanx Weapon System around the protected base; the DCS unit has its own radar. In DCS its engagement of rockets/missiles/bombs is measured by the Phase 0 probe mission |

Essential roles: CRAM

Sources:
- https://en.wikipedia.org/wiki/Counter_Rocket,_Artillery,_and_Mortar  (LPWS deployed in sections of several mounts around a base)
- https://en.wikipedia.org/wiki/Phalanx_CIWS#Land-based_variant

## `CSG-USN` - US Navy carrier strike group escort

Era: Modern · Users: USA · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| NAVAL_AD | `CVN_73` | 1 |  |  | any Supercarrier hull: CVN_71/72/73/75 |
| NAVAL_AD | `TICONDEROG` | 1 |  | spacing 3000 m | Ticonderoga CG, air-defence commander |
| NAVAL_AD | `USS_Arleigh_Burke_IIa` | 2 |  | spacing 3000 m |  |
| NAVAL_AD | `PERRY` | 1 |  | spacing 1500 m | plane guard |

Essential roles: NAVAL_AD

Sources:
- https://en.wikipedia.org/wiki/Carrier_strike_group  (typical CSG: 1 CG, 2-3 DDG/FFG)

## `HQ-7` - HQ-7B (FM-90) battery

Era: Modern · Users: China, Pakistan, Iran · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `HQ-7_STR_SP` | 1 |  |  | search unit; acts as C2 and search radar |
| SHORAD | `HQ-7_LN_SP` | 3 | 4 | ring 300 m | each launch unit carries its own tracking radar |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/HQ-7  (battery: 1 search unit + 3 launch units)

## `IRIS-T-SLM` - IRIS-T SLM fire unit

Era: Modern · Users: Germany, Ukraine, Egypt, Sweden · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `CHAP_IRISTSLM_CP` | 1 |  |  | tactical operations centre; Currenthill pack (free, in CoreMods) |
| STR | `CHAP_IRISTSLM_STR` | 1 |  |  | TRML-4D radar |
| LN | `CHAP_IRISTSLM_LN` | 3 | 8 | ring 400 m |  |

Essential roles: STR, LN

Sources:
- https://en.wikipedia.org/wiki/IRIS-T_SLM  (fire unit: TOC, TRML-4D, 3 launchers x 8 missiles)

## `NASAMS` - NASAMS fire unit

Era: Modern · Users: Norway, USA, Netherlands, Finland, Spain, Ukraine · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| C2 | `NASAMS_Command_Post` | 1 |  |  | Fire Distribution Center |
| SR | `NASAMS_Radar_MPQ64F1` | 1 |  |  | AN/MPQ-64F1 Sentinel |
| LN | `NASAMS_LN_C` | 3 | 6 | ring 400 m | AIM-120C canisters (LN_B for AIM-120B) |

Essential roles: C2, SR, LN

Sources:
- https://en.wikipedia.org/wiki/NASAMS  (fire unit: 1 FDC, 1 Sentinel, 3 launchers x 6 missiles; battery = 3 fire units)

## `PANTSIR` - SA-22 Greyhound (Pantsir-S1) battery

Era: Modern · Users: Russia, Syria · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `CHAP_PantsirS1` | 4-6 | 12 | spacing 300 m | Currenthill pack unit (free, in CoreMods) |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/Pantsir_missile_system

## `SAG-RU` - Russian surface action group

Era: Modern · Users: Russia · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| NAVAL_AD | `MOSCOW` | 1 |  |  | Slava-class cruiser, SA-N-6 |
| NAVAL_AD | `NEUSTRASH` | 1 |  | spacing 3000 m |  |
| NAVAL_AD | `REZKY` | 1 |  | spacing 3000 m |  |
| NAVAL_AD | `MOLNIYA` | 2 |  | spacing 2000 m |  |

Essential roles: NAVAL_AD

Sources:
- https://en.wikipedia.org/wiki/Slava-class_cruiser

## `TOR-M2` - SA-15 Gauntlet (Tor-M2) battery

Era: Modern · Users: Russia, Belarus · *approximate*

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| SHORAD | `CHAP_TorM2` | 4 | 16 | spacing 300 m | Currenthill pack unit (free, in CoreMods) |

Essential roles: SHORAD

Sources:
- https://en.wikipedia.org/wiki/Tor_missile_system#Tor-M2

## `AAA-US-WWII` - US automatic-weapons AAA section (WWII)

Era: WWII · Users: USA, UK · *approximate*

> **Requires the DCS: WWII Assets Pack DLC.** A mission that uses these units only loads for players and servers that own it; Janus warns about this in the setup report and `spawnBattery` refuses the preset when the DLC is missing.

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `M45_Quadmount` | 2-4 |  | spacing 60 m | M45 quad .50 cal |
| AAA | `M1_37mm` | 0-2 |  | spacing 80 m |  |
| AAA | `bofors40` | 0-2 |  | spacing 80 m | Bofors 40 mm (core unit) |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/M45_Quadmount

## `EW-WWII-GERMAN` - German radar site, Freya + Würzburg (WWII)

Era: WWII · Users: Germany · *approximate*

> **Requires the DCS: WWII Assets Pack DLC.** A mission that uses these units only loads for players and servers that own it; Janus warns about this in the setup report and `spawnBattery` refuses the preset when the DLC is missing.

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| EWR | `FuMG-401` | 1 |  |  | Freya LZ early warning |
| EWR | `FuSe-65` | 1-2 |  | spacing 200 m | Würzburg-Riese tracking |
| POWER | `Maschinensatz_33` | 0-1 |  |  |  |

Essential roles: EWR

Sources:
- https://en.wikipedia.org/wiki/Freya_radar
- https://en.wikipedia.org/wiki/W%C3%BCrzburg_radar

## `FLAK-88` - Heavy Flak battery, 8.8 cm Flak 18/36/37 (WWII)

Era: WWII · Users: Germany · *approximate*

> **Requires the DCS: WWII Assets Pack DLC.** A mission that uses these units only loads for players and servers that own it; Janus warns about this in the setup report and `spawnBattery` refuses the preset when the DLC is missing.

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `flak18` | 4 |  | ring 60 m | 4-gun heavy battery (6 later in the war) |
| AAA_FC | `KDO_Mod40` | 1 |  |  | Kommandogerät 40 director |
| AAA | `Flakscheinwerfer_37` | 0-2 |  | ring 300 m | searchlights for night defence |
| POWER | `Maschinensatz_33` | 0-1 |  |  |  |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/8.8_cm_Flak_18/36/37/41  (batteries of 4-6 guns with a Kommandogerät director)

## `FLAK-LIGHT` - Light Flak platoon, 2 cm Flak 38 / 3.7 cm (WWII)

Era: WWII · Users: Germany · *approximate*

> **Requires the DCS: WWII Assets Pack DLC.** A mission that uses these units only loads for players and servers that own it; Janus warns about this in the setup report and `spawnBattery` refuses the preset when the DLC is missing.

| Role | DCS type | Count | Missiles | Layout | Note |
|---|---|---|---|---|---|
| AAA | `flak38` | 3-4 |  | spacing 60 m |  |
| AAA | `flak36` | 0-2 |  | spacing 80 m | 3.7 cm Flak 36 |

Essential roles: AAA

Sources:
- https://en.wikipedia.org/wiki/2_cm_Flak_30/38/Flakvierling

