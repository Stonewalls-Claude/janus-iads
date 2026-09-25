#!/usr/bin/env python3
"""Build tests/probe/janus_probe.miz from an empty template mission + tests/probe/janus_probe.lua.

    python3 tools/build_probe_miz.py --template <empty Syria .miz> [--out tests/probe/janus_probe.miz]

The template only supplies theatre, date, weather and options. Its trigger block is replaced by one
MISSION START -> DO SCRIPT FILE -> janus_probe.lua; every other embedded script is dropped.
"""
import argparse
import os
import re
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESC = ('JANUS IADS PHASE 0 PROBE. AI-only. Spawns blue C-RAM/Avenger/Patriot and red Tor/Pantsir sites on Syria and '
        'sends six attacker waves (ARM, Kh-31P/Kh-22, KAB-500, S-8 rockets, Grad, FAB-250) 4 min apart. '
        'Records SHOT/HIT/DEAD to dcs.log as JANUS_PROBE lines. Run 30 minutes.')

TRIG = '''	["trig"] =
	{
		["actions"] =
		{
			[1] = "a_do_script_file(getValueResourceByKey(\\"ResKey_100\\"));",
		},
		["conditions"] =
		{
			[1] = "return(true)",
		},
		["customStartup"] =
		{
		},
		["events"] =
		{
		},
		["flag"] =
		{
			[1] = true,
		},
		["func"] =
		{
		},
		["funcStartup"] =
		{
			[1] = "if mission.trig.conditions[1]() then mission.trig.actions[1]() end",
		},
	},
'''
TRIGRULES = '''	["trigrules"] =
	{
		[1] =
		{
			["actions"] =
			{
				[1] =
				{
					["file"] = "ResKey_100",
					["predicate"] = "a_do_script_file",
				},
			},
			["colorItem"] = "0xffffffff",
			["comment"] = "Janus probe: DO SCRIPT FILE janus_probe.lua",
			["eventlist"] = "",
			["predicate"] = "triggerStart",
			["rules"] =
			{
			},
		},
	},
'''


def replace_block(src, key, new):
    m = re.search(r'^\t\["%s"\] = \n\t\{\n' % key, src, re.M)
    if not m:
        raise SystemExit('no [%s] block in template mission' % key)
    depth, i = 0, m.end() - 2
    while i < len(src):
        c = src[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                end = src.index('\n', i) + 1
                return src[:m.start()] + new + src[end:]
        i += 1
    raise SystemExit('unbalanced [%s] block' % key)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--template', required=True)
    ap.add_argument('--out', default=os.path.join(REPO, 'tests', 'probe', 'janus_probe.miz'))
    ap.add_argument('--scripts', nargs='+', default=[os.path.join(REPO, 'tests', 'probe', 'janus_probe.lua')],
                    help='Lua files, loaded in this order by one MISSION START trigger')
    ap.add_argument('--title', default='JANUS PROBE')
    ap.add_argument('--desc', default=DESC, help='briefing text')
    a = ap.parse_args()
    zin = zipfile.ZipFile(a.template)
    mission = zin.read('mission').decode('utf-8')
    keys = ['ResKey_%d' % (100 + i) for i in range(len(a.scripts))]
    names = [os.path.basename(p) for p in a.scripts]
    trig = TRIG.replace('a_do_script_file(getValueResourceByKey(\\"ResKey_100\\"));',
                        ''.join('a_do_script_file(getValueResourceByKey(\\"%s\\"));' % k for k in keys))
    acts = ''.join('''				[%d] = 
				{
					["file"] = "%s",
					["predicate"] = "a_do_script_file",
				},
''' % (i + 1, k) for i, k in enumerate(keys))
    head, tail = TRIGRULES.split('\t\t\t["actions"] =\n', 1)
    tail = tail[tail.index('\t\t\t["colorItem"]'):]
    rules = head + '\t\t\t["actions"] =\n\t\t\t{\n' + acts + '\t\t\t},\n' + tail
    rules = rules.replace('Janus probe: DO SCRIPT FILE janus_probe.lua', 'Janus probe: DO SCRIPT FILE ' + ' > '.join(names))
    mission = replace_block(mission, 'trig', trig)
    mission = replace_block(mission, 'trigrules', rules)
    dictionary = ('dictionary = \n{\n' + ''.join('\t["DictKey_Translation_%d"] = "%s",\n' % (i, a.desc.replace('"', "'")) for i in (1, 2, 3))
                  + '\t["DictKey_Translation_4"] = "%s",\n}\n' % a.title)
    map_resource = 'mapResource = \n{\n' + ''.join('\t["%s"] = "%s",\n' % (k, n) for k, n in zip(keys, names)) + '}\n'
    with zipfile.ZipFile(a.out, 'w', zipfile.ZIP_DEFLATED) as zout:
        zout.writestr('mission', mission)
        for name in ('options', 'warehouses'):
            if name in zin.namelist():
                zout.writestr(name, zin.read(name))
        zout.writestr('l10n/DEFAULT/dictionary', dictionary)
        zout.writestr('l10n/DEFAULT/mapResource', map_resource)
        for p, n in zip(a.scripts, names):
            zout.writestr('l10n/DEFAULT/' + n, open(p, 'rb').read())
    print('wrote', a.out, os.path.getsize(a.out), 'bytes; theatre',
          re.search(r'\["theatre"\] = "([^"]+)"', mission).group(1))


if __name__ == '__main__':
    main()
