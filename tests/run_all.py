#!/usr/bin/env python3
"""Build dist/janus.lua, then run every tests/test_*.lua under a Lua 5.1 interpreter.

    python3 tests/run_all.py            (also what `dcs-check --tests tests` calls)
Exit 1 if the build or any test fails. Set LUA51=/path/to/lua5.1 if it is not on PATH.
"""
import glob
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'tools'))
from build import find_lua51  # noqa: E402


def main():
    # dcs-check passes --lua <its Lua 5.1>; honour it
    if '--lua' in sys.argv:
        os.environ['LUA51'] = sys.argv[sys.argv.index('--lua') + 1]
    r = subprocess.run([sys.executable, os.path.join(REPO, 'tools', 'build.py')], cwd=REPO)
    if r.returncode != 0:
        print('build failed')
        sys.exit(1)
    lua = find_lua51()
    if not lua:
        print('no Lua 5.1 interpreter found (set LUA51); tests not run')
        sys.exit(1)
    failed = 0
    for t in sorted(glob.glob(os.path.join(REPO, 'tests', 'test_*.lua'))):
        rel = os.path.relpath(t, REPO)
        print('==', rel)
        r = subprocess.run([lua, rel, 'dist/janus.lua'], cwd=REPO)
        if r.returncode != 0:
            failed += 1
    print('%d test file(s) failed' % failed if failed else 'all tests passed')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
