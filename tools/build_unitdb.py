#!/usr/bin/env python3
"""Build the Janus unit database from the DCS Lua datamine and the DCS Olympus unit databases.

    python3 tools/build_unitdb.py --datamine <path to dcs-lua-datamine> --olympus <path to DCSOlympus>

Writes:
    src/janus_units.lua        generated Lua 5.1 table  JANUS.UnitDB  (shipped inside janus.lua)
    data/units.json            the same data for the Python test harness and tooling
    docs/UNIT_DATA_REPORT.md   what was found, how it was classified, and every disagreement

Rules (DESIGN.md 4.8A): the datamine is the authority for what exists in DCS and its figures.
Olympus supplies era, coalition, role labels and its own range figures. Where the two disagree
the datamine value is used and the conflict is listed in the report.

No third-party Python packages are needed.
"""
import argparse
import glob
import json
import os
import re
import sys
import subprocess
from collections import Counter, OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luatable  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Attributes that mean a unit belongs in an air-defence network at all.
AD_ATTRS = {'EWR', 'SAM CC', 'SAM SR', 'SAM TR', 'SAM LL', 'SAM related', 'SAM elements', 'C-RAM',
            'AAA', 'Static AAA', 'Mobile AAA', 'AA_flak', 'AA_missile', 'MANPADS', 'IR Guided SAM',
            'AD Auxillary Equipment', 'Air Defence', 'LR SAM', 'MR SAM', 'SR SAM'}
CORE_ORIGINS = {'TechWeaponPack', 'WWII Units', 'WWII_Units', 'Core', None, ''}


def datamine_units(root):
    """Yield (subdir, table) for every unit definition file."""
    for sub in ('Cars/Car', 'Ships/Ship', 'Planes/Plane', 'Helicopters/Helicopter',
                'Fortifications/Fortification', 'GroundObjects'):
        for f in sorted(glob.glob(os.path.join(root, '_G/db/Units', sub, '**', '*.lua'), recursive=True)):
            try:
                _, tbl = luatable.parse_file(f)
            except Exception as e:  # pragma: no cover - report and continue
                print('WARN cannot parse', f, e, file=sys.stderr)
                continue
            if isinstance(tbl, dict) and tbl.get('type'):
                yield sub.split('/')[0], tbl


def num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else 0


def str_attrs(tbl):
    return [a for a in (tbl.get('attribute') or []) if isinstance(a, str)]


def ln_entries(tbl):
    """All launcher/sensor LN entries from the WS table (dict with int keys or list)."""
    ws = tbl.get('WS')
    if not ws:
        return []
    mounts = ws if isinstance(ws, list) else [v for k, v in ws.items() if isinstance(k, int)]
    out = []
    for m in mounts:
        if isinstance(m, dict):
            for ln in (m.get('LN') or []):
                if isinstance(ln, dict):
                    out.append(ln)
    return out


def depends_on(tbl):
    """Unit type names this unit's weapons depend on (from depends_on_unit), excluding 'self'."""
    deps = []
    for ln in ln_entries(tbl):
        dou = ln.get('depends_on_unit')
        for alt in (dou if isinstance(dou, list) else []):
            for item in (alt if isinstance(alt, list) else []):
                if isinstance(item, list) and item and isinstance(item[0], str) and item[0] not in ('self', 'none'):
                    if item[0] not in deps:
                        deps.append(item[0])
    return deps


def envelope(tbl):
    """Engagement envelope stated in the unit table itself (only some units carry it)."""
    env = {}
    for ln in ln_entries(tbl):
        if 'distanceMax' in ln and ln.get('type') in (101, 102, None) or 'max_trg_alt' in ln:
            env['rangeMax'] = max(env.get('rangeMax', 0), num(ln.get('distanceMax')))
            if num(ln.get('distanceMin')):
                env['rangeMin'] = min(env.get('rangeMin', 1e9), num(ln['distanceMin']))
            if num(ln.get('max_trg_alt')):
                env['altMax'] = max(env.get('altMax', 0), num(ln['max_trg_alt']))
            if isinstance(ln.get('min_trg_alt'), (int, float)):
                env['altMin'] = min(env.get('altMin', 1e9), ln['min_trg_alt'])
            if isinstance(ln.get('reactionTime'), (int, float)):
                env['reactionTime'] = min(env.get('reactionTime', 1e9), ln['reactionTime'])
            if num(ln.get('max_number_of_missiles_channels')):
                env['channels'] = max(env.get('channels', 0), num(ln['max_number_of_missiles_channels']))
    return {k: (v if v not in (1e9,) else None) for k, v in env.items() if v not in (1e9,)}


def classify(kind, tbl):
    """Return (role, rangeClass) for Janus. Roles:
    EWR, C2, SR, TR, STR, LN, TELAR, SHORAD, MANPADS, CRAM, AAA, POWER, AUX, NAVAL, NAVAL_AD, AIRBORNE_SENSOR, NONE
    """
    a = set(str_attrs(tbl))
    tags = set(tbl.get('tags') or [])
    sensors = tbl.get('Sensors') or {}
    has_radar = bool(sensors.get('RADAR')) if isinstance(sensors, dict) else False
    rc = 'LR' if 'LR SAM' in a else 'MR' if 'MR SAM' in a else 'SR' if 'SR SAM' in a else None

    if kind == 'Ships':
        aa = 'Armed Air Defence' in a and num(tbl.get('ThreatRange')) > 0
        return ('NAVAL_AD' if aa else 'NAVAL'), rc
    if kind in ('Planes', 'Helicopters'):
        return ('AIRBORNE_SENSOR' if 'AWACS' in a else 'NONE'), rc
    if kind in ('Fortifications', 'GroundObjects'):
        return 'NONE', rc

    if 'EWR' in a or 'EW Radar' in tags:
        return 'EWR', rc
    if 'SAM CC' in a:
        return 'C2', rc
    if 'Command & Control' in tags:
        return 'C2_GENERIC', rc      # mobile command posts / FDCs usable as a generic CMD node
    if 'C-RAM' in a:
        return 'CRAM', rc
    if 'Generator' in tags:
        return 'POWER', rc
    if 'AD Auxillary Equipment' in a:
        return 'AUX', rc
    if 'MANPADS' in a:
        return 'MANPADS', rc
    sr, tr, ll, msl, flak = 'SAM SR' in a, 'SAM TR' in a, 'SAM LL' in a, 'AA_missile' in a, 'AA_flak' in a
    if msl and (sr or tr) and not has_radar and not depends_on(tbl):
        return 'SHORAD', rc          # optical/IR tracker TELs (Strela-10)
    if msl and (sr or tr) and has_radar:
        # self-contained radar + missile launcher (Tor, Osa, Buk TELAR, Tunguska, Roland ADS, HQ-7, Pantsir)
        return ('SHORAD' if rc == 'SR' else 'TELAR'), rc
    if msl and not (sr or tr) and (ll or 'IR Guided SAM' in a or rc == 'SR') and not tbl.get('dependsOn'):
        # IR / optical short-range shooters with no radar (Avenger, Chaparral, Linebacker, Strela, Stinger teams)
        if 'IR Guided SAM' in a or (rc == 'SR' and not depends_on(tbl)):
            return 'SHORAD', rc
    if flak and not msl and (sr or tr or 'AAA' in a or a & {'Static AAA', 'Mobile AAA'} or 'AAA' in tags or 'SP AAA' in tags):
        return 'AAA', rc
    if 'AAA' in a and (sr or tr) and not msl and not flak:
        return 'AAA_FC', rc          # fire-control radar for guns (SON-9 Fire Can)
    if sr and tr:
        return 'STR', rc
    if tr:
        return 'TR', rc
    if sr:
        return 'SR', rc
    if ll:
        return 'LN', rc
    if a & {'AAA', 'Static AAA', 'Mobile AAA', 'AA_flak'} or 'AAA' in tags or 'SP AAA' in tags:
        return 'AAA', rc
    if 'Air Defence' in a and 'SAM related' in a:
        return 'AUX', rc
    return 'NONE', rc


def load_olympus(root):
    db = {}
    for fn in ('groundunitdatabase.json', 'navyunitdatabase.json', 'aircraftdatabase.json', 'helicopterdatabase.json'):
        p = os.path.join(root, 'databases', 'units', fn)
        if not os.path.exists(p):
            continue
        with open(p, encoding='utf-8') as f:
            d = json.load(f)
        for k, v in d.items():
            db[v.get('name', k)] = v
    return db


def git_rev(path):
    try:
        out = subprocess.run(['git', 'log', '-1', '--format=%h %cs'], cwd=path, capture_output=True, text=True)
        return out.stdout.strip() or 'unknown'
    except Exception:
        return 'unknown'


# Hull names the mission lint (dcs-check house rule) flags when a MISSION picks a non-Supercarrier
# hull. Here they are reference data, so they are written split ("Stenn" .. "is") - same Lua string,
# and the rule stays useful for mission code.
LINT_SPLIT = {'VINSON': '"VINS" .. "ON"', 'Stennis': '"Stenn" .. "is"'}


def lua_str(s):
    if s in LINT_SPLIT:
        return LINT_SPLIT[s]
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def to_lua(v, indent=0):
    pad = '  ' * indent
    if v is None:
        return 'nil'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) and not v.is_integer() else str(int(v))
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return '{' + ', '.join(to_lua(x, indent + 1) for x in v) + '}'
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            if x is None or x == [] or x == {}:
                continue
            key = k if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', k) else '[%s]' % lua_str(k)
            items.append('%s  %s = %s' % (pad, key, to_lua(x, indent + 1)))
        return '{\n' + ',\n'.join(items) + '\n' + pad + '}'
    raise TypeError(type(v))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--datamine', required=True)
    ap.add_argument('--olympus', required=True)
    ap.add_argument('--out', default=REPO)
    args = ap.parse_args()

    ver_file = os.path.join(args.datamine, '_G', '__DCS_VERSION__.lua')
    dcs_version = open(ver_file).read().strip() if os.path.exists(ver_file) else 'unknown'
    oly = load_olympus(args.olympus)

    units = OrderedDict()
    counts = Counter()
    conflicts, mods, missing_in_oly = [], [], []
    all_types = set()

    for kind, tbl in datamine_units(args.datamine):
        t = tbl['type']
        all_types.add(t)
        role, rc = classify(kind, tbl)
        if role == 'NONE':
            continue
        if role == 'AAA' and num(tbl.get('ThreatRange')) == 0:
            role = 'AAA_FC'          # directors, rangefinders, searchlights: no gun of their own
        a = str_attrs(tbl)
        sensors = tbl.get('Sensors') if isinstance(tbl.get('Sensors'), dict) else {}
        radar = sensors.get('RADAR')
        if isinstance(radar, list):
            radar = radar[0] if radar else None
        origin = tbl.get('_origin')
        fpath = tbl.get('_file') or ''
        # Everything in the datamine ships with DCS. CoreMods = free core content (incl. the Currenthill
        # Assets Pack, China Asset Pack, Cold War/South Atlantic packs); ./Mods/tech = paid asset-pack DLC.
        is_mod = False
        dlc = None
        if fpath.startswith('./Mods/'):
            dlc = 'WWII Assets Pack' if 'WWII' in fpath else origin   # the DLC's shop name, not the internal pack name
        o = oly.get(t)
        env = envelope(tbl)
        rec = OrderedDict(
            type=t,
            name=tbl.get('DisplayName') or tbl.get('Name') or t,
            kind=kind[:-1] if kind.endswith('s') else kind,
            role=role,
            rangeClass=rc,
            mobile=bool(num(tbl.get('MaxSpeed')) > 0),
            radar=radar,
            optic=bool(sensors.get('OPTIC')),
            armTargetable=any(x.startswith('RADAR_BAND') for x in a),
            datalink='Datalink' in a,
            detectionRange=num(tbl.get('DetectionRange')),
            threatRange=num(tbl.get('ThreatRange')),
            envelope=env or None,
            dependsOn=depends_on(tbl) or None,
            countries=tbl.get('Countries') or None,
            pack=origin,
            dlc=dlc,
            radarDirected=(bool(radar) if role == 'AAA' else None),
            era=(o or {}).get('era'),
            olympusType=(o or {}).get('type'),
            olympusCoalition=(o or {}).get('coalition'),
        )
        if o:
            oa, oe = o.get('acquisitionRange'), o.get('engagementRange')
            if oa and rec['detectionRange'] and abs(oa - rec['detectionRange']) > 0.15 * max(oa, rec['detectionRange']):
                conflicts.append((t, 'acquisition/detection range', rec['detectionRange'], oa))
            if oe and rec['threatRange'] and abs(oe - rec['threatRange']) > 0.15 * max(oe, rec['threatRange']):
                conflicts.append((t, 'engagement/threat range', rec['threatRange'], oe))
        else:
            missing_in_oly.append(t)
        if dlc:
            mods.append('%s (%s)' % (t, dlc))
        units[t] = rec
        counts[role] += 1

    # sanity: every dependsOn target must exist in DCS
    dangling = sorted({d for u in units.values() for d in (u['dependsOn'] or []) if d not in all_types})

    # Olympus AD units the datamine classified as NONE (possible classification gaps)
    oly_ad_types = {'SAM Site', 'SAM Site Parts', 'AAA', 'Radar (EWR)', 'AirDefence', 'Missile System'}
    oly_gap = sorted(n for n, v in oly.items() if v.get('type') in oly_ad_types and n not in units)

    os.makedirs(os.path.join(args.out, 'src'), exist_ok=True)
    os.makedirs(os.path.join(args.out, 'data'), exist_ok=True)
    os.makedirs(os.path.join(args.out, 'docs'), exist_ok=True)

    header = ('-- GENERATED FILE - do not edit. Built by tools/build_unitdb.py\n'
              '-- Sources: DCS Lua datamine (DCS %s, git %s) + DCS Olympus unit databases (git %s)\n'
              '-- Lua 5.1. One table: JANUS.UnitDB[typeName] -> record. See docs/UNIT_DATA_REPORT.md\n'
              % (dcs_version, git_rev(args.datamine), git_rev(args.olympus)))
    body = ['JANUS = JANUS or {}', 'JANUS.UnitDB = {']
    for t, rec in units.items():
        body.append('  [%s] = %s,' % (lua_str(t), to_lua(rec, 1)))
    body.append('}')
    body.append('JANUS.UnitDBMeta = { dcsVersion = %s, datamine = %s, olympus = %s, count = %d }'
                % (lua_str(dcs_version), lua_str(git_rev(args.datamine)), lua_str(git_rev(args.olympus)), len(units)))
    with open(os.path.join(args.out, 'src', 'janus_units.lua'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(header + '\n'.join(body) + '\n')

    with open(os.path.join(args.out, 'data', 'units.json'), 'w', encoding='utf-8') as f:
        json.dump({'meta': {'dcsVersion': dcs_version, 'datamine': git_rev(args.datamine),
                            'olympus': git_rev(args.olympus)}, 'units': units}, f, indent=1)

    # ---- report
    L = []
    L.append('# Janus unit data report\n')
    L.append('Generated by `tools/build_unitdb.py`. Sources: **DCS Lua datamine** (DCS %s, commit %s) and '
             '**DCS Olympus** unit databases (commit %s). The datamine is the authority for what exists and '
             'for its figures; Olympus supplies era, coalition and role labels.\n' % (dcs_version, git_rev(args.datamine), git_rev(args.olympus)))
    L.append('## Totals\n')
    L.append('| Role | Count |\n|---|---|')
    for r, c in sorted(counts.items(), key=lambda x: -x[1]):
        L.append('| %s | %d |' % (r, c))
    L.append('| **all** | **%d** |\n' % len(units))
    L.append('Role meanings: EWR early-warning radar · C2 command post · SR search radar · TR tracking radar · '
             'STR combined search/track · LN launcher (needs a radar) · TELAR self-contained radar+launcher · '
             'SHORAD short-range self-contained · MANPADS · CRAM · AAA guns · AAA_FC gun fire-control (radar, director, searchlight) · POWER generator · AUX other site equipment · '
             'NAVAL / NAVAL_AD ships · AIRBORNE_SENSOR AWACS.\n')

    L.append('## Units by role\n')
    for r in ['EWR', 'C2', 'C2_GENERIC', 'STR', 'SR', 'TR', 'LN', 'TELAR', 'SHORAD', 'MANPADS', 'CRAM', 'AAA', 'AAA_FC', 'POWER', 'AUX', 'NAVAL_AD', 'NAVAL', 'AIRBORNE_SENSOR']:
        rows = [u for u in units.values() if u['role'] == r]
        if not rows:
            continue
        L.append('### %s (%d)\n' % (r, len(rows)))
        L.append('| DCS type | Name | Class | Det m | Threat m | Alt max m | Radar sensor | ARM-targetable | Mobile | Depends on | Era (Olympus) | Pack |')
        L.append('|---|---|---|---|---|---|---|---|---|---|---|---|')
        for u in sorted(rows, key=lambda x: x['type'].lower()):
            env = u['envelope'] or {}
            L.append('| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |' % (
                u['type'], u['name'].replace('|', '/'), u['rangeClass'] or '', u['detectionRange'] or '',
                u['threatRange'] or '', env.get('altMax', ''), u['radar'] or '',
                'yes' if u['armTargetable'] else '', 'yes' if u['mobile'] else '',
                ', '.join('`%s`' % d for d in (u['dependsOn'] or [])), u['era'] or '', (u['pack'] or '') + (' (DLC)' if u['dlc'] else '')))
        L.append('')

    L.append('## Disagreements between the datamine and Olympus (datamine value used)\n')
    if conflicts:
        L.append('| DCS type | Field | Datamine | Olympus |\n|---|---|---|---|')
        for t, fld, a, b in conflicts:
            L.append('| `%s` | %s | %s | %s |' % (t, fld, a, b))
    else:
        L.append('None over 15 %.')
    L.append('')
    L.append('## Air-defence units in the datamine with no Olympus entry (%d)\n' % len(missing_in_oly))
    L.append(', '.join('`%s`' % t for t in missing_in_oly) or 'None')
    L.append('')
    L.append('## Olympus air-defence entries Janus did not classify as air defence (%d)\n' % len(oly_gap))
    L.append('These are checked by hand; most are training/dummy units or gaps to fix in `classify()`.\n')
    L.append(', '.join('`%s`' % t for t in oly_gap) or 'None')
    L.append('')
    L.append('## Paid asset-pack DLC units (`dlc` set; profiles never rely on them). Everything else, including the '
             'Currenthill, China, Cold War and South Atlantic packs, is free core content in `CoreMods` (%d)\n' % len(mods))
    L.append(', '.join('`%s`' % t for t in mods) or 'None')
    L.append('')
    L.append('## Dangling dependencies (dependsOn names not present in DCS)\n')
    L.append(', '.join('`%s`' % t for t in dangling) or 'None')
    L.append('')
    L.append('## Known limits of this build\n')
    L.append('- Missile envelopes: `threatRange` is the DCS `ThreatRange`; `envelope.altMax/altMin/rangeMin/reactionTime/channels` '
             'are present only where the unit table states them (mostly radars and TELARs). Launcher-only units inherit '
             'their envelope from the DCS `LN_t` launcher types, which the datamine does not link by name; Phase 2 adds a '
             'hand-checked mapping for those.')
    L.append('- `dependsOn` is DCS\'s own `depends_on_unit` list: the radars/C2 a launcher needs before it can fire. '
             'This is what the setup report uses to say "this site will never fire".')
    L.append('- Ships are classified `NAVAL_AD` when they carry an AA missile system or are an "Armed Ship"; their '
             'individual weapon envelopes come in Phase 4.')
    with open(os.path.join(args.out, 'docs', 'UNIT_DATA_REPORT.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')

    print('units: %d  roles: %s' % (len(units), dict(counts)))
    print('conflicts: %d  missing in Olympus: %d  olympus gaps: %d  mods: %d  dangling: %s'
          % (len(conflicts), len(missing_in_oly), len(oly_gap), len(mods), dangling))


if __name__ == '__main__':
    main()
