# Janus IADS - Quick start

Janus turns the SAM sites, radars and command posts you place in the Mission Editor into an integrated air-defence
network: radars stay quiet until the network needs them, sites hand targets to each other, and they defend
themselves against anti-radiation missiles. It works for red and blue at the same time.

You do not need to write any code. You need one file and four steps.

## What you need
- DCS World (single player, hosted game or dedicated server; nothing to install on the server).
- `janus.lua` from the [Releases](../../releases) page.
- Nothing else. No MIST, MOOSE or Skynet. If your mission already loads them, Janus does not mind.

## The four steps

### 1. Add the trigger
In the Mission Editor open **Triggers** (the "SET RULES FOR TRIGGER" panel).
1. **New** trigger, type **4 MISSION START**, name it `Janus`.
2. Leave **CONDITIONS** empty.
3. **ACTIONS** -> **New** -> **DO SCRIPT FILE** -> **OPEN** -> pick `janus.lua`.

The file is copied into the `.miz`, so players and servers get it automatically.

### 2. Name your groups
Janus finds air defence by the **first word of the group name**:

| Start the group name with | For | Example |
|---|---|---|
| `SAM` | a SAM battery (radar + launchers in one group) | `SAM SA-6 Hama` |
| `EW` | an early-warning radar | `EW North` |
| `CMD` | a command post (a unit, or a static object such as a bunker) | `CMD Damascus` |
| `PD` | point defence (Tor, Pantsir, C-RAM, Avenger...) | `PD Tor Hama` |
| `AAA` | anti-aircraft guns | `AAA ZU-23 Hama` |
| `COMMS` | a radio relay (unit or static, e.g. a comms tower) | `COMMS Relay 1` |
| `POWER` | a power plant (unit or static, e.g. a generator) | `POWER Plant 2` |
| `SHIP` | air-defence ships | `SHIP CG Leyte Gulf` |
| `AWACS` | an AWACS group (optional word: A-50, E-3, E-2 groups are found by aircraft type) | `AWACS Overlord` |

Upper or lower case does not matter. The side (red or blue) comes from the units. Mission makers who already name
Skynet sites `SAM ...` and `EW ...` do not need to rename anything.

**Two DCS rules that Janus cannot change:**
- A SAM battery's launchers only fire if the **radar is in the same group**. Put the whole battery in one group.
- Some SAMs will not fire on sloping ground (Hawk above about 2 degrees, SA-2 and SA-5 above 3, SA-3 and SA-10 above
  5). Place them on flat ground. Janus warns you in its setup report if one is on a slope.

### 3. Save and fly
That is all. Janus starts by itself one second after the mission starts, with a sensible doctrine for each side
(red: Soviet 1985; blue: modern US).

### 4. Check what it found (recommended)
Janus writes a **setup report** to `dcs.log` (in `Saved Games\DCS\Logs`): every group it recognised, what it is,
and anything wrong, in plain English. For example:

```
Janus IADS 1.0.0 setup report (DCS unit data 2.9.30)
Recognised 6 red and 0 blue air-defence groups.
  [red] SAM SA-2 Hanoi -> SAM (6x LN)
    PROBLEM: SAM SA-2 Hanoi has no radar or sensor of its own: it will never fire
1 group(s) contain air-defence units but do not start with a role word, so Janus ignores them:
  [red] 'SA6 site' (4 AD units) - did you mean 'SAM SA6 site'?
```

To see the report on screen and the network drawn on the F10 map while you build, turn on **check mode**:
1. Copy `janus_settings.lua` from the release next to your mission and open it in any text editor (Notepad works).
2. Change `CHECK_MODE = false` to `CHECK_MODE = true` and save.
3. Add a second **DO SCRIPT FILE** with `janus_settings.lua` to the same trigger, **above** `janus.lua`.

Turn check mode off again before you publish the mission.

## Next
- [Build your first IADS in 10 minutes](TUTORIAL.md)
- [Recipes](RECIPES.md): airbase defence, Vietnam SAM belt, carrier group, harder or easier SAMs
- [Names and tags](NAMES.md): every role word and bracket tag
- [Troubleshooting](TROUBLESHOOTING.md) and the [Glossary](GLOSSARY.md)
- For scripters: [Lua API](API.md)
