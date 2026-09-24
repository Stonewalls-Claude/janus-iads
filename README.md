# Janus IADS

**Integrated air defence for DCS World, for both coalitions, in one script.**

*Janus, the two-faced Roman god, looks both ways at once.* One engine runs red and blue air
defence networks in the same mission: command posts, early-warning radars, AWACS, SAM batteries,
short-range and point defence (including C-RAM), AAA and naval units. Each side follows its own
doctrine, from Vietnam-era SA-2 belts to modern Patriot/C-RAM defences.

> **Status: Phase 0 (foundation).** `janus.lua` loads, recognises your air-defence groups, checks
> that every site can actually work and writes a plain-English setup report. It does not yet
> control the sites - that starts in Phase 1. See [`docs/DESIGN.md`](docs/DESIGN.md) for the plan.

## Install (no coding needed)
1. Download `janus.lua` from **Releases** (or `dist/janus.lua` from this repo).
2. In the Mission Editor add a trigger: **MISSION START** → action **DO SCRIPT FILE** → `janus.lua`.
3. Start your air-defence group names with a role word:

   | Word | Use it for | Example |
   |---|---|---|
   | `SAM` | a SAM site (radar + launchers in one group) | `SAM SA-6 Hama` |
   | `EW` | an early-warning radar | `EW North` |
   | `CMD` | a command post | `CMD Damascus` |
   | `PD` | point defence: Tor, Pantsir, Avenger, **C-RAM** | `PD C-RAM Incirlik` |
   | `AAA` | guns | `AAA KS-19 Hanoi` |
   | `SHIP` | a warship or task group | `SHIP CG Leyte Gulf` |
   | `AWACS` | an AWACS aircraft | `AWACS Overlord` |
   | `COMMS` / `POWER` | relay and power nodes (optional) | `POWER Plant 2` |

4. Fly. Janus starts itself one second after loading and writes a **setup report** to `dcs.log`
   (search for `JANUS [setup]`). It tells you what it recognised and anything that will not work,
   for example: *"SAM SA-2 Hanoi: SAM SA-2 S-75 "Guideline" LN needs one of: SNR_75V"*. It also tells you
   when a site uses paid DLC units (e.g. the WWII Assets Pack), because players without that DLC cannot join
   the mission. Free asset packs (Currenthill's Pantsir, Tor-M2, IRIS-T SLM…) need nothing extra.

### Optional settings (still no code)
Copy [`examples/janus_settings.lua`](examples/janus_settings.lua) into your mission and load it
with a second DO SCRIPT FILE **before** `janus.lua`. Every line has a comment saying what it does.
Set `CHECK_MODE = true` to see the setup report on screen when the mission starts.

## What is in the repo
| Path | What |
|---|---|
| `dist/janus.lua` | the one file you install (built from `src/`) |
| `src/` | the sources: core, generated unit database, battery presets, name parser, setup |
| `docs/DESIGN.md` | the design and the phase plan |
| `docs/UNIT_DATA_REPORT.md` | every DCS air-defence unit Janus knows, how it was classified, and source conflicts |
| `docs/BATTERY_PRESETS.md` | real-world battery compositions mapped to DCS units, with sources |
| `tools/` | `build_unitdb.py` (DCS datamine + Olympus → unit DB), `check_presets.py`, `build.py`, `probe_report.py` |
| `tests/` | offline test harness (`fake_dcs.lua`, `run_all.py`) and the Phase 0 engagement probe |
| `examples/` | settings file template |

## Building and testing (developers)
```
python3 tools/build_unitdb.py --datamine <dcs-lua-datamine> --olympus <DCSOlympus>   # after a DCS patch
python3 tools/check_presets.py        # validates presets, writes docs/BATTERY_PRESETS.md
python3 tests/run_all.py              # builds dist/janus.lua and runs the offline tests (needs Lua 5.1)
dcs-check --ns JANUS --tests tests src tests/probe   # the lint gate: Lua 5.1, sanitized env, zero errors
```
Unit data comes from [Quaggles/dcs-lua-datamine](https://github.com/Quaggles/dcs-lua-datamine)
and the [DCS Olympus](https://github.com/Pax1601/DCSOlympus) unit databases.

Licensed under the GNU GPL v3.0. See [LICENSE](LICENSE).
