# Probe results (Phase 0 / 0.5)

Each run has its own mission file, never overwritten (`JANUS_PROBE.miz`, `JANUS_PROBE_V2.miz`, ...); its log and
Tacview are saved under the same name in `I:\Claude-Workspace\logs`.

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
