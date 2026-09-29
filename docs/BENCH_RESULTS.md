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
