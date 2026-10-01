# Request to the StonewallC standards owner: STANDARDS.md / HVY_STANDARDS.md changes for Janus

**From:** the Janus IADS session, 2026-09-30. **Apply when:** GCI 2.14.0 runs on `JANUS.gci` and the Phase 2.5 gate
bench has passed (see `docs/DESIGN.md` §9). Until then Skynet stays the standard. Janus cannot edit these files: they
live in the StonewallC repo. Line numbers are from the 2026-09-26 copy. Every change applies to both STANDARDS.md and
HVY_STANDARDS.md (HVY lines are 4 lower).

## 1. Line 33 - Release / pinned frameworks
Replace `Pinned: MIST 4.5.126, VEAF Skynet-IADS v3.5.0 ([`lib/`](../lib/)); all Lua works with both.` with:
> Pinned: MIST 4.5.126 and Janus IADS (`lib/janus.lua`, a release tag of `janus-iads`, GPL-3.0). Janus needs no MIST.
> Skynet-IADS 3.5.0 stays in `lib/` only for legacy missions and the Phase 5 comparison bench.

## 2. Line 34 - Load order
Replace `MIST → Skynet → StonewallC_core.lua` with
`MIST → JANUS_SETTINGS (optional, the mission's Janus settings) → janus.lua → StonewallC_core.lua`, and drop
`→ StonewallC_skynet_setup.lua` from the end. Add:
> GCI finds Janus by looking up `JANUS.gci` (version check, pcall, falls back to its own picture); Janus never calls
> GCI, so the only order rule is Janus before GCI.

## 3. Lines 55-56 - naming table
Replace the two Skynet rows with:

| Kind | Example | Rule |
|---|---|---|
| SAM (Janus) | `SAM SA-11 Latakia VET` | Janus matches the **group** name start; the crew tier word (GRN/REG/VET/ACE) is read anywhere in the name |
| EW (Janus) | `EW 55G6 Tartus REG` | Janus matches the **group** name start (Skynet matched the unit name; a unit named `… REG-1` still works for both) |
| Command post / radio / power (Janus) | `CMD Bunker Tartus`, `COMMS Relay Homs`, `COMMS Tartus [ag]`, `POWER Gen Tartus` | groups **or static objects**; `[ag]` = air-ground radio for GCI seats; `[alt:Name]` = alternate post |
| AWACS (Janus) | `Magic AEW ACE` or `AWACS A-50 North` | recognised by aircraft type (A-50, E-3A, E-2C, KJ-2000...): callsign-first names work; the group holds AWACS aircraft only |

The existing names keep working, so no mission has to be renamed.

## 4. Line 96 - "unit 1 is the radar"
Keep the rule for Skynet missions; add: "Janus finds the radar anywhere in the group. DCS still needs the radar and
launchers **in one group** (probe run 3)."

## 5. New lines worth adding (from Janus probes)
- SAMs on flat ground: Hawk ≤ 2°, SA-2 and SA-5 ≤ 3°, SA-3 and SA-10 ≤ 5° (steeper and DCS never launches; Janus's
  setup report warns). SA-6, SA-11, Patriot fire on steep ground.
- Hawk launches only inside ~25 km in DCS; place it under the threat axis.
- Do not copy a new `.miz` into the server's Missions folder while a queued test runs (DCSServerBot loads it and the
  test queue aborts the job).
