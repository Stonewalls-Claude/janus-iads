# Janus IADS - Names and tags

Everything Janus needs from you is in the group name: a **role word** first, then any name you like, then optional
**tags** in square brackets.

```
SAM SA-10 Hama VET [net:North] [cmd:Damascus]
^^^ ^^^^^^^^^^ ^^^ ^^^^^^^^^^^^^^^^^^^^^^^^^^
role   label   tier  tags
```

## Role words
| Word | What it is | Notes |
|---|---|---|
| `SAM` | a SAM battery | radar and launchers in **one** group (DCS will not fire launchers without a radar in their group) |
| `EW` | early-warning radar | feeds the network's air picture |
| `CMD` | command post | a unit or **any static object** (bunker, command center, tent) |
| `PD` | point defence | Tor, Pantsir, C-RAM, Avenger, Roland...: stays up when missiles come in and shoots them where DCS can (Tor and Pantsir shoot down HARMs; in DCS the C-RAM only shoots at aircraft) |
| `AAA` | guns | ZU-23, S-60, Shilka, Gepard, Vulcan, flak |
| `COMMS` | radio relay | a unit or a static (comms tower); links sites to a command post that is out of direct reach |
| `POWER` | power plant | a unit or a static (generator); sites near it lose power when it is destroyed |
| `SHIP` | air-defence ship | cruisers, destroyers, frigates; a carrier group can be its own network (`[net:CSG]`) |
| `AWACS` | AWACS | optional: an aircraft group made only of A-50 / E-3 / E-2 / KJ-2000 is found by type, whatever its name |

Only `CMD`, `COMMS` and `POWER` can be static objects. The words can be changed in `janus_settings.lua`
(`ROLE_WORDS`) if your missions already use other words.

## Crew tier
Put `GRN`, `REG`, `VET` or `ACE` anywhere in the name (or `[skill:VET]`). It sets how quickly the crew reacts: how
fast a cued radar comes up, how long before a cut-off site acts alone, how quickly it notices an anti-radiation
missile. No tier = `REG`. The DCS skill of the units is separate and still set in the Mission Editor.

## Tags
| Tag | Meaning |
|---|---|
| `[net:North]` | put this group in a separate network called North (default: one network per side). Networks share nothing |
| `[cmd:Damascus]` | link to the command post labelled `Damascus` (`CMD Damascus`) instead of the nearest one |
| `[relay:Relay 1]` | link through the relay `COMMS Relay 1` |
| `[power:Plant 2]` | take power from `POWER Plant 2` (several: `[power:Plant 2, Plant 3]`); default: any power node within 8 km |
| `[alt:Damascus 2]` | on a command post: `CMD Damascus 2` is its alternate, which takes over when this one is lost |
| `[ag]` | on a `COMMS` group or static: this is the command post's air-ground radio (for a ground-control script) |
| `[seats:4]` | on a command post: how many fighter-controller seats it has (for a ground-control script) |
| `[emcon:...]` | radar policy for this group, overriding the doctrine: `always` (always on), `dark` (never on), `cued` (on when the network gives it a target), `periodic` (on and off on a timer), `rotating` (EW radars take turns) |
| `[hold]` | never go dark for an anti-radiation missile: this site stays up and fights |
| `[warn]` | with `BASE_WARNING` on: give the "INCOMING" warning for this site too (C-RAM sites always do) |

Tag names are not case-sensitive. A tag Janus does not know is ignored.

## How sites link up without tags
- Each side is one network unless you use `[net:...]`.
- A site links to the nearest command post within the doctrine's link range (Soviet / NATO default 120 km), or
  through a `COMMS` relay. Command posts and relays link to each other within 80 km.
- A side with no command post at all is a flat network: every site shares the picture, nothing can be cut off.
- A site that loses its link waits (by crew tier: 30 s for ACE up to several minutes for green crews) and then acts on
  its own, searching with its own radar.
