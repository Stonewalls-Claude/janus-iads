# Probe results - run 1 (2026-09-24, Syria, DCS 2.9.29)

Raw log: `I:\Claude-Workspace\logs\janus_probe_run1_20260924.log` (also the Tacview `Tacview-20260924-082209-DCS-Host-JANUS_PROBE`).

## Findings
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

## Weapons engaged by defenders

| Attacking weapon | Launched | Hit by a defender | First hit after launch (s) | Defender |
|---|---|---|---|---|
| AIM_120C | 4 | 0 |  |  |
| C_8CM | 8 | 0 |  |  |
| FAB-250-M62 | 8 | 0 |  |  |
| FIM_92C | 18 | 0 |  |  |
| GRAD_9M22U | 40 | 0 |  |  |
| KAB_500Kr | 5 | 0 |  |  |
| X_31P | 1 | 0 |  |  |

## Per defender / shooter

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
