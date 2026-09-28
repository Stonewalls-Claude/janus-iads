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
