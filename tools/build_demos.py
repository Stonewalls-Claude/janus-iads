#!/usr/bin/env python3
"""Build the Janus demo missions (Phase 5) as ordinary Mission Editor missions.

    python3 tools/build_demos.py --log <dcs.log of the JANUS_PROBE_DEMO run> [--template tests/bench/JANUS_BENCH_05C.miz]

The demo-layout probe (tests/probe/janus_probe_demo.lua) let JANUS.spawnBattery place every site on flat ground on
the real Syria terrain and logged each unit (JANUS_DEMO UNIT lines). This tool writes those units into the missions as
Mission Editor groups (so mission makers can open the demo and copy groups), adds command posts, relays, power, AWACS,
player slots and AI waves, and loads janus_settings.lua + janus.lua from a MISSION START trigger.

Output: demo/JANUS_DEMO_RED.miz, JANUS_DEMO_BLUE.miz, JANUS_DEMO_BOTH.miz, JANUS_DEMO_NAVAL.miz
"""
import argparse, math, os, re, zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FT = 0.3048
AGM88C = "{B06DD79A-F21E-4EB9-BD9D-AB3844618C93}"
MK82 = "{BCE4E030-38E9-423E-98ED-24BE3DA87C32}"
KH31P = "{X-31P}"
KH22 = "{12429ECF-03F0-4DF6-BCBD-5D38B6343DE1}"
FAB250 = "{FAB_250_M62}"
SHIP_CAT = 3


# ------------------------------------------------------------------ Lua serializer
def lua(v, ind=1):
    pad = '\t' * ind
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(round(v, 3)) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, list):
        v = {i + 1: x for i, x in enumerate(v)}
    if isinstance(v, dict):
        if not v:
            return '{}'
        parts = []
        for k, x in v.items():
            key = '[%d]' % k if isinstance(k, int) else '["%s"]' % k
            parts.append('%s%s = %s,' % (pad, key, lua(x, ind + 1)))
        return '{\n' + '\n'.join(parts) + '\n' + '\t' * (ind - 1) + '}'
    raise TypeError(type(v))


# ------------------------------------------------------------------ probe log
def read_log(path):
    airbases, groups = {}, {}
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.search(r'JANUS_DEMO AIRBASE (.*)$', line)
        if m:
            name, x, z, y = m.group(1).strip().split('|')
            airbases[name] = (float(x), float(z), float(y))
        m = re.search(r'JANUS_DEMO UNIT (.*)$', line)
        if m:
            side, coa, cat, gname, i, typ, x, z, h = m.group(1).strip().split('|')
            g = groups.setdefault(gname, {'side': side, 'coa': int(coa), 'cat': int(cat), 'units': []})
            g['units'].append((typ, float(x), float(z), float(h)))
    return airbases, groups


class Mission:
    def __init__(self):
        self.gid, self.uid = 1000, 1000
        self.countries = {}   # country id -> {"vehicle": [...], "ship": [...], "plane": [...], "static": [...]}
        self.ids = {}         # group name -> group id

    def _add(self, cid, kind, grp):
        self.countries.setdefault(cid, {}).setdefault(kind, []).append(grp)
        self.ids[grp['name']] = grp['groupId']

    def next_ids(self, n):
        self.gid += 1
        first = self.uid + 1
        self.uid += n
        return self.gid, first

    def ground(self, cid, name, units, skill='Good', ship=False):
        gid, u0 = self.next_ids(len(units))
        x0, z0 = units[0][1], units[0][2]
        us = []
        for i, (typ, x, z, _h) in enumerate(units):
            u = {'skill': skill, 'type': typ, 'unitId': u0 + i, 'x': x, 'y': z, 'name': '%s-%d' % (name, i + 1),
                 'heading': 0, 'playerCanDrive': False}
            if ship:
                u.update({'transportable': {'randomTransportable': False}, 'frequency': 127500000, 'modulation': 0})
            us.append(u)
        grp = {'visible': False, 'tasks': [], 'uncontrollable': False, 'task': 'Ground Nothing', 'taskSelected': True,
               'route': {'spans': [], 'points': [{'alt': 0, 'type': 'Turning Point', 'ETA': 0, 'alt_type': 'BARO',
                                                  'formation_template': '', 'x': x0, 'y': z0, 'ETA_locked': True,
                                                  'speed': 0, 'action': 'Turning Point' if ship else 'Off Road',
                                                  'task': {'id': 'ComboTask', 'params': {'tasks': []}},
                                                  'speed_locked': True}]},
               'groupId': gid, 'hidden': False, 'units': us, 'x': x0, 'y': z0, 'name': name, 'start_time': 0}
        self._add(cid, 'ship' if ship else 'vehicle', grp)

    def static(self, cid, name, typ, shape, x, z):
        gid, uid = self.next_ids(1)
        grp = {'heading': 0, 'route': {'points': [{'alt': 0, 'type': '', 'name': '', 'x': x, 'y': z, 'speed': 0,
                                                   'formation_template': '', 'action': ''}]},
               'groupId': gid, 'hidden': False, 'dead': False, 'x': x, 'y': z, 'name': name,
               'units': [{'category': 'Fortifications', 'shape_name': shape, 'type': typ, 'unitId': uid, 'rate': 100,
                          'x': x, 'y': z, 'name': name, 'heading': 0}]}
        self._add(cid, 'static', grp)

    def plane(self, cid, name, typ, n, route, alt, task, tasks=None, skill='Excellent', pylons=None, fuel=5000,
              start=0, blue=True, speed=220):
        gid, u0 = self.next_ids(n)
        (x0, z0), (x1, z1) = route[0], route[1]
        h = math.atan2(z1 - z0, x1 - x0)
        us = []
        for i in range(n):
            cs = {1: 1, 2: 1, 3: i + 1, 'name': 'Enfield1%d' % (i + 1)} if blue else 100 + gid % 100 * 10 + i
            us.append({'alt': alt, 'alt_type': 'BARO', 'skill': skill, 'speed': speed, 'type': typ, 'unitId': u0 + i,
                       'psi': 0, 'x': x0 - i * 1000 * math.cos(h), 'y': z0 - i * 1000 * math.sin(h) + i * 600,
                       'name': '%s-%d' % (name, i + 1), 'heading': h, 'callsign': cs, 'onboard_num': '%03d' % (u0 % 1000 + i),
                       'payload': {'pylons': pylons or {}, 'fuel': fuel, 'flare': 60, 'chaff': 60, 'gun': 100}})
        pts = []
        for j, (x, z) in enumerate(route):
            pts.append({'alt': alt, 'action': 'Turning Point', 'alt_type': 'BARO', 'speed': speed,
                        'task': {'id': 'ComboTask', 'params': {'tasks': (tasks or []) if j == 0 else []}},
                        'type': 'Turning Point', 'ETA': 0, 'ETA_locked': j == 0, 'x': x, 'y': z,
                        'formation_template': '', 'speed_locked': True})
        grp = {'modulation': 0, 'tasks': [], 'radioSet': False, 'task': task, 'uncontrolled': False, 'taskSelected': True,
               'route': {'points': pts}, 'groupId': gid, 'hidden': False, 'units': us, 'x': x0, 'y': z0, 'name': name,
               'communication': True, 'start_time': start, 'frequency': 251 if blue else 124}
        self._add(cid, 'plane', grp)

    def inject(self, mission_text):
        for cid, kinds in self.countries.items():
            body = ''.join('\t\t\t\t\t["%s"] = %s,\n' % (k, lua({'group': v}, 7)) for k, v in kinds.items())
            pat = re.compile(r'(\[\d+\] =\s*\{\s*\n)(\s*\["id"\] = %d,\s*\n\s*\["name"\] = "[^"]*",)' % cid)
            m_text, n = pat.subn(lambda m: m.group(1) + body + m.group(2), mission_text, count=1)
            assert n == 1, 'country %d not in the template' % cid
            mission_text = m_text
        return mission_text


def task(id_, params, n=1, enabled=True):
    return {'number': n, 'auto': False, 'id': id_, 'enabled': enabled, 'params': params}


def option(n, name, value):
    return task('WrappedAction', {'action': {'id': 'Option', 'params': {'value': value, 'name': name}}}, n)


ROE_FREE, ROE_HOLD = 0, 4   # AI.Option.Air.val.ROE (weapon free / hold); option id 0 = ROE


def sead_tasks():
    return [task('EngageTargets', {'targetTypes': ['Air Defence'], 'priority': 0}, 1), option(2, 0, ROE_FREE)]


def hold_tasks():
    return [option(1, 0, ROE_HOLD)]


def awacs_tasks(alt):
    return [task('AWACS', {}, 1), task('Orbit', {'pattern': 'Race-Track', 'altitude': alt, 'speed': 200}, 2)]


def attack_group(gid):
    return [task('AttackGroup', {'groupId': gid, 'expend': 'All', 'attackQtyLimit': False, 'weaponType': 1073741822}, 1),
            option(2, 0, ROE_FREE)]


def bomb_point(x, z):
    return [task('Bombing', {'x': x, 'y': z, 'expend': 'All', 'attackQtyLimit': False, 'groupAttack': True,
                             'weaponType': 1073741822, 'altitudeEnabled': False, 'direction': 0}, 1), option(2, 0, ROE_FREE)]


# ------------------------------------------------------------------ demo content
RUSSIA, USA = 0, 2


def rename(groups, old, new):
    groups[new] = groups.pop(old)


def red_side(m, ab, groups, clients):
    hx, hz, _ = ab['Hama']
    m.static(RUSSIA, 'CMD Hama', '.Command Center', 'ComCenter', hx + 2500, hz + 2500)
    m.static(RUSSIA, 'COMMS Homs Relay', 'Comms tower M', 'tele_bash_m', hx - 20000, hz + 6000)
    sa10 = groups['SAM SA-10 Hama VET']['units'][0]
    m.static(RUSSIA, 'POWER Hama', 'GeneratorF', 'GeneratorF', sa10[1] - 1500, sa10[2] + 1500)
    for name, g in groups.items():
        if g['side'] == 'RED':
            ME = name + (' [relay:Homs Relay]' if name == 'SAM SA-6 Homs REG' else '')
            m.ground(RUSSIA, ME, g['units'], skill='High' if 'VET' in name else 'Good')
    m.plane(RUSSIA, 'Mainstay AEW', 'A-50', 1, [(hx + 90000, hz - 30000), (hx + 90000, hz + 50000)], 9000, 'AWACS',
            awacs_tasks(9000), fuel=70000, blue=False, speed=200)
    if clients:
        red_client(m, ab)


def red_client(m, ab):
    ix, iz, _ = ab['Incirlik']
    m.plane(RUSSIA, 'Red Client Frogfoot', 'Su-25T', 2, [(ix - 40000, iz + 150000), (ix - 20000, iz + 40000)], 3000,
            'Ground Attack', skill='Client', pylons={2: {'CLSID': FAB250}, 9: {'CLSID': FAB250}}, fuel=3790, blue=False,
            speed=200)


def blue_waves_at_red(m, ab):
    hx, hz, _ = ab['Hama']
    south = lambda dx, dz: (hx - 170000 + dx, hz + dz)
    m.plane(USA, 'Blue Client Viper', 'F-16C_50', 2, [south(0, -10000), (hx - 40000, hz - 10000)], 18000 * FT, 'SEAD',
            skill='Client', pylons={3: {'CLSID': AGM88C}, 7: {'CLSID': AGM88C}}, fuel=3249)
    m.plane(USA, 'Blue Bait', 'F-16C_50', 2, [south(0, 0), (hx + 20000, hz + 5000), (hx + 80000, hz + 40000)], 18000 * FT,
            'CAP', hold_tasks(), fuel=3249, start=120)
    m.plane(USA, 'Blue SEAD', 'F-16C_50', 2, [south(-10000, -20000), (hx - 50000, hz - 5000), south(-10000, -20000)],
            22000 * FT, 'SEAD', sead_tasks(), pylons={3: {'CLSID': AGM88C}, 4: {'CLSID': AGM88C}, 6: {'CLSID': AGM88C},
                                                      7: {'CLSID': AGM88C}}, fuel=3249, start=240)
    homs = m.ids.get('SAM SA-6 Homs REG [relay:Homs Relay]')
    m.plane(USA, 'Blue Strike', 'F-16C_50', 4, [south(10000, 20000), (hx - 45000, hz + 8000), south(10000, 20000)],
            20000 * FT, 'Ground Attack', attack_group(homs) if homs else [],
            pylons={3: {'CLSID': MK82}, 4: {'CLSID': MK82}, 6: {'CLSID': MK82}, 7: {'CLSID': MK82}}, fuel=3249, start=480)


def blue_side(m, ab, groups, clients):
    ix, iz, _ = ab['Incirlik']
    m.static(USA, 'CMD Incirlik', '.Command Center', 'ComCenter', ix + 2000, iz - 2500)
    for name, g in groups.items():
        if g['side'] == 'BLUE':
            m.ground(USA, name, g['units'], skill='High' if 'VET' in name else 'Good')
    m.plane(USA, 'Magic AEW', 'E-3A', 1, [(ix - 40000, iz - 60000), (ix - 40000, iz + 20000)], 9000, 'AWACS',
            awacs_tasks(9000), fuel=60000, speed=200)
    if clients:
        m.plane(USA, 'Blue Client Hornet', 'FA-18C_hornet', 2, [(ix - 20000, iz + 10000), (ix - 120000, iz + 60000)],
                20000 * FT, 'CAP', skill='Client', fuel=4900)


def red_waves_at_blue(m, ab):
    ix, iz, _ = ab['Incirlik']
    east = lambda dx, dz: (ix - 60000 + dx, iz + 200000 + dz)
    m.plane(RUSSIA, 'Red Bait', 'Su-24M', 2, [east(0, 0), (ix + 5000, iz + 10000), (ix + 60000, iz - 120000)],
            15000 * FT, 'CAP', hold_tasks(), fuel=9000, start=120, blue=False)
    m.plane(RUSSIA, 'Red SEAD', 'Su-34', 1, [east(-10000, -10000), (ix - 20000, iz + 90000), east(-10000, -10000)],
            23000 * FT, 'SEAD', sead_tasks(), pylons={3: {'CLSID': KH31P}, 4: {'CLSID': KH31P}, 8: {'CLSID': KH31P},
                                                      9: {'CLSID': KH31P}}, fuel=9800, start=240, blue=False)
    m.plane(RUSSIA, 'Red Strike Incirlik', 'Su-24M', 2, [east(10000, 0), (ix, iz), east(10000, 0)], 6000 * FT,
            'Ground Attack', bomb_point(ix, iz), pylons={2: {'CLSID': FAB250}, 3: {'CLSID': FAB250}, 6: {'CLSID': FAB250},
                                                         7: {'CLSID': FAB250}}, fuel=9000, start=420, blue=False)


def naval(m, ab, groups):
    bx, bz, _ = ab['Bassel Al-Assad']
    m.static(RUSSIA, 'CMD Latakia', '.Command Center', 'ComCenter', bx + 3000, bz + 3000)
    for name, g in groups.items():
        if g['side'] == 'NAVAL':
            units = g['units']
            # the public demo uses the free CVN-74 Stennis, not a Supercarrier hull (owner, 2026-10-01: players
            # without the module must be able to fly it); the carrier is its own SHIP group in the escort's [net:CSG]
            # network (it carries Sea Sparrow, RAM and CIWS, so without a role word the setup report flags it)
            carrier = [u for u in units if u[0].startswith('CVN_')]
            if carrier:
                units = [u for u in units if not u[0].startswith('CVN_')]
                c = carrier[0]
                m.ground(USA, 'SHIP Stennis REG [net:CSG]', [('Stennis', c[1], c[2], c[3])], skill='Excellent', ship=True)
            m.ground(USA if g['coa'] == 2 else RUSSIA, name, units, ship=True)
    ike = groups['SHIP Ike REG [net:CSG]']['units'][0]
    m.plane(USA, 'Magic AEW', 'E-3A', 1, [(ike[1] - 60000, ike[2] - 40000), (ike[1] + 20000, ike[2] - 40000)], 9000,
            'AWACS', awacs_tasks(9000), fuel=60000, speed=200)
    m.plane(USA, 'Blue Client Hornet', 'FA-18C_hornet', 2, [(ike[1] - 10000, ike[2] - 10000), (ike[1] + 80000, ike[2] + 60000)],
            20000 * FT, 'CAP', skill='Client', fuel=4900)
    m.plane(RUSSIA, 'Red Bait Fleet', 'Su-24M', 2, [(bx + 30000, bz + 60000), (ike[1], ike[2] + 3000), (ike[1] - 60000, ike[2] - 80000)],
            3000, 'CAP', hold_tasks(), fuel=9000, start=120, blue=False)
    m.plane(RUSSIA, 'Red Backfire', 'Tu-22M3', 2, [(bx + 120000, bz + 150000), (ike[1] + 60000, ike[2] + 60000),
                                                   (bx + 120000, bz + 150000)],
            30000 * FT, 'Antiship Strike', attack_group(m.ids['SHIP Ike REG [net:CSG]']),
            pylons={1: {'CLSID': KH22}, 3: {'CLSID': KH22}}, fuel=50000, start=300, blue=False, speed=250)


SETTINGS = '''-- Janus IADS settings for this demo. Change a value and save; see docs/QUICKSTART.md.
JANUS_SETTINGS = {
  CHECK_MODE = %s,          -- true: setup report on screen and the network on the F10 map
  RED_DOCTRINE = "%s",
  BLUE_DOCTRINE = "%s",
  STATS = true,               -- radar time, shots, kills and losses per site in dcs.log
  STATS_EVERY = 600,
  BASE_WARNING = %s,
}
'''

DEMOS = {
    'RED': ('Janus IADS demo - RED network. A Soviet-style air defence around Hama: command post, two EW radars, SA-10 '
            'with a Tor beside it, SA-6 behind a radio relay, SA-11, SA-2 with a gun ring, SA-3, an A-50, and a power '
            'plant. Blue AI sends bait, HARM shooters and a Mk-82 strike; two blue F-16C player slots carry HARMs. '
            'Open the F10 map to watch the SAM radars come up only when the network cues them. Copy any group into your '
            'own mission: the names are all Janus needs.', 'SOVIET_PVO_1985', 'US_MODERN', 'false'),
    'BLUE': ('Janus IADS demo - BLUE network. A US air defence at Incirlik: command post, FPS-117, Patriot, Hawk, NASAMS, '
             'C-RAM and Avengers on the base, an E-3. Weapons tight: blue SAMs fire only at identified aircraft. Red AI '
             'sends Su-24 bait, a Su-34 with Kh-31P and a Su-24 bomb run on the base (watch for the INCOMING warning); '
             'two red Su-25T player slots.', 'SOVIET_PVO_1985', 'US_MODERN', 'true'),
    'BOTH': ('Janus IADS demo - BOTH sides at once: the red Hama network and the blue Incirlik network, each with its '
             'own doctrine, AWACS and player slots, and AI waves both ways.', 'SOVIET_PVO_1985', 'US_MODERN', 'true'),
    'NAVAL': ('Janus IADS demo - NAVAL. A US carrier group (CVN-74 Stennis; escort Ticonderoga, two Arleigh Burkes, Perry) off Latakia, the escort as its '
              'own network ([net:CSG]) under an E-3, against Su-24 bait and Tu-22M3s with Kh-22; a Russian surface group '
              'to the north. Two F/A-18C player slots.', 'SOVIET_PVO_1985', 'US_MODERN', 'false'),
}


def build(template, out, desc, settings, janus, populate):
    zi = zipfile.ZipFile(template)
    mtext = zi.read('mission').decode('utf-8')
    m = Mission()
    populate(m)
    mtext = m.inject(mtext)
    acts = 'a_do_script_file(getValueResourceByKey(\\"ResKey_100\\"));a_do_script_file(getValueResourceByKey(\\"ResKey_101\\"));'
    mtext = re.sub(r'(\["trig"\] =\s*\{\s*\["actions"\] =\s*\{\s*\[1\] = ")[^\n]*(",)', lambda x: x.group(1) + acts + x.group(2), mtext, count=1)
    mtext = re.sub(r'\["comment"\] = "[^"]*"', '["comment"] = "Janus IADS: DO SCRIPT FILE janus_settings.lua > janus.lua"', mtext, count=1)
    res = 'mapResource = \n{\n\t["ResKey_100"] = "janus_settings.lua",\n\t["ResKey_101"] = "janus.lua",\n}\n'
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zi.namelist():
            if n.startswith('l10n/DEFAULT/') and n.endswith('.lua'):
                continue
            d = zi.read(n)
            if n == 'mission':
                d = mtext.encode('utf-8')
            elif n == 'l10n/DEFAULT/mapResource':
                d = res.encode('utf-8')
            elif n == 'l10n/DEFAULT/dictionary':
                t = d.decode('utf-8')
                t = re.sub(r'("DictKey_Translation_[12]"\] = )"[^"]*"', lambda x: x.group(1) + '"' + desc + '"', t)
                d = t.encode('utf-8')
            zo.writestr(n, d)
        zo.writestr('l10n/DEFAULT/janus_settings.lua', settings.encode('utf-8'))
        zo.writestr('l10n/DEFAULT/janus.lua', janus)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--log', required=True)
    ap.add_argument('--template', default=os.path.join(REPO, 'tests/bench/JANUS_BENCH_05C.miz'))
    ap.add_argument('--out', default=os.path.join(REPO, 'demo'))
    a = ap.parse_args()
    ab, groups = read_log(a.log)
    for need in ('Hama', 'Incirlik', 'Bassel Al-Assad'):
        assert need in ab, 'airbase %s not in the log' % need
    janus = open(os.path.join(REPO, 'dist/janus.lua'), 'rb').read()
    os.makedirs(a.out, exist_ok=True)
    plans = {
        'RED': lambda m: (red_side(m, ab, groups, False), blue_waves_at_red(m, ab)),
        'BLUE': lambda m: (blue_side(m, ab, groups, False), red_waves_at_blue(m, ab), red_client(m, ab)),
        'BOTH': lambda m: (red_side(m, ab, groups, True), blue_side(m, ab, groups, True), blue_waves_at_red(m, ab),
                           red_waves_at_blue(m, ab)),
        'NAVAL': lambda m: naval(m, ab, groups),
    }
    for key, (desc, red, blue, warn) in DEMOS.items():
        out = os.path.join(a.out, 'JANUS_DEMO_%s.miz' % key)
        m = build(a.template, out, desc, SETTINGS % ('false', red, blue, warn), janus, plans[key])
        n = sum(len(v) for k in m.countries.values() for v in k.values())
        print('wrote %s (%d groups)' % (out, n))


if __name__ == '__main__':
    main()
