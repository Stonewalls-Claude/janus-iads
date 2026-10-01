#!/usr/bin/env python3
"""Build the bench 07 missions (Janus vs Skynet 3.5.0, Phase 5 release gate) from JANUS_BENCH_05C.miz.

    python3 tools/build_bench07.py --skynet <skynet-iads-compiled.lua> --mist <mist_4_5_126.lua> [--runs 3]

Writes tests/bench/JANUS_BENCH_07_J<n>.miz (bench 07 -> janus.lua) and JANUS_BENCH_07_S<n>.miz
(MIST -> Skynet -> bench 07), one numbered file per run. The bench file gets its VARIANT line set per mission.
"""
import argparse, os, re, zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESC = {
    'JANUS': 'JANUS IADS BENCH 07 (Phase 5 release gate), JANUS variant. Red SOVIET_PVO_1985 network vs blue bait, SEAD '
             'and Mk-82 strikes. Ends with a SCORE line and BENCH 07 COMPLETE at 25 min.',
    'SKYNET': 'JANUS IADS BENCH 07 (Phase 5 release gate), SKYNET 3.5.0 variant (stock). Same red network and blue waves '
              'as the Janus variant. Ends with a SCORE line and BENCH 07 COMPLETE at 25 min.',
}


def actions_lua(n):
    acts = ''.join('a_do_script_file(getValueResourceByKey(\\"ResKey_%d\\"));' % (100 + i) for i in range(n))
    rules = ''.join('\t\t\t\t[%d] = \n\t\t\t\t{\n\t\t\t\t\t["file"] = "ResKey_%d",\n\t\t\t\t\t["predicate"] = "a_do_script_file",\n\t\t\t\t},\n'
                    % (i + 1, 100 + i) for i in range(n))
    return acts, rules


def build(template, out, variant, scripts):
    zi = zipfile.ZipFile(template)
    m = zi.read('mission').decode('utf-8')
    acts, rules = actions_lua(len(scripts))
    m = re.sub(r'(\["trig"\] =\s*\{\s*\["actions"\] =\s*\{\s*\[1\] = ")[^\n]*(",)', lambda x: x.group(1) + acts + x.group(2), m, count=1)
    m = re.sub(r'(\["trigrules"\] =\s*\{\s*\[1\] =\s*\{\s*\["actions"\] =\s*\{\n).*?(\t\t\t\},\n\t\t\t\["colorItem"\])',
               lambda x: x.group(1) + rules + x.group(2), m, count=1, flags=re.S)
    m = re.sub(r'\["comment"\] = "[^"]*"', '["comment"] = "Janus bench 07 (%s): DO SCRIPT FILE %s"' % (variant, ' > '.join(s[0] for s in scripts)), m, count=1)
    res = 'mapResource = \n{\n' + ''.join('\t["ResKey_%d"] = "%s",\n' % (100 + i, s[0]) for i, s in enumerate(scripts)) + '}\n'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zi.namelist():
            if n.startswith('l10n/DEFAULT/') and n.endswith('.lua'):
                continue
            d = zi.read(n)
            if n == 'mission':
                d = m.encode('utf-8')
            elif n == 'l10n/DEFAULT/mapResource':
                d = res.encode('utf-8')
            elif n == 'l10n/DEFAULT/dictionary':
                t = d.decode('utf-8')
                t = re.sub(r'("DictKey_Translation_[12]"\] = )"[^"]*"', lambda x: x.group(1) + '"' + DESC[variant] + '"', t)
                d = t.encode('utf-8')
            zo.writestr(n, d)
        for name, data in scripts:
            zo.writestr('l10n/DEFAULT/' + name, data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--skynet', required=True)
    ap.add_argument('--mist', required=True)
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--first', type=int, default=1, help='number of the first run (never overwrite an earlier run)')
    ap.add_argument('--janus-only', action='store_true', help='only the Janus variant (Skynet runs already done)')
    a = ap.parse_args()
    bench = open(os.path.join(REPO, 'tests/bench/janus_bench_07.lua'), encoding='utf-8').read()
    assert 'local VARIANT = "JANUS"' in bench
    janus = open(os.path.join(REPO, 'dist/janus.lua'), 'rb').read()
    sky, mist = open(a.skynet, 'rb').read(), open(a.mist, 'rb').read()
    template = os.path.join(REPO, 'tests/bench/JANUS_BENCH_05C.miz')
    for r in range(a.first, a.first + a.runs):
        for v in ('J',) + (() if a.janus_only else ('S',)):
            out = os.path.join(REPO, 'tests/bench/JANUS_BENCH_07_%s%d.miz' % (v, r))
            assert not os.path.exists(out), out + ' exists: every run gets its own mission file'
        bj = bench.encode('utf-8')
        bs = bench.replace('local VARIANT = "JANUS"', 'local VARIANT = "SKYNET"', 1).encode('utf-8')
        build(template, os.path.join(REPO, 'tests/bench/JANUS_BENCH_07_J%d.miz' % r), 'JANUS',
              [('janus_bench_07.lua', bj), ('janus.lua', janus)])
        if not a.janus_only:
            build(template, os.path.join(REPO, 'tests/bench/JANUS_BENCH_07_S%d.miz' % r), 'SKYNET',
                  [('mist_4_5_126.lua', mist), ('skynet-iads-compiled.lua', sky), ('janus_bench_07.lua', bs)])
        print('built run', r)


if __name__ == '__main__':
    main()
