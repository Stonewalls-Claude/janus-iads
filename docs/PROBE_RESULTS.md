# Probe results (Phase 0 / 0.5)

Each run has its own mission file, never overwritten (`JANUS_PROBE.miz`, `JANUS_PROBE_V2.miz`, ...); its log and
Tacview are saved under the same name in `I:\Claude-Workspace\logs`.

## Run 3 (2026-09-25 03:03-03:34 UTC, JANUS_PROBE_V3.miz, probe v0.4 + janus.lua)

Raw log: `I:\Claude-Workspace\logs\janus_probe_run3_20260925.log`; Tacview `Tacview-20260924-230341-DCS-Host-JANUS_PROBE_V3`.
Server state before the run: stopped since 01:51 UTC (last mission `Alpha_Sortie_1_Syria_rev2.miz`), nobody connected;
started via WebGUI `startServer`, then V3 loaded.

### A. Switching radars on and off (7 red systems, weapons hold, as seen by `unit:getRadar()`)
| System | ALARM GREEN -> RED (first) | EMISSION OFF | EMISSION ON | ALARM GREEN | ALARM RED again |
|---|---|---|---|---|---|
| SA-10 (S-300PS) | not up within 60 s | (already off) | **on at once** | off at once | **55 s** |
| SA-11 | not up within 60 s | (already off) | **on at once** | off at once | **49 s** |
| SA-6 | 11 s | off at once | on at once | off at once | 11 s |
| SA-15 Tor | 10 s | off at once | on at once | off at once | 11 s |
| Pantsir-S1 | 5 s | off at once | on at once | off at once | 5 s |
| SA-2 | never showed a radar | - | - | - | - |
| SA-5 | never showed a radar | - | - | - | - |

- **`enableEmission(false/true)` is instant** (inside one 1-s sample) for every system that showed a radar, and
  `enableEmission(true)` brought the SA-10 and SA-11 up at once even though ALARM RED had not finished warming them
  up. **ALARM GREEN -> RED has a real warm-up**: ~5 s Pantsir, ~10 s SA-6/Tor, ~50-55 s SA-11/SA-10.
- SA-2 and SA-5 never reported an active radar via `getRadar()` in ALARM RED with no target in range; this needs a
  target to answer (probe v4).
- The RWR observer (unarmed F-16C, `getDetectedTargets(Controller.Detection.RWR)`) never reported any emitter, so RWR
  timings were not measured; the AI RWR query does not appear to work this way. Not needed: `getRadar()` is enough.

### B. Can a launcher-only group fire using another group's radar?
**No.** Two unarmed C-130s flew through the area for ~15 min. The split SA-10 (radars in one group, launchers in
another) and split SA-6 never fired. The complete SA-11 control group shot down both C-130s (hits at 563 s and 1077 s).
DCS launchers only work with a radar **in the same group**.

### C. Do ARMs keep guiding after the target radar goes dark 5 s after launch?
| Weapon | Target | Flight | Closest approach | Target |
|---|---|---|---|---|
| AGM-45A Shrike #1 | SA-10 64N6 search radar (the F-4E picked the SA-10, not the SA-2) | 19.5 s | 5,085 m | alive |
| AGM-45A Shrike #2 | same | 19.9 s | 4,835 m | alive |
| AGM-88C HARM #1 | SA-6 1S91 | 218.9 s | 640 m | alive |
| AGM-88C HARM #2 | SA-2 P-19 | 142.8 s | 3,447 m | alive |
**In DCS both Shrike and HARM lose the target when its radar goes dark**: all four missed and every target survived.
In run 2, HARMs whose target kept emitting hit. So in DCS, going dark early enough always defeats an ARM, HARM included.

### D. Patriot vs red ARMs / anti-ship missile
Su-34 (4x Kh-31P), Su-24M (2x Kh-58U) and Tu-22M3 (3x Kh-22) were given `AttackUnit` on the Patriot radar. **None
launched**, as in run 2 with SEAD/EngageTargets. The Patriot fired 3 PAC-2s at the Tu-22M3. Red AI ARM launches
against the Patriot site could not be produced by either tasking; Patriot vs ARM stays unanswered.

### E. Range at which a radar first holds a weapon
The 55G6 EW radar held the first HARM **2 s after launch at 103.8 km**; the 1L13 held one at **106 km**. Both then
tracked every HARM continuously. Neither targeted SAM radar ever listed the HARM (they were dark 5 s after launch).
DCS early-warning radars see ARMs at 100+ km within seconds, far beyond anything plausible. This confirms that the
4.5A filter is essential.

### F. janus.lua in DCS (first time)
Loaded after the probe with **no script errors**. The setup report recognised 16 red and 1 blue groups with the right
roles and flagged all four split groups as "will never fire", naming the missing radar type for each launcher group.

---

## Run 2 (2026-09-24, JANUS_PROBE_V2.miz, v0.3 layout: no air-to-air weapons, sites ~250 km apart)

Raw log: `I:\Claude-Workspace\logs\janus_probe_run2_20260924.log`.

### Findings
1. **DCS point defence DOES engage anti-radiation missiles, in seconds.** Five AGM-88C were fired at the red site
   (2x Tor 9A331, 2x Pantsir-S1, 1L13 EWR):
   | HARM | Launched | First defender shot | Result |
   |---|---|---|---|
   | #1 (at Pantsir-2) | 634.6 s | Pantsir 665.3 s (+31 s) | killed by Pantsir at 670.7 s (+36 s) |
   | #2 (at Pantsir-1) | 693.8 s | - | **hit Pantsir-2 at 736.9 s** (the site's attention was on #3/#4) |
   | #3 (at Tor-1) | 701.9 s | Pantsir 711.1 s (+9 s), Tor 715.1 s (+13 s) | killed at 721.1 s (+19 s) |
   | #4 (at Pantsir-2) | 704.6 s | Tor 719.4 s, Pantsir 716.0/723.9 s | killed at 721.5 s (+17 s) |
   | #5 (at Pantsir-1) | 767.2 s | - (Pantsir-2 dead, Tor busy on the F-16s) | **hit Pantsir-1 at 776.4 s** |
   3 of 5 HARMs shot down; both Pantsirs lost; Tor survived and then killed both F-16s (hits at 759 s and 775 s).
   Reaction time once the site was "warmed up": 9-13 s from launch to first shot. The first, cold, engagement took 31 s.
2. **Radars track incoming weapons, and quickly.** The 1L13 EWR reported the first HARM 0.4 s after launch
   (`getDetectedTargets` returns weapon objects, `Object.Category.WEAPON`, with `visible`/`type` flags). Tor and Pantsir
   picked the same HARM up 10-25 s later at closer range. **This is the input the plausibility gate (DESIGN 4.5 step 2)
   needs: the network's sensors really do hold the weapon.**
3. **C-RAM tracked the KAB-500Kr, the S-8 rockets, Grad rockets and FAB-250s but never fired at any of them** (0 shots
   at weapons; 456 gun hits, all on aircraft). Run 1 finding confirmed: C-RAM in DCS is a gun for aircraft.
4. **Patriot tracked the KAB-500Kr, Grad rockets and FAB-250s and never fired at them either**; it fired 3 PAC-2s at the
   Su-34s and the Tu-22M3 (all hits). Patriot does not do anti-missile work in DCS (at least not against bombs and
   rockets; it was never presented with a Kh-31P, see 6).
5. **Avenger 10 Stingers, 8 hits, all aircraft.** Grad: 40 rockets, 12 hits - on the Patriot radar, ECS, AMG, a C-RAM
   and an Avenger: unopposed artillery is a real threat to a Patriot site in DCS.
6. **Not answered:** the red ARM shooters (Su-24M Kh-58U, Su-34 Kh-31P) with the SEAD task + `EngageTargets Air Defence`
   flew their route and never launched, although the Patriot radar was emitting (it engaged other aircraft). The
   Tu-22M3 never launched its Kh-22 either. Next probe (v3) gives them an explicit `AttackGroup` on the Patriot group with
   `weaponType` = ARM / AShM, and a lower ingress so they are not out of parameters. Patriot vs Kh-31P/Kh-22 stays open.

### What this means for Janus
- The HARM-defence ladder's first rung ("point defence engages") is real for Tor and Pantsir: expect a shot 9-13 s after
  launch from an alerted site, 30 s from a cold one, and a kill about 20 s after launch. HARM #2 and #5 show the
  weakness Janus should fix: DCS's own point defence engages one threat at a time and forgets the site it was
  protecting; Janus's WTA (DESIGN 4.3, "point defence bids at a discount") should keep one shooter on the incoming
  weapon while the other keeps the radar covered, and shut the targeted radar down when no interceptor is free.
- Weapon tracks from EW radars arrive within a second of launch - plenty for the "short confirmation" (4.5 2a) to use
  2-3 sensor updates and still react in under 10 s.
- Blue point defence in DCS is guns and Stingers against aircraft; there is no blue anti-missile capability to build
  on, so blue doctrine (US_MODERN) defends its radars by shutdown/decoy/relocation, not interception, unless Phase 0.5b
  shows Patriot engaging a Kh-31P.


Note: DCS raises S_EVENT_SHOT for missiles, bombs and rockets, not for gun rounds, so gun "shots" are 0 while their hits are counted.

## Weapons engaged by defenders

| Attacking weapon | Launched | Hit by a defender | First hit after launch (s) | Defender |
|---|---|---|---|---|
| AGM_88 | 5 | 3 | 36.1 | CHAP_PantsirS1, Tor 9A331 |
| C_8CM | 8 | 0 |  |  |
| FAB-250-M62 | 8 | 0 |  |  |
| FIM_92C | 16 | 0 |  |  |
| GRAD_9M22U | 40 | 0 |  |  |
| KAB_500Kr | 2 | 0 |  |  |
| MIM_104 | 3 | 0 |  |  |
| SA57E6 | 7 | 0 |  |  |
| SA9M330 | 6 | 1 | 2.1 | F-16C_50 |

## Per defender / shooter

| Type | Shots | Hits on weapons | Hits on units |
|---|---|---|---|
| CHAP_PantsirS1 | 7 | 2 | 0 |
| F-16C_50 | 5 | 1 | 15 |
| Grad-URAL | 40 | 0 | 12 |
| HEMTT_C-RAM_Phalanx | 0 | 0 | 456 |
| M1097 Avenger | 16 | 0 | 14 |
| Mi-24P | 8 | 0 | 5 |
| Patriot ln | 3 | 0 | 0 |
| Patriot str | 0 | 0 | 4 |
| Su-25T | 8 | 0 | 17 |
| Su-34 | 2 | 0 | 9 |
| Tor 9A331 | 6 | 1 | 2 |
| nil | 0 | 0 | 149 |

---

## Run 1 (2026-09-24, JANUS_PROBE.miz, v0.2 layout)

Raw log: `I:\Claude-Workspace\logs\janus_probe_run1_20260924.log` (also the Tacview `Tacview-20260924-082209-DCS-Host-JANUS_PROBE`).

### Findings
1. **C-RAM (`HEMTT_C-RAM_Phalanx`) did not engage a single weapon**: not the Kh-31P, the KAB-500Kr, the S-8 rockets,
   nor 40 Grad rockets (21 of which hit the trucks it was protecting). It fired 283 gun rounds - all at the Mi-24s.
   In DCS the land Phalanx behaves as radar-directed AAA against aircraft, not as counter-rocket/missile. **Design
   change:** Janus treats C-RAM as short-range AAA/point defence against aircraft and helicopters; the "C-RAM
   intercepts incoming weapons" feature (DESIGN 4.5 step 3, 4.8 base warning) is downgraded to "if DCS ever does it,
   Janus records it" and the docs must not promise interception.
2. **Kh-31P vs the Hawk search radar: launched at 711 s, impact at 813 s = 102 s of flight**, and nothing shot at it
   (the Patriot at B2 was the intended target but the Su-34 chose the closer Hawk bait). 100 s is the budget the
   HARM-defence ladder (DESIGN 4.5) has to work with for a long-range ARM; AGM-88 from closer will be far less.
3. **Avenger: 16 Stingers, 16 hits, all on aircraft**; never fired at a weapon.
4. **Grad: 40 rockets, 21 hits on the truck group** from 15 km with FireAtPoint - usable as a stand-in artillery threat.
5. **Not answered (run design fault):** blue F-16s carried AIM-120s and met the red attackers head-on; they killed the
   Fencers before any Kh-58 launch and never fired a HARM, so **Tor and Pantsir vs ARM is untested**, as is Patriot
   vs Kh-31P. Phase 0.5 rerun: no air-to-air weapons, blue sites + red attackers in the south, red sites + blue
   attackers ~150 nm north, so the two air packages never meet.
6. Probe mechanics: DCS raises `S_EVENT_SHOT` for missiles/bombs/rockets but not gun rounds; `S_EVENT_HIT` on a
   weapon never occurred, so `HIT-WEAPON` is unproven as a signal (a `DEAD` line with a numeric name and nil type at
   1347 s was most likely a weapon dying, i.e. a weapon's death does arrive as `S_EVENT_DEAD` with the object already
   gone). Phase 0.5 adds a per-tick check of `Weapon` objects in flight via `getDetectedTargets` on the defenders.


Note: DCS raises S_EVENT_SHOT for missiles, bombs and rockets, not for gun rounds, so gun "shots" are 0 while their hits are counted.

### Weapons engaged by defenders

| Attacking weapon | Launched | Hit by a defender | First hit after launch (s) | Defender |
|---|---|---|---|---|
| AIM_120C | 4 | 0 |  |  |
| C_8CM | 8 | 0 |  |  |
| FAB-250-M62 | 8 | 0 |  |  |
| FIM_92C | 18 | 0 |  |  |
| GRAD_9M22U | 40 | 0 |  |  |
| KAB_500Kr | 5 | 0 |  |  |
| X_31P | 1 | 0 |  |  |

### Per defender / shooter

| Type | Shots | Hits on weapons | Hits on units |
|---|---|---|---|
| F-16C_50 | 4 | 0 | 3 |
| Grad-URAL | 40 | 0 | 21 |
| HEMTT_C-RAM_Phalanx | 0 | 0 | 283 |
| M1097 Avenger | 18 | 0 | 22 |
| Mi-24P | 8 | 0 | 0 |
| Su-25T | 8 | 0 | 0 |
| Su-34 | 6 | 0 | 20 |
| nil | 0 | 0 | 4 |

## Run 4 - Hawk probe (2026-09-29, `JANUS_PROBE_HAWK.miz`)
Why did the bench 02 Hawks never fire? Plain DCS (no janus.lua), z690, DCS 2.9.29, 25 min, loaded 00:57 UTC.
Seven blue sites, each with its own pair of unarmed red Su-24M flying straight over it at 15,000 ft.
Log: `I:\Claude-Workspace\logs\janus_probe_hawk_20260929.log`.

| Site | Setup | Worst unit slope | Detected | Fired (first shot) | Kills |
|---|---|---|---|---|---|
| H1 | flat, full battery (PCP, SR, CWAR, TR, 3 LN), no route | 1.0 deg | yes (SR + CWAR, 45 nm) | yes, TR locked at ~14 nm | 2/2 |
| H2 | flat, bench 02 set (no CWAR) | 0.7 deg | yes (SR) | yes, ~15 nm | 2/2 |
| H3 | full battery on a mountainside | 11.6-31.7 deg | yes (SR + CWAR) | **never** - TR never locked, targets 0.2 nm overhead | 0 |
| H4 | flat, full battery + one-point "Off Road" route | 1.3 deg | yes | yes, ~15 nm | 2/2 |
| H5 | flat, `enableEmission(false)` at 5 s, `(true)` at 150 s | 0.6 deg | yes | yes | 2/2 |
| H6 | flat, ALARM RED + emission 15 s on / 60 s off through the pass | 0.7 deg | yes | **never** - targets 0.6 nm overhead | 0 |
| H7 | Patriot control | 1.5 deg | yes | yes | 2/2 |

**Findings**
1. **Sloped ground mutes the Hawk**: the search radars see the target, the tracking radar never locks. ED's advice
   (keep Hawks under ~2 deg) matches; all firing sites stood on <= 1.3 deg.
2. **Short emission windows mute the Hawk**: in 15 s windows it never gets from detection to TR lock to launch.
   One off -> on switch (H5, the Janus "cued" start) is fine.
3. Not causes: a missing CWAR (H2 fired), a one-point route (H4 fired).
4. The Hawk only launches once the TR locks, at ~13-15 nm (ED-confirmed short-range bug since 2.9.12).
5. Bench 02's Hawks were emitting continuously (cued), so slope is the likely cause there; their slopes were not
   measured. The setup report now measures and reports it.

**Janus workaround (built 2026-09-29)**
- Setup report: every Hawk launcher/radar on ground steeper than 2 deg is reported as a problem with its slope
  (`M.SLOPE_LIMITS`, `M.slopeAt`). Future battery spawning must pick flat ground (Phase 4 spawnBattery).
- EMCON: doctrine `periodicByType = { ["Hawk tr"] = "always" }` - a Hawk site that would fall back to the periodic
  policy stays up instead; an explicit `[emcon:periodic]` tag still wins. Cued starts are unchanged (H5 works).

## Run 5 - SA-2 probe (2026-09-29, `JANUS_PROBE_SA2.miz`)
Why has the SA-2 never launched in benches 01-03? Plain DCS (no janus.lua), z690, 25 min, loaded 02:29 UTC.
Seven sites, each overflown from the north by 2 unarmed Su-24M at 20,000 ft. Log: `I:\Claude-Workspace\logs\janus_probe_sa2_20260929.log`.

| Site | Setup | Worst unit slope | Fan Song track | Fired (first shot) | Kills |
|---|---|---|---|---|---|
| S1 | Fan Song + P-19 + 6 launchers facing the threat, flat | 1.6 deg | yes (~24 nm) | t=241 | 2/2 |
| S2 | bench layout (3 launchers) facing west, flat | 0.7 deg | yes | t=295 | 2/2 |
| S3 | full site facing directly away, flat | 1.4 deg | yes | t=349 (later: launchers slew) | 2/2 |
| S4 | bench layout on a mountainside | 10.8-31.7 deg | **never** | **never** (targets 1.5 nm away) | 0 |
| S5 | full site, `enableEmission(false)` at 5 s, `(true)` at 150 s | 1.3 deg | yes | t=284 | 2/2 |
| S6 | full site, ALARM RED by script | 1.0 deg | yes | t=327 | 2/2 |
| S7 | SA-3 control | 0.6 deg | yes | t=481 | 2/2 |

**Findings**
1. **Sloped ground mutes the SA-2** exactly like the Hawk: the P-19 sees the target, the Fan Song never tracks,
   nothing launches. The limit lies between 1.6 deg (fires) and ~11 deg (does not) - not measured yet.
2. Launcher heading does not stop it: facing away only delays the first shot (~50-100 s) while the launchers slew
   (DCS 2.9.8 change). 3 launchers instead of 6, one emission off->on switch and ALARM RED all work.
3. So the bench SA-2 (never fired in benches 01-03, slope never measured) most likely stood on sloped ground.

**Janus workaround (built 2026-09-29)**: `SNR_75V` and `S_75M_Volhov` added to `M.SLOPE_LIMITS` (2 deg, provisional),
so the setup report flags a sloped SA-2. Future battery spawning must pick flat ground for every SAM, and the
benches should place all SAMs with the flat-ground finder. Open: the exact SA-2 threshold, and whether other
systems (SA-3, SA-6, SA-10...) have the same limit.

## Run 6 - Phase 2 pre-build probe (2026-09-30, `JANUS_PROBE_P2.miz`)
Plain DCS (no janus.lua), z690, loaded 00:12:50 UTC (8:12 pm EDT), 48 min of mission time. Paused once at t=1035 by a
client connect that timed out (no one joined), resumed at 01:05 UTC. 0 script errors. Log:
`I:\Claude-Workspace\logs\janus_probe_p2_20260930.log`. Every ladder site landed in its band.

### A. Level ladder - missile launches vs ground slope (one site weapons free at a time, 2 unarmed Su-24M overhead)
| Site | System | Unit slopes | Result | Notes |
|---|---|---|---|---|
| L01 | SA-2 | 2.7-3.3 deg | **fires** 2/2 hits | Fan Song tracked at ~18 nm |
| L02 | Hawk | 3.0-3.5 deg | **mute** | Hawk sr held both targets to 1.5 nm; Hawk tr never came on |
| L03 | SA-2 | 4.8-6.1 deg | **mute** | Fan Song never on, targets passed 0.8 nm away |
| L04 | Hawk | 4.5-6.4 deg | **mute** | as L02 |
| L05 | SA-3 | 3.1-5.0 deg | **fires** 2 | |
| L06 | SA-6 | 3.8-4.9 deg | **fires** 2 | |
| L07 | SA-11 | 3.5-5.0 deg | **fires** 3 | |
| L08 | SA-10 | 3.1-4.8 deg | **fires** 2 | |
| L09 | Patriot | 3.4-4.9 deg | **fires** 2 | |
| L10 | SA-3 | 11.9-19.9 deg | **mute** | only the P-19 on; Low Blow never on (targets 0.3 nm) |
| L11 | SA-6 | 13.7-26.5 deg | **fires** 2 | |
| L12 | SA-11 | 10.2-17.2 deg | **fires** 2 | |
| L13 | SA-10 | 13.6-22.3 deg | **mute** | no radar came on at all, though the group "detected" both targets |
| L14 | Patriot | 10.9-13.7 deg | **fires** 2 | |

With runs 4-5 (Hawk fires <= 1.3, SA-2 fires <= 1.6, both mute on 11-32): **limits set in `M.SLOPE_LIMITS`**:
Hawk 2 deg, SA-2 3 deg, SA-3 5 deg, SA-10 5 deg (5-11.9 / 4.8-13.6 not measured, so 5 is conservative).
SA-6, SA-11 and Patriot fired on 10-26 deg: no limit set. Each limited type's radars and launchers are listed; the
setup report names the worst unit.

### B. Identification - the detection `type` flag
| Sensor | Reports the aircraft type? |
|---|---|
| EW radars (FPS-117, 55G6, 1L13, P-19 as EW) | **never** - held Su-27 / MiG-29A / MiG-31 / Tu-22M3 / A-50 from 313 km to overhead, `type` always 0 |
| E-3A | **always**, from first contact (up to 382 km): every red type |
| A-50 | **always**, from first contact (up to 299 km): blue jets and even the ground EW radars |
| SA-11 (Buk SR/TELAR) | yes, from 99 km |
| SA-6 (1S91) | yes, from 52 km |
| SA-10 | only inside 18 km |
| Hawk | only inside 12 km |
| SA-2, SA-3, Patriot | never |

So in DCS, identification comes from AWACS and a few SAM radars, never from ground EW. Janus's track picture takes
the type from any sensor that reports it (DESIGN 4.2); for a ground-only network the doctrine fallback is needed.

### C. Static command posts, radios, generators
| Object | Life at spawn | Died at | Events |
|---|---|---|---|
| Bunker 1 | 4 | 20 kg | UNIT_LOST + DEAD |
| Military staff | 1200 | 1000 kg | UNIT_LOST + DEAD |
| Comms tower M | 200 | 150 kg | DEAD |
| TV tower | 150 | 60 kg | DEAD |
| GeneratorF | 10 | 20 kg | DEAD |
| Electric power box | 150 | 150 kg | DEAD |
| Shelter | 8000 | **survived 3000 kg** (life 3049) | - |
| .Command Center | 4000 | **not tested** (probe bug: its first blast was scheduled at "now" and never ran) | - |
| Ural-375 PBU, SKP-11 (units) | 2 | 20 kg | UNIT_LOST + DEAD |
- DCS **does** fire `S_EVENT_DEAD` (and often `S_EVENT_UNIT_LOST`) for statics, at once (the 2 s poll saw it up to 2 s later); after
  death a static reports `isExist() == false`, `getLife() == 0` and `StaticObject.getByName` still finds it.
- Statics: `Object.getCategory` = 3 (STATIC), **no `getCategoryEx`** (the call fails); `getDesc().life` is 0 for
  `.Command Center` and `Bunker 1`, so use `getLife()` at spawn.
- The dedicated server logs "Can't open model" for `.Command Center` and `Bunker 1` (no shapes on a server); they still
  exist and take damage.
- `coalition.getStaticObjects` lists script-spawned statics; ME-placed statics not tested.
- Open: `.Command Center` destruction; how much a real bomb does to the 8000-life Shelter.

## Run 7 - SA-5 slope, SA-3 / SA-10 in between, Command Center (2026-09-30, `JANUS_PROBE_P3.miz`)
Plain DCS, z690, queue job `20260930-113223`, loaded 11:32 UTC, 41 min, 0 script errors.
Log: `I:\Claude-Workspace\logs\janus_probe_p3_20260930.log`. Every site landed in its band.

| Site | System | Unit slopes | Result | Notes |
|---|---|---|---|---|
| M01 | SA-5 | 0.0-0.5 deg | **fires** 2 | targets start 100 km out at 25,000 ft |
| M02 | SA-5 | 2.8-3.4 deg | **fires** 2 | |
| M03 | SA-5 | 5.1-6.4 deg | **mute** | only the Tin Shield (RLS_19J6) came on; Square Pair never; targets to 2.9 nm |
| M04 | SA-5 | 10.8-21.0 deg | **mute** | as M03 |
| M05 | SA-3 | 6.9-7.9 deg | **mute** | only the P-19 on (run 6: fires at 5.0) |
| M06 | SA-10 | 6.5-8.7 deg | **mute** | no radar on at all (run 6: fires at 4.8) |

Limits: **SA-5 3 deg** (`RPC_5N62V`, `S-200_Launcher`); SA-3 and SA-10 stay at 5 deg, now bracketed (fire <= 5.0 / 4.8,
mute from 6.5-6.9).

Statics: **`.Command Center` died** after 20+60+150+400+1000+3000 kg (life 4000 -> 3892 -> 3622 -> 2901 -> 1100 -> 0,
S_EVENT_DEAD); **Shelter died** after a second 3000 kg blast (life 8000 -> ... -> 3049 -> 0). A static command post can
be killed, but it takes a heavy strike.

## Run 8 - red AI anti-radiation missiles (2026-09-30, `JANUS_PROBE_P4.miz`)
Plain DCS, z690, queue job `20260930-130430`, 25 min, 0 script errors. Log:
`I:\Claude-Workspace\logs\janus_probe_p4_20260930.log` (Tacview in the queue results). Seven lanes 70 km apart, blue
sites weapons hold with radars on, one red shooter per lane from 130 km east.

| Lane | Shooter, weapons, task | Loaded? | Fired | Result |
|---|---|---|---|---|
| L1 | Su-24M 2x Kh-58U, SEAD | **no: gun only** | - | pylons 2/7 with `{FE382A68-...}` load nothing |
| L2 | Su-34 4x Kh-31P, SEAD | yes | 1 at 84.6 km (at the **L1 Hawk**, another lane) | hit, 108 s; 3 missiles never used |
| L3 | Su-34 4x Kh-31P, AttackGroup on its Patriot, weaponType ARM | yes | 1 at 82.7 km (at the **L2 Patriot**) | hit the Patriot str, 105 s |
| L4 | Su-25T 2x Kh-58U + 2x Kh-25MPU, SEAD | yes | Kh-58U at 68 and 53.5 km, Kh-25MP at 29 km (L3 Patriot) | all 3 hit; Kh-58U flew **284 s and 190 s**, Kh-25MP 89 s |
| L5 | Su-34 2x Kh-31P, SEAD; Hawk dark 20 s after launch | yes | 1 at 87 km at the Hawk, 1 at 86 km at the **L4 Patriot** | Hawk shot: **missed by 14.2 km** (radar dark 75 s before arrival); Patriot shot hit, 113 s |
| L6 | Su-24M 2x Kh-31P, SEAD | **no: gun only** | - | pylons 2/7 with `{D8F2C90B-...AF03}` load nothing |
| L7 | JF-17 2x LD-10, SEAD | yes | 1 at 29.4 km at the L5 Patriot (by then up) | hit its ECS, 79 s |

Findings:
1. **Red AI does fire ARMs, at Patriots too.** Runs 2-3 "never launched" had two causes: the Su-24M carried no
   missiles at all (the Kh-58U / Kh-31P CLSIDs load nothing on its pylons 2/7, silently), and the Patriot was weapons
   free (runs 2-3). Every loaded shooter fired; 6 of 7 ARMs hit a radar (4 Patriots, 1 Hawk; the 7th missed because
   the Hawk went dark).
2. The AI picks **any** emitting radar in reach, not its assigned one: 3 of 5 shooters fired at a neighbouring lane,
   even with `AttackGroup` + `weaponType` ARM on its own Patriot.
3. Launch ranges: Kh-31P 83-87 km, Kh-58U 53-68 km, LD-10 and Kh-25MP 29 km. Average speeds: Kh-31P ~770-920 m/s,
   **Kh-58U only 190-280 m/s** (from 13,000 ft; a slow, lofted flight), Kh-25MP ~330, LD-10 ~370.
4. **Kh-31P has no memory either**: the Hawk went dark 20 s after launch and the missile missed by 14 km.
5. **Patriot never fires at ARMs**: the dark Patriot at L5 came up weapons free at the Kh-31P launch and fired three
   PAC-2 at aircraft 74-99 km away, none at the Kh-31P passing 6 km from it.
6. Su-34s used 1 of 4 Kh-31P per pass (L2 and L3 kept 3).

For Janus: ARM speeds in `janus_arm.lua` set from these (Kh-31P 800, Kh-58U 300, LD-10 400 m/s); red SEAD is usable in
benches (Su-34 Kh-31P, Su-25T Kh-58U/Kh-25MPU, JF-17 LD-10); blue doctrine cannot count on Patriot shooting ARMs.

## Run 9 - probes 4, 6 and 7 again on DCS 2.9.30 (2026-09-30, after the "SAM acquisition below the horizon" fix)
DCS 2.9.30.28536, z690, queue jobs `20260930-213948-*` (`JANUS_PROBE_HAWK_R2.miz`, `JANUS_PROBE_P2_R2.miz`,
`JANUS_PROBE_P3_R2.miz`, same scripts as runs 4, 6 and 7), 0 script errors. Logs `I:\Claude-Workspace\logs\
janus_probe_{hawk,p2,p3}_dcs2930_20260930.log`.

**Nothing measurable changed.**
- Slope ladders (runs 6 and 7): the same sites on the same slopes gave the same verdict in all 20 windows - SA-2 fires
  at 2.7-3.3 deg and is mute at 4.8-6.1; Hawk mute from 3 deg; SA-3 / SA-10 fire to 5 and are mute from 6.5-6.9;
  SA-5 fires to 3.4 and is mute from 5.1; SA-6, SA-11, Patriot fire on 10-26 deg. **`SLOPE_LIMITS` unchanged.**
- Hawk (run 4): same shots within a second of 2.9.29 (H1, H2, H4, H5 fire; steep H3 and the 15 s-window H6 never do);
  the Hawk still launches only at ~13-15 nm. **`W.DCS_REACH` (Hawk 25 km) unchanged.**
- Identification (run 6): same "type" flag ranges (AWACS 299 / 382 km, SA-11 99 km, SA-6 52 km, SA-10 / Hawk 11-13 km).
- Statics: same blast results; `.Command Center` killed in the P2 rerun too (the run-6 timer bug is fixed).
So the slope mutes are not the below-horizon acquisition bug; whatever the patch fixed does not show in these tests.

