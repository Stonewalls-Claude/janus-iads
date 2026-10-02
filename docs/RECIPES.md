# Janus IADS - Recipes

Copy-and-adapt setups. Each one needs only the Mission Editor plus, where it says so, one line changed in
`janus_settings.lua` (loaded **above** `janus.lua` in the same MISSION START trigger). Battery compositions follow
real units; [BATTERY_PRESETS.md](BATTERY_PRESETS.md) lists every preset with its unit types and sources.

## Choose a doctrine for each side
In `janus_settings.lua`:
```lua
RED_DOCTRINE = "RUSSIA_MODERN",
BLUE_DOCTRINE = "NATO_COLDWAR",
```
| Doctrine | In one line |
|---|---|
| `SOVIET_PVO_1985` (red default) | command post decides, SAMs dark until the target is deep in their ring (ambush), slow to act alone, two batteries per important target |
| `RUSSIA_MODERN` | quicker crews, ambush, EW radars take turns, sites under Tor/Pantsir cover stay up against HARMs |
| `NATO_COLDWAR` | datalinked picture, **weapons tight** (only shoots aircraft it has identified), point defence always on when cut off |
| `US_MODERN` (blue default) | fastest reactions, datalink picture, point defence always on, **weapons tight** |
| `NVA_VIETNAM_1965_72` | deep ambush, short radar bursts, slow voice links, SA-2 sites blink on and off, several sites fire at one package |
| `US_VIETNAM_1965_72` | Hawk batteries with radars always on, simple control |
| `GENERIC_THIRD_WORLD` | poor coordination: radars always on, every site fires at what it sees, slow everything |

## Protect an airbase with Patriot and C-RAM (blue)
- `CMD <base>`: any static (Command Center) on the base.
- `EW <base>`: an FPS-117.
- `SAM Patriot <base>`: one group: **Patriot str** (radar), **Patriot ECS**, **Patriot EPP**, **Patriot AMG**, and 4-8
  **Patriot ln** launchers about 300 m from the radar.
- `PD C-RAM <base>`: two to four **HEMTT_C-RAM_Phalanx**, and `PD Avenger <base>` with **M1097 Avenger**s.
- Settings: `BASE_WARNING = true` gives blue players an "INCOMING! <airbase> - take cover" message when bombs,
  rockets or air-to-ground missiles come within 12 km of the C-RAM. For a siren, set
  `BASE_WARNING_SOUND = "siren.ogg"` and make the Mission Editor pack the file into the mission: use it once in any
  trigger action (for example SOUND TO COUNTRY on a flag that never comes true).

What DCS does (tested): the Patriot does **not** shoot down anti-radiation missiles, and the C-RAM engages aircraft
only, not bombs or missiles. Janus cannot change that. Use Avengers and fighters for leakers.

## A Soviet SAM belt with command posts that matter (red)
- One `CMD` per sector, a few `EW` radars 30-60 km forward, SA-2 / SA-3 / SA-6 / SA-11 batteries between them, and a
  `PD Tor` beside the most valuable SAM.
- Add `COMMS Relay 1` (a comms tower static) between a far-forward site and its command post, and tag the site
  `[relay:Relay 1]`: destroy the tower and the site is cut off.
- Add `POWER Plant 1` (a generator static) near a site: destroy it and the site runs on reserve for 5 minutes, then
  goes down.
- A second command post with `[alt:North 2]` on the first (`CMD North [alt:North 2]` and `CMD North 2`) takes over
  when the first is destroyed.

## Vietnam SAM belt with AAA (red)
- `SAM SA-2 <name>`: **SNR_75V** Fan Song in the middle, six **S_75M_Volhov** launchers in a ring 70 m out, one
  **p-19 s-125 sr** (Flat Face). Flat ground: SA-2s do not fire above about 3 degrees.
- `AAA <name>`: rings of **ZU-23 Emplacement** (300 m) and **S-60_Type59_Artillery** (800 m), a **SON_9** Fire Can.
- Settings:
  ```lua
  RED_DOCTRINE = { base = "NVA_VIETNAM_1965_72", aaa = { mode = "trap" } },
  BLUE_DOCTRINE = "US_VIETNAM_1965_72",
  ```
  `aaa = { mode = "trap" }` turns on **flak traps**: the guns hold their fire until an aircraft is well inside their
  reach and below their ceiling, then all open up at once.
- Give the blue strike package F-4Es with AGM-45 Shrikes for Iron Hand.

## Carrier group air defence (blue or red)
- Name the escorts `SHIP <name> [net:CSG]` (one group for the whole escort is fine). With `[net:CSG]` the group is its
  own network, linked wherever it sails; without it, it joins the side's main network and is cut off when it sails
  out of link range of a command post.
- An AWACS group (E-2, E-3, A-50) over the fleet is found by type and extends the picture; no name needed.

## Make the SAMs harder or easier
- **Crew tier in the name**: `GRN` (slow), `REG`, `VET`, `ACE` (quick). It changes reaction times, how long a cut-off
  site waits before acting alone, how fast it notices an incoming HARM, and how soon it comes back after hiding from one
  (ACE at once, green crews a minute later).
- **DCS skill** in the Mission Editor still sets how well the units themselves shoot.
- **Doctrine**: `GENERIC_THIRD_WORLD` is the easiest to take apart, `RUSSIA_MODERN` and `US_MODERN` the hardest.
- **Per site**: `[emcon:always]` keeps a radar on all the time (easy to find and hit), `[emcon:dark]` keeps it off
  (a decoy or a reserve site: it will not fire), `[hold]` makes it ignore HARMs.

## With a ground-control (GCI) script
Janus never flies fighters. A GCI script (for example StonewallC GCI 2) can read Janus's air picture, command posts
and SAM zones through `JANUS.gci` and vector fighters at the targets the SAMs leave alone (`commitRequests`). Load
Janus first, the GCI script after it. See [API.md](API.md).

## Spawning batteries during the mission (Lua)
For scripters and dynamic missions: `JANUS.spawnBattery("SA-11", { x = ..., z = ... })` builds a real-world battery on
the nearest ground flat enough for it to fire. See [API.md](API.md).
