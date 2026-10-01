# Janus IADS — design (draft 0.8, 2026-09-29)

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
   runs on the same test bench scenario. Skynet is deprecated (owner, 2026-09-29), so this comparison is made
   once, at the end (Phase 5 release gate), not during the build.
6. **Easy for anyone, including people who don't code.** Install it with one trigger and no Lua.
   Name your groups, and it works. Every instruction is written for a mission maker who has never
   opened a script. See §5.
7. **Standalone.** Janus loads and runs entirely on its own - no GCI, no StonewallC files, no Skynet, no MIST - so
   it can be published to the community like Skynet. Without a GCI script a mission still gets the full IADS
   (SAMs, EW, command posts, power, EMCON, HARM defence); AWACS is then just one more sensor in the picture.
   `JANUS.gci` (4.10) is optional and read-only: Janus never checks whether anything reads it (agreed 2026-09-29).

## 2. Non-goals (v1)
- Not a dynamic campaign, a spawner or a GCI voice system. It provides hooks for those instead; for GCI it is the
  radar and command network the GCI script runs on (4.10).
- Janus does not fly or control fighters. It feeds GCI (4.10): picture, command nodes, SAM zones, commit requests;
  the GCI script (StonewallC GCI 2.0, or any community GCI) decides and talks. Everything about fighters - voices,
  SRS, commit logic - lives in the GCI script, never in Janus.
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

**DCS limit (probe run 3):** a launcher only fires with a radar **in its own DCS group**; split radar and launcher
groups never engaged. So a Janus *battery* is always one DCS group, and network links work by controlling each
group's emissions and ROE (who emits, who may fire), never by lending one group's radar to another group's launchers.
The setup report already flags launcher-only groups as "will never fire".

### 4.1A Static command posts, radios and power (agreed 2026-09-29; Phase 2, seat parts Phase 2.5)
Command posts, radios and power plants are usually buildings, so Janus reads **DCS static objects** as network nodes,
not only ground-unit groups. A static named with a role word (`CMD North`, `COMMS North`, `POWER North`) becomes a
node with the same tags as a group. Groups still work (mobile command posts on trucks). Statics have no AI, so they
cost the server almost nothing.

What losing each one does:
| Node | If it is destroyed |
|---|---|
| **Command post** (`CMD`) | Its GCI seats are gone (4.10). Its radars and SAMs lose their command link and go autonomous per doctrine, as today. If the doctrine names an alternate command post, it takes over after the doctrine delay and the seats move there |
| **Link radio / relay** (`COMMS`) | Connects the command post to its radars and SAM sites. Sites behind it lose their link (as today); the command post falls back to a backup channel: slower cues and shorter range, set per doctrine |
| **Air-ground radio** (`COMMS ... [ag]`) | Lets the command post's GCI seats talk to fighters. Seats stay alive but drop to the doctrine's backup radio (short range, slow delivery); with no backup they see the picture but cannot talk to fighters |
| **Power** (`POWER`) | As today: the node it feeds goes on its timed reserve, then drops |

Degraded, not dead: only the command post itself kills seats; losing radios or power degrades them.

**Alternate command post** (doctrine field, e.g. `alternateCP = { delay = TIER(...), authority = ... }`, and tag
`[alt:North 2]` on the main post): real networks kept backup posts. Soviet/Russian: long takeover delay, reduced
authority; NATO/US: short delay. No alternate named -> no takeover.

Checked in DCS (probe run 6, 2026-09-30): `.Command Center`, `Bunker 1`, `Military staff`, `Shelter`,
`Comms tower M`, `TV tower`, `GeneratorF` and `Electric power box` spawn as statics (category Fortifications).
DCS fires `S_EVENT_DEAD` (often also `S_EVENT_UNIT_LOST`) when a static dies; a dead static reports `isExist()`
false and life 0. So Janus uses the event and keeps a cheap `isExist` check on its 5-s network pass as a backstop.
Statics have no `getCategoryEx` (Janus must not call it on them) and their life varies hugely (GeneratorF 10, Comms
tower 200, Military staff 1200, Command Center 4000, Shelter 8000), which is fine: a hardened post should be hard
to kill. Not yet seen: a `.Command Center` destroyed, ME-placed statics.

### 4.2 Track picture
- **Sensor polling** goes through `Controller:getDetectedTargets()` on emitting sensors. It is
  **budgeted and round-robin**: N sensors per tick, with results cached per tick. Each coalition's
  sensors are polled once, however many networks use them.
- **Fusion:** detections of the same object merge into one track, with position history, speed,
  classification (fixed-wing / helicopter / missile / unknown) and the sensors that hold it.
- **Classification:** Janus uses the DCS category of the detected object where DCS reports it. Its
  own kinematic rules only fill gaps; Janus never waits minutes to decide.
- **Identification (agreed 2026-09-29):** a track's exact aircraft type is known only when DCS says the detecting
  sensor knows it: `getDetectedTargets()` returns a `type` flag per detection (DCS's own model of NCTR / ESM /
  visual ID). Once any sensor holding the track reports `type = true`, the track carries its DCS type name from
  then on (until the track is dropped). Until then it has only its class. Doctrine can add an ID delay by crew tier.
  **Probe run 6 (2026-09-30):** ground EW radars *never* report the type (313 km to overhead); AWACS (E-3A, A-50)
  always do from first contact (up to 380 km); SA-11 from ~100 km, SA-6 from ~50 km, SA-10 and Hawk only inside
  ~15 km; SA-2, SA-3 and Patriot never. So a network with an AWACS or Buk/Kub radars identifies through them; for a
  ground-EW-only network the doctrine fallback applies: a track held continuously by a linked command node for the
  doctrine's ID time (by crew tier) gets its type. Phase 2 builds both.

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

### 4.5 Launch detection and anti-radiation missile (ARM) defence
"ARM" means **every** anti-radiation weapon, not just HARM: AGM-45 Shrike, AGM-78 Standard ARM, AGM-88 HARM, ALARM,
Kh-58, Kh-25MP/MPU, Kh-28, Kh-31P and any future one. In DCS they are identified by
`weapon:getDesc().guidance == Weapon.GuidanceType.RADAR_PASSIVE`, so a new ARM works without a code change. Per-type
data (range, speed, whether it remembers the emitter's position after shutdown, visible motor smoke) lives in a small
table built from the DCS datamine, like the unit database.

**An ARM's job is suppression, not only kills.** A site that goes dark because it believes an ARM is coming is
suppressed even if nothing was fired. Janus models that, the bench scores it (emitting time lost), and it is why
knowing *when* a crew notices matters as much as what it does next.

1. **Ground truth vs crew knowledge.** `S_EVENT_SHOT` and the weapon object tell Janus where the missile really is.
   That is the simulation's view, never the operators'. Nothing reacts to it until the awareness model (4.5A) says a
   crew has noticed. DCS's own detection is too generous for this (probe run 2: a 1970s 1L13 VHF radar "tracked" a
   HARM 0.4 s after launch), so Janus filters it.
2. **Plausibility gate:** a site reacts only once 4.5A has made it aware: by its own sensors, by a cue, or by a network
   warning. The reaction is delayed by doctrine and crew tier (GRN/REG/VET/ACE).
2a. **Short confirmation, not a long one.** Before a site commits to the response ladder, it needs a
   brief confirmation: the weapon must still be tracked, and be closing on an emitter, for a
   doctrine-set number of sensor updates (default ~3), or be held by two sensors. This stops false
   alarms (e.g. an air-to-air missile or a jet that merely points at a site) without the minutes-long
   delay we measured in Medusa 1.5.0. Doctrine can allow mistakes: green crews may react late or to
   the wrong threat, on purpose. *(The Medusa author's next version uses 5 scans, ~15 s; ours is
   triggered by the launch event, so it can be shorter.)*
3. **Response ladder** (per doctrine, per battery): point defence engages → radar shutdown for the time in 4.5B →
   decoy emission from a spare radar → relocation of mobile systems → accept the hit (for sites ordered to hold).
   Shutting down has a price: with command-guided SAMs (SA-2, SA-3, SA-5, SA-6, S-300 track-via-missile) a missile in
   flight is lost when its guidance radar goes dark, so the ladder weighs "finish this shot" against "save the radar".
4. The same path handles **red ARMs against blue** and **blue ARMs against red**, plus cruise missiles and guided
   bombs for point defence.
   **Probe finding (run 1, 2026-09-24):** DCS's land Phalanx (`HEMTT_C-RAM_Phalanx`) never fired at any weapon
   (ARM, guided bomb, rockets, Grad) - only at aircraft. Janus therefore classes C-RAM as radar-directed short-range
   AAA / point defence against aircraft and helicopters. **Run 2:** Tor and Pantsir DO engage ARMs (first shot 9-13 s
   after launch from an alerted site, ~31 s cold; kill ~20 s after launch; 3 of 5 HARMs downed, but two got through
   while the site was busy). Patriot tracks weapons but never fires at them. EW radars report a launched weapon
   within a second via `getDetectedTargets`, which is the sensor input for the plausibility gate.
   **Run 3:** a DCS 55G6 held a HARM 2 s after launch at 104 km and a 1L13 at 106 km, so DCS's own detection must never
   be used raw (4.5A filter).


### 4.5A ARM awareness model (how a crew finds out)
Four cues, each checked per site at the scheduler rate. The first one to fire makes the site aware.

| Cue | Works for | Model |
|---|---|---|
| **Radar sees the missile** | only radars that can track small, fast targets (tier A/B below) | the weapon must be within `detectionRange × (RCS_arm / RCS_ref)^(1/4)` (radar range scales with the fourth root of target size; HARM-class ≈ 0.1 m² vs a fighter-sized reference gives roughly 35–40 % of the listed range), inside the radar's elevation limits and line of sight; then a per-scan chance that rises with crew tier and falls with how many tracks the crew already has |
| **Behaviour cue** | every site, including tier C | a known SEAD type or ARM carrier inside its ARM's range, nose on the site, or popping up / pulling up; fires *before* any launch, so pre-emptive shutdowns (real suppression) happen. Nervous or green crews trigger more often |
| **Eyes** | optical channels (Tor, Pantsir, Roland, Rapier trackers) and doctrine "observers" (NVA) | short range, daylight, visibility from the mission weather; much easier for smoky motors (Shrike) |
| **Network warning** | any site linked to C2 | another node that became aware passes it on after a comms delay; nothing arrives if the C2/comms path is down (4.6) |

| Tier | Systems | Sees the missile on radar? | Main cue | Typical response |
|---|---|---|---|---|
| **A**: built to kill precision weapons | Tor, Pantsir | yes, tens of km at best | radar + optics | engage it; site keeps emitting |
| **B**: sees it late, can't reliably hit it | S-300PS, SA-11, SA-6, Hawk, Patriot | sometimes, late in the dive | radar (late) + behaviour + network | go dark, decoy, or accept |
| **C**: effectively blind to it | SA-2, SA-3, SA-5, older EW radars | rarely | behaviour, observers, network | go dark on suspicion; crew tier decides |

Probe v3 logs the range at which each DCS radar first holds each weapon, so the filter above is tuned against
measured DCS behaviour instead of guesses. All figures here are gameplay defaults from open sources, not published
system data, and every one is a doctrine setting.

### 4.5B Going dark: how long
**Measured in DCS (probe run 3):** `enableEmission(false/true)` switches a radar off/on **at once**, while
ALARM GREEN -> RED takes ~5 s (Pantsir), ~10 s (SA-6, Tor) and ~50-55 s (SA-11, SA-10). And in DCS **both Shrike and
HARM lose their target when the radar goes dark** (4 of 4 missed, targets unharmed). So Janus switches radars with
`enableEmission`, keeps sites at ALARM RED, and **adds the restart time below itself**: otherwise every site could
flick back on instantly and dodge every ARM, which would make DCS SEAD pointless. The restart times are Janus rules,
not DCS behaviour. To keep a real ARM threat, going dark is only allowed once the crew is aware (4.5A), costs the
engagement in progress, and has a doctrine cap.

Dark time = **predicted time until impact + a margin**, then the system's **restart time**. The prediction uses the
estimated launch time (when the crew noticed, not the real launch) and the ARM type's speed; its error grows for
lower-tier crews. A site comes back early if the network learns the missile died (point defence killed it). While a
suspected ARM shooter stays in range and nose-on, the site stays dark: that is suppression working. Doctrine sets a
**maximum dark time**; after it the site restarts, relocates, or stays down (Soviet PVO waits; NVA "blinks" back up).

| System | What goes dark | Minimum | Typical | Restart to emitting | Other options |
|---|---|---|---|---|---|
| **S-300PS (SA-10)** | the engagement radar (30N6 Flap Lid); the battalion can keep searching with the 64N6 if it is not the target | 30 s | 60–120 s (a HARM from long range flies a minute or more: probe runs saw 102 s for a Kh-31P and 143–219 s for long-range HARM shots) | ~10 s from hot standby (Janus rule; DCS itself takes ~55 s from ALARM GREEN) | hand the engagement to another battery; relocate (pack and set-up are each commonly quoted at ~5 min) |
| **SA-11 Buk** | only the targeted TELAR: each TELAR has its own radar, so the others and the Snow Drift stay up | 20 s | 45–90 s | ~5–10 s (Janus rule; DCS takes ~49 s from ALARM GREEN) | the other TELARs cover; shoot-and-scoot, ~5 min to move |
| **SA-5 (S-200)** | the 5N62 Square Pair illuminator | 60 s | 90–180 s (usually targeted by long-range ARMs, and it cannot move) | ~20–30 s | none: fixed site; depends on EW and decoys |
| SA-2 / SA-3 (for comparison) | Fan Song / Low Blow | 15 s | Soviet: until impact + margin; NVA: 20–60 s "blinks" | ~10 s | dummy sites, relocation over hours, not minutes |

**Shrike and other early ARMs.** They suppress just the same, and Janus treats them the same way. The differences are
all in the per-type data: shorter range (the shooter has to come closer, so behaviour cues fire more easily), a visible
motor trail (the "eyes" cue works), and, in the real Shrike, no memory of the emitter's position, so a site that goes
dark in time makes it miss. That is why short NVA "blinks" worked against Shrike and were far riskier against later ARMs
with memory. **Probe run 3:** in DCS, Shrike *and* HARM both lose guidance when the radar switches off, so DCS itself
models no memory. Janus cannot steer a missile, so it cannot add memory back; the restart rules above and the crew
awareness model are what keep ARMs dangerous.

### 4.5C How Phase 3 implements ARM defence (built 2026-09-30)
Source: `src/janus_arm.lua` (+ hooks in `janus_emcon.lua`, `janus_wta.lua`; doctrine field `arm`). Tests:
`tests/test_arm.lua`. Bench: `tests/bench/janus_bench_05.lua`.

- **Launches.** `S_EVENT_SHOT` with a weapon whose guidance is `RADAR_PASSIVE` starts a ground-truth flight (position and
  velocity every second). Per-type speed / range / smoky motor from a table (Kh-31P, Kh-58U, LD-10 speeds measured in
  probe run 8; an unlisted ARM gets 700 m/s, 80 km). No crew is told.
- **Awareness (4.5A).** Each second, for every enemy ARM in flight and every working ground node of each network:
  - *radar*: an emitting radar holds it inside `detectionRange x factor` with line of sight, with chance `p` x crew
    (GRN 0.6 ... ACE 1.4) / (1 + tracks held / 10). Tier A (Tor, Pantsir) factor 0.4, p 0.8; tier B (modern SAM
    radars, 64H6E / FPS-117) 0.35, 0.25; tier C (SA-2/3/5, P-19, 55G6, 1L13...) 0.25, 0.03. Airborne radars never.
  - *eyes*: a group with an optical unit (UnitDB `optic`) within 10 km (15 km for smoky motors), 06:00-19:00, chance 0.5
    x crew; works while the radar is dark.
  - *confirmation*: `confirmScans` sightings inside `confirmWindow` s, or eyes, or two linked sensors holding it
    within 1.5 s of each other.
  - *network*: a confirmed ARM reaches every linked node after `netDelay[tier]` (the confirming node at once);
    unlinked nodes know only what they saw themselves.
  - *suspicion*: an identified SEAD type (F-16C, F/A-18C, F-4E, Tornado, Su-24M, Su-34, Su-25T, JF-17), moving, nose-on
    within `shooterCone` degrees and `shooterRange`, gives an emitting radar a `suspicion[tier]` chance per second of
    going dark for `suspectDark` s (never tier A, point defence, [hold] sites or a site with its own missile flying).
- **Which radar is threatened.** From what the node knows (its own last fix or the network's, dead-reckoned): a missile
  within `cone` degrees of the radar (or within 2 km), and (linked nodes) no more than 10 km beyond the first radar on
  its path that was emitting (or dark for < 120 s) when the network first judged it - fixed per missile, so the sites
  behind do not go dark one after another - and nobody once the missile is past that radar (bench 05). Time to impact =
  distance / max(missile speed, half the table speed). The most urgent threat is the one acted on. No radar holds an
  ARM beyond 50 km.
- **Ladder,** after `reaction[tier]` s: *engage* (tier A or point defence with `pdEngage`: forced up), *accept* ([hold] or
  doctrine `accept`), *covered* (`trustPd` and a working point-defence or tier-A site within `pdCoverRange`: stays up),
  *finish* (`finishShot`, own missile in flight, more than `finishMargin` s to impact), else *dark* for time to impact
  x (1 +- `predictErr[tier]`) + `margin`, at least the per-type minimum (SA-10 30 s, SA-11 20, SA-5 60, SA-2/3 15) or
  `minDark`. Point defence and tier-A sites within `pdCoverRange` of any threatened site are forced up (10 s, renewed).
- **Holding dark (suppression).** When the dark time runs out, a site stays dark in 5 s steps while an identified SEAD
  aircraft is still nose-on; `afterMax = "restart"` caps the whole dark period at `maxDark` (then 60 s with no new
  suspicion), `"wait"` has no cap. A site is released early when the network watched the missile die (last fix within
  3 s of its end) and no other known missile is aimed at it; it is then logged as "gone N km short (shot down?)" or
  "gone at a radar".
- **EMCON / WTA.** The ARM decision overrides the EMCON policy (dark beats minOn and the own-missile hold; forced-up
  still waits for the restart time). WTA offers no targets to a site dark against an ARM.
- **Scoring.** Per node: seconds dark, times dark, ARM hits (with the radar state at the hit); per network summary every
  300 s; `JANUS.arm.stats` (launched, hits, hits on dark radars, missiles seen to die short).
- **Doctrines.** SOVIET_PVO waits out the SEAD aircraft (`afterMax = "wait"`, maxDark 300); RUSSIA_MODERN trusts
  Tor/Pantsir cover; US_MODERN never goes dark on suspicion and reacts fastest; NVA blinks (maxDark 60, minDark 10,
  higher suspicion); GENERIC_THIRD_WORLD confirms slowly (5 sightings) and reacts late.
- **Not built (parked):** decoy emitters, relocation (8B research), C-RAM against weapons (DCS never does it).
- **Retested on DCS 2.9.30 (horizon fix), 2026-09-30:** slope limits, the Hawk's short reach and benches 04/05
  unchanged (probe run 9).
- **DCS reality (bench 05):** AGM-88C still hits a radar that went dark (4 of 5 hits); Kh-31P does not. Against HARMs
  going dark buys suppression (no new launches) and point defence is what saves the radar; relocation and decoys
  (parked) are the real answer.
- **Cost.** Idle networks skip nodes with no ARM state; 150 nodes / 30 aircraft stay ~1.2 ms Lua per simulated second.

### 4.6 Degradation and autonomy
- Losing a C2 or its comms link means subordinate nodes switch to **autonomous mode** after a
  doctrine delay. They use only their own sensors and fall back to local EMCON rules.
- A lost EW or AWACS means batteries it alone covered become autonomous. This is re-evaluated on a
  slow timer and on every node's death or return.
- A battery with a lost or damaged radar is degraded or offline. Mobile systems may relocate and
  come back up.
- Units spawned later are picked up by name (`S_EVENT_BIRTH`) and linked automatically.

### 4.6A How Phase 1 implements the network (built 2026-09-25)
Source: `src/janus_network.lua`, `janus_tracks.lua`, `janus_emcon.lua`, `janus_doctrine.lua`, `janus_debugview.lua`.

- **Nodes.** One node per named group. Role word → node kind: `CMD` → C2, `COMMS` → relay, `POWER` → power,
  `EW`/`AWACS` → early warning, `SAM` → battery, `PD` → point defence, `AAA` → guns, `SHIP` → naval. A node is
  *working* while it still has the equipment its kind needs (a battery needs a radar, a command post a command
  vehicle); losing that equipment degrades it even if trucks survive.
- **Networks.** One per coalition, plus one per `[net:Name]` tag. A network with no `CMD` group is a *flat* network:
  every node shares the picture and nothing goes autonomous from command loss (the zero-code case: just `SAM` and
  `EW` groups).
- **Links.** Command posts and relays form a mesh (hops up to `relayRange`, default 80 km). Every other node attaches
  to the nearest reachable hub within `linkRange` (default 120 km). Tags override: `[cmd:Name]` ties a node to one
  command post, `[relay:Name]` to one relay. Losing a hub cuts only the nodes that depended on it.
- **Power.** A `POWER` group powers nodes within `powerRange` (8 km), or those that name it with `[power:Name]`.
  When all of a node's sources die it runs on reserve for `powerReserve` (300 s), then goes offline (radar off).
  Nodes with no power group nearby are self-powered.
- **Autonomy.** A node that loses its link waits `autonomyDelay` for its crew tier, then acts alone with the
  doctrine's `autonomous` EMCON policy. A battery with no working, linked EW radar covering it also falls back to
  that policy. Links are rechecked every 5 s and on every unit death.
- **Crew tier.** `[skill:VET]` or a bare `GRN`/`REG`/`VET`/`ACE` word in the group name; default REG. It sets the
  autonomy delay and the cue reaction delay.
- **Track picture (Phase 1 part).** Emitting radars are polled round-robin (6 per second, each at most every 5 s)
  with `getDetectedTargets`; enemy aircraft and helicopters become tracks, shared across the network by linked
  sensors and kept locally by every radar. Weapons are ignored until the ARM awareness model (Phase 3).
- **EMCON.** Every radar group sits at `ALARM_STATE RED`; Janus switches emitters with `enableEmission`. Policies:
  `always`, `dark`, `cued` (up when a network track is inside engagement range × `cueFactor`, after the tier's
  `cueDelay`; held for `cueHold` after the last track), `periodic` (on/off timer, staggered per site; stays up
  while its own radar holds a target in range) and `rotating` (a share of the EW radars up at once, shifting every
  period). Janus rules: a radar that went dark may not come back before its **restart time** (per range class, per
  unit type overrides) and a radar that came up stays up at least `minOn`. `[emcon:<policy>]` forces a policy.
- **Pickup.** Groups spawned after start (Olympus, scripts, late activation) that follow the naming rules are added
  on `S_EVENT_BIRTH` and linked on the next update.
- **Check mode.** `CHECK_MODE = true` draws every node on the F10 map: a ring (engagement range, or EW range), a
  label with kind, tier and state (linked / unlinked / autonomous / offline) and a line to its command hub.
- **Cost.** Offline harness: 150 nodes and 30 aircraft cost about 0.8 ms of Lua time per simulated second.

### 4.6B How Phase 2 implements static nodes, the track picture and WTA (built 2026-09-30)
Source: `src/janus_network.lua`, `janus_tracks.lua`, `janus_wta.lua`, `janus_emcon.lua`, `janus_setup.lua`.
Tests: `tests/test_phase2.lua`. Bench: `tests/bench/janus_bench_04.lua` (DCS gate run pending).

- **Static nodes.** The setup scan reads `coalition.getStaticObjects` too; a static whose name starts with `CMD`,
  `COMMS` or `POWER` becomes a node (other role words on a static are reported and ignored). A static is alive while
  it exists with life > 0; its death arrives as `S_EVENT_DEAD` and the 5-s network pass catches any it missed.
  Statics spawned later are picked up from their `S_EVENT_BIRTH`. Tags work as on groups; bare flags like `[ag]` parse
  as `tags.ag = "true"`.
- **Air-ground radio.** `COMMS ... [ag]` is not a relay: it belongs to the command post named by `[cmd:]` or the
  nearest within `agRange` (15 km). Per post `agState` = `own` (no radio modelled), `ok`, or the doctrine's
  `agBackup.mode` (`backup` / `none`) when every radio is down (destroyed or out of power). Changes are logged and
  fire the `radio` callback (for the GCI interface, 4.10).
- **Backup link.** After the normal link search, a node that found no path but has a working, active command post
  within `linkBackup.range` stays linked with `linkVia = "backup"`; `linkBackup.delay[tier]` is added to its cue delay.
- **Alternate command post.** `[alt:Name]` on a post makes Name its alternate: the alternate stands by (not a
  command root) while the main post is up; `altTakeover[tier]` after the main post goes down (destroyed, equipment,
  power) it takes over (`takeover` callback); if the main post comes back, the alternate stands down again.
- **Track picture.** Tracks carry a number (stable per aircraft across pictures), class, position, velocity (from
  successive plots), the sensors holding them and identification: the DCS type once a detection reports `type`, or on
  the network picture after the doctrine's `idTime[tier]` of continuous track (`idBy = "held N s"`). A detection with
  neither a visual nor a range fix is ignored.
- **WTA** (`wta` doctrine fields, every 2 s, per network, linked batteries and point defence only):
  - Envelope per battery from DCS data: range from the launchers, minimum range / altitude band / channels from the
    tracking radar (defaults 5 % of range, 30-20,000 m, 1 channel).
  - Pk estimate: base by range class (LR 0.75, MR 0.7, SR 0.6); falls to 40 % between 70 % and 100 % of range;
    crossing up to x0.7; receding beyond half range x0.6; faster than 600 m/s x0.7; crew GRN 0.8 / REG 1 / VET 1.1 /
    ACE 1.2; 0 outside the envelope or with no missiles (`Unit:getAmmo`, refreshed every 10 s). Judged now and `lead`
    seconds ahead, whichever is better, so the radar is up in time.
  - Threat: time until the track reaches the nearest defended node (command post, battery, point defence, EW) at its
    closing speed (floor 50 m/s): `1000 / (t + 30)`; x1.2 below 1,500 m; helicopters x0.7.
  - DCS reality over unit data (bench 04): Hawk reach capped at 25 km (`W.DCS_REACH`), Patriot 2 channels
    (`W.DCS_CHANNELS`).
  - A shooter's channel stays reserved for the target it is already guiding, so a new, bigger threat cannot pull it
    off (bench 04 ping-pong).
  - Assignment in threat order: shooters already on the target stay while within `handoffMargin` of the best bid;
    then the best bids (point defence at `pdDiscount`) are added until the combined Pk reaches `pkGoal` or
    `maxShooters`; a shooter takes at most its channels. Logged: assigned / handed from A to B / no shooter can engage.
  - EMCON: on a WTA network a linked battery is cued only by its assignment (plus cue delay, feed delay and backup
    delay); unassigned batteries stay dark. Networks with `wta.enabled = false` (GENERIC_THIRD_WORLD) and unlinked or
    autonomous batteries keep the Phase 1 behaviour.
- **Cost.** Offline harness, 150 nodes and 30 aircraft: about 1.0 ms of Lua time per simulated second with WTA
  (0.6 ms without).

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

### 4.10 Ground control (GCI) interface (agreed 2026-09-29; core in Phase 2.5, rest in Phase 4)
Janus never flies or vectors fighters. StonewallC GCI 2.0 already controls red and blue AI fighters (AEW seats,
ground posts, SRS voices) and builds its picture from Skynet's EW radars (or "EW ..." groups). Janus replaces that
source and becomes the network GCI runs on, through one read-only table `JANUS.gci`.

**One command hierarchy, not two (agreed 2026-09-29).**
- Janus owns the command posts and the air picture. GCI controller seats sit *inside* Janus command nodes and consume
  that picture; they never build a second one. With Janus running, GCI does not read DCS radars itself; its
  "EW ..." fallback is only for missions without Janus.
- SAM orders stay inside Janus and never touch the radio (the voice/datalink delays of `c2LossCue` are timings,
  not SRS traffic). Fighter orders go out only through GCI.
- **The picture is shared, authority flows down.** Every sensor, AWACS included, feeds one picture (with the
  doctrine's link delay); anything linked to it sees the same tracks. There is no round trip: AWACS does not send its
  picture down to the command post to have orders sent back up. What runs top-down is *authority* - which node
  controls which fighters, the SAM and fighter zones, and SAM weapons control. It is published as state that GCI
  reads when it needs it, never as messages, so it costs the server nothing extra.
- **Command node kinds:** ground command post (CRC / PVO regimental CP), naval command node (carrier CIC, flagship),
  and **airborne command node** (A-50, E-3, E-2). An AWACS is both a sensor feeding the picture and a command node
  whose parent is a ground or naval command post. Janus does not fly it; it only reads its radar and tracks whether
  it is alive and linked.
- **Seats are bound to a node.** Every GCI seat names the Janus command node it sits in (name tag or GCI config).
  Node destroyed -> its seats are gone (or move to the alternate command post, 4.1A). Node unpowered -> seats silent
  until power returns. Node cut off from the picture -> its seats keep talking on a stale or thinner picture with the
  doctrine's delays. Air-ground radio lost -> seats drop to the backup radio (4.1A); `commandNodes` reports it.
- **Airspace authority belongs to the command post.** SAM-only / fighter-only / joint zones and SAM weapons control
  are command-node decisions: Janus owns and publishes them; GCI and Janus's own batteries both obey them.
- **Doctrine sets delegation** (new profile field, Phase 2.5):

  | | NATO / US | Soviet / Russian |
  |---|---|---|
  | AWACS radar | Datalinked to the network (Link 11/16); the CRC sees it within seconds | Datalinked to ground command posts |
  | Who talks to fighters | AWACS controllers, under authority delegated by the CRC | Mostly ground command posts; A-50 is chiefly a flying radar, its controllers a backup |
  | Parent CP lost | AWACS takes over as senior controller | A-50 controllers carry on, slower and with less authority |

- **Parked (not Phase 2.5):** fighters' own radar tracks (Link 16) feeding back into the Janus picture; SRS
  channels for Soviet/Russian ground-post controllers (a StonewallC standard update, GCI side).

**How GCI connects: GCI pulls, Janus never calls GCI (agreed 2026-09-29).**
- Janus never references GCI or any other consumer. There is no `GCI.setGroundSource` or other registration from
  Janus's side; that push model (GCI 2.13.0, `docs/requests/GCI_GROUND_CONTROL.md`) is replaced.
- GCI looks up `JANUS.gci` itself on each tick. It checks `JANUS.gci.version` (an integer interface version, bumped
  on any breaking change; Phase 2.5 ships version 1) and uses Janus only if it knows that version.
- GCI wraps every call into `JANUS.gci` in `pcall`. Janus missing, an unknown version or an error -> GCI warns once
  and runs in its own mode (its "EW ..." scan and flat ground post). A Janus bug never takes the fighters down.
- **Events, same tick:** GCI may subscribe with `JANUS.gci.on(event, fn, key)` (`nodeLost`, `nodeRestored`,
  `nodeDegraded`, `authorityChanged`), each carrying node name, kind, coalition and new state. It is still GCI calling
  Janus: Janus keeps an anonymous callback list, calls each one through `M.safe`, and never knows who is on it.
  - **No pile-up on hot reload:** `key` is any string the subscriber picks; subscribing again with the same event and
    key *replaces* the old callback instead of adding a second one. `on` also returns a handle, and
    `JANUS.gci.off(handle)` removes it. A subscriber that reloads can never make events fire twice.
  - **Janus reload:** `JANUS.gci.instance` is a number that changes every time Janus starts. A subscriber that sees
    it change signs up again (Janus's old callback list went with the old instance).
  - Events only make GCI react sooner. GCI still re-reads `commandNodes` every tick, so a missed event does no harm.
- **One picture, one radar list.** With Janus usable, GCI must not build its own picture (no true-position checks
  of enemy aircraft against radar range) and must not add DCS AWACS aircraft on its own: `radarHeads` and `tracks`
  already include every AWACS the network owns, so adding them again would count them twice.
- **Doctrine comes from Janus.** `commandNodes` carries the doctrine's delegation (`fighterControl` = `"ground"` or
  `"aew"`, AWACS takeover rule, alternate CP); with Janus usable it replaces GCI's own `handoffMode` setting.
- **Interface test (Janus side, Phase 2.5):** `tests/test_gci_api.lua` pins the `JANUS.gci` contract offline - the
  version, each function's output shape, empty results with no network, no error with Janus half-started, callbacks
  that throw, re-subscribing with the same key fires once, `off` works, `instance` changes on restart, and that nothing in `src/` names GCI. It includes a small reference consumer written the way GCI must
  be (pull, version check, `pcall`, fallback). The old fake-link test in dcs-missions is retired when GCI 2.14.0
  moves onto `JANUS.gci`.

Real-world basis:
- NATO/US: airspace split into MEZ (SAMs), FEZ (fighters) and JEZ (both, needs good ID); a control centre
  (CRC/TAOC) directs interceptors and sets weapons control status; centralized control = SAMs ask before firing,
  decentralized = own ROE (USMC MCWP 3-22 ch. 3; JP 3-52).
- Soviet PVO: close ground control; the same command post owns fighters and SAMs and picks the weapon per target;
  Lazur datalink sent heading/altitude/speed and could switch the fighter's radar on (RUSI 2019; ED forum).
- North Vietnam: controllers placed MiGs in ambush stations for one fast pass (MiG-17 head-on, MiG-21 from the
  rear), built around the SA-2 belts.

`JANUS.gci` (per coalition; every function returns cached tables built on Janus's own timers, so calling it every
GCI tick is cheap):
- **version** - interface version (integer, 1 in Phase 2.5).
- **on(event, fn, key)** / **off(handle)** - optional event subscription (above); **instance** - changes each Janus
  start.
- **tracks(coal)** - the coalition's fused air picture (4.2): the tracks Janus already holds, never true positions.
  Each track: id, position, altitude, velocity, classification, time last seen, and the radars/command nodes that
  hold it, plus **identification**: `typeName` (the DCS type, e.g. `F-14B`) and `typeKnown = true` only once a sensor
  holding the track has identified it (below); otherwise `typeName = nil` and only the class (fixed-wing /
  helicopter / missile) is given, and a consumer assumes the worst case for that class. GCI needs the type for its
  threat logic (missile reach, "outranged", "hot on us"); Janus's own WTA uses it for kill probability. A seat sees the picture its command node sees (with the doctrine's link delay, stale when cut off). This
  is what lets GCI drop its own picture.
0. **commandNodes(coal)** - every command node (ground, naval, airborne) with position, kind, parent, alive /
   powered / linked state and delegated authority from the doctrine. GCI binds each seat to one of these.
1. **radarHeads(coal)** - working, powered, emitting EW radars (and AWACS nodes) with position and usable range, in
   the shape GCI's `radarHeads` already uses. Losing command posts, relays or power degrades GCI exactly as it
   degrades the SAMs.
2. **controlState(coal, point)** - whether a ground controller can reach that area, from the doctrine: Soviet/Russian
   needs a linked command post (lost C2 = fighters on their own radars); US/NATO keeps the datalink picture
   (`c2LossCue` datalink); Vietnam voice-only, short range. GCI uses it to decide which ground seats exist.
3. **samZones(coal)** - live engagement zones of the coalition's *emitting, working* batteries (real reach, not
   static rings). GCI keeps friendly fighters out of friendly MEZs (doctrine: FEZ/MEZ separation) as well as
   enemy ones; an enemy site that has gone dark or died drops out of the enemy zones.
4. **commitRequests(coal)** - tracks the SAM network will not engage (outside every zone, below coverage, leakers,
   or deliberately left to fighters by doctrine) as hand-off requests; GCI decides whether to vector a flight.
   This is the old "fighter hand-off" module.
5. **Weapons control** - doctrine sets weapons free / tight for batteries near friendly fighters (JEZ vs MEZ);
   DCS's own ID never shoots friendlies, so this is about realism and fighter-or-SAM choice, not safety.

**Built (Phase 2.5 core, 2026-09-30):** `src/janus_gci.lua`, contract test `tests/test_gci_api.lua` (with the reference
consumer), bench monitor `tests/bench/janus_gci_monitor.lua`. As built:
- `version` 1; `instance` changes each start; `on(event, fn, key)` / `off(handle)`; events `nodeLost`, `nodeRestored`
  (repaired, power, linked, radio ok), `nodeDegraded` (equipment, no power, unlinked, radio backup / none),
  `authorityChanged` (alternate in command / standby); payload `{ event, name, kind, coalition, state, reason, net, t }`;
  subscribers run through `M.safe`.
- `tracks(coal [, nodeName])` -> copies `{ id, num, x, y, z, vx, vy, vz, class, typeKnown, typeName, lastSeen, holders }`
  (`id` is the DCS unit ID - contract, tested);
  with a node name: what that post sees (network picture while up and linked, plus its own radar), nothing if dead or
  unpowered.
- `commandNodes(coal)` -> `{ name, kind = "ground"|"airborne", net, tier, x, y, z, alive, powered, working, linked,
  active, inCommand, parent, alternate, alternateFor, radio = own|ok|backup|none, reach (m: the air-ground radio's
  reach now - doctrine `agReach` with the radio up or not modelled, `agBackup.range` on backup, 0 with none; an
  airborne node `agReach`), seats ([seats:n] tag), fighterControl, awacsTakeover }`. An AWACS group needs no role word:
  an airplane group made only of AWACS types (A-50, E-3A, E-2C, KJ-2000...) is an airborne node whatever its name
  (callsign-first names such as "Magic AEW ACE"; added 2026-09-30). Doctrine: SOVIET / RUSSIA / NVA / THIRD_WORLD `fighterControl = "ground"`; NATO / US
  `"aew"` with `awacsTakeover = true`; US_VIETNAM `"aew"`.
- `radarHeads(coal)` -> `{ name, x, y, z, r2, airborne, net }` for working, powered, emitting, linked EW radars and AWACS.
- `controlState(coal, point [, postName])` -> `{ ground, via, radio, reach, dist }`: a post in command whose radio
  reaches the point (its `reach` above) and a radar head covering it; the nearest such post answers, or only `postName`
  when given (additions of 2026-09-30, no version bump).
- `samZones(coal)` -> `{ name, kind, net, x, z, r, rMin, altMin, altMax, emitting, linked, tier }` for every working
  battery and point-defence group; the consumer keeps friendly fighters out of all of them and uses `emitting` for
  the enemy's.
- Not yet: an unlinked EW's voice-relayed picture in `radarHeads` (8A `c2LossCue`) - GCI sees only linked heads.

Cost: all of it reuses the Phase 1-2 picture and the 1-s coverage pass; GCI polls it on its own tick. Both sides
stand alone: Janus runs without any GCI (goal 7), and GCI 2.0 keeps working without Janus (falls back to its own
"EW ..." groups). Load order when both are used: Janus first, then GCI (STANDARDS.md to be updated when Skynet is
removed).

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
  (`[skill:VET]`, `[emcon:dark]`, `[protects:SAM SA-10 Hama]`, `[hold]` = never go dark for an ARM). No file needed.

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
  `[relay:Relay 1]`, `[power:Plant 2]`, `[protects:SAM SA-10 Hama]`, `[skill:VET]` (or just `VET` in the name),
  `[emcon:dark]` (`always`, `dark`, `cued`, `periodic`, `rotating`), `[ag]` (a `COMMS` air-ground radio, 4.1A),
  `[alt:Damascus 2]` (alternate command post, 4.1A).
- **Static objects** use the same names: a bunker named `CMD Damascus`, a comms tower `COMMS Relay 1` or
  `COMMS Damascus [ag]`, a generator `POWER Plant 2` (4.1A).
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
3. **Server test bench** (Janus benches during the build; the Skynet/Medusa comparison at the end):
   - Red: Janus `SOVIET_PVO_1985` vs Skynet 3.5.0 on the same scenario, repeated runs, **once, as the
     Phase 5 release gate**. Janus must win on combined score (blue losses, red losses, emitting time,
     HARMs defeated).
   - Every bench places each SAM on flat ground (probe runs 4-5: sloped Hawks and SA-2s never fire).
   - Blue: Patriot/Hawk/C-RAM/Avenger network against red strikes with Kh-58/Kh-31P and cruise
     missiles.
   - Both sides at once: performance and correctness.
   - C-RAM capability check: how often DCS actually engages HARMs, cruise missiles, guided bombs
     and rockets, so the docs only promise what DCS delivers.
   - Probe v3 (`JANUS_PROBE_V3.miz`): range at which each radar first holds each weapon (tunes 4.5A), Patriot vs
     Kh-31P/Kh-22, and whether a Shrike/HARM keeps guiding after its target radar goes dark.
   - Every run gets its own numbered `.miz`, log and Tacview; mission files are never overwritten.
   - Vietnam: an NVA SA-2/AAA network against a US Iron Hand/strike package (Shrike-armed).
4. After each DCS patch, rerun the suite and the bench before a release is marked compatible.

## 8. Release
- A public GitHub repo (Janus IADS): `janus.lua` in releases, docs, demo missions (red, blue, both,
  naval), changelog, semantic versioning, an issue template.
- **Licence: the user decides.** MIT is permissive and gets the widest use. GPL-3.0 requires
  modifications to stay open, like Skynet.
- Skynet is deprecated (owner, 2026-09-29, too many issues); Janus is meant to replace it in the StonewallC
  standard. STANDARDS.md still names Skynet (load order, GCI picture fallback) and is updated when Janus
  takes over; the final Janus-vs-Skynet bench (Phase 5) records the comparison.

### 8A. Phase 2 fix list (from bench 01, agreed 2026-09-27) - items 1-5 built 2026-09-27; bench 02 (2026-09-28, `docs/BENCH_RESULTS.md`) confirmed 1-3 and 5 in DCS, item 4 proven offline only; open: blue Hawks never fired
1. **EW cover after C2 loss is doctrine-driven** (`c2LossCue = { mode, range, delay[tier] }` per profile), keeping
   "linked to command" and "under EW cover" separate:
   | Doctrine | EW feed after the command post is lost |
   |---|---|
   | SOVIET_PVO_1985 / RUSSIA_MODERN | voice relay from a working EW within short range; long cue delay, coarse position; batteries fall back to their own acquisition radar sooner |
   | NATO_COLDWAR / US_MODERN | data link keeps flowing: any linked EW/AWACS still cues batteries; engagement becomes decentralized (autonomous authority) |
   | NVA_VIETNAM_1965_72 | voice and ground observers only; slow, short range |
   | GENERIC_THIRD_WORLD | none: batteries blind except their own radar (Iraq 1991 case) |
   Cost: reuses the 1-s coverage pass; no new polling.
2. POWER, COMMS and CMD nodes get no link-lost or autonomy messages (only emitters and batteries do).
3. Network summary must not list a C2 node as its own parent (`CMD North -> CMD North`).
4. Keep a site emitting while its own missiles are in flight at a live target (S_EVENT_SHOT bookkeeping).
5. Bench 02: kill the relay before CMD (or use a second network) so the relay-loss path is exercised.
6. **Hawks (probe run 4, 2026-09-29)**: DCS Hawks never fire from ground steeper than ~2 deg or inside short
   emission windows. Setup report measures and reports the slope; `periodicByType` keeps Hawks up instead of the
   periodic policy. Bench 03 (2026-09-29): 4 Su-24M killed by Hawks under Janus (cued, datalink, no EW) - done.
7. **SA-2 never launched in benches 01-03**: probe run 5 (2026-09-29) found slope again - an SA-2 on sloped ground never tracks or fires; heading, launcher count, emission switching and ALARM RED do not matter. SA-2 units added to the setup slope check. Next: place every bench SAM on flat ground and measure the slope limit for other systems.

### 8B. Phase 3 research items (parked, not for build yet)
- HARM has inertial memory (flies to the last known emitter position, larger miss distance) and the F-16 HTS pod
  allows POS/PB shots at stored coordinates: going dark lowers the hit chance but does not guarantee a miss
  (bench 01: SA-6 STR hit 39 s after going dark). Re-probe dark-after-launch timings; include Kh-58/Kh-31P.
- SAM relocation ("shoot and scoot") needs real teardown/move/set-up times per system before it is modelled.
- Moving ground units is expensive in DCS: research best practices (and possible regional culling) before any
  relocation feature; performance first.

## 9. Phases
| Phase | Delivers | Exit gate |
|---|---|---|
| 0 | Unit data generated from the DCS datamine + Olympus databases; battery preset data with sources; project skeleton, build, harness; C-RAM/AI engagement probe mission | **Done 2026-09-24.** Probe run 1 (`docs/PROBE_RESULTS.md`): C-RAM never engages weapons in DCS (aircraft only); Kh-31P flight 102 s, unopposed |
| 0.5 | Probe runs 2 (JANUS_PROBE_V2.miz) and 3 (JANUS_PROBE_V3.miz): ARM defence, weapon tracking, EMCON timing, cross-group cueing, ARM memory, janus.lua smoke test | **Done 2026-09-25** (`docs/PROBE_RESULTS.md`): Tor/Pantsir shoot HARMs 9-13 s after launch; EW radars hold ARMs at 100+ km within 2 s (filter needed); `enableEmission` is instant, ALARM warm-up 5-55 s; launchers need a radar in their own group; Shrike and HARM both miss once the radar goes dark; janus.lua runs clean in DCS. Open, not blocking: Patriot vs red ARMs (red AI never launched), SA-2/SA-5 radar state without a target |
| 1 | Network model, links, C2/comms/power, EW, batteries, autonomy, EMCON | Harness green; red network runs on the bench. **Done 2026-09-27** (`docs/BENCH_RESULTS.md`): bench 01 ran with no Janus errors; cueing, power reserve, C2 loss, 180 s autonomy, periodic EMCON, own-track hold and restart times all behaved as designed. To fix: POWER/COMMS link and autonomy log noise, C2 listed as its own parent, relay-loss path untested (bench ordering). Open: should EW cue batteries directly after C2 loss? A HARM hit an SA-6 radar 39 s after it went dark (feeds Phase 3) |
| 2 | Track picture, WTA with kill probability, handoffs; static command posts, radios and power as network nodes, link-radio backup channel, alternate command post (4.1A). **Done 2026-09-30** (4.6B): offline tests and mutation check green; bench 04 passed in DCS (`docs/BENCH_RESULTS.md`) | Static nodes degrade the network as designed; track picture, WTA and handoffs work on a Janus bench with no Janus errors (no Skynet comparison during the build; see Phase 5) |
| 2.5 | **GCI feed core** (4.10, agreed 2026-09-29; Janus side **built 2026-09-30**; **gate passed 2026-09-30** on the GCI session's `StonewallC_GCIJ_BENCH` FULL / NOGCI / NOJANUS runs, `docs/BENCH_RESULTS.md`: `janus_gci.lua`, interface test 68 checks, bench monitor; GCI 2.14.0 is the GCI session's): one command hierarchy - `JANUS.gci.commandNodes` (ground, naval and airborne command nodes, AWACS as a sensor + command node, doctrine delegation field, seat binding, air-ground radio and its backup, seats moving to the alternate command post; 4.1A), `radarHeads`, `controlState`, `samZones`, `tracks` (with identification), `version`, `instance`, `on()`/`off()`, interface test; so StonewallC GCI 2.0 can be built on Janus instead of Skynet | `tests/test_gci_api.lua` green; GCI 2.0 runs on the Janus picture (`tracks`, `radarHeads`, no picture of its own) on a bench: its seats sit in Janus command nodes and fall silent when their node dies, follow Janus EW/C2 losses per doctrine, and fighters keep out of live SAM zones; the same bench runs clean with no GCI loaded |
| 3 | Launch detection and HARM defence ladder, point defence, C-RAM. **Done 2026-09-30** (4.5C): `janus_arm.lua`, `tests/test_arm.lua` (237 checks), mutation check green; probe run 8 (red ARMs); bench 05 runs 1-2, 0 Janus errors. Closed by the owner 2026-09-30 with a bench 05 re-validation on DCS 2.9.30 (horizon fix) to follow | HARM defence works on the full bench, repeated runs |
| 4 | Blue doctrine, naval, AWACS, AAA (fire discipline built 2026-09-30: `janus_aaa.lua`, doctrine `aaa` free / flak trap; ground observers `arm.observers`), battery-preset spawning (flat ground only), both coalitions at once, rest of `JANUS.gci` (commitRequests, weapons control; 4.10). Vietnam moved to Phase 6 (owner, 2026-09-30) | Blue bench plus dual-side performance targets met; GCI runs on the Janus picture and loses control when Janus loses C2/EW. Public **beta** (0.9 pre-release) after this phase |
| 5 | Optional modules, non-coder docs (quick start, tutorial, recipes, troubleshooting), demo missions, public 1.0 | A non-coder builds a working IADS from the quick start alone (the project owner, as the test user); **Janus beats Skynet 3.5.0 on the same bench, repeated runs** (the one comparison, recorded for the release) |
| 6 | **Vietnam** (owner, 2026-09-30): NVA_VIETNAM_1965_72 tuned on a bench - flak traps on (`janus_aaa.lua`, built in Phase 4), ground spotters seeing Shrike launches (`arm.observers`, built), VHF voice reach ~150 km, Fan Song blinks, dummy sites, MiG GCI ambush stations via GCI - and US_VIETNAM_1965_72 (Hawk-defended bases). Small: mostly doctrine values on existing machinery | A Vietnam bench (NVA SA-2/AAA network vs a Shrike-armed Iron Hand/strike package) runs clean and reads like history |
| 7 | **Iran 1970s - Spellout / Peace Ruby** (owner, 2026-09-30): the US-built Imperial Iranian radar networks (19 sites built 1962-77: Spellout in the north, Peace Ruby in the south, joined by the Peace Net troposcatter link; digitised radar data to two hardened command posts, primary and backup) with the Shah-era SAMs (Improved Hawk, Rapier). Small: two sector networks, an alternate command post (`[alt:]`) and the backup link already exist | An Iran bench (two sectors, primary post lost -> backup post takes over, sectors keep sharing over the backup link) runs clean |
| 8 | **Iraq 1991 - Kari** (owner, 2026-09-30): the French-built KARI command system (national ADOC, sector operations centres, intercept operations centres, EW radars reporting up the chain), Soviet and western SAMs (SA-2/3/6/8, Roland), very heavy AAA, and how it fell apart (decapitation of the SOCs/IOCs, decoy drones making sites emit, HARMs against autonomous emitters). Bigger: needs a tiered command chain (ADOC > SOC > IOC) and decoy handling | A Kari bench (tiered C2, decoys, decapitation) runs clean and reads like history |

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
8. ARM defence covers every anti-radiation weapon (Shrike through Kh-31P), identified by passive-radar guidance.
   Crews react to what they could plausibly notice (4.5A), never to the weapon object itself; dark time follows 4.5B;
   ARM success is scored as suppression (emitting time lost), not only kills (decided 2026-09-24).
9. One command hierarchy (4.10): Janus owns command posts, AWACS command nodes and the one air picture; GCI seats sit
   inside Janus command nodes; SAM orders stay in Janus, fighter orders go only through GCI; authority flows down as
   state, the picture is shared (decided 2026-09-29).
10. Janus is standalone and publishable on its own; `JANUS.gci` is an optional read-only interface any GCI script may
    use (decided 2026-09-29). GCI pulls: it looks up `JANUS.gci`, checks `version`, calls through `pcall` and falls
    back to its own mode; Janus never calls or names GCI. `JANUS.gci.tracks` shares the fused picture, so GCI builds
    none of its own (decided 2026-09-29).
11. Command posts, radios and power can be static objects (4.1A). Command post lost = its seats lost; radios and
    power lost = degradation. Two radios: link radio (`COMMS`, command post to sites) and air-ground radio
    (`COMMS [ag]`, seats to fighters), each with a doctrine backup; alternate command posts are a doctrine field
    (decided 2026-09-29).
