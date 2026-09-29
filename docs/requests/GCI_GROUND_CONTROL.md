# Request from the mission GCI: Janus runs the ground side of fighter control

**From:** the owner, via the StonewallC mission / GCI session, 2026-09-29.
**For:** the Janus session. Read this with `docs/DESIGN.md` §4.1 (network model), §4.6 (degradation) and §4.8
(fighter hand-off module).
**Status:** requirements, agreed with the owner. Nothing here is built in Janus yet. The owner has chosen to
**wait for Janus** instead of adding a stop-gap to the GCI, and wants Janus's priority raised so red is fleshed
out properly.

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
