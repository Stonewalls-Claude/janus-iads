# Janus IADS

**Integrated air defence for DCS World, for both coalitions, in one script. No coding needed.**

*Janus, the two-faced Roman god, looks both ways at once.* One engine runs red and blue air-defence networks in the
same mission: command posts, early-warning radars, AWACS, SAM batteries, point defence (including C-RAM), guns and
ships. Each side follows its own doctrine, from Vietnam-era SA-2 belts to modern Patriot defences.

What it does in your mission:
- **SAM radars stay dark** until the network gives them a target, so they are hard to find and kill.
- **The network picks the shooter**: the best-placed site engages each aircraft, and targets are handed between
  sites instead of everyone firing at the same jet.
- **Command posts, relays and power plants matter**: destroy them and sites are cut off, run on reserve power, then
  act alone after a delay that depends on the crew.
- **HARM defence that works in seconds**: crews notice anti-radiation missiles the way real crews could, go dark
  for the time the missile needs, finish a shot first or stay up under Tor/Pantsir cover.
- **Doctrines** for Soviet, modern Russian, Cold War NATO, modern US, North Vietnamese, US Vietnam-era and third-world
  air defences; weapons tight for blue (only identified aircraft are engaged).
- **Tells you what it found**: a plain-English setup report in `dcs.log` (and on screen in check mode) with every
  mistake it can spot, such as a SAM on a slope too steep to fire or launchers without their radar.

## Install (four steps)
1. Download `janus.lua` from **Releases**.
2. Mission Editor -> Triggers: **MISSION START**, action **DO SCRIPT FILE** -> `janus.lua`.
3. Start your air-defence group names with a role word: `SAM`, `EW`, `CMD`, `PD`, `AAA`, `SHIP` (and optionally
   `COMMS`, `POWER`, `AWACS`). Example: `SAM SA-6 Hama`.
4. Fly.

Everything else is optional. Start here:
| | |
|---|---|
| [Quick start](docs/QUICKSTART.md) | the four steps in detail, the setup report, check mode |
| [Your first IADS in 10 minutes](docs/TUTORIAL.md) | an SA-6, an EW radar and a command post, step by step |
| [Recipes](docs/RECIPES.md) | airbase defence with Patriot and C-RAM, Soviet SAM belt, Vietnam with flak traps, carrier group, harder or easier |
| [Names and tags](docs/NAMES.md) | every role word and `[tag]` |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | symptom -> cause -> fix |
| [Glossary](docs/GLOSSARY.md) | IADS terms in one line each |
| [Demo missions](demo/) | red, blue, both sides, naval (Syria): open, fly, copy groups |
| [Lua API](docs/API.md) | for scripters: events, runtime changes, battery spawning, the GCI interface |
| [Battery presets](docs/BATTERY_PRESETS.md) | how real batteries are built, mapped to DCS units, with sources |

Works on single player, hosted games and dedicated servers. Needs nothing else: no MIST, MOOSE or Skynet (it runs
alongside them). Nothing to install on the server.

## What DCS does that Janus cannot change
Measured on test missions (`docs/PROBE_RESULTS.md`, `docs/BENCH_RESULTS.md`):
- Launchers only fire with a radar in their own group.
- Some SAMs do not engage from sloping ground: Hawk above about 2 degrees, SA-2 and SA-5 above 3, SA-3 and SA-10 above 5.
- The AGM-88 HARM still hits a radar that has gone dark; Tor and Pantsir can shoot it down.
- The Patriot does not engage anti-radiation missiles; the C-RAM engages aircraft only.
- The Hawk launches only once its radar locks, at about 13-15 nm.

## Repository
| Path | What |
|---|---|
| `dist/janus.lua` | the one file you install (built from `src/`) |
| `src/` | the sources, one module per file |
| `examples/janus_settings.lua` | the optional settings file |
| `demo/` | demo missions |
| `docs/` | user docs above; `DESIGN.md` (design and phase plan), test results, unit data report |
| `tools/` | unit database build, preset check, build, mission builders |
| `tests/` | offline test harness and tests, server probes and benches |

## Building and testing (developers)
```
python3 tools/build_unitdb.py --datamine <dcs-lua-datamine> --olympus <DCSOlympus>   # after a DCS patch
python3 tools/check_presets.py        # validates presets, writes docs/BATTERY_PRESETS.md
python3 tests/run_all.py              # builds dist/janus.lua and runs the offline tests (needs Lua 5.1)
dcs-check --ns JANUS --tests tests src tests/probe dist   # lint gate: Lua 5.1, sanitized env, zero errors
```
Unit data comes from [Quaggles/dcs-lua-datamine](https://github.com/Quaggles/dcs-lua-datamine) and the
[DCS Olympus](https://github.com/Pax1601/DCSOlympus) unit databases.

Licensed under the GNU GPL v3.0. See [LICENSE](LICENSE).
