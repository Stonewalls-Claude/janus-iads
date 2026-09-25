# Changelog

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
