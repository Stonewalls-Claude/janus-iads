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
