# Request from the mission GCI: Janus runs the ground side of fighter control

**From:** the owner, via the StonewallC mission / GCI session, 2026-09-29.
**For:** the Janus session. Read this with `docs/DESIGN.md` §4.1 (network model), §4.6 (degradation) and §4.8
(fighter hand-off module).
**Status (updated 2026-09-29 by the Janus session): answered - build from `docs/DESIGN.md` §4.1A and §4.10, not
from sections 3.1-3.4 below.** The needs in this request all stand; the *mechanism* changed. The original text is
kept below as history. Nothing is built in Janus yet (Phase 2.5, after Phase 2).

## 0. Janus reply (2026-09-29, agreed with the owner)

**The link runs the other way.** `GCI.setGroundSource(fn)` would make Janus hand GCI a function, so Janus would
have to know GCI exists. That breaks Janus's standalone rule (DESIGN goal 7). Instead, GCI **pulls**:
- GCI looks up `JANUS.gci` itself each tick and checks `JANUS.gci.version` (integer; 1 in Phase 2.5).
- Every call goes through `pcall`. Janus missing, an unknown version or an error -> GCI warns once and runs in its
  current mode (`EW …` scan and flat ground post). This keeps the error handling GCI 2.13.0 already has.
- Janus never names GCI; `tests/test_gci_api.lua` checks that nothing in Janus's `src/` does.

**One command hierarchy (DESIGN §4.10).** Janus owns the command posts (ground, naval and AWACS) and the one air
picture; GCI's controller seats sit inside Janus command nodes. SAM orders stay in Janus; fighter orders go only
through GCI. Command posts, relays and power can be static objects (DESIGN §4.1A); destroying a post removes its
seats, destroying a radio or power degrades them.

Where each request now lives:
| This request | Answered by (DESIGN) | Change for GCI |
|---|---|---|
| 3.1 ground radar picture via `setGroundSource` | `JANUS.gci.radarHeads(coal)` (§4.10), same list format (`x, y, z, name, r2`) | Pull it; retire `setGroundSource` |
| (new) the picture itself | `JANUS.gci.tracks(coal)` - Janus's fused tracks, never true positions; each carries `typeName` + `typeKnown` once a sensor has identified it (DCS detection `type` flag, DESIGN §4.2), otherwise class only | GCI stops building its own picture; uses the type for missile reach / "outranged" / "hot on us", worst case for the class when `typeKnown` is false |
| (new) AWACS | Included in `radarHeads` / `tracks` / `commandNodes` as an airborne command node | GCI must not add DCS AWACS on its own (double count) |
| 3.2 intercept posts, seats, state | `JANUS.gci.commandNodes(coal)`: kind, parent, alive / powered / linked, air-ground radio state, alternate CP, delegation. Seat counts stay GCI-side (seats are GCI's; a `[seats:n]` tag on the post is read by GCI) | GCI binds each seat to a node; replaces the one flat post per side |
| 3.2 statics | §4.1A, Phase 2; death detection probed first | - |
| 3.3 push callbacks | `JANUS.gci.on(event, fn, key)` / `off(handle)`: `nodeLost`, `nodeRestored`, `nodeDegraded`, `authorityChanged`; same key replaces, so hot reloads never pile up; `JANUS.gci.instance` changes when Janus restarts | GCI subscribes one fixed callback per Janus instance under its own key, re-subscribes when `instance` changes, and still re-reads `commandNodes` every tick (events only speed things up) |
| 3.4 doctrine hint | `fighterControl` (`"ground"` / `"aew"`) plus AWACS takeover rule in `commandNodes` | Replaces `cfg.handoffMode` when Janus is usable; "CRC dies, AWACS takes over" vs "A-50 carries on, slower" comes from Janus |
| (new) friendly SAM zones | `JANUS.gci.samZones(coal)` for *both* sides | GCI keeps fighters out of friendly MEZs as well as enemy rings |
| 3.5 scramble requests | `JANUS.gci.commitRequests(coal)`, Phase 4 | - |
| (new) interface test | `tests/test_gci_api.lua` in Janus, with a reference consumer | The dcs-missions fake-link test (`harness_gci_handoff.lua` J) is retired with GCI 2.14.0 |
| Parked | SRS channels for Soviet/Russian ground-post controllers | StonewallC standard update, GCI side |

**Update 2026-09-30: the Janus side is built** (`src/janus_gci.lua`, final shapes in DESIGN §4.10 "Built").
Start from `tests/test_gci_api.lua`: its reference consumer shows the pull / version check / pcall / fallback / one
subscription per `instance` pattern, and `tests/bench/janus_gci_monitor.lua` is a working in-DCS example.

Acceptance (section 5) stands, with two additions: GCI builds no picture of its own while Janus is usable, and the
same bench runs clean with no GCI loaded. GCI 2.14.0 (the GCI session's work list) starts after Janus Phase 2.5
lands.

---

## 1. Why this came up

On 2026-09-29 we ran a GCI load test on the dedicated server, 160 AI aircraft a side (`StonewallC_GCIMAX_TEST`).
The GCI (`dcs-missions/scripts/StonewallC_gci.lua`) worked, but it showed that the **red ground side is too thin**:

- The GCI models all red ground control as **one flat "ground post" with 2 controller seats** per coalition. It
  exists whenever the side has any `EW …` radar, and nothing can destroy it except killing every EW radar.
- At T+0, 19 red flights overflowed those 2 seats and flew uncontrolled until seats freed up.
- Red's real doctrine is the opposite of that. Soviet PVO and Iraqi KARI (1991) were **ground-centric**: a
  network of sector operations centres and intercept operations centres, fed by the EW radars, ran the
  intercepts. The A-50 extended the picture; it did not replace the ground controllers. Iraq had almost no
  airborne early warning at all.
- In Desert Storm those command nodes (sector and intercept operations centres) were struck on the first night.
  Taking them out blinded and fragmented the network. (History from general knowledge; verify before you quote
  it in docs.)

The owner wants that on the red side: **real, targetable ground command and control, so strike aircraft can
degrade the system**. This belongs in Janus.

## 2. Who owns what

Janus stays ground-based IADS only. The GCI stays the air side. They complement each other; neither runs the
other.

| Janus (ground) | GCI (air) |
|---|---|
| EW radars, command posts, comms relays, power, and the links between them | Controller seats, their tiers and cadence |
| Which radars feed the picture (linked, working, emitting) | Vectors, commit / hold / bug-out decisions, fight planning |
| Which command posts are alive, linked and powered | Radio calls, SRS channels, voices (red 135.1–135.9, blue 136.1–136.9 AM) |
| Degradation when a node dies, is cut off or loses power | Hand-off between ground posts and AEW aircraft |
| Doctrine data (how centralised a side is) | Reading that doctrine to decide who controls a flight |

Janus must not need the GCI to run, and the GCI must not need Janus. Without Janus, the GCI falls back to its
own `EW …` name scan and the flat ground post, as today.

## 3. What the GCI needs from Janus

### 3.1 The ground radar picture (plug already exists on the GCI side)

GCI 2.13.0 adds `GCI.setGroundSource(fn)`. Janus registers a function; the GCI calls it every picture tick
(5 s) per coalition:

```lua
-- fn(coal) -> list of the side's ground radars that feed fighter control, or nil (GCI falls back to its name scan)
{ { x = <m>, y = <m>, z = <m>, name = "EW 55G6 Aleppo", r2 = <reach in m, squared (optional)> }, ... }
```

Rules for what Janus puts in that list:
- Only radars that are **working, powered, emitting and linked** to a working command post. A radar cut off by a
  dead relay, a dead command post or a dead power plant drops out, even though the radar itself is alive. That is
  how a strike on a relay blinds a sector.
- A radar in autonomous mode (Janus §4.6) is **not** in the list, unless the doctrine says an autonomous EW still
  passes a voice-relayed picture (DESIGN §8A item 1, `c2LossCue`); then include it with a shorter reach.
- `r2` is the reach against a medium-altitude fighter. If left out, the GCI uses `ewRangeNm` (150 NM).
- It must be cheap: the GCI calls it every 5 s per side. Return a cached list that Janus refreshes on its own
  link timer and on node deaths.
- If the function errors, the GCI warns once and falls back to its name scan, so a Janus bug does not take the
  fighters down with it.

### 3.2 Intercept posts (new; the GCI side will be built to match)

Janus publishes the **command posts that can run intercepts**. The GCI turns each one into a ground controller
with its own seats, replacing today's single flat post. Proposed call (Janus decides the final shape and tells the
GCI session):

```lua
-- fn(coal) -> list of intercept posts
{ { name = "CMD SOC North", x = <m>, z = <m>,
    seats = 3,                 -- intercept controllers at this post (doctrine / tag driven)
    tier = "veteran",          -- crew tier (GRN / REG / VET / ACE word, as elsewhere)
    radars = { "EW 55G6 Aleppo", "EW 1L13 Tabqa" },   -- the linked EW radars this post sees
    state = "linked" },        -- "linked" | "isolated" (alive but cut off) | "offline" (dead or unpowered)
  ... }
```

- **Seats per post** come from doctrine and a name tag, for example `[seats:3]`. Suggested defaults:
  - Soviet PVO / Iraqi: 2–3 per sector post; a large national air-defence HQ more.
  - NATO / US: fewer ground seats; the AWACS does most of the controlling.
- A post that is **offline** takes its seats off the air at once. Its flights go to the A-50 if one is up and in
  reach, otherwise they fly on their own radar. The GCI already handles this fallback.
- A post that is **isolated** (alive, but its relay is dead) keeps only what its own co-located radar sees, or
  goes blind, by doctrine.
- Posts and relays should support **static structures** as well as vehicles, so mission makers can place a
  bunker, command centre or relay tower that strike aircraft can target. Probe note from the fake-DCS work: a
  static's category is STATIC (3), it has no `getCategoryEx`, and its UNIT_LOST / DEAD events look different from
  a vehicle's. Janus's death handling must catch static deaths.

### 3.3 Events

Callbacks, or the existing planned `onNodeLost` / `onNodeRestored`, for CMD, COMMS, POWER and EW nodes, so the GCI
reacts in the same tick instead of on its next poll:
- post offline → its seats close, flights hand over;
- relay or power lost → the radars behind it leave the picture;
- node restored → back on the air.

Each event should carry the node name, kind, coalition and new state.

### 3.4 Doctrine hint (optional)

A per-network field the GCI can read to set who controls fighters:

| Janus doctrine | `fighterControl` | GCI behaviour |
|---|---|---|
| `SOVIET_PVO_1985`, `GENERIC_THIRD_WORLD`, `NVA_VIETNAM_1965_72` | `"ground"` | Ground posts keep their flights; the AEW takes overflow and flights beyond ground cover; if the posts go down, the AEW takes the lot |
| `NATO_COLDWAR`, `US_MODERN`, `US_VIETNAM_1965_72` | `"aew"` | Ground posts hand flights to an AEW with room |
| `RUSSIA_MODERN` | `"ground"` (A-50U does more) | as ground, with a larger AEW share |

The GCI already has this as a setting (`GCI.cfg.handoffMode`, red `overflow`, blue `aew`), so the hint is only
needed to keep both sides consistent automatically.

### 3.5 Scramble requests (already planned: DESIGN §4.8 "fighter hand-off")

When Janus publishes committed tracks and scramble requests, the GCI can use them to launch ground-alert QRA. It is
not needed for the first cut.

## 4. What stays out of Janus

Controller seats and their tiers, radio calls, SRS channels and voices, vectors, fight planning, and anything
airborne except treating an AEW as a sensor (Janus §4.1 already lists AEW as an airborne sensor for the ground
network). Those remain the GCI's.

## 5. Acceptance (a bench the GCI session can run with Janus loaded)

1. A red network with 2–3 CMD posts (at least one a static bunker), 1–2 relays and 4 EW radars. Fighter control
   comes from those posts, with seats as published.
2. Strike a CMD post: its seats go off the air within one GCI tick of the death event; its flights move to the
   A-50, or fly on their own radar if there is none.
3. Strike a relay: the EW radars behind it leave the GCI picture, and the posts that depended on them lose that
   coverage.
4. Kill every post while an A-50 is up: the A-50 takes the whole workload.
5. No Janus errors, no GCI errors, and Janus's cost stays inside its §6 budget at the GCIMAX load (about 300 aircraft).

## 6. Contacts in the other repo

- GCI plug and hand-off: `dcs-missions/scripts/StonewallC_gci.lua` 2.13.0 (`GCI.setGroundSource`, `nodesFor`,
  `handOff`, `cfg.handoffMode`).
- Tests: `dcs-missions/tests/harness_gci_handoff.lua`, section J (a fake ground source feeding the ground post).
- Load test: `dcs-missions/missions/StonewallC_GCIMAX_TEST` (PC only) and `tests/harness_gcimax_test.lua`.

## 7. Janus reply to the GCI follow-up (2026-09-30) - added to v1, no version bump
- `commandNodes(coal)[i].reach`: each command node's air-ground radio reach in metres, from its own doctrine and radio
  state (agReach up / not modelled, agBackup.range on backup, 0 with none; airborne nodes agReach).
- `controlState(coal, point, postName)`: the optional third argument asks about that post only.
- Contract test: a track's `id` is the DCS unit ID (`tests/test_gci_api.lua`).
- AWACS naming: **Janus changed, the standard does not have to.** An airplane group made only of AWACS types is an
  airborne command node whatever its name ("Magic AEW ACE" works; "AWACS ..." still works; tags in the name apply;
  spawned-later groups are picked up the same way). The only rule left for the standard: an AWACS group holds AWACS
  aircraft only (a mixed group with escorts needs the role word).

## 8. Phase 2.5 closed (2026-09-30)
The GCI session's bench (`dcs-missions/docs/design/GCI_JANUS.md` section 10) met every gate item: FULL / NOGCI /
NOJANUS, 0 script errors each. Recorded in `docs/BENCH_RESULTS.md`; DESIGN section 9 marks Phase 2.5 done. Open
from here: commit requests and weapons control (`JANUS.gci` Phase 4), SRS channels for Soviet ground posts (standard).

