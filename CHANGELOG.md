# Changelog

## Unreleased - Phase 4 started (2026-09-30)
- New `janus_aaa.lua`: gun fire discipline per doctrine `aaa` - "free" (DCS default, every shipped profile) or
  "trap" (flak trap: guns hold fire until a known target is inside 0.7 x their reach and below their ceiling, keep
  firing 20 s after it left; a gun site with no picture at all fires at will). Guns now get EW cover / voice plots
  like SAMs.
- Doctrine `arm.observers = { range, smokeRange }`: ground spotters at every site see ARMs by eye (off in the shipped
  profiles).
- DCS 2.9.30 (horizon fix) retest (probe run 9, benches 04/05 run 3): slope limits, Hawk reach, identification and
  ARM behaviour unchanged; unit database regenerated from the 2.9.30 datamine (no unit or figure changed).
- Historical profiles after 1.0: Phase 6 Vietnam, Phase 7 Iran 1970s (Spellout / Peace Ruby), Phase 8 Iraq 1991 (Kari); DESIGN section 9 updated. `tests/test_phase4.lua`.

## Unreleased - Phase 2.5 closed (2026-09-30)
- GCI 2.14.1 / `StonewallC_gci_janus.lua` 1.1.0 ran on `JANUS.gci` v1 in the GCI session's bench (FULL, NOGCI,
  NOJANUS; 0 script errors): picture, seats in command nodes, AEW takeover, SAM-zone avoidance, both fallbacks.

## Unreleased - Phase 3: ARM defence (2026-09-30, closed; re-validation on DCS 2.9.30 queued)
- New `janus_arm.lua` (DESIGN 4.5C): every passive-radar-guided weapon is an ARM; crews notice it only by radar
  (tier A/B/C, crew, load, line of sight), by eye (optical units, daylight) or over the network; confirmation;
  response ladder engage / accept ([hold]) / covered (trustPd) / finish the shot / dark for the estimated time to
  impact; point defence forced up; suppression while an identified SEAD aircraft stays nose-on; restart or wait at
  maxDark; early release when the network sees the missile die; suspicion cue; scoring (dark time, hits).
- Doctrine field `arm` in every profile (SOVIET waits, RUSSIA_MODERN trusts Tor/Pantsir, US never dark on suspicion,
  NVA blinks, third world slow). EMCON applies ARM decisions; WTA skips sites dark against an ARM.
- Probe run 8: red AI does fire ARMs (Su-34 Kh-31P, Su-25T Kh-58U / Kh-25MPU, JF-17 LD-10); the Su-24M loadouts load
  nothing; Patriot never shoots ARMs; ARM speeds updated. Bench 05 (Phase 3 gate) added.
- `docs/requests/STANDARDS_JANUS.md`: the STANDARDS.md changes for when Janus replaces Skynet.
- Test harness: weapons in flight (`F.launch`), deterministic random rolls (`F.rnd`), `land.isVisible`.
- JANUS.gci additions (no version bump): `commandNodes[].reach` (radio reach per node and doctrine),
  `controlState(coal, point, postName)`, contract check that track `id` is the DCS unit ID. AWACS groups are
  recognised by aircraft type, so callsign-first names ("Magic AEW ACE") need no role word.

## Unreleased - bench 04 / probe run 7 follow-ups (2026-09-30)
- Bench 04 passed (Phase 2 gate). WTA fixes from it: a shooter keeps its channel for the target it is guiding (no
  ping-pong); Hawk reach capped at 25 km and Patriot given 2 channels to match DCS.
- Probe run 7: SA-5 slope limit 3 deg (`RPC_5N62V`, `S-200_Launcher`); SA-3 / SA-10 5 deg limits confirmed; static
  Command Center and Shelter can be destroyed.

## Unreleased - Phase 2.5: JANUS.gci ground-control interface (2026-09-30)
- New `janus_gci.lua` (DESIGN 4.10): version, instance, keyed event subscriptions (nodeLost / nodeRestored /
  nodeDegraded / authorityChanged), tracks (coalition or per command node), commandNodes, radarHeads, controlState,
  samZones. Read-only copies; safe before start and with no network; Janus names no consumer.
- Network fires restored / degraded / standdown callbacks (repair, power, link, equipment, alternate stand-down).
- Doctrine: `fighterControl`, `awacsTakeover`, `agReach`, `agBackup.range`.
- `tests/test_gci_api.lua` (68 checks) with a reference consumer (pull, version check, pcall, fallback, one subscription
  per Janus instance); `tests/bench/janus_gci_monitor.lua` logs what a GCI would see (tag JANUS_GCIMON), loaded in
  bench 04. Mutation check on janus_gci.lua and the network changes: all caught (equivalents marked).

## Unreleased - Phase 2: static nodes, track picture, weapon-target assignment (2026-09-30)
- Static objects named `CMD` / `COMMS` / `POWER` are network nodes (DESIGN 4.1A, 4.6B): death by S_EVENT_DEAD with the
  5-s network pass as backstop, late statics picked up on BIRTH, wrong role words on statics reported.
- Bare `[flag]` tags; `COMMS ... [ag]` air-ground radios with per-post state (own / ok / backup / none) and a `radio`
  callback; backup link after relay loss (`linkBackup`: range, extra cue delay per tier); alternate command posts
  (`[alt:Name]`, `altTakeover` per tier, stand-down when the main post returns, `takeover` callback).
- Track picture: stable track numbers, class, velocity, holders, identification from the detection `type` flag or
  after `idTime` of continuous network track; detections without any fix ignored.
- New `janus_wta.lua`: envelope from DCS data, Pk estimate (range, aspect, speed, crew, ammo, lead), threat ranking,
  assignment with salvo (`pkGoal`, `maxShooters`), channel limits, point-defence discount, hysteresis and logged
  handoffs. On WTA networks EMCON cues only assigned batteries. GENERIC_THIRD_WORLD has WTA off.
- New doctrine fields: `linkBackup`, `agRange`, `agBackup`, `altTakeover`, `idTime`, `wta`.
- Tests: `tests/test_phase2.lua` (146 checks); mutation check 296/296 on the changed lines. Bench 04 built
  (`tests/bench/JANUS_BENCH_04.miz`), not run yet.
- `docs/HANDOFF_AI_REALISM.md`: DCS AI weirdness, gotchas and SEAD ideas for the AI realism session.

## Unreleased - Phase 2 fixes from bench 01 (2026-09-27)
- Probe run 6 (`tests/probe/JANUS_PROBE_P2.miz`, run 2026-09-30): level ladder for SAM launches on sloped ground,
  sensor identification (`type` flag), static command posts / radios / power and their death events.
- Setup slope check from probe run 6: SA-2 limit 2 -> 3 deg; new limits SA-3 5 deg and SA-10 5 deg (radars and
  launchers); Hawk stays 2; SA-6, SA-11 and Patriot fire on 10-26 deg and get none.
- Probe scripts follow the new dcs-check drift rule (reschedule from the callback's time, not the clock);
  `tools/build_probe_miz.py` accepts a probe .miz as its template.
- EW feed after command loss is now doctrine-driven (`c2LossCue`, DESIGN 8A): SOVIET_PVO_1985 / RUSSIA_MODERN /
  NVA use a voice relay from a nearby EW radar (short range, long extra cue delay), NATO_COLDWAR / US_MODERN keep a
  data-linked picture, GENERIC_THIRD_WORLD gets nothing. "Linked to command" and "under EW cover" are separate.
- A site stays emitting while its own missiles fly at a live target (S_EVENT_SHOT bookkeeping, max 120 s).
- POWER, COMMS and CMD nodes no longer log link-lost / autonomy messages; a command post is no longer listed as its
  own parent; power plants are never reported as unlinked.
- Coalition separation confirmed and pinned by test 12 in tests/test_network.lua (2026-09-29): a blue `EW` radar
  right beside a red network gives red no cover, no links and no plots, and a blue `EW` spawned mid-mission joins
  the blue network. (The coalition-blind `EW` pickup was Skynet's, not Janus's: Janus builds one network per
  coalition from `coalition.getGroups(side)` and the unit's own coalition on spawn.)
- Harness: 111 network checks (was 60) incl. doctrine table pins; mutation check on the changed lines 117/117.
- Hawks (probe run 4): the setup report flags Hawk units on ground steeper than 2 deg (DCS will not let them
  engage); Hawk sites never fall back to the short periodic radar window (`periodicByType`), they stay up.
- SA-2 (probe run 5): the setup report also flags SA-2 units (SNR_75V, S_75M_Volhov) on ground steeper than 2 deg.
- tests/bench/janus_bench_03.lua + JANUS_BENCH_03.miz: Hawks on flat ground under Janus (4 kills), SA-2/Tor route,
  slope-warning check; results in docs/BENCH_RESULTS.md.
- Every DCS event handler is now visibly wrapped (dcs-check house rule of 2026-09-28): core dispatcher via
  M.wrap, probe/bench handlers via wrapHandler.
- tests/bench/janus_bench_02.lua + JANUS_BENCH_02.miz: relay loss before CMD loss, voice and datalink feeds, a blue
  US_MODERN network against unarmed Su-24M.

## 0.1.0-phase0 (2026-09-24)
Foundation only; Janus does not control sites yet.
- Unit database generated from the DCS Lua datamine (DCS 2.9.29) and DCS Olympus: 179 air-defence-relevant types,
  roles, ranges, DCS dependency chains, era. Report in docs/UNIT_DATA_REPORT.md.
- 38 battery presets (SA-2 → Pantsir/Tor-M2, Patriot/Hawk/NASAMS/IRIS-T SLM/Rapier/Roland/HQ-7, C-RAM, AAA, WWII flak, EW, naval) with sources,
  every DCS type name verified. docs/BATTERY_PRESETS.md.
- DLC policy: Currenthill units are free core content and used freely; presets that need the WWII Assets Pack declare
  `requires`, the docs box it, and the setup report warns that the mission only loads for DLC owners.
- janus.lua: core (single JANUS table, tagged logging, error budget, xpcall wrappers, one scheduler, event bus,
  settings merge), group-name parser with [tags], setup scan + plain-English report, autostart.
- Offline harness (tests/fake_dcs.lua) and 42 checks; tools/build.py; probe script for the C-RAM / AI engagement test.

## 0.1.1-phase0 (2026-09-24)
- Probe run 1 results (docs/PROBE_RESULTS.md): C-RAM does not engage weapons in DCS; design 4.5 amended. Phase 0.5 (clean rerun) added.
- tools/probe_report.py: shooter type parsing fixed.

## 0.1.2-phase0.5 (2026-09-24)
- Probe v0.3 (JANUS_PROBE_V2.miz): no A/A weapons, sites 250 km apart, weapon-tracking sweep. Run 2 results in docs/PROBE_RESULTS.md: Tor/Pantsir engage HARMs in 9-13 s; EWR tracks weapons at launch; C-RAM/Patriot never fire at weapons.
- Rule: every test run gets its own numbered .miz, log and Tacview.

## design 0.6 (2026-09-24)
- DESIGN 4.5 generalised to all anti-radiation missiles (Shrike to Kh-31P); new 4.5A crew-awareness model (radar/behaviour/eyes/network cues, tiers A-C) and 4.5B dark-time defaults (S-300PS, SA-11, SA-5, SA-2/3); decision 8.

## 0.1.3-phase0.5 (2026-09-25)
- Probe v0.4 (JANUS_PROBE_V3.miz, run 3): EMCON timings, cross-group cueing (none in DCS), Shrike/HARM lose guidance when the radar goes dark, EW radars hold ARMs at 100+ km, janus.lua smoke test in DCS passed. docs/PROBE_RESULTS.md run 3.
- DESIGN draft 0.7: 4.1 battery = one DCS group; 4.5B Janus switches radars with enableEmission and imposes its own restart times; Phase 0.5 done.

## 0.2.0-phase1 (2026-09-25)
- Network model: nodes from named groups, command/relay mesh, power with reserve, autonomy by crew tier, flat networks without a command post, [cmd:]/[relay:]/[power:]/[net:]/[skill:]/[emcon:] tags, pickup of groups spawned later.
- Track picture (aircraft) from budgeted radar polling; EMCON policies always/dark/cued/periodic/rotating with Janus restart times and minimum on-time; ALARM RED + enableEmission.
- Doctrine profiles as data (7 profiles, Phase 1 fields); custom doctrine tables in settings.
- Check mode draws the network on the F10 map.
- Harness: 60 new checks (test_network.lua); 150 nodes cost ~0.8 ms per simulated second.
- Bench 01 mission (tests/bench/JANUS_BENCH_01.miz).
