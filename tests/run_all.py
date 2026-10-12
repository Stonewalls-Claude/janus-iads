#!/usr/bin/env python3
"""Build dist/janus.lua, then run every tests/test_*.lua under a Lua 5.1 interpreter.

    python3 tests/run_all.py                 (also what `dcs-check --tests tests` and `testq mutate --suite` call)
    python3 tests/run_all.py arm phase5      only harnesses whose name contains one of these
    python3 tests/run_all.py -v              also print every harness's own output
    python3 tests/run_all.py --lua <lua51>   the interpreter (else LUA51, PATH, the dcs-check kit's)

One row per harness ("  PASS  test_arm.lua  3.1s  test_arm: 262 passed, 0 failed") and a last line
"SUITE PASS: ..." or "SUITE FAIL: ...", the contract dcs-check and the PC's test queue read. Exit 1 if the build or
any harness fails.
"""
import argparse
import glob
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'tools'))
from build import find_lua51  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('filter', nargs='*', help='only harnesses whose name contains one of these')
    ap.add_argument('--lua', help='Lua 5.1 interpreter')
    ap.add_argument('-v', '--verbose', action='store_true', help="print each harness's own output")
    a = ap.parse_args(argv)
    if a.lua:
        os.environ['LUA51'] = a.lua
    r = subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'build.py')], cwd=REPO)
    if r.returncode != 0:
        print('SUITE FAIL: the build failed')
        return 1
    lua = find_lua51()
    if not lua:
        print('SUITE FAIL: no Lua 5.1 interpreter found (pass --lua or set LUA51)')
        return 1
    files = sorted(glob.glob(os.path.join(REPO, 'tests', 'test_*.lua')))
    if a.filter:
        files = [f for f in files if any(x in os.path.basename(f) for x in a.filter)]
    passed = failed = 0
    for f in files:
        name = os.path.basename(f)
        t0 = time.time()
        p = subprocess.run([lua, os.path.relpath(f, REPO), 'dist/janus.lua'], cwd=REPO, capture_output=True, text=True)
        out = p.stdout + p.stderr
        lines = [l for l in out.splitlines() if l.strip()]
        summary = lines[-1].strip() if lines else 'no output'
        ok = p.returncode == 0
        passed, failed = passed + ok, failed + (not ok)
        print('  %-5s %s  %.1fs  %s' % ('PASS' if ok else 'FAIL', name, time.time() - t0, summary))
        if a.verbose or not ok:
            shown = out if a.verbose else '\n'.join(l for l in out.splitlines() if 'FAIL' in l or 'rror' in l)
            if shown.strip():
                print('    ' + shown.strip().replace('\n', '\n    '))
    print('SUITE %s: %d passed, %d failed' % ('PASS' if failed == 0 and files else 'FAIL', passed, failed))
    return 0 if failed == 0 and files else 1


if __name__ == '__main__':
    sys.exit(main())
