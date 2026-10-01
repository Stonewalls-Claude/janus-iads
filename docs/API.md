# Janus IADS - Lua API (for scripters)

Nothing here is needed for a normal mission: `janus.lua` starts itself. Everything Janus owns lives in one global
table, `JANUS`; settings come from `JANUS_SETTINGS`, set **before** `janus.lua` loads. Coalitions are numbers:
1 red, 2 blue. Sites are named by their DCS group (or static) name.

## Settings (`JANUS_SETTINGS`)
Set in `janus_settings.lua` or any script loaded before `janus.lua`. Every field is optional.

| Field | Default | Meaning |
|---|---|---|
| `AUTOSTART` | `true` | start 1 s after loading; `false` = call `JANUS.start()` yourself |
| `AUTOSTART_DELAY` | `1` | seconds |
| `CHECK_MODE` | `false` | setup report on screen, network on the F10 map |
| `LOG_LEVEL` | `2` | 0 errors, 1 + warnings, 2 + info, 3 + debug |
| `RED_DOCTRINE` / `BLUE_DOCTRINE` | `"SOVIET_PVO_1985"` / `"US_MODERN"` | a profile name, or a table (below) |
| `ROLE_WORDS` | `SAM EW CMD PD AAA COMMS POWER SHIP AWACS` | the words at the start of group names |
| `STATS` | `false` | per-site statistics in dcs.log |
| `STATS_EVERY` | `600` | seconds between reports (0 = only at mission end) |
| `BASE_WARNING` | `false` | "INCOMING" to the side of a C-RAM (or `[warn]`) site when a ground-attack weapon comes near |
| `BASE_WARNING_RANGE` | `12000` | metres |
| `BASE_WARNING_SOUND` | `""` | a sound file packed in the mission, e.g. `"siren.ogg"` |
| `BASE_WARNING_COOLDOWN` | `30` | seconds before the same place warns again |

### Custom doctrine
A table with `base` (a profile name) and the fields to change; nested tables are merged one level deep:
```lua
JANUS_SETTINGS = {
  RED_DOCTRINE = { base = "NVA_VIETNAM_1965_72", aaa = { mode = "trap" }, arm = { maxDark = 90 } },
  BLUE_DOCTRINE = { base = "US_MODERN", wta = { weapons = "free" } },
}
```
Every field is described at the top of `src/janus_doctrine.lua`; the profiles are in `JANUS.Doctrines`.

## Starting
```lua
JANUS_SETTINGS = { AUTOSTART = false }
-- ... load janus.lua, spawn your groups ...
JANUS.start{ red = "RUSSIA_MODERN", blue = "NATO_COLDWAR" }
```
`JANUS.VERSION` is the version string.

## Events
```lua
local handle = JANUS.subscribe("engage", function(ev)
  env.info(ev.site .. " engages track " .. ev.track)
end, "my-script")          -- optional key: subscribing again with the same key replaces the function
JANUS.unsubscribe(handle)
```
| Event | Fields (plus `event`, `t` = mission seconds) |
|---|---|
| `engage` | `coalition, net, site, from` (site it was handed from, or nil), `track` (number), `unitId` (DCS unit ID of the aircraft), `typeName` (nil until identified), `pk` |
| `harmDetected` | `coalition, net, arm` (ARM id), `site` (who confirmed it), `how` (`radar`, `eyes` or `2 sensors`) |
| `emission` | `coalition, net, site, on, reason` |
| `nodeLost` | `coalition, net, site, kind` |
| `nodeRestored` | `coalition, net, site, kind, reason` (repaired / power / linked / ...) |
| `nodeDegraded` | `coalition, net, site, kind, reason` (equipment / no power / unlinked / ...) |

Your function runs inside Janus's error guard: an error in it is logged and never stops the IADS.

## Runtime changes
| Call | Effect |
|---|---|
| `JANUS.setEmcon(site, policy)` | `"always"`, `"dark"`, `"cued"`, `"periodic"`, `"rotating"`, or `nil` for the doctrine's again. Returns false for an unknown site or policy |
| `JANUS.setWeapons(coal, state [, net])` | `"free"`, `"tight"`, `"hold"` for the side's networks (or one, by name or key). Returns how many changed |
| `JANUS.setHold(site, on)` | `true`: the site never goes dark for an ARM (the `[hold]` tag) |
| `JANUS.addGroup(groupName)` | take a group spawned by another script now (Janus also picks up named groups at their birth event) |
| `JANUS.spawnBattery(preset, point [, opts])` | below |

These work once Janus has started (1 s after loading); before that there are no sites and they return false.

## Reading
| Call | Returns |
|---|---|
| `JANUS.site(name)` | `{ name, kind, coalition, net, tier, alive, working, powered, linked, emitting, emcon, dark, assigned, x, z }` (a copy) or nil |
| `JANUS.siteNames([coal])` | sorted site names |
| `JANUS.stats()` | `{ [site] = { coalition, kind, emitMin, shots, kills, lost } }` (also with `STATS` off) |

`kind` is one of `C2`, `COMMS`, `POWER`, `EW` (AWACS too), `BATTERY`, `PD`, `AAA`, `NAVAL`.

## Spawning a battery
```lua
local name, info = JANUS.spawnBattery("SA-11", { x = 10000, z = 20000 }, { coalition = 1, tier = "VET", aaa = true })
if not name then env.info("no site: " .. info) end
```
Builds the battery from its real-world preset (`JANUS.Presets`, listed in [BATTERY_PRESETS.md](BATTERY_PRESETS.md)) on the
nearest ground flat enough for all its units to fire, and Janus takes it into the network.
- `point`: `{ x, z }` (or `{ x, y }` as the Mission Editor gives it).
- `opts`: `coalition` (1 / 2), `country` (DCS country id; default Russia / USA), `label`, `tier` (`GRN/REG/VET/ACE`,
  also sets the DCS skill), `heading` (degrees), `full` (optional units too), `aaa` (the preset's gun ring as a
  separate `AAA ... guns` group), `search` (metres, default 5000), `maxSlope` (degrees; default the strictest DCS
  limit of its units), `tags` (e.g. `"[net:North]"`).
- Returns the group name and `{ x, z, slope, limit, units, aaa }`, or `nil` and the reason (no flat ground, no water
  for a ship preset, a unit type this DCS install does not have).

## Ground control: `JANUS.gci`
A read-only interface for GCI scripts (`version` 1): the air picture, command posts, radar heads, SAM zones, commit
requests (targets the SAMs leave to fighters) and weapons control. The contract is in DESIGN section 4.10 and
`docs/requests/GCI_GROUND_CONTROL.md`; `tests/test_gci_api.lua` contains a reference consumer.
Call it through `pcall` and check `JANUS.gci.version`, so your script still runs without Janus.
