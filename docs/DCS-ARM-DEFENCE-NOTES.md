# DCS Engine Notes: SAMs vs Anti-Radiation Missiles (ARM Defence)

**Janus IADS design reference — researched 2026-09-24**

This note answers: *"Why does a blue IADS not fire at red anti-radiation missiles (Kh-58, Kh-25MP/MPU, Kh-31P), and is that a bug?"* Short answer: it is mostly a **hard engine limitation** (per-unit-type capability, not scriptable), plus several **real bugs** (some fixed, some open). Everything below is sourced; links at the end.

---

## 1. The engine rules (what Lua can and cannot do)

### 1.1 ENGAGE_AIR_WEAPONS is a permission, not a capability
- Option ID **20**, `AI.Option.Ground.id.ENGAGE_AIR_WEAPONS`, values `true`/`false`, added DCS 1.5.6.
- Hoggit wiki wording: all ground groups *have* the option, but "it only really applies to SAM sites and **is dependent on the missile tracking capabilities of a radar system**."
- That tracking capability lives in the unit's C++ sensor/weapon definition. **If the type can't track missiles, no Lua setting will make it fire at one.**
- Skynet's `setCanEngageAirWeapons()` / `setCanEngageHARM()` are explicitly just wrappers for this option and only work "if the SAM is able to do so in DCS."

### 1.2 Which types can actually engage ARMs
- Skynet FAQ (as of July 2022, still the best public test data): only **SA-15 Tor, SA-10/S-300, NASAMS and Patriot** could be made to engage HARMs. Everything else — **Hawk, Roland, Rapier, Chaparral, Avenger, Gepard, Vulcan, SA-2/3/5/6/8/11** — cannot engage missiles at all.
- A Nov 2023 ED thread notes **"SA-15s can now engage small bombs"**, i.e. ED has been quietly expanding the intercept target classes on capable units in 2.9.x. Re-test the capability list per DCS patch; do not hard-code it forever.
- **Centurion C-RAM (LPWS)**: in-game (free asset, high-fidelity model listed in the 2.9.11 changelog). Skynet 3.3.0 added it as a point-defence unit. Caveat: as of Nov 2023, **unguided rockets (e.g. BM-21) have no collision/damage model and cannot be destroyed**, so its literal C-RAM role is hollow; its value is as a gun-based point defence vs missiles. Verify vs Kh-25/58/31 in our own test mission before relying on it.
- **Naval CIWS** (Phalanx on CG/DDG/FFG, AK-630 etc.) does engage missiles and is the most reliable "C-RAM" in the game — relevant for our carrier-group standard, less so for land IADS.

### 1.3 There is no per-target tasking
- Skynet README: "There is currently no way to tell a SAM site to only target a certain contact via the lua scripting engine." A script can only toggle emissions, alarm state, ROE and the options above. **Janus cannot order "shoot that HARM"; it can only put a capable site in a state where the DCS AI chooses to.**

### 1.4 Native ARM evasion now exists in the engine — EVASION_OF_ARM
- Option ID **31**, `AI.Option.GROUND.id.EVASION_OF_ARM`, **added DCS 2.9.6**.
- "Allows AI radar units to take defensive actions to avoid anti radiation missiles. Units are allowed to **shut radar off and displace**." `false`/`0` = no evasion; positive number = disperse for that many seconds; behaviour is **skill-level dependent** (exact effect undocumented).
- **Community testing says it barely works (as of mid-2024, unfixed since):** testers running multiple SAM types at Excellent/expert skill saw evasion only from the **SA-5**; SA-3, SA-6, SA-10 and SA-15 kept radiating until destroyed. One lead: some SAM templates may need the "Evasion of ARM" **waypoint action added manually** rather than the option activating automatically. No ED reply in either thread, and no changelog fix found since 2.9.6.
- **Design decision for Janus:** the engine's own ARM evasion will fight our HARM-defence logic (double shutdowns, units wandering off their emplacement, desync between what Janus thinks a site is doing and what the AI is doing). Recommended: Janus explicitly sets `EVASION_OF_ARM = false` (`setOption(31, false)`) on every managed radar group at activation and owns the shutdown/relocate behaviour itself — with a config switch to hand it back to the engine for unmanaged sites. Since the native option is unreliable anyway, disabling it costs nothing today; re-test it each DCS patch — if ED ever finishes it, "engine displaces, Janus manages emissions" could become a viable hybrid.

---

## 2. The bugs (history and current status)

| Issue | System | Status | Notes |
|---|---|---|---|
| Modern SAMs lost ability to engage ARMs/cruise missiles entirely | S-300, Patriot, Tor, SM | **Fixed** (~2.5.6 changelog: "Restored ability") | Proof this capability has regressed before; watch every patch. |
| Patriot fires 9+ missiles at one AGM-88, all miss; PAC-2s self-detonate or fly straight at close range | Patriot | **Fixed** (Chizh confirmed MIM-104 guidance accuracy issue Dec 2022; fix landed OB late Jan 2023) | Post-fix: ~5 missiles per AGM-88 kill (Flappie). Still a huge ammo drain; testers say it launches too far out for good Pk. |
| Patriot kills cruise missiles but not Scuds; 3 missiles per intercept attempt | Patriot | Partially addressed by the guidance fix | "Two interceptors per ARM" is the realistic benchmark it still doesn't meet. |
| NASAMS ignores inbound Kh-58U, shoots AMRAAMs at the launch aircraft instead | NASAMS | **Open** ("reported earlier") | Root cause per Flappie: **DCS NASAMS is single-target — it cannot engage several targets simultaneously**. Once the launch aircraft died, it tracked and killed the Kh-58. |
| NASAMS AIM-120s do no damage / disappear after launch in MP | NASAMS (all AI SAMs implicated) | Reported Feb 2024 | Apparent MP desync; SAM-vs-missile performance is measurably worse on dedicated servers than in the ME. **Test on the dedicated server, not just locally.** |
| Hawk battery tracks but never launches; Patriot in same spot fires fine | Hawk | **Investigating** (Aug 2026, 2.9.28) | Cause per ED (BIGNEWY): terrain slope + reaction time. A Hawk PCP at exactly **2° pitch disables the entire site**. ED asked the team about relaxing the limit. |
| SA-10 "new" ED radars return no detection range to scripts | SA-10 (new radar models) | Open (per Skynet 3.2.0 notes) | Any script that reads sensor ranges (as Janus does) must handle a nil/0 detection range and fall back to a data-table value. |

### 2.1 Detection is half the problem
- Skynet docs: since the HARM RCS updates in **DCS 2.7**, older radars (SA-2, SA-6 class) identify a HARM only at very close range, "usually less than 10 seconds before impact."
- Data-file RCS values (Airgoons reference): **Kh-58 ≈ 0.12 m², Kh-31 ≈ 0.3 m²**, AGM-88 similar class. Even Patriot/NASAMS-class radars get late detections; a Mach 3+ Kh-31P compresses the timeline further.
- Skynet's HARM classifier (worth mirroring in Janus): contact **> 800 kt** and **≤ 2 flight-path changes**; per-radar detection chance combined multiplicatively across radars that see it.

---

## 3. What this means for Janus

1. **Per-type capability flag.** The unit database (built from the DCS datamine + Olympus DBs) carries `canEngageARM` per type. Seed list: Patriot, NASAMS, SA-10, SA-15 = true; C-RAM = true-pending-test; everything else false. Re-validate the list after every DCS patch (add to the patch-test checklist alongside TACAN).
2. **Assert the options, don't assume them.** On activation and after *any* ROE/alarm-state/task change, re-set on capable sites: `ALARM_STATE = RED`, `ENGAGE_AIR_WEAPONS = true` (id 20), and `EVASION_OF_ARM = false` (id 31). Option changes in DCS have a history of clobbering each other.
3. **Emission control is the only ARM defence for most of the fleet.** For every non-capable type, Janus's defence is detect → shut down → (optionally displace) → relight after time-to-impact + buffer. Skynet's numbers work: shut down radars within 20 NM ahead and ±15° of the HARM track, relight up to 180 s after computed impact. A DCS HARM losing its emitter glides to last known position and typically misses by 50–100 m.
4. **Point-defence grouping rule.** Point-defence launchers that should deconflict against multiple inbound HARMs must be **in the same ME group**; separate groups all fire at the same HARM (Skynet finding). NASAMS additionally is single-target per site regardless — never assign one NASAMS site to defend against a multi-ARM volley alone.
5. **Saturation logic.** Keep emitting while (point-defence launchers + ready missiles) ≥ inbound ARMs; shut down beyond that (Skynet's tested saturation point). For Patriot, budget ~5 interceptors per ARM kill post-fix, not 2 — bias toward shutdown once inbound count × 5 exceeds ready missiles, to avoid a 4-ship SEAD flight Wincestering a battery for free.
6. **Emission on/off method (MP-tested).** Skynet 3.0.0 moved to `enableEmission()` so mobile units stay responsive, then **3.2.0 reverted SAM-site HARM defence to AI ON/OFF "for better multiplayer support."** Janus targets a dedicated server: default to AI ON/OFF for HARM shutdowns of static sites, use `enableEmission()` only for units that must keep moving, and test both on the dedicated server.
7. **Share HARM tracks IADS-wide.** Skynet's biggest HARM-defence rewrite (3.0.0) was sharing detections across all connected radars instead of per-emitter detection; its 3.2.0 fix "only one HARM could be detected by IADS" shows the track-store must handle N simultaneous ARMs. Janus's track files should treat ARM contacts as first-class multi-track objects from day one.
8. **Placement sanity check at build time.** On IADS activation, sample terrain slope under every Hawk/Patriot/NASAMS unit (`land.getHeight` grid around the unit position) and `env.warning` any site on ≥ ~2° slope — cheap, and catches the Aug 2026 Hawk-won't-fire condition on both ME-placed and Olympus-spawned sites.
9. **Blue C-RAM requirement.** Land C-RAM = Centurion, deployed as point defence around EW radars / Patriot sites, same-group pairs where possible. Do **not** promise counter-rocket capability (rockets currently indestructible). Add a Janus test mission: Centurion + inbound Kh-25MP/Kh-58/AGM-88 volley, run after each DCS patch.
10. **Vietnam profile.** SA-2/SA-3 era systems have effectively zero ARM detection or intercept ability in DCS — historically correct. The Vietnam doctrine profile should rely purely on shutdown discipline + relocation, never point defence.
11. **Autonomous-mode gap.** Skynet's known issue: autonomous sites don't shut down for inbound HARMs (no IADS to warn them). Janus should keep a minimal "last-ditch" local HARM check on autonomous sites so a decapitated IADS doesn't become a HARM magnet.

---

## Sources
- Skynet-IADS README (walder): https://github.com/walder/Skynet-IADS
- Skynet-IADS releases (3.0.0 HARM rewrite, 3.2.0 fixes/reversion, 3.3.0 C-RAM): https://github.com/walder/Skynet-IADS/releases
- Hoggit wiki — ENGAGE_AIR_WEAPONS (id 20): https://wiki.hoggitworld.com/view/DCS_option_engage_air_weapons
- Hoggit wiki — EVASION_OF_ARM (id 31, added 2.9.6): https://wiki.hoggitworld.com/view/DCS_option_Evasion_of_arm
- ED Forums — SAM Radar ARM Evade (only SA-5 observed evading, Jul-Aug 2024, unanswered): https://forum.dcs.world/topic/353266-sam-radar-arm-evade/
- ED Forums — New SAM AI changed but not changed? (SA-3/6/10 never evade; waypoint-action lead): https://forum.dcs.world/topic/353852-new-sam-ai-changed-but-not-changed/
- DCS 2.9.6 changelog (EVASION_OF_ARM introduced): https://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.6.57650/
- ED Forums — Patriot unreliable vs munitions (fixed internally; Chizh/NineLine/Flappie): https://forum.dcs.world/topic/313261-patriot-extremely-unreliable-at-intercepting-incoming-munitions/
- ED Forums — Patriot not intercepting missiles: https://forum.dcs.world/topic/316388-patriot-system-not-intercepting-missiles/
- ED Forums — NASAMS self-protect / ignores Kh-58U (single-target root cause): https://forum.dcs.world/topic/328135-nasams-very-low-and-inconsistent-ability-to-self-protect/
- ED Forums — NASAMS launcher can't fire at several targets: https://forum.dcs.world/topic/278116-nasams-bug-a-launcher-cant-fire-at-several-targets-at-the-same-time/
- ED Forums — NASAMS AIM-120s no damage in MP (desync): https://forum.dcs.world/topic/330442-nasams-aim-120s-not-doing-damage-and-disappearing-shortly-after-launch-in-multiplayer/
- ED Forums — Hawk detects but won't launch, 2.9.28 / slope limit (investigating): https://forum.dcs.world/topic/391530-mim-23-hawk-detects-hostile-aircraft-but-does-not-launch-missiles-dcs-292826385
- ED Forums — C-RAM cannot destroy incoming rockets: https://forum.dcs.world/topic/335389-c-ram-cannot-actually-destroy-incoming-rockets/
- DCS 2.9.11 changelog (Centurion C-RAM free asset): https://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.11.4686/
- DCS Steam changelog (~2.5.6, "Restored ability" for modern SAMs vs ARMs): https://store.steampowered.com/news/posts/?appids=223750
- Airgoons DCS reference — RCS values, western air defences: https://www.airgoons.com/w/DCS_Reference/Air_Defences/Western
