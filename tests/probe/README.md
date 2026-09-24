# Phase 0 engagement probe

Question: what does DCS's own AI engage, and how quickly? Janus's docs must only promise what DCS delivers,
and its HARM-defence design (DESIGN.md 4.5) assumes point defence can hit incoming weapons.

1. Build `janus_probe.miz` (Syria) with `tools/build_probe_miz.py` (layout is described at the top of `janus_probe.lua`);
   load `janus_probe.lua` with DO SCRIPT FILE at MISSION START. No other scripts.
2. Run it on the dedicated server for ~25 minutes (each attacker wave is triggered 3 minutes apart).
3. `python3 tools/probe_report.py "C:\Users\flier\Saved Games\DCS.dcs_serverrelease\Logs\dcs.log" > docs/PROBE_RESULTS.md`

Waves (all against the same defended point; defenders: 2× C-RAM, 2× Avenger, Patriot battery on blue; 2× Tor, 2× Pantsir on red
at a second point attacked by blue F-16 AGM-88):
| Wave | Weapon class | Attacker |
|---|---|---|
| 1 | anti-radiation missile | F-16C AGM-88C vs Tor/Pantsir; Su-24M Kh-58U vs C-RAM/Avenger site |
| 2 | ARM vs Patriot; anti-ship missile | Su-34 Kh-31P vs Patriot; Tu-22M3 Kh-22 vs C-RAM site |
| 3 | guided bomb | Su-34 KAB-500Kr |
| 4 | unguided rockets | Mi-24P S-8 |
| 5 | artillery rockets | BM-21 Grad (does C-RAM count these?) |
| 6 | gun strafe / dumb bombs | Su-25 |

Build the .miz: `python3 tools/build_probe_miz.py --template <empty Syria .miz>` (the StonewallC IADS test .miz works as the template; only its theatre, date, weather and options are kept). The probe script spawns everything itself, so the .miz has no units.

Exit gate for Phase 0: `docs/PROBE_RESULTS.md` exists with one row per weapon class.
