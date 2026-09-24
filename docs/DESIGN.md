# Janus IADS — design (draft 0.5, 2026-09-24)

*Janus: the two-faced Roman god who looks both ways at once.*
Janus runs integrated air defence networks for **both coalitions in the same mission**. It is one
standalone Lua file for DCS World, written from scratch.

---

## 1. Goals
1. **A real integrated network.** It covers command, early warning, SAM batteries, point defence,
   naval units, power and comms nodes, and airborne sensors. Losing a node degrades the network
   instead of just deleting a unit.
2. **Both sides from one engine.** Red and blue differ only in their **doctrine profiles**: how
   authority is delegated, how emissions are controlled, how HARM defence works and which systems
   they use.
3. **HARM defence that works in seconds.** It is triggered by launch events and gated by what the
   defenders could plausibly see. Our test showed Medusa 1.5.0 taking about 2 minutes, which is too
   slow (see medusa-iads/medusa#41).
4. **Efficient.** Janus is driven by events and runs on a budgeted update loop, so running both
   coalitions costs well under twice as much as one.
5. **Measurably better.** Before any claim is made, Janus must beat Skynet 3.5.0 across repeated
   runs on the same test bench scenario.
6. **Easy for anyone, including people who don't code.** Install it with one trigger and no Lua.
   Name your groups, and it works. Every instruction is written for a mission maker who has never
   opened a script. See §5.

## 2. Non-goals (v1)
- Not a dynamic campaign, a spawner or a GCI voice system. It provides hooks for those instead.
- Janus does not fly fighters. The optional **fighter hand-off** module only passes tracks and
  commit requests to mission code or other scripts.
- Janus does not fake physics. Every shot is fired by DCS's own AI. Janus decides *who* emits and
  engages, *when* and *what at*.

## 3. Principles
| | |
|---|---|
| Runtime | Lua 5.1, DCS's sanitized scripting environment (no `io`/`os`/`lfs`/`require`) |
| Dependencies | **None.** No MIST, MOOSE or other framework. It works alongside them |
| Distribution | One file, `janus.lua`, loaded with a DO SCRIPT FILE at mission start |
| Globals | One table, `JANUS` |
| Licence | **GPL-3.0.** Code is written new. Skynet is also GPL-3.0, so borrowing a piece of it with attribution is allowed if it ever helps. Medusa is AGPL-3.0: ideas only, no code, so Janus doesn't become AGPL |
| Safety | Every scheduled function and event handler is wrapped in xpcall. Errors are tagged and rate-limited so one failure can't stop the network |
| Multiplayer | Assumes a dedicated server, no local player, and mission time that stops while paused. Tolerates units spawned by Olympus/scripts and units that stop existing |

## 4. Architecture

```
            ┌────────────── JANUS engine (shared) ──────────────┐
 DCS events │ Event bus → Track picture → Threat eval → WTA → EMCON │ → unit AI options
 (shot,hit, │        ▲              ▲             │            │   (alarm state, ROE,
 dead,birth)│   Sensor poll    Launch detect      └→ Point-defence cueing   emission on/off)
            └───────────────────────────────────────────────────┘
               per network: nodes, links, doctrine, state
     RED network(s)  ──────────────  BLUE network(s)   (any number per coalition)
```

### 4.1 Network model
A **network** belongs to one coalition and has a doctrine profile. A coalition can run several
networks, for example a national IADS plus a separate naval group.

Node types:
| Node | Role | Examples |
|---|---|---|
| **Command (C2)** | Coordinates the network. Losing it pushes subordinate nodes toward autonomy | Command post, S-300 54K6, Patriot ECS/CP, HQ bunker |
| **Comms / relay** | Links nodes to C2. Destroying one cuts the nodes behind it | Relay tower, comms truck, static object |
| **Power** | Powers C2, EW or sites. Losing it drops the node or puts it on a timed reserve | Generator, power-plant static |
| **Early warning** | Long-range search that feeds the track picture | 55G6, 1L13, FPS-117, Dog Ear; SAM search radars acting as EW |
| **Airborne sensor** | AWACS/AEW feeding the network. Coverage moves with the aircraft | A-50, E-3, E-2 |
| **Battery (LR/MR)** | Long/medium-range SAM site | SA-2/3/5/6/10/11, HQ-2/9, Patriot, Hawk, NASAMS* |
| **SHORAD** | Short-range area defence | Roland, Osa, Strela, Chaparral, Avenger, Linebacker, HQ-7 |
| **Point defence** | Protects a named asset, including engaging incoming weapons | Tor, Pantsir*, Tunguska, **C-RAM (`HEMTT_C-RAM_Phalanx`)** |
| **AAA** | Guns, radar-directed or barrage, cued by the network, with flak-trap tactics | KS-19 100 mm, S-60 57 mm, ZU-23, Shilka; Vulcan, Gepard* |
| **Naval** | A ship as both sensor and shooter, grouped as a task force | Ticonderoga, Arleigh Burke, Perry; Moskva, Molniya, Type 052/054* |

\* The unit type name must be confirmed against the current DCS unit list (phase 0).

**Links** say which C2 a node reports to, which sensors cue which batteries, and which point
defence protects which asset. By default they are **inferred** from distance and system role. They
can also be set **explicitly** by name tags or through the Lua API.

### 4.2 Track picture
- **Sensor polling** goes through `Controller:getDetectedTargets()` on emitting sensors. It is
  **budgeted and round-robin**: N sensors per tick, with results cached per tick. Each coalition's
  sensors are polled once, however many networks use them.
- **Fusion:** detections of the same object merge into one track, with position history, speed,
  classification (fixed-wing / helicopter / missile / unknown) and the sensors that hold it.
- **Classification:** Janus uses the DCS category of the detected object where DCS reports it. Its
  own kinematic rules only fill gaps; Janus never waits minutes to decide.

### 4.3 Threat evaluation and weapon-target assignment (WTA)
- **Threat score:** time-to-weapons-release against defended assets, closure, altitude and type.
- **Battery choice:** a **kill-probability estimate** (range/altitude envelope from DCS unit data,
  aspect, target speed, ammo left). The best battery engages. Others stay dark unless doctrine says
  to salvo or use layered engagements.
- **Handoffs:** passes a target from EW to battery and from battery to battery as it moves, with
  hysteresis so radars don't flicker on and off.
- **Point defence can bid, at a discount.** Point-defence and SHORAD units (Tor, Pantsir, C-RAM,
  Avenger…) take part in battery choice, but their bids are weighted down (per doctrine), so they
  are saved for defending their asset unless they really are the best shooter. *(Idea from the
  Medusa author's planned WTA change, medusa-iads/medusa#41; our own implementation.)*

### 4.4 Emission control (EMCON)
Doctrine picks a policy per node role: **dark until cued**, **periodic search**, **rotating**
(sites take turns emitting) or **always on**. Emitting time is the main cost of being found by
ELINT (Hound, players' RWR), so every policy aims to minimise it.

### 4.5 Launch detection and HARM defence
1. `S_EVENT_SHOT` gives the weapon, the launcher and (for most guided weapons) the target at once.
2. **Plausibility gate:** a defender may react only if one of its network's emitting sensors holds
   the **launcher or the weapon** within its detection envelope and line of sight. The reaction is
   delayed by doctrine and crew skill (e.g. veteran 2–4 s, green 8–15 s, plus random spread). This
   keeps it fair.
2a. **Short confirmation, not a long one.** Before a site commits to the response ladder, it needs a
   brief confirmation: the weapon must still be tracked, and be closing on an emitter, for a
   doctrine-set number of sensor updates (default ~3), or be held by two sensors. This stops false
   alarms (e.g. an air-to-air missile or a jet that merely points at a site) without the minutes-long
   delay we measured in Medusa 1.5.0. Doctrine can allow mistakes: green crews may react late or to
   the wrong threat, on purpose. *(The Medusa author's next version uses 5 scans, ~15 s; ours is
   triggered by the launch event, so it can be shorter.)*
3. **Response ladder** (per doctrine, per battery): point defence engages → radar shutdown with a
   timed restart → decoy emission from a spare radar → relocation of mobile systems → accept the hit
   (for sites ordered to hold).
4. The same path handles **red ARMs against blue** (Kh-58, Kh-25MPU, Kh-31P) and **blue ARMs against
   red** (AGM-88, ALARM), plus cruise missiles and guided bombs for point defence.
   **Probe finding (run 1, 2026-09-24):** DCS's land Phalanx (`HEMTT_C-RAM_Phalanx`) never fired at any weapon
   (ARM, guided bomb, rockets, Grad) - only at aircraft. Janus therefore classes C-RAM as radar-directed short-range
   AAA / point defence against aircraft and helicopters. **Run 2:** Tor and Pantsir DO engage ARMs (first shot 9-13 s
   after launch from an alerted site, ~31 s cold; kill ~20 s after launch; 3 of 5 HARMs downed, but two got through
   while the site was busy). Patriot tracks weapons but never fires at them. EW radars report a launched weapon
   within a second via `getDetectedTargets`, which is the sensor input for the plausibility gate.

### 4.6 Degradation and autonomy
- Losing a C2 or its comms link means subordinate nodes switch to **autonomous mode** after a
  doctrine delay. They use only their own sensors and fall back to local EMCON rules.
- A lost EW or AWACS means batteries it alone covered become autonomous. This is re-evaluated on a
  slow timer and on every node's death or return.
- A battery with a lost or damaged radar is degraded or offline. Mobile systems may relocate and
  come back up.
- Units spawned later are picked up by name (`S_EVENT_BIRTH`) and linked automatically.

### 4.7 Doctrine profiles (data, not code)
Shipped profiles, which mission makers can copy and edit:
| Profile | Summary |
|---|---|
| `SOVIET_PVO_1985` | Centralised control, strict EMCON, slow autonomy, early shutdown on HARM launch, decoys |
| `RUSSIA_MODERN` | Faster autonomy, Pantsir/Tor point defence prioritised against weapons, rotating EMCON |
| `NATO_COLDWAR` | Delegated authority, weapons-tight until identified, Hawk/Roland layering, AWACS-led picture |
| `US_MODERN` | AWACS/data-link picture, Patriot anti-ARM behaviour, C-RAM and Avenger point defence, naval integration |
| `NVA_VIETNAM_1965_72` | North Vietnamese SA-2 network: very short Fan Song emissions, sites cued by P-12/P-19 and MiG GCI, heavy AAA belts (KS-19, S-60, ZU-23), flak traps and dummy sites, frequent relocation, radar shutdown the moment a Shrike/ARM launch is seen, optical/manual tracking modes where DCS allows |
| `US_VIETNAM_1965_72` | Blue counterpart: Hawk batteries defending airbases, radar-directed guns, simple procedural control |
| `GENERIC_THIRD_WORLD` | Poor coordination, long delays, frequent always-on emitters |

Each profile sets skill-based delays, EMCON policies, HARM response ladder, autonomy delay,
salvo/layering rules, ROE and identification rules (blue: weapons tight, IFF), and relocation rules.

### 4.8 Optional modules (same file, off by default)
- **Fighter hand-off:** publishes committed tracks and scramble requests as callbacks for GCI/CAP
  scripts.
- **Base warning:** "INCOMING" siren or message for airbases and FOBs protected by C-RAM.
- **Debug view:** F10 map marks for the track picture, links, coverage and emitting sites
  (debug missions only).
- **Stats:** per-site emitting time, shots, kills and losses in the log, the same metrics the test
  bench uses.

## 4.8A Unit data sources
Janus's unit data is **generated at build time** from two sources and shipped inside `janus.lua`,
so users install nothing extra:
| Source | Gives us | Use |
|---|---|---|
| **DCS Lua datamine** (Quaggles/dcs-lua-datamine, refreshed every DCS patch) | Exact type names, sensor definitions, weapons, missile performance | Authority for what exists in DCS and its figures |
| **DCS Olympus unit databases** (`Mods/Services/Olympus/databases/units/*.json`: 351 ground, 56 naval, 140 aircraft) | Era, coalition, role ("SAM Site Parts", "AAA"), acquisition and engagement ranges, battery templates | Classifying roles, envelopes, era filters for doctrine profiles |
Where they disagree, the datamine wins and the conflict is listed in the build report
(`docs/UNIT_DATA_REPORT.md`, generated by `tools/build_unitdb.py`; Phase 0 result: 179 air-defence types, 22 range
disagreements over 15 %, none over the units that matter most). Confirmed
so far: NASAMS (`NASAMS_Radar_MPQ64F1`, `NASAMS_LN_B/C`, `NASAMS_Command_Post`), Rapier
(`rapier_fsa_*`), C-RAM (`HEMTT_C-RAM_Phalanx`), SON-9 Fire Can (`SON_9`), SNR-75 Fan Song
(`SNR_75V`) with `S_75M_Volhov`, and naval classes (TICONDEROG, USS_Arleigh_Burke_IIa, PERRY,
MOSCOW, PIOTR, NEUSTRASH, Type_052B/C, Type_054A…). **Correction (Phase 0):** the datamine only
contains what ships with DCS, and the Currenthill pack (`CHAP_*`: Pantsir-S1, Tor-M2, IRIS-T SLM…) lives in
`CoreMods` as free core content, so nothing in the database is a third-party mod. The only paid content is the
WWII Assets Pack (`./Mods/tech/WWII Units`), flagged `dlc`.

**DLC policy (decided 2026-09-24):** Currenthill units are free core content and Janus uses them like any other
unit. Paid DLC units (today only the WWII Assets Pack) are allowed in presets and profiles, but every preset that
needs them declares `requires = { "WWII Assets Pack" }` (checked by `tools/check_presets.py` against the unit
database), the preset docs show a warning box, `spawnBattery` refuses such a preset when the DLC is not installed,
and the setup report tells the mission maker that the mission only loads for players and servers that own the DLC.

## 4.9 Battery presets (real-world composition)
A library of **how real batteries are built**, sourced from open references and marked approximate
where sources disagree. Each preset lists roles and counts (search / track / C2 / launchers /
reloads), missiles per launcher, typical spacing and layout, and the era/nation variants.

Examples (to be verified in phase 0 against sources and DCS unit types):
| Preset | Composition |
|---|---|
| SA-2 (S-75), 1960s–70s | 1× Fan Song (SNR-75) + 6× launchers in a ring ("Star of David"), Spoon Rest/Flat Face acquisition, AAA ring |
| SA-3 (S-125) | 1× Low Blow + 4× launchers (2 rails each) + Flat Face acquisition |
| SA-6 (Kub) | 1× Straight Flush (1S91) + 4× TEL (2P25, 3 missiles each) + reload trucks |
| SA-11 (Buk) | 1× C2 (9S470) + 1× Snow Drift (9S18) + 6× TELAR (9A310) |
| SA-10 (S-300PS) battalion | C2 (54K6), Big Bird or Clam Shell search, Flap Lid tracking, 8–12 TEL |
| Patriot battery | 1× radar (MPQ-53/65) + ECS + EPP + comms relay + 4–8 launchers |
| Hawk battery (Phase III) | PAR + CWAR + 2× HPIR + PCP + 6× launchers (3 missiles each) |
| C-RAM section | Phalanx LPWS units + sensor, protecting a base or asset |

Uses:
1. **Spawning:** `JANUS.spawnBattery("SA-6", point, {coalition, skill, variant})` builds a
   realistically laid-out site, and optionally its AAA ring.
2. **Validation:** a Mission Editor site that is missing an essential component (e.g. SA-2 without
   a Fan Song, Patriot without a radar) is logged at start-up, so it isn't silently dead.
3. **Engine data:** ammo, reload time and redundancy feed the kill-probability model, and the loss
   of a critical radar is handled correctly.
4. **Realism mode:** optional warnings when a Mission Editor site doesn't match its real-world
   composition (for mission makers who care).

## 5. Installing and running it (for people who don't code)
This is a **hard requirement**, not a nice-to-have. A feature that needs Lua to use counts as an
optional extra, never as part of the basic setup.

### 5.0 Zero-code quick start (the whole install)
1. Download `janus.lua` from the Releases page.
2. In the Mission Editor, add a trigger: **MISSION START**, no condition, action **DO SCRIPT FILE**
   → `janus.lua`.
3. Name your air-defence groups starting with a role word (§5.1): `SAM …`, `EW …`, `CMD …` and so on.
4. Save and fly. **That's it.**

Rules that keep it that simple:
- **Starts itself.** With no settings, Janus starts both coalitions a second after loading, using
  the default doctrine for each side. You never have to type `JANUS.start()`.
- **Nothing to install on the server or PC.** You never edit `MissionScripting.lua` and never
  install a mod. Everything lives inside the `.miz`, so it works in single player, on a hosted
  game and on a dedicated server.
- **No other scripts needed.** You don't need MIST, MOOSE or anything else, and loading those
  alongside Janus does no harm.
- **Settings without code (optional).** `janus_settings.lua` is a short file, written in plain
  English, where you change a value between quotes, e.g. `RED_DOCTRINE = "SOVIET_PVO_1985"`, and
  every option has a comment saying what it does. Load it with a second DO SCRIPT FILE *before*
  `janus.lua`.
- **Settings by name (optional).** Put tags in square brackets in the group name
  (`[skill:VET]`, `[emcon:dark]`, `[protects:SAM SA-10 Hama]`). No file needed.

### 5.0.1 It tells you what it found
- At mission start Janus writes a **setup report** to `dcs.log`: networks per side, what each
  group was recognised as, links, and anything wrong, in plain English. For example:
  "SAM SA-2 Hanoi has launchers but no Fan Song radar. It will never fire. Add an SNR-75 Fan Song
  unit to the group."
- **Setup check mode** (`CHECK_MODE = true` in the settings file) also puts that report on screen
  and draws F10 map marks (networks, links, coverage rings). You can check a mission in 30
  seconds without reading a log.
- Unrecognised groups are listed with a suggestion, e.g. "'Sam SA6 site' — did you mean
  'SAM SA-6 …'?". Nothing fails silently.

### 5.0.2 Documentation written for non-coders
- **Quick start** as a one-page illustrated guide, with screenshots of each Mission Editor step.
- **"Build your first IADS in 10 minutes"** tutorial: an SA-6, an EW radar and a command post,
  then how to watch it work in Tacview.
- **Recipes** you can copy: "protect an airbase with Patriot + C-RAM", "Vietnam SAM belt with
  AAA", "carrier group air defence", "make the SAMs harder or easier".
- **Demo missions** for every map we test on, ready to open, fly and copy groups from.
- **Troubleshooting** table: symptom → cause → fix ("my SAMs never turn on", "HARMs always hit",
  "the server lags").
- **Glossary** of IADS terms (EW, EMCON, WTA, SEAD, point defence) in one line each.
- Lua API reference kept **separate**, for the people who want it.

## 5A. Mission-maker interface (names, tags, API)

### 5.1 Names (defaults, all configurable)
A group or unit is picked up by a **role word at the start of its name**. The coalition comes from
the unit, so the same words work for red and blue:
```
SAM SA-10 Hama        EW North        CMD Damascus        PD Pantsir Hama     AAA KS-19 Hama
SAM Patriot Incirlik  EW FPS-117      CMD CAOC            PD C-RAM Incirlik
COMMS Relay 1         POWER Plant 2   SHIP CG Leyte Gulf  AWACS Overlord
```
- **Optional tags** in brackets set explicit links or settings: `[net:North]`, `[cmd:Damascus]`,
  `[protects:SAM SA-10 Hama]`, `[skill:VET]`, `[emcon:dark]`.
- Mission makers who already follow Skynet's `SAM`/`EW` naming need no renaming.

### 5.2 Lua (optional; for scripters)
```lua
-- nothing needed: janus.lua starts itself with defaults
-- scripters can instead set JANUS_SETTINGS = { AUTOSTART = false } and call:
JANUS.start{ red = "SOVIET_PVO_1985", blue = "US_MODERN" }
```
There is a full API for spawned units, custom doctrine, callbacks (`onEngage`, `onHarmDetected`,
`onNodeLost`…) and runtime changes (EMCON, ROE, weapons hold).

## 6. Performance
- Driven by events. The single scheduler tick is budgeted: sensor polls, track updates and
  decisions each take a slice per tick.
- Squared distances, a spatial grid for nearby-node queries, cached DCS unit data, no
  `world.searchObjects` in the loop.
- Targets, **to be set from the first measurements**: script time per mission-minute and server
  FPS impact on the test bench at 10, 50 and 150 nodes, with and without both coalitions.

## 7. Testing
1. **Lint:** dcs-check, Lua 5.1, sanitized, zero errors.
2. **Offline harness:** a fake DCS built from real unit data. It covers links, autonomy, EMCON,
   WTA, the launch-detection gate and every doctrine profile, with a regression test for every bug.
3. **Server test bench** (the Skynet/Medusa bench, extended):
   - Red: Janus `SOVIET_PVO_1985` vs Skynet 3.5.0 on the same scenario, repeated runs. Janus must
     win on combined score (blue losses, red losses, emitting time, HARMs defeated).
   - Blue: Patriot/Hawk/C-RAM/Avenger network against red strikes with Kh-58/Kh-31P and cruise
     missiles.
   - Both sides at once: performance and correctness.
   - C-RAM capability check: how often DCS actually engages HARMs, cruise missiles, guided bombs
     and rockets, so the docs only promise what DCS delivers.
   - Vietnam: an NVA SA-2/AAA network against a US Iron Hand/strike package (Shrike-armed).
4. After each DCS patch, rerun the suite and the bench before a release is marked compatible.

## 8. Release
- A public GitHub repo (Janus IADS): `janus.lua` in releases, docs, demo missions (red, blue, both,
  naval), changelog, semantic versioning, an issue template.
- **Licence: the user decides.** MIT is permissive and gets the widest use. GPL-3.0 requires
  modifications to stay open, like Skynet.
- It stays in the StonewallC standard as the IADS **only after** it wins on the bench. Skynet
  remains the standard until then.

## 9. Phases
| Phase | Delivers | Exit gate |
|---|---|---|
| 0 | Unit data generated from the DCS datamine + Olympus databases; battery preset data with sources; project skeleton, build, harness; C-RAM/AI engagement probe mission | **Done 2026-09-24.** Probe run 1 (`docs/PROBE_RESULTS.md`): C-RAM never engages weapons in DCS (aircraft only); Kh-31P flight 102 s, unopposed |
| 0.5 | Clean probe rerun (JANUS_PROBE_V2.miz): no air-to-air weapons, sites ~250 km apart, weapon-tracking sweep | **Run 2 done 2026-09-24** (`docs/PROBE_RESULTS.md`): Tor/Pantsir shoot HARMs 9-13 s after launch (31 s cold), 3 of 5 killed; EWR tracks a HARM 0.4 s after launch; C-RAM and Patriot track but never fire at weapons. Open: Patriot vs Kh-31P/Kh-22 (red ARM shooters never launched) -> v3 probe with explicit AttackGroup tasks |
| 1 | Network model, links, C2/comms/power, EW, batteries, autonomy, EMCON | Harness green; red network runs on the bench |
| 2 | Track picture, WTA with kill probability, handoffs | Beats Skynet on the bench, excluding HARM effects |
| 3 | Launch detection and HARM defence ladder, point defence, C-RAM | Beats Skynet on the full bench, repeated runs |
| 4 | Blue doctrine, naval, AWACS, AAA, Vietnam profiles, battery-preset spawning, both coalitions at once | Blue and Vietnam benches plus dual-side performance targets met |
| 5 | Optional modules, non-coder docs (quick start, tutorial, recipes, troubleshooting), demo missions, public 1.0 | A non-coder builds a working IADS from the quick start alone (the project owner, as the test user) |

## 10. Decisions
1. Licence: **GPL-3.0** (decided 2026-09-23).
2. GitHub: **a new public repo, `janus-iads`, under Stonewalls-Claude** (decided 2026-09-23).
3. Default name words: `SAM`/`EW`/`CMD`/`PD`/`AAA`/`COMMS`/`POWER`/`SHIP`/`AWACS` (defaults kept; `AAA` added).
4. Build: `dist/janus.lua` is generated from `src/` by `tools/build.py`, each module in its own `do … end` block;
   the unit database and presets are Lua data files generated/validated by `tools/` and shipped inside the one file
   (decided 2026-09-24).
5. Lint gate: `dcs-check --ns JANUS --tests tests src tests/probe dist`, zero errors and zero warnings; the offline
   harness runs under the kit's Lua 5.1 (decided 2026-09-24).
6. DLC: Currenthill = free, used freely; WWII Assets Pack units allowed with a declared `requires`, doc box, spawn
   refusal without the DLC, and a setup-report warning (see 4.8A).
7. The probe script shares the `JANUS` namespace (`JANUS.probe`) so the one-global rule holds everywhere.
