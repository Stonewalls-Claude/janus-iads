# Janus IADS - Troubleshooting

First step for any problem: open `dcs.log` (Saved Games\DCS\Logs, or the server's Saved Games folder) and search for
`setup report`. Janus lists every group it found and everything it thinks is wrong. Every later decision it makes is
logged on a line containing `JANUS [`.

| Symptom | Likely cause | Fix |
|---|---|---|
| Nothing happens, no `JANUS` lines in dcs.log | The trigger is missing or not MISSION START | Triggers: **4 MISSION START**, action **DO SCRIPT FILE** `janus.lua` |
| A group is not in the setup report | Its name does not start with a role word | Rename it `SAM ...`, `EW ...` etc. The report lists air-defence groups it skipped and suggests a name |
| "has no radar or sensor of its own: it will never fire" | Launchers and radar are in different groups | Put the radar and its launchers in one group. DCS does not fire launchers without a radar in their own group |
| "stands on a 4.2 deg slope" | DCS will not let that SAM engage on sloping ground | Move the site to flat ground: Hawk below 2 degrees, SA-2 / SA-5 below 3, SA-3 / SA-10 below 5 |
| SAM radars never turn on | They are waiting to be cued: nothing is in their reach yet, or no EW radar covers them | That is the point: radars come up when the network gives them a target. With no `EW` group and no command post they search on their own, on and off |
| SAM radars are on all the time | The doctrine keeps them on (`GENERIC_THIRD_WORLD`, `US_VIETNAM_1965_72`), the site is tagged `[emcon:always]`, or it has lost command and is searching on its own | Pick another doctrine, remove the tag, or check its link to a command post in the report / F10 map (check mode) |
| Blue SAMs ignore an aircraft | `NATO_COLDWAR` and `US_MODERN` are **weapons tight**: they only fire at aircraft they have identified | Give the network an AWACS or a radar that identifies types, wait for the identification time, or set weapons free in the settings (`BLUE_DOCTRINE = { base = "US_MODERN", wta = { weapons = "free" } }`) |
| The Hawk never fires | Slope (above 2 degrees), or the target is beyond about 25 km: in DCS the Hawk only launches once its radar locks at 13-15 nm | Flat ground; place Hawks where targets come within 25 km |
| HARMs always hit | In DCS an AGM-88 still hits a radar after it has gone dark | Add point defence (`PD Tor ...`, `PD Pantsir ...`) near valuable sites: they stay up and shoot HARMs down. Under `RUSSIA_MODERN` a covered site stays up too |
| The Patriot does not shoot at missiles | In DCS the Patriot does not engage anti-radiation missiles | Nothing Janus can change. Avengers and fighters for leakers |
| C-RAM does not shoot at bombs or rockets | In DCS the C-RAM engages aircraft only | Nothing Janus can change. `BASE_WARNING = true` still warns players |
| A site stays dark for minutes after a HARM | Soviet doctrine waits while a SEAD aircraft stays pointed at it | That is the doctrine (`SOVIET_PVO_1985` waits; others come back sooner). Tag the site `[hold]` to keep it up |
| A static named `SAM ...` or `EW ...` is ignored | Only command posts, relays and power plants can be static objects | Use a unit group for SAMs and radars |
| "uses a DCS: WWII Assets Pack unit" | That unit is paid DLC | Players and servers without the DLC cannot load the mission. Use non-DLC units or say so in the briefing |
| Two networks do not share targets | Sites are tagged with different `[net:...]` names | Same tag (or no tag) for sites that should work together |
| A carrier group's ships stop working far from land | Ships without a tag join the main network and lose their link far from a command post | Tag the escort `SHIP ... [net:CSG]`: the group becomes its own network |
| The server lags | A very large mission | Janus is measured at 300 sites and 300 aircraft for both sides together; if the server still lags, check other scripts first (dcs.log timestamps), then turn off `CHECK_MODE` and `STATS` |
| Error lines `ERROR JANUS [...]` | A bug, or a unit or script removed something Janus was using | Janus keeps running (every part is guarded). Please report it with the dcs.log lines around the error |

## Still stuck?
Open an issue on the GitHub page with: the Janus version (first `JANUS` line in dcs.log), the setup report, the
lines around the problem, and if possible the mission file.
