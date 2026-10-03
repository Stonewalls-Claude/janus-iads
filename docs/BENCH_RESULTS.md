# Janus IADS - bench results

## Bench 01 - Phase 1 network (2026-09-27)
Mission `tests/bench/JANUS_BENCH_01.miz` (bench script 0.1.0, `dist/janus.lua` 0.1.0-phase0 build with the Phase 1
modules), z690 dedicated server, DCS 2.9.29.27278. Loaded 09:21 UTC. The server was paused from t=74 s to 09:56 UTC
(the log does not say by what), then ran through END (t=1800) to t≈1910. Log: `I:\Claude-Workspace\logs\janus_bench01_20260927.log`.

Red network (SOVIET_PVO_1985, all REG): CMD North, COMMS Relay West, EW West (+ POWER Grid West), EW East,
SAM SA-10 North, PD Tor North, SAM SA-2 Centre, SAM SA-6 Coast (behind the relay). Script: kill POWER at 240 s,
CMD at 420 s, relay at 900 s; waves of 2x F-16C at 60 s and 600 s (unarmed) and 1080 s (2x AGM-88C each).

### Result: Phase 1 exit gate met
The red network ran on the bench and every Phase 1 mechanism fired, on time, with **no Janus script errors**
(305 JANUS lines, no error-budget entries).

| Check | Expected | Seen | |
|---|---|---|---|
| Setup / network build | 9 red sites recognised, links built | 9 recognised; SA-6 linked through COMMS Relay West, EW West powered by POWER Grid West, the rest to CMD North | pass |
| EW EMCON (`always`) | both EW radars up from start | EW East and EW West ON at t=0 | pass |
| Cued battery | SA-10 up only when the network has a track in reach | SA-10 North ON at t≈318 (cued, track 136 km); shot down Transit 1 (t=767, 815) | pass |
| Power loss (t=240) | EW West on reserve for 300 s, then dark | "on reserve power for 300 s" at 243; out of power, OFF (offline) at 543 | pass |
| C2 loss (t=420) | everything unlinked; batteries lose cover and fall back to the autonomous policy | all nodes unlinked at 423; 4 batteries lost EW cover, cued -> periodic at 423 | pass |
| Autonomy timer | REG = 180 s under SOVIET_PVO_1985 | all nodes autonomous at 603 | pass |
| Periodic EMCON | 15 s on / 60 s off, staggered per site | SA-2, Tor, SA-6, SA-10 cycling 15/60 with per-site offsets | pass |
| Own-track hold | a periodic site that is engaging stays up | SA-6 held ON 1016-1162 while shooting down Transit 2; SA-10 held ON 1846-1906 while shooting down SEAD 3 | pass |
| Restart time | no instant re-light after going dark | shortest dark gap 15 s (SA-10, restart 10 s) | pass |
| Equipment loss | site with its tracking radar dead goes offline | SA-6 STR hit at 1556 -> "lost its BATTERY equipment", offline | pass |
| Relay loss (t=900) | SA-6 loses its path | relay destroyed; no change, because CMD was already dead (bench ordering - see below) | not tested |

Kills: all 6 blue aircraft (Transit 1 by SA-10, Transit 2 by SA-6, SEAD 3 by SA-10 after END). Red losses: the three
scripted nodes plus SA-6 Coast's 1S91 (2 AGM-88C hits).

### Findings
1. **HARM hit a radar that had gone dark.** SEAD 3-1 launched at the SA-6 STR at t=1458.8; Janus took the SA-6 dark
   on its periodic cycle at 1462; the HARM hit at 1501 (39 s after the radar went dark). This goes against probe run 3
   ("Shrike and HARM both miss once the radar goes dark"). Likely the AGM-88C flies on to the last known position
   of a stationary emitter. Phase 3 (DESIGN 4.5B) must not assume that going dark defeats a HARM already in flight;
   re-probe the geometry (launch range, time to impact vs dark time).
2. **Losing C2 blinds every battery**, even with EW East still working and in range: EW cover is only given through a
   linked network, so with CMD dead the batteries fall to `periodic`. Design question for the owner: should an EW
   radar keep cueing batteries in its own area directly (a local/voice link, slower and shorter range) after C2 is lost?
3. **Earlier "radar off with missiles in flight" worry is not a bug.** SA-10 went OFF at t=815 0.3 s after its last
   target was destroyed; the missiles still flying had nothing left to guide on. A guard that keeps a site up while its
   own missiles are airborne and the target is alive is still worth adding (cheap, via S_EVENT_SHOT).
4. Cosmetic / log noise, to fix:
   - `POWER Grid West ... lost its link to command` / `(NOT LINKED)` and later `is now autonomous`: POWER nodes do
     not need a C2 link and should not get link or autonomy messages. COMMS and CMD also get "autonomous" messages.
   - The network summary prints `CMD North -> CMD North` (a C2 node listed as its own parent).
5. Bench design: kill the relay **before** CMD (or on a second network) so the relay-loss path is actually tested in
   bench 02. DCS also let SA-10 fire at the AGM-88s (blank targets in SHOT lines) - expected from the probes.
6. Server: something paused the server 74 s in (09:22 UTC) with no players on; watch for this on future benches.

### Next
Fix items 3 (guard), 4 and add unit tests for them; decide item 2; carry item 1 into the Phase 3 design and probe list.

## Bench 02 - Phase 2 fixes (2026-09-28)
Mission `tests/bench/JANUS_BENCH_02.miz` (bench script 0.2.0 + `dist/janus.lua` with the DESIGN 8A fixes), z690.
Loaded 03:46 UTC (after the carrier FLIGHTOPS_TEST_v3 had posted TEST COMPLETE at 03:36; no CSG_TEST ran that night),
ran unpaused to END (t=1800) and on to t≈2024, then paused. Log: `I:\Claude-Workspace\logs\janus_bench02_20260928.log`,
Tacview `Tacview-20260927-234613-DCS-Host-JANUS_BENCH_02.zip.acmi`. Geometry as planned (no sea shifts):
SA-6-EW West 47 km, SA-10-EW East 55 km, SA-2-EW East 34 km, Hawks 40-46 km from EW South.

### Result: Phase 2 fixes 1-3 and 5 confirmed in DCS; fix 4 proven offline only; no Janus errors
| Check | Expected | Seen | |
|---|---|---|---|
| Relay loss (t=300), SOVIET voice feed | SA-6 cut off, fed by EW West by voice | SA-6 unlinked at 303, "under voice cover from EW West" the same second; cued ON at 483 (track 20 km, REG 6 + 60 s); shot down Transit 1-2 (553), Transit 2-1 (887), Transit 2-2 (985) | pass |
| Red C2 loss (t=660) | batteries fed by the nearest working EW | SA-2, Tor, SA-10 "under voice cover from EW East" at 663 (bench 01: all lost cover); SA-10 cued ON at 1227 (track 124 km), shot down Transit 3-1/3-2 and both SEAD F-16s | pass |
| Blue C2 loss (t=480), US_MODERN datalink | Hawks keep the picture | both Hawks "under datalink cover from EW South" at 483; Hawk East cued ON at 490 (track 57 km), Hawk West at 870; blue autonomy after 30 s (REG) | pass (Janus side) |
| Power loss (t=900) | EW West reserve 300 s, then SA-6 loses its feed | reserve at 903, out of power at 1203, SA-6 "lost EW cover", cued -> periodic the same second | pass |
| Log noise | no link/autonomy lines for POWER/COMMS/CMD, no self-parent, POWER never "NOT LINKED" | 0 such lines; summary shows `CMD North [C2 REG]` with no parent | pass |
| Missile-in-flight hold | a site going dark with its own missiles in the air is held up | never triggered: every radar that went dark had no missile in flight (the periodic SA-6 was held by its own-track rule). Proven by harness test 13 only | not exercised |
| Equipment loss | SA-6 STR killed -> offline | HARM hit at 1560 -> "lost its BATTERY equipment", offline | pass |

Kills: 8 blue F-16C (6 transit, 2 SEAD) - SA-6 3, SA-10 5. Red losses: scripted nodes + SA-6 1S91 (1 of 2 HARMs).

### Findings
1. **The Hawks never fired.** Both were emitting for ~1,000 s with network tracks at 57 km and the unarmed Su-24M
   waves routed over them, but DCS logged no Hawk SHOT and neither Su-24 died. Janus's side worked (feed, cue, ON);
   why the Hawks held fire is open - check the Tacview (did the Su-24s get inside ~45 km? Hawk crew alarm/ROE state?).
   Bench 03 should put a Hawk shot on record before blue results are trusted.
2. **HARMs vs the periodic SA-6:** HARM 1 (t=1377) was launched while the SA-6 was up and did not hit; HARM 2
   (t=1550) was launched while it was up, the SA-6 went dark on its cycle at 1555 and the HARM hit at 1560 -
   again consistent with HARM inertial memory (DESIGN 8B).
3. SA-2 and Tor never emitted: under the cued policy no track came inside their reach before the SA-10/SA-6 killed
   the aircraft. Not a fault, but bench 03 needs a route that reaches them.
4. The missile-in-flight hold needs a DCS case that forces it (e.g. a periodic site engaging at long range).

## Bench 03 - Hawks under Janus, SA-2/Tor, slope warning (2026-09-29)
Mission `tests/bench/JANUS_BENCH_03.miz` (bench 0.3.0 + `dist/janus.lua` with the probe run 4 fixes), z690.
Loaded 01:41 UTC, END 02:11 UTC, then paused. No Janus errors. Log: `I:\Claude-Workspace\logs\janus_bench03_20260929.log`.

| Check | Seen | |
|---|---|---|
| Setup report slope warning | "SAM Hawk Slope: 'Hawk tr' stands on a 30.5 deg slope ... move the site to flat ground" at start | pass |
| Hawk East (flat, worst unit 1.9 deg), cued by EW South | cued ON at 185 s (44 km track); 6 shots; **both Su-24M of wave A shot down** (512, 562) | pass |
| Hawk East after CMD South loss (datalink cover) | shots at 485-552 continued under datalink cover; wave B (t=660): cued ON again, 3 shots, no kill | pass (fires); B missed |
| Hawk Lone (flat 0.97 deg, no EW -> Janus keeps it up, periodicByType) | ON from start, 4 shots, **both Su-24M of wave L shot down** (512, 561) | pass |
| Tor (cued) | cued ON (14 km track), 4 shots, **both F-16C of wave 1 shot down** (474, 491) | pass |
| SA-2 (cued, then voice cover after CMD North loss) | cued ON twice (54 km, 40 km tracks, ~11 min emitting) but **never launched** | open |
| SA-6 Lone (no EW, periodic) | 4 shots, both F-16C of wave 2 shot down (676, 728); own-track rule kept it up | pass |
| Voice cover after CMD North loss | SA-2 and Tor "under voice cover from EW East" at 603 | pass |
| Missile-in-flight hold | still never triggered (own-track rule covers these cases) | not exercised |

Kills: 4 Su-24M by Hawks (first Hawk kills under Janus), 4 F-16C (Tor 2, SA-6 2); wave 3 (F-16C) and wave B (Su-24M) survived.

### Findings
1. **The Hawk workaround works**: flat placement + no short periodic windows = Hawks kill under Janus, cued, cut off
   (datalink) and with no early warning at all.
2. **The SA-2 has never launched in any bench** (01, 02, 03), although cued with tracks inside its envelope for minutes.
   Next probe: SA-2 alone in plain DCS (flat vs our placement, with/without Janus switching), like the Hawk probe.
3. The missile-in-flight hold has not been needed in three benches; it stays harness-proven only.

## Bench 04 - Phase 2 gate (2026-09-30, `JANUS_BENCH_04.miz` + JANUS.gci monitor) - PASS
z690, queue job `20260930-114225`, loaded 12:14 UTC, END 12:36 (t=1320), then paused. **0 Janus errors** (also 0 from
the bench and the monitor). Log: `I:\Claude-Workspace\logs\janus_bench04_20260930.log`. A first attempt at 11:29
was aborted after 150 s by the test queue (a new .miz copied into Missions - see HANDOFF_AI_REALISM.md).

| Check | Expected | Seen | Result |
|---|---|---|---|
| Statics as nodes | 5 red statics become C2 / COMMS / POWER nodes | setup lists all five with type and life; network built as designed | pass |
| Relay destroyed (t=420) | SA-3 West unlinked (130 km: no backup), autonomous after 180 s | "lost its link" at 423, autonomous at ~603; relinked when the reserve post took over (783) | pass |
| Generator destroyed (480) | EW East on 300 s reserve, then dark | reserve at 483, "out of power" at 783 | pass |
| Air-ground radio destroyed (540) | post's radio -> backup | "air-ground radio: backup" at 543; monitor COMMAND shows radio backup | pass |
| Command post destroyed (600) | every battery / EW / AWACS unlinked; CMD Bunker Reserve takes over after 180 s | all unlinked at 603; "takes over command" at 783; SAMs relinked the same second | pass |
| Track picture | types from the AWACS, class only after the AWACS was cut off | TRACKS lines F-16C_50 / Su-24M / E-3A / A-50 from the start; after 600 new tracks appeared as "fixed-wing" until identified | pass |
| WTA | best battery assigned, others dark; handoffs logged | 49 assignment / handoff lines; salvo (SA-10 + SA-11 on one F-16, SOVIET pkGoal 0.85); "out of missiles" for Patriot and SA-11 | pass, see 1 |
| JANUS.gci | monitor reads heads, command nodes, tracks, zones, control, events | every 60 s; events nodeLost / nodeDegraded / nodeRestored / authorityChanged at the right times | pass |

Shots: SA-11 South 12, Patriot 8, SA-3 West 3, SA-10 Centre 2 (25). Hits on 5 of 8 blue F-16C (SA-11 4, SA-3 2
aircraft). **Patriot: 8 PAC-2 at the two Su-24M of wave A, no hit. Hawk: never fired.**

Findings:
1. **Handoff ping-pong (fixed after the run).** Blue's two Su-24M swapped between Patriot and Hawk every 2 s (18
   "handed" lines): the Patriot has one channel in the unit data, so whichever target ranked first took it. WTA now
   keeps a shooter's channel for the target it is already guiding (test added), and uses 2 Patriot channels
   (DCS fired at both Su-24M 3 s apart).
2. **The Hawk was assigned targets it cannot reach in DCS**: the Su-24M route passed ~50 km from it; its data reach is
   45 km but DCS launches only after the TR locks at 13-15 nm (probe run 4). WTA now caps the Hawk at 25 km.
3. The Patriot's 8 misses on unarmed, non-manoeuvring Su-24M at 15,000 ft are a DCS matter (AI realism hand-off).
4. The 3000 kg blasts on statics also destroyed map scenery (power lines etc.): dozens of `S_EVENT_DEAD` with
   category 5 (SCENERY). Janus ignores them; noted for mission makers.
5. After the reserve post took over, the A-50 stayed "in command" as an airborne node while unlinked (t=603-783) -
   by design; a GCI applies `awacsTakeover` from the doctrine (SOVIET: no).

**Phase 2 gate met** (static nodes degrade as designed; track picture, WTA and handoffs work; no Janus errors).

## Bench 05 - Phase 3 gate, run 1 (2026-09-30, `JANUS_BENCH_05.miz`) - works, fixes made
Blue HARM (2 waves of 2 F-16C, 4x AGM-88C) and Shrike (F-4E) SEAD against the red SOVIET_PVO network (SA-10 + Tor,
SA-11, SA-6, SA-2, 55G6); red Kh-31P SEAD (2 waves of 1 Su-34) against the blue US_MODERN network (Patriot, Hawk,
FPS-117); unarmed bait so the SAMs come up. z690, queue job `20260930-134146`, 20 min, **0 Janus errors**. Log:
`I:\Claude-Workspace\logs\janus_bench05_20260930.log`.

| | Red network (blue ARMs) | Blue network (red ARMs) |
|---|---|---|
| ARMs fired | 16 AGM-88C, 2 AGM-45A | 4 Kh-31P |
| Seen by the crews | every one that came within sensor range: radar 27-55 km (SA-11, SA-10), 8-10 km (Tor radar and eyes), 2-sensor confirmations | all 4 (Hawk 11-25 km, Patriot 46 km, FPS-117 91-121 km: too far, see fix 2) |
| Responses | dark (SA-11 x6, SA-10 x3, SA-2, SA-6, EW), "finish the shot" (SA-11 x4, SA-10), Tor "engage" (5 missiles), suspicion (F-16C / F-4E nose-on: SA-10, SA-11, SA-2) | dark (Hawk x2, Patriot, FPS-117), Patriot "finish the shot" |
| ARM hits on radars | 5: SA-11 LN x2 and SR (**all three while dark**), SA-11 LN (dark), Tor (up, engaging: destroyed) | **0**: every Kh-31P missed a dark Hawk (331 m, 885 m, 6 km) or was lost |
| Point defence | Tor fired 5 SA9M330 at HARMs and 1 at a Shrike; one HARM ended 3.6 km short (shot down); Tor killed the F-4E | - |
| Emitting time lost | 1,561 s over 6 sites (20 dark periods) | 509 s over 3 sites |

Findings:
1. **DCS AGM-88C hits radars that went dark** (4 of 5 hits were on dark SA-11 radars, dark 20-70 s before impact),
   as in benches 01-02; **Kh-31P does not** (probe run 8 and here: 0 of 4). Going dark saves a site from red ARMs but
   not from blue HARMs in DCS 2.9.29; against HARMs it still suppresses (no new launches at a dark site) and point
   defence is what saves the radar. Noted for the AI realism hand-off.
2. **Janus fix: too many sites went dark for one missile.** The threat cone reached far past the targeted site: an SA-6
   30 km behind the SA-11 was dark 354 s, the 55G6 261 s, the Patriot 179 s for a Kh-31P aimed at the Hawk. Now a
   missile threatens only radars within 10 km beyond the first emitter on its path (fixed per missile, emitting or
   dark for < 120 s), and nobody once it is past that radar (DESIGN 4.5C).
3. **Janus fix: sight range.** The FPS-117 "held" a Kh-31P at 121 km (0.35 x its 470 km range). No radar now holds an
   ARM beyond 50 km.
4. The "finish the shot" rung worked (SA-11 kept guiding its Buks, then went dark 20-40 s before impact).
5. Suspicion cues fired against F-16C and F-4E nose-on at 11-57 km (30 s dark each, extended while nose-on).
6. The WTA "no shooter" / reassignments during ARM dark periods worked (a dark site got no targets).

## Bench 05 - Phase 3 gate, run 2 (2026-09-30, `JANUS_BENCH_05B.miz`, with the run-1 fixes)
Same mission, queue job `20260930-140509`, 20 min, **0 Janus errors**. Log:
`I:\Claude-Workspace\logs\janus_bench05b_20260930.log`. DCS 2.9.29.27468.

| | Run 1 | Run 2 |
|---|---|---|
| ARMs fired | 22 | 20 |
| Emitting time lost (red / blue) | 1,561 s / 509 s | **605 s / 171 s** |
| Sites dark for a missile aimed elsewhere | SA-6 354 s, 55G6 261 s, Patriot 179 s, FPS-117 224 s | **none** (only the targeted site, and the SA-2 / Hawk a HARM or Kh-31P was really heading for) |
| ARM hits on radars | 5 (4 on dark radars) | 8 (7 on dark radars): SA-11 SR x2, SA-2 P-19 x2, Hawk sr / tr x3 (Kh-31P), 1 more on the SA-11 |
| Tor | engaged 5 missiles, downed 1 HARM, destroyed by a HARM | engaged the HARM at the SA-10 |

Findings:
1. The run-1 fixes work: no collateral dark periods, a third of the lost emitting time.
2. Hits on dark radars came from **late awareness**, not from Janus holding sites up: the SA-2 (tier C) and the Hawk
   learned of their missiles 9 s out (no sensor within reach earlier; the 50 km cap now keeps the FPS-117 from
   "seeing" a Kh-31P at 120 km), and a missile 9 s out hits whether or not the radar is on. Where the crew knew
   early (SA-11 x3, SA-10), HARMs still hit dark SA-11s: the DCS AGM-88 behaviour noted in run 1.
3. **Gate status:** the Janus side works in both runs (awareness, confirmation, ladder, finish-the-shot, point
   defence, suppression, scoring, no errors). Against HARMs, DCS 2.9.29 gives going dark little protective value, so
   the defensive benefit Janus can add is suppression and point defence until relocation/decoys (parked) exist.

**DCS update pending (owner, 2026-09-30):** the latest DCS patch fixes SAM acquisition below the horizon. Both bench
05 runs, probes 4-8 and the slope limits were measured on 2.9.29.27468 or earlier. After the server updates: rerun the
slope ladders (probe runs 6-7: the "sloped ground mutes SAMs" finding may have been this bug, so
`SLOPE_LIMITS` may shrink or go), probe run 4 (Hawk short range), and benches 04/05; regenerate the unit database
from the new datamine.

## Phase 2.5 gate - GCI on JANUS.gci (2026-09-30, run by the GCI session) - PASS
Source: `dcs-missions/docs/design/GCI_JANUS.md` section 10 (GCI session's bench `missions/StonewallC_GCIJ_BENCH`,
built with `build_gcij_bench.py`; dedicated server via dcs-testq). Janus bench 04's network with `[seats:N]` posts and
StonewallC-named AEWs (`Mainstay AEW VET`, `Darkstar AEW ACE` - recognised by type, no "AWACS" word), GCI DCA flights
both sides, transits; red post killed at 600 s, blue CRC at 840 s. Three builds, 25 min each, **0 script errors in
all three**.

| Gate item (DESIGN section 9, 2.5) | Result |
|---|---|
| GCI runs on the Janus picture, no picture of its own | FULL: picture source "janus" all run, no flat post, both AEWs are Janus controllers |
| Seats sit in Janus command nodes and fall silent when their node dies | North's 3 seats up; flights released to the A-50 when North's radio fell to backup (543 s); seats closed 5 s after the post died; Reserve took over at 785 s with 3 seats; blue CRC dead -> E-3 took the full workload, no blue ground seats |
| Fighters keep out of live SAM zones | FULL: 0 fighter entries into any hot SAM zone (NOGCI, for comparison: one uncontrolled fighter drifted 0.1 NM into its own SA-10 zone) |
| The same bench runs clean with no GCI loaded | NOGCI: Janus alone, 0 errors, nothing talked to fighters |
| (GCI fallback) runs with no Janus loaded | NOJANUS: GCI's own picture, flat posts GROUND:1 / GROUND:2 plus both AEWs, fighters controlled, 0 errors |

FULL scored 8 PASS and 1 FAIL; the FAIL was the bench's own timing (an A-50 "gap" sample taken 3 s before Janus's
`nodeLost` event read "full"; every later sample was right; fixed in the GCI test 1.0.1). Note for consumers: a
destroyed **group** node reaches `nodeLost` on Janus's next network pass (up to 5 s after `S_EVENT_DEAD`); a static
node's `S_EVENT_DEAD` is handled at once. Subscribe to the event rather than sampling on a clock.

## Benches 04 (run 3) and 05 (run 3) on DCS 2.9.30 (2026-09-30)
Current Janus (Phase 3 included), DCS 2.9.30.28536, queue jobs `20260930-213948-*`, **0 Janus errors** in both.
Logs `I:\Claude-Workspace\logs\janus_bench0{4,5}_dcs2930_20260930.log`.

- **Bench 04:** same degradation path as run 2 (relay -> SA-3 autonomous, generator -> EW out of power, radio ->
  backup, post -> reserve takes over; 4 nodeLost / 1 authorityChanged GCI events). Shots: SA-11 12, Patriot 8 (one
  Su-24M hit this time), SA-10 5, SA-3 2; Hawk 0 (assigned once at 14 km, inside its 25 km DCS reach, then handed back
  to the Patriot). **Handoff lines 20 -> 2: the bench-04 ping-pong fix holds in DCS.**
- **Bench 05 (Phase 3 re-validation):** 19 ARMs; red sites went dark 15 times (872 s lost), blue 3 times (198 s);
  5 radar hits (4 on dark radars: SA-11 x2, SA-2 x2; the Tor while engaging), 0 on blue; the Tor fired 5 times at
  missiles and one HARM ended 3.3 km short. Same picture as run 2: Janus behaves as designed; DCS HARMs still hit dark
  radars, Kh-31Ps still miss dark Hawks.

## Bench 06 - Phase 4 gate (queued 2026-10-01, `JANUS_BENCH_06.miz`, testq `20261001-014750-JANUS-bench-06-Phase-4-gate`)
Both coalitions at once on Syria, 20 min. Red SOVIET_PVO_1985 with flak traps; blue NATO_COLDWAR (weapons tight).
Every SAM, EW, gun and ship group spawned by `JANUS.spawnBattery` at 3 s (36 presets, 12 per side far behind as load);
A-50 "Mainstay AEW" and E-3A "Magic AEW" (no role word); CSG-USN at sea as its own network `[net:CSG]`; waves as bench
05 plus a low pass past the SA-2 gun ring (flak trap) and Su-24Ms at the carrier group; GCI weapons hold at 420 s,
free at 540 s, tight at 780 s. The .miz embeds the build before the DLC check in `spawnBattery` (no effect on these
presets). Offline smoke run of the bench script: 36 presets spawned, 0 failed, 0 Janus errors.
**Result (run 1, 2026-10-01 02:01-02:21 UTC, 1241 s, end marker seen): PASS.** Log
`dcs-testq/results/20261001-014750-JANUS-bench-06-Phase-4-gate/`.
| Gate item | Result |
|---|---|
| No Janus errors | 0 `ERROR ... JANUS`, 0 bench script errors (DCS's own Su-24M "corrupt damage model" / animator lines only) |
| Preset spawning on flat ground | 36 spawned, 0 failed; every worst slope under its limit (Hawk 0.99-1.94 vs 2, SA-2 2.34 vs 3, SA-10 4.91 vs 5); moved 0-4500 m from the point asked; all picked up at BIRTH (37 pick-ups incl. guns) |
| Both coalitions at once | red 21 nodes (C2 1, EW 2 incl. A-50, SAM 10, PD 6, AAA 2), blue 20 (C2 1, EW 2 incl. E-3A, SAM 11, PD 4, AAA 1, NAVAL 1) |
| Naval | `SHIP Ike [net:CSG]` its own network; WTA assigned it Red Bait Ships; 9 SM-2ER, hits on a Su-24M and the Su-34 |
| AWACS by type | "Mainstay AEW" / "Magic AEW" picked up with no role word |
| Flak trap | SA-2 West guns held ("flak trap set"), OPEN FIRE on Blue Low 1, "trap reset" after; Centre guns held (no one came close) |
| Weapons control | blue tight -> hold at 420 s ("held: weapons hold", no blue SAM fired) -> free at 540 -> tight at 780; applied to both blue networks (returns 2) |
| commitRequests | every 60 s both sides; reasons "out of reach" / "no shooter free" / "weapons hold" as expected |
Shots: red SAM Centre 5, SA-11 2, Osa (rear load site) 6, SA-2 guns 16; blue Patriot 10, ship 9; blue SEAD 13 AGM-88 (0 hits:
radars dark or HARMs short). Hits: S-300 and Buk on the blue bait, Patriot on a Su-24M, SM-2 x2, Osa on Blue Low 1.

## Bench 07 - Janus vs Skynet (Phase 5, 2026-10-01, `JANUS_BENCH_07_<run>.miz`, testq `...-JANUS-bench-07-*`)
Same red IADS (SA-10, SA-11, SA-2, Tor, EW, command post) and the same blue SEAD/DEAD/strike waves, run once under
Skynet v3.5.0 and once under Janus. Score (higher = better for red) = 3 x blue aircraft lost - 3 x red radars lost -
other red units lost + HARMs that missed. One input to the owner's whole-system judgement, not the gate on its own
(owner: losing to Skynet on this score is acceptable for realism; old radars stay worse at seeing HARMs).

| Runs | Build | Score | Blue lost | Red radars lost | HARMs / hits | Red shots |
|---|---|---|---|---|---|---|
| S1-S3 | Skynet v3.5.0 | 28, 29, 19 (avg 25.3) | 6, 6, 5 | 2, 0, 3 | 40 / 0 | 97 |
| J2-J3 | Janus, Phase 4 ARM ladder | 19, 18 (avg 18.5) | 5, 6 | 3, 3 | 32 / 10 | 68 |
| J4-J5 | + launch cue | 21, 25 (avg 23) | 7, 7 | 4, 3 | 35 / 10 | 56 |
| J7-J8 | "fix 1" (inside-reach, no cue) - rejected design | 12, 19 (avg 15.5) | 5, 7 | 4, 3 | 30 / 13 | 67 |
| **J10-J12** | **ambush, suppress, kill** (finishShot still on) | **18, 37, 21 (avg 25.3)** | 5, 8, 4 | **2, 1, 1** | 43 / 6 | 94 |
| **J13-J15** | **final build (finishShot off)** | **14, 38, 24 (avg 25.3)** | 6, 9, 5 | 5, 2, 1 | 50 / 10 | 107 |
| **J16** | **final build + `A.HORIZON`** (test2, 2026-10-02) | **24** | 6 | 4 | 20 / 2 | 34 |

J1 aborted (mission copied while it started - a process error, since fixed: copy first, then queue); J6 and J9
cancelled. All completed runs: 0 `ERROR ... JANUS` lines, 0 bench error lines.

### Findings
1. **The ambush design matches Skynet's average score (25.3 each) and loses the fewest radars of any build** (4 in
   three runs; Skynet 5, earlier Janus builds 6-7 in two). HARM hits fell from 10-13 per two runs to 6 per three.
2. Skynet's 0 HARM hits come from shutting down early on every HARM; Janus's old radars (tier C) see HARMs late on
   purpose, so some hits remain. Accepted (owner).
3. **Only the threatened site goes dark** (owner rule): in J10-J12 every ARM darkened exactly one site. In J8 two ARMs
   darkened an SA-2 standing 11 km in front of the targeted SA-10 on the same line; kept on purpose (DESIGN 4.5B).
4. **Spent HARMs (run 13):** a HARM fired at the SA-11 ~150 s before anyone saw it (the SA-11 had been dark for
   minutes) pointed at the SA-6 36 km on; Janus shut the SA-6 for 148 s at ~229 s to impact. The missile died at the
   SA-11. The same pattern appears 9 times across benches 05 and 07 (185-229 s to impact, never a hit on the site that
   went dark); real threats all came in under 110 s. Fixed after run 15: `A.HORIZON` 120 s (DESIGN 4.5B). Runs 13-15
   ran without the fix. **Confirmed in run 16:** no shutdown more than 120 s from impact (10 dark periods), every ARM
   darkened one site, 0 errors.
5. Run-to-run spread is large (Janus 18-37, Skynet 19-29): DCS AI and HARM outcomes vary, so single runs decide nothing.

## Demo smoke runs (2026-10-01, `JANUS_DEMO_<RED|BLUE|BOTH|NAVAL>_T1.miz`)
All four demos loaded from Mission Editor groups with janus_settings.lua + janus.lua: setup reports recognised every
group (RED 13 red, BLUE 8 blue, BOTH 13 + 8, NAVAL 2 + 2), no PROBLEM lines, 0 `ERROR ... JANUS` lines. These ran the
build before finishShot went off; the demo .miz files now carry the 1.0 build. NAVAL_T1 still had CVN-73; the demo now
uses CVN-74 Stennis (non-Supercarrier, so demos need no DLC). NAVAL_T2 (Stennis, final build): 0 errors, the
escort and the E-3 recognised, the escort its own [net:CSG] network; the setup report flagged the carrier group (no
role word, but it carries Sea Sparrow / RAM / CIWS). Fixed: the carrier is now `SHIP Stennis REG [net:CSG]` (checked
offline: both ships join blue/CSG).

## Phase 5 gate - whole-system judgement (draft for the owner, 2026-10-01)
The owner judges Janus as a whole system, not by one score. The evidence:

| Question | Evidence | Verdict |
|---|---|---|
| Does it hold up against the incumbent? | Bench 07: Janus final build runs 13-16 avg 25.0 (14, 38, 24, 24), Skynet avg 25.3; ambush build runs 10-12 also 25.3; best single run Janus 38, Skynet 29 | Even on Skynet's own scoring |
| Does it keep its radars alive? | Red radars lost a run: Janus runs 10-12 1.3, runs 13-16 3.0 (5, 2, 1, 4), Skynet 1.7; earlier Janus builds 3-3.5 | Worse than Skynet; the cost of old radars seeing HARMs late and of ambushing inside the ring (accepted for realism) |
| Is it realistic? | Old radars see HARMs late (6-10 hits in three runs vs Skynet 0); sites ambush inside 0.8 of reach; shut down only for detected ARMs; only the threatened site goes dark | Realism kept where the owner asked for it (score cost accepted) |
| Is it stable? | Every bench 07 run and every demo smoke run: 0 Janus errors; perf test 300 sites + 300 aircraft inside budget | Pass |
| Can a non-coder use it? | Four demos load from Mission Editor groups with a clean setup report; quick start, tutorial, recipes, troubleshooting | Owner's quick-start test still to do |
| Is the code clean? | dcs-check 0 errors; mutation check green on every changed line; tests 900+ | Pass, except the launch cue (off, TODO after 1.0) |

**Recommendation:** pass, subject to the owner's quick-start test. The `A.HORIZON` fix came after runs 13-15 and was
confirmed by run 16 on test2 (score 24, 0 errors, no long or multi-site shutdowns).
