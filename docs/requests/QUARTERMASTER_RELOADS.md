# Request from the StonewallC Quartermaster: ammunition events and a same-name respawn

**From:** the owner, via the StonewallC logistics (Quartermaster) session, 2026-10-07/08.
**For:** the Janus session. Read with `docs/DESIGN.md` §5.2 (scripter's API) and `docs/API.md`.
**Status:** open - nothing built in Janus. The StonewallC side is designed in `dcs-missions/docs/design/QUARTERMASTER.md`
§6.3 (Phase 5); it works without these (it just respawns), but the site then looks destroyed to Janus.

## 1. Why

The owner's logistics system reloads SAM sites: an empty battery raises a reload job, a helicopter or an AI convoy
brings the reload set, and the battery comes back full. DCS cannot refill a launcher by script, so the only refill
is **respawning the group in place under the same name** (`coalition.addGroup` replaces a group of that name).

Janus already reads every launcher's missiles every 10 s (`janus_wta.lua` `refreshAmmo`, `W.AMMO_INTERVAL`) and
stops an empty battery bidding. Logistics should use that instead of polling `getAmmo` a second time.

Two things stop it today:

1. **Nobody outside Janus hears that a battery is empty.** The "out of missiles" line is a log entry only.
2. **A same-name respawn is invisible to Janus.** `janus_network.lua` `N.pickUp` returns at once for a name it
   already knows (`if N.nodes[name] then return end`), so after the respawn the node still holds the old, dead
   `Group` / `Unit` objects: `refreshAlive` finds no live units and the site reads as destroyed (and `nodeLost`
   fires on the next update). Respawning under a **new** name instead adds a second node and leaves the old one as a
   false `nodeLost` that GCI and the network both react to.

## 2. What we ask (generic; Janus never names Quartermaster - DESIGN goal 7)

### 2.1 An `ammo` event

`JANUS.subscribe("ammo", fn [, key])`, published from `refreshAmmo` when a shooter's known missile count crosses a
threshold:

```lua
{ event = "ammo", t = <mission s>, coalition = n, net = "<key>", site = "<group name>", kind = "BATTERY" | "PD" | "NAVAL",
  missiles = <ready missiles, all launchers>, launchers = <live launchers>, low = true | false, empty = true | false }
```

- Fired on the change only: full -> low, low -> empty, and back up after a refresh (so a subscriber sees the reload
  land). Never every 10 s.
- `low` threshold: a doctrine or settings value (suggest: missiles <= one launcher's load, or 25 % of the starting
  count; Janus's choice). Unknown ammo (`n.ammo == nil`) fires nothing.
- Ships (`NAVAL`) included for completeness; the owner has no ship reloads planned (blue only, port reloads later).

### 2.2 `JANUS.refreshGroup(groupName) -> true / false`

For a script that has respawned a known group under the same name:

- Re-inspect the group (`M.names.parseGroup`, `M.inspectGroup`) and **rebind the existing node** to the new `Group`
  and units: same node table, same `net`, `tier`, `parent`, links, EMCON policy and history; `alive`/`working`
  recomputed; `n.ammo` re-read at once (not on the next 10 s pass).
- Fire `nodeRestored` with `reason = "respawned"` if the node had been lost or degraded; no `nodeLost` for the gap.
- Unknown name -> behave as `JANUS.addGroup` (pick it up as new). A name whose group does not exist -> `false`.
- Optional, nice to have: `N.pickUp` could do this itself when a BIRTH arrives for a known name whose recorded units
  are all gone (the Olympus respawn case too), so `refreshGroup` is only the explicit, immediate form.

### 2.3 What the caller promises (documented in API.md)

- It respawns only when the site has no assigned track (`JANUS.site(name).assigned` empty).
- It keeps the same group name and unit names, the radar and launchers in one group (probe run 3), and gives new IDs
  (StonewallC `M.renewIds`).
- It calls `JANUS.refreshGroup(name)` about 1 s after the respawn (units are complete a moment after the first BIRTH,
  as `janus_network.lua` already notes).

## 3. Acceptance

- Offline: a test in `tests/` that empties a battery (fake `getAmmo`), sees exactly one `ammo` event with
  `empty = true`, respawns the group under the same name, calls `refreshGroup`, and sees: the same node, alive,
  linked, its EMCON policy kept, ammo full, one `ammo` event back up, no `nodeLost`. A second test: a respawn under a
  name Janus never saw behaves as `addGroup`.
- `tests/test_gci_api.lua` stays green (GCI's view of the node does not blink).
- Server, when the PC is linked: the StonewallC `QM_PROBE` mission's SAM case (same-name respawn keeps radar and
  launchers paired and full) is the DCS half; the Janus half re-runs that probe with Janus loaded.

## 4. Not asked

- No logistics inside Janus (who brings the reload, how long it takes, convoys): all StonewallC.
- No change to WTA beyond what the ammo count already does.
