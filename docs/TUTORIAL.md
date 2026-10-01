# Build your first IADS in 10 minutes

You will build a small red air-defence network on the Syria map (any map works): one SA-6 battery, one
early-warning radar and a command post, then fly a blue jet at it and watch the network work. No code.

## 1. A new mission (1 minute)
1. Mission Editor -> **New mission** -> Syria. Leave red as Russia, blue as USA.
2. Pick an open, flat area away from the coast, for example the plain east of Hama. Flat matters: some SAMs will not
   fire on slopes.

## 2. The command post (1 minute)
1. **Static object** -> category **Fortifications** -> type **Command Center** (any bunker or tent works too).
2. Country: Russia. Name it **`CMD Hama`**.

That is the network's brain. Without it the sites still work, but nobody can cut them off.

## 3. The early-warning radar (1 minute)
1. **Ground vehicle** -> Russia -> category **Air Defence** -> type **55G6 EWR** (Tall Rack) or **1L13 EWR**.
2. Place it 20-30 km from the command post. Group name: **`EW Hama`**.

The EW radar sees far but cannot shoot. Janus keeps it on all the time and passes what it sees to the SAMs.

## 4. The SA-6 battery (3 minutes)
1. **Ground vehicle** -> Russia -> Air Defence -> **Kub 1S91 str** (the Straight Flush radar). Group name:
   **`SAM SA-6 Hama`**.
2. In the **same group** add four **Kub 2P25 ln** launchers around the radar, about 200 m out. (Use the group's unit
   list: **Add** a unit, set its type.) One group, five units.
3. Optional: put `VET` in the name (`SAM SA-6 Hama VET`) for a quicker crew.

Placing it 20-40 km in front of the EW radar is a good start.

## 5. Load Janus (1 minute)
1. Triggers -> **New** -> **4 MISSION START**, name `Janus`.
2. Actions -> **New** -> **DO SCRIPT FILE** -> open `janus.lua`.
3. Optional but useful the first time: add `janus_settings.lua` (with `CHECK_MODE = true`) as a DO SCRIPT FILE
   **above** `janus.lua`. You will get the setup report on screen and the network drawn on the F10 map.

## 6. Something to shoot at (1 minute)
1. **Airplane** -> USA -> **F-16C** (or any jet). Put it 120 km from the SA-6, give it a waypoint over the SA-6 at
   5,000 m.
2. To watch from inside: make it **Client** or **Player**. To watch from outside: leave it AI and use the F10 map.

## 7. Fly and watch (2 minutes)
Save and fly. What you should see:
- **At start** (check mode): the setup report, then lines on the F10 map: `EW Hama` and `SAM SA-6 Hama` joined to
  `CMD Hama` in green.
- **The SA-6 radar is off.** The EW radar is on. Your radar-warning receiver shows the Tall Rack / Box Spring only.
- **The jet comes inside the SA-6's reach:** the command post cues the SA-6. Its radar comes up a few seconds later
  (quicker for VET or ACE crews) and it fires.
- **The jet turns away:** the SA-6 stays up for half a minute, then goes quiet again.

Things to try next:
- Destroy `CMD Hama` (or set it to a low life and shoot it). The SA-6 is cut off; after a few minutes (by crew tier)
  it starts searching on its own, on and off.
- Give the jet two AGM-88 HARMs and a SEAD task. When the crew sees the HARM coming, the SA-6 goes dark until it would
  have hit, then comes back. Add a `PD Tor Hama` group (one **Tor 9A331**) next to the SA-6 and the Tor stays up and
  shoots at the HARM.

## 8. Watch it in Tacview
If you record with Tacview, open the file and look at the SA-6's radar: on only while the jet was in reach, off before
and after, off while a HARM was inbound. That is the whole idea: radars that only emit when it is worth the risk.

## Where to go from here
- [Recipes](RECIPES.md) for bigger setups (airbase defence, Vietnam, carrier groups).
- [Names and tags](NAMES.md) for relays, power, separate networks and per-site radar rules.
- `dcs.log` (Saved Games\DCS\Logs) explains every decision Janus makes, in lines starting `JANUS`.
