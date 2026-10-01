# Hand-off to the AI realism session: DCS AI weirdness, gotchas and SEAD ideas

**From:** the Janus IADS session. **Started:** 2026-09-30. Kept up to date as Janus testing goes on.
Everything below was seen on the z690 dedicated server (DCS 2.9.29) in Janus probes and benches unless marked
otherwise. Sources: `docs/PROBE_RESULTS.md` (runs 1-6) and `docs/BENCH_RESULTS.md` (benches 01-03) in this repo.
Janus will never fly or task aircraft; anything about attackers is for the AI realism / mission scripts.

## 1. DCS AI SEAD - what the attackers do (and don't)
| Seen | Where | Suggestion for the AI realism side |
|---|---|---|
| **Su-24M ARM loadouts load nothing.** A script-spawned Su-24M with Kh-58U `{FE382A68-8620-4AC0-BDF5-709BFE3977D7}` or Kh-31P `{D8F2C90B-887B-4B9E-9FE2-996BC9E9AF03}` on pylons 2/7 (the pydcs pylon list) spawns with its gun only, silently. This, not AI behaviour, is why "red ARM shooters never launched" in runs 1-3 | probe run 8 (`getAmmo` at spawn) | Check `Unit:getAmmo()` after spawning any scripted strike aircraft; find the right Su-24M pylon numbers / CLSIDs (Mission Editor export of a hand-loaded Su-24M) |
| **Red AI ARMs work**: Su-34 Kh-31P (SEAD task) fires at 83-87 km, Su-25T Kh-58U at 53-68 km and Kh-25MPU at 29 km, JF-17 LD-10 at 29 km; 6 of 7 hit (Patriot and Hawk radars) | probe run 8 | Red SEAD packages are viable. Su-34s fired only 1 of 4 Kh-31P per pass: plan extra passes or more shooters |
| **AI ARM shooters pick any emitter in reach**, even with `AttackGroup` + `weaponType` ARM on a specific group (3 of 5 fired at a neighbouring site) | probe run 8 | To hit a specific site, keep other emitters out of the shooter's reach (or dark) during the attack |
| **DCS Kh-58U is slow**: 190-280 m/s average from a Su-25T at 13,000 ft (a 68 km shot took 284 s) | probe run 8 | Long warning time for the defence; launch from higher / faster platforms if that matters |
| **Blue AI HARM shots work** (F-16C AGM-88C) and they are one-shot-per-emitter, from well inside range | benches 01-02 | Consider pre-briefed (POS) HARM shots on known sites - the F-16 HTS pod allows it in real life - so SEAD does not depend on the SAM emitting at launch time |
| **Kh-31P has no memory**: the Hawk went dark 20 s after launch and the Kh-31P missed by 14 km; in bench 05 all 4 Kh-31P missed dark Hawks | probe run 8, bench 05 | Red SEAD against sites that blink needs more missiles or a strike follow-up |
| **AGM-88C does hit radars that went dark** (bench 05: 4 of 5 hits were on SA-11 radars dark 20-70 s before impact) - blue HARMs are far more dangerous than red ARMs in DCS 2.9.29 | bench 05 (and benches 01-02) | Blue SEAD works as-is; red SEAD is weaker. An asymmetry worth knowing when balancing missions |
| **Tor shoots HARMs and Shrikes** when emitting (bench 05: 5 missiles engaged, one HARM downed 3.6 km out) but a HARM still killed it | bench 05 | Point defence buys time, not immunity |
| **HARM keeps flying to the last position after the radar goes dark** and still hits: SA-6 STR hit 39 s (bench 01) and 5 s (bench 02) after going dark. Probe run 3 (Shrike and HARM missing once dark) was the opposite, so it depends on timing/geometry | benches 01-02 vs probe 3 | SEAD flights don't need to "hold the lock"; a HARM already in the air is a threat even if the site shuts down. Janus Phase 3 will model the crew's side |
| DCS AI attackers with `REACTION_ON_THREAT = EVADE_FIRE` still flew straight over SAMs they had no weapons against | all benches | For realism, unarmed/transit flights should route around known MEZs (the GCI / mission side) |
| **Tor and Pantsir shoot HARMs down**: first shot 9-13 s after launch from an alerted site, ~30 s from a cold one; 3 of 5 HARMs killed in run 2, both Pantsirs lost | probe run 2 | SEAD packages against Tor/Pantsir-defended sites need more ARMs per target (or decoys, e.g. ADM-160 MALD if available) |
| **C-RAM and Patriot track weapons but never fire at them** (KAB-500, rockets, Grad, FAB-250, Kh-31P). Probe run 8: a weapons-free Patriot fired three PAC-2 at aircraft 74-99 km away and none at a Kh-31P passing 6 km from it | probe runs 1-2, 8 | Nothing to exploit on the attack side; noted so nobody plans on DCS C-RAM or Patriot defending against ARMs |
| Avenger: 16 Stingers, 16 hits, all on aircraft | probe run 1 | - |

## 2. DCS AI SAM behaviour that surprises people
> **DCS 2.9.30 ("SAM acquisition below the horizon fixed"), retested 2026-09-30 (probe run 9):** the slope mutes,
> the Hawk's ~13-15 nm launch range, identification ranges and HARM-vs-dark-radar behaviour are all unchanged. The
> fix does not touch these. Skynet engagements against genuinely low or terrain-masked targets may still change -
> not covered by Janus's tests.

| Seen | Where | Consequence |
|---|---|---|
| **Patriot fired 8 PAC-2 at two unarmed, straight-flying Su-24M at 15,000 ft and hit nothing** | bench 04 | Worth a probe on the AI side: PAC-2 vs non-manoeuvring bombers (range, altitude, skill); if it is a DCS quirk, blue missions over-rely on Patriot |
| **Hawk useful reach is ~25 km in DCS** (launches only after the TR locks at 13-15 nm) although its data says 45 km; a Hawk with targets passing 50 km away never fires | bench 04, probe 4 | Place Hawks under the expected threat axis, not beside it |
| The Patriot engaged two targets 3 s apart although its unit data lists one channel | bench 04 | Unit-data "channels" are not reliable for DCS behaviour |
| SA-5 (S-200) mutes on ground steeper than ~3-5 deg like the SA-2 (fires at 3.4, mute at 5.1); the Square Pair never comes on | probe run 7 | Place SA-5 sites on ground < 3 deg |
| **Sloped ground mutes SAMs**: search radar sees the target, tracking radar never locks, no launch. Hawk mutes from 3 deg (fires at <= 1.3), SA-2 from 4.8 deg (fires at 3.3), SA-3 and SA-10 mute at 12-22 deg (fire at 5), SA-6 / SA-11 / Patriot still fire on 10-26 deg | probe runs 4-6 | Any mission (not just Janus) must put Hawk and SA-2 on ground flatter than ~2-3 deg. Janus's setup report warns |
| **Hawks don't fire in short radar windows** (15 s on / 60 s off): no time from detection to TR lock to launch. Hawk also launches only once its TR locks at ~13-15 nm (ED short-range bug since 2.9.12) | probe run 4 | Keep Hawk radars on; Janus does this by doctrine |
| SA-2 launchers slew to the intercept azimuth (since 2.9.8) - only delays the shot | probe run 5 | - |
| A launcher only fires with a radar **in its own group** (split radar / launcher groups never engage) | probe run 3 | Every SAM site = one group |
| `enableEmission(false/true)` is instant; ALARM-state warm-up is ~5 s Pantsir, ~10 s SA-6/Tor, 50-55 s SA-11/SA-10 | probe run 3 | - |
| **Ground EW radars see ARMs far too well**: 55G6 / 1L13 held a HARM 2 s after launch at 104-106 km | probe run 3 | Janus filters this (crews react only to what they could notice) |
| **Aircraft identification**: ground EW radars never report the aircraft type; E-3A and A-50 report every type from first contact (up to ~380 km); SA-11 from ~100 km, SA-6 ~50 km, SA-10 / Hawk inside ~15 km; SA-2, SA-3, Patriot never | probe run 6 | AWACS identification in DCS is near-omniscient; if the AI realism side wants a slower ID for AI fighters/AWACS, it has to add it |
| SA-2 and SA-5 report no active radar via `getRadar()` in ALARM RED with no target | probe run 1 | - |
| RWR detection via `getDetectedTargets(Controller.Detection.RWR)` on an F-16C never reported any emitter | probe run 1 | Don't build AI "RWR awareness" on that call |

## 3. Scripting / server gotchas
- **Static objects:** `Object.getCategory` = 3 (STATIC) and **no `getCategoryEx`** (the call errors). DCS fires
  `S_EVENT_DEAD` (often also `S_EVENT_UNIT_LOST`) when a static dies; afterwards `isExist()` is false, `getLife()` 0,
  and `StaticObject.getByName` still returns it. `getDesc().life` is 0 for `.Command Center` and `Bunker 1` - use
  `getLife()`. Life varies hugely: GeneratorF 10, Bunker 1 4, TV tower 150, Electric power box 150, Comms tower M 200,
  Military staff 1200, .Command Center 4000, Shelter 8000 (survived a 3000 kg blast). (probe run 6)
- **Big explosions destroy map scenery** (power lines, buildings): a 3000 kg `trigger.action.explosion` produced dozens
  of `S_EVENT_DEAD` with category 5 (SCENERY) and nil type names (bench 04). Event handlers must category-check.
- `.Command Center` (life 4000) dies to roughly 4600 kg of blasts in total; `Shelter` (8000) needs two 3000 kg ones.
- The dedicated server logs "Can't open model" for `.Command Center`, `Bunker 1` and some destroyed-vehicle models -
  harmless (no shapes on a server).
- **A `timer.scheduleFunction` at exactly "now" never ran** in probe run 6 (the first of a staggered set). Schedule at
  now + a little.
- `Su-24M: Corrupt damage model` errors in dcs.log whenever unarmed Su-24M were spawned by script (payload with no
  pylons). Harmless so far.
- DCS raises `S_EVENT_SHOT` for missiles, bombs and rockets, not gun rounds.
- `Unit:getAmmo()` returns nil when a unit has nothing left (not an empty table).
- **Server:** a client that tries to connect and times out **pauses the server** (probe run 6, t=1035, no one
  joined). Something also paused it 74 s into bench 01 with nobody on. Unattended tests need a resume guard.
- **Server:** copying a **new** .miz into the server's Missions folder while a test runs makes DCSServerBot add it to
  the list, which logs "loading mission from <new file>"; the test queue agent reads that as "another mission was
  loaded" and aborts the running test (bench 04, 2026-09-30, aborted at 150 s). Overwriting an already-listed .miz in
  place does not. Copy new missions in only when the server is idle.
- **Server:** the test queue (`tools\dcs-testq`) cannot start a test when the server is fully stopped (after a flight
  night): it waits 180 s for a "loading mission from" line and fails. The WebGUI `startServer` call restarts it (on its
  saved "current" mission). WebGUI `addMissions` also logs "loading mission from" lines (it parses the files), which
  can fool a log watcher.

## 4. Open questions worth a probe (not Janus's to answer)
- ~~Can red AI be made to launch Kh-58U / Kh-31P at an emitting radar at all?~~ Yes (probe run 8); the Su-24M loadout
  is what failed.
- Which pylons / CLSIDs give a script-spawned Su-24M its Kh-58U / Kh-31P?
- Does a HARM launched in POS / pre-briefed mode (if DCS AI supports it) hit a site that never emits?
- Is the AWACS all-types identification affected by range, aspect or skill?
