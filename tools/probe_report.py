#!/usr/bin/env python3
"""Summarise a probe run from dcs.log:  python3 tools/probe_report.py <dcs.log> [> docs/PROBE_RESULTS.md]

Reads the JANUS_PROBE lines and reports, per attacking weapon type, whether any defender hit it
and how long after launch (first HIT-WEAPON minus SHOT time), plus per-defender totals.
"""
import re
import sys
from collections import defaultdict

LINE = re.compile(r'JANUS_PROBE (?P<t>[\d.]+) (?P<kind>[A-Z-]+) (?P<rest>.*)')
KV = re.compile(r'(\w+)=(.*?)(?= \w+=|$)')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    shots = []            # (t, weapon type, shooter type)
    hits_on_weapons = []  # (t, defender type, weapon type)
    per_defender = defaultdict(lambda: defaultdict(int))
    for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
        m = LINE.search(line)
        if not m:
            continue
        t, kind, rest = float(m.group('t')), m.group('kind'), m.group('rest')
        kv = dict(KV.findall(rest))
        if kind == 'SHOT':
            st = re.search(r'\(([^)]*)\)$', kv.get('shooter', ''))
            stype = st.group(1) if st else kv.get('shooter', '?')
            shots.append((t, kv.get('weapon', '?'), stype))
            per_defender[stype]['shots'] += 1
        elif kind == 'HIT-WEAPON':
            wt = re.search(r'a weapon: ([^)]*)\)', rest)
            hits_on_weapons.append((t, kv.get('shooter', '?'), wt.group(1) if wt else '?'))
            per_defender[kv.get('shooter', '?')]['hitsOnWeapons'] += 1
        elif kind == 'HIT':
            per_defender[kv.get('shooter', '?')]['hitsOnUnits'] += 1

    out = ['# Probe results\n',
           'Note: DCS raises S_EVENT_SHOT for missiles, bombs and rockets, not for gun rounds, so gun "shots" are 0 '
           'while their hits are counted.\n', '## Weapons engaged by defenders\n',
           '| Attacking weapon | Launched | Hit by a defender | First hit after launch (s) | Defender |', '|---|---|---|---|---|']
    by_weapon = defaultdict(list)
    for t, w, s in shots:
        by_weapon[w].append(t)
    for w, times in sorted(by_weapon.items()):
        hits = [(ht, d) for ht, d, hw in hits_on_weapons if hw == w]
        first = ''
        if hits:
            launch = max([lt for lt in times if lt <= hits[0][0]] or [times[0]])
            first = '%.1f' % (hits[0][0] - launch)
        out.append('| %s | %d | %d | %s | %s |' % (w, len(times), len(hits), first, ', '.join(sorted({d for _, d in hits}))))
    out += ['', '## Per defender / shooter\n', '| Type | Shots | Hits on weapons | Hits on units |', '|---|---|---|---|']
    for d, s in sorted(per_defender.items()):
        out.append('| %s | %d | %d | %d |' % (d, s['shots'], s['hitsOnWeapons'], s['hitsOnUnits']))
    print('\n'.join(out))


if __name__ == '__main__':
    main()
