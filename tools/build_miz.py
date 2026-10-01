#!/usr/bin/env python3
"""Build a script-only test mission: a template .miz with its MISSION START trigger replaced by DO SCRIPT FILEs.

    python3 tools/build_miz.py --template tests/bench/JANUS_BENCH_05C.miz --out tests/probe/JANUS_PROBE_DEMO.miz \
        --desc "..." dist/janus.lua tests/probe/janus_probe_demo.lua

The scripts load in the order given. Every other embedded .lua in the template is dropped; theatre, date, weather,
options and the units already in the template are kept.
"""
import argparse, os, re, zipfile


def build(template, out, scripts, desc=None):
    zi = zipfile.ZipFile(template)
    m = zi.read('mission').decode('utf-8')
    acts = ''.join('a_do_script_file(getValueResourceByKey(\\"ResKey_%d\\"));' % (100 + i) for i in range(len(scripts)))
    rules = ''.join('\t\t\t\t[%d] = \n\t\t\t\t{\n\t\t\t\t\t["file"] = "ResKey_%d",\n\t\t\t\t\t["predicate"] = "a_do_script_file",\n\t\t\t\t},\n'
                    % (i + 1, 100 + i) for i in range(len(scripts)))
    m, n1 = re.subn(r'(\["trig"\] =\s*\{\s*\["actions"\] =\s*\{\s*\[1\] = ")[^\n]*(",)', lambda x: x.group(1) + acts + x.group(2), m, count=1)
    m, n2 = re.subn(r'(\["trigrules"\] =\s*\{\s*\[1\] =\s*\{\s*\["actions"\] =\s*\{\n).*?(\t\t\t\},\n\t\t\t\["colorItem"\])',
                    lambda x: x.group(1) + rules + x.group(2), m, count=1, flags=re.S)
    assert n1 == 1 and n2 == 1, 'template has no single MISSION START trigger to replace'
    names = [os.path.basename(s[0]) for s in scripts]
    m = re.sub(r'\["comment"\] = "[^"]*"', lambda x: '["comment"] = "DO SCRIPT FILE %s"' % ' > '.join(names), m, count=1)
    res = 'mapResource = \n{\n' + ''.join('\t["ResKey_%d"] = "%s",\n' % (100 + i, n) for i, n in enumerate(names)) + '}\n'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zi.namelist():
            if n.startswith('l10n/DEFAULT/') and n.endswith('.lua'):
                continue
            d = zi.read(n)
            if n == 'mission':
                d = m.encode('utf-8')
            elif n == 'l10n/DEFAULT/mapResource':
                d = res.encode('utf-8')
            elif n == 'l10n/DEFAULT/dictionary' and desc:
                t = d.decode('utf-8')
                t = re.sub(r'("DictKey_Translation_[12]"\] = )"[^"]*"', lambda x: x.group(1) + '"' + desc.replace('"', "'") + '"', t)
                d = t.encode('utf-8')
            zo.writestr(n, d)
        for (path, data), name in zip(scripts, names):
            zo.writestr('l10n/DEFAULT/' + name, data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--template', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--desc')
    ap.add_argument('scripts', nargs='+')
    a = ap.parse_args()
    build(a.template, a.out, [(p, open(p, 'rb').read()) for p in a.scripts], a.desc)
    print('wrote', a.out)


if __name__ == '__main__':
    main()
