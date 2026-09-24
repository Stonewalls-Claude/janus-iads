#!/usr/bin/env python3
"""Validate src/janus_presets.lua against data/units.json and write docs/BATTERY_PRESETS.md.

Checks: every preset unit `type` exists in DCS (data/units.json), its Janus role matches the
preset's role (or a compatible one), and every `essential` role is present. Exit 1 on any error.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import luatable  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# preset role -> acceptable unit-db roles
COMPAT = {
    'TR': {'TR', 'STR', 'AAA_FC'}, 'SR': {'SR', 'STR', 'EWR', 'C2'}, 'STR': {'STR'}, 'LN': {'LN'},
    'TELAR': {'TELAR'}, 'SHORAD': {'SHORAD', 'TELAR'}, 'C2': {'C2', 'C2_GENERIC', 'EWR'}, 'C2_GENERIC': {'C2_GENERIC', 'C2'},
    'EWR': {'EWR'}, 'CRAM': {'CRAM'}, 'AAA': {'AAA'}, 'AAA_FC': {'AAA_FC'}, 'POWER': {'POWER'},
    'AUX': {'AUX', 'NONE'}, 'NAVAL_AD': {'NAVAL_AD'}, 'MANPADS': {'MANPADS'},
}


def main():
    src = os.path.join(REPO, 'src', 'janus_presets.lua')
    text = open(src, encoding='utf-8').read()
    # the file is `JANUS = JANUS or {}` then `JANUS.Presets = { ... }`
    start = text.index('JANUS.Presets = ') + len('JANUS.Presets = ')
    presets = luatable.parse_literal(text[start:])
    units = json.load(open(os.path.join(REPO, 'data', 'units.json'), encoding='utf-8'))['units']

    errors, warnings = [], []
    for pid, p in presets.items():
        roles_present = set()
        needed = set()
        for u in p.get('units', []) + (p.get('aaa_ring') or []):
            rec = units.get(u.get('type'))
            if rec and rec.get('dlc'):
                needed.add(rec['dlc'])
        declared = set(p.get('requires') or [])
        if needed != declared:
            errors.append('%s: `requires` must be %s (units from: %s), preset says %s'
                          % (pid, sorted(needed) or 'absent', ', '.join(sorted(needed)) or '-', sorted(declared) or 'absent'))
        p['_needed'] = sorted(needed)
        for u in p.get('units', []):
            t, role = u.get('type'), u.get('role')
            roles_present.add(role)
            if t not in units:
                if role == 'AUX':
                    warnings.append('%s: AUX unit `%s` is not in the air-defence unit DB (fine if it exists in DCS)' % (pid, t))
                else:
                    errors.append('%s: unknown DCS type `%s`' % (pid, t))
                continue
            ur = units[t]['role']
            if ur not in COMPAT.get(role, {role}):
                errors.append('%s: `%s` is role %s in the unit DB, preset says %s' % (pid, t, ur, role))
        for r in p.get('essential', []):
            if r not in roles_present:
                errors.append('%s: essential role %s has no unit' % (pid, r))
        for u in p.get('aaa_ring', []) or []:
            if u.get('type') not in units:
                errors.append('%s: aaa_ring type `%s` unknown' % (pid, u.get('type')))
        if not p.get('sources'):
            errors.append('%s: no sources' % pid)

    # ---- doc
    L = ['# Janus battery presets\n',
         'Generated from `src/janus_presets.lua` by `tools/check_presets.py` (%d presets, all DCS type names verified '
         'against `data/units.json`). Real-world compositions are **approximate**: tables of organisation changed by '
         'year, army and export customer; each preset lists its sources.\n\n'
         'Everything in `CoreMods` is free DCS content, including the Currenthill pack (`CHAP_*`: Pantsir-S1, Tor-M2, '
         'IRIS-T SLM, Project 22160). Presets that use paid DLC units say so in a box.\n' % len(presets)]
    for pid in sorted(presets, key=lambda k: (presets[k].get('era', ''), k)):
        p = presets[pid]
        L.append('## `%s` - %s\n' % (pid, p.get('name', '')))
        L.append('Era: %s · Users: %s%s\n' % (p.get('era', ''), ', '.join(p.get('nations', [])),
                                                ' · *approximate*' if p.get('approx') else ''))
        if p.get('_needed'):
            L.append('> **Requires the DCS: %s DLC.** A mission that uses these units only loads for players and '
                     'servers that own it; Janus warns about this in the setup report and `spawnBattery` refuses the '
                     'preset when the DLC is missing.\n' % ' + '.join(p['_needed']))
        L.append('| Role | DCS type | Count | Missiles | Layout | Note |\n|---|---|---|---|---|---|')
        for u in p.get('units', []):
            c = u.get('count')
            c = '%d-%d' % tuple(c) if isinstance(c, list) else str(c)
            lay = []
            if u.get('ring'):
                lay.append('ring %d m' % u['ring'])
            if u.get('spacing'):
                lay.append('spacing %d m' % u['spacing'])
            L.append('| %s | `%s` | %s | %s | %s | %s |' % (u.get('role'), u.get('type'), c, u.get('missiles', ''),
                                                          ', '.join(lay), u.get('note', '')))
        if p.get('aaa_ring'):
            L.append('\nOptional AAA ring: ' + ', '.join('%d× `%s`%s' % (a['count'], a['type'], ' at %d m' % a['ring'] if a.get('ring') else '')
                                                         for a in p['aaa_ring']))
        L.append('\nEssential roles: %s\n' % ', '.join(p.get('essential', [])))
        L.append('Sources:')
        for s in p.get('sources', []):
            L.append('- %s' % s)
        L.append('')
    with open(os.path.join(REPO, 'docs', 'BATTERY_PRESETS.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(L) + '\n')

    for w in warnings:
        print('WARN', w)
    for e in errors:
        print('ERROR', e)
    print('%d presets, %d errors, %d warnings' % (len(presets), len(errors), len(warnings)))
    sys.exit(1 if errors else 0)


if __name__ == '__main__':
    main()
