#!/usr/bin/env python3
"""mutate.py - prove the tests catch breakage (mutation check), Janus IADS.

    python3 tests/mutate.py                  # every module, up to 30 breaks each (a sample)
    python3 tests/mutate.py arm wta          # only modules whose name contains these
    python3 tests/mutate.py --max 0          # every possible break (slow)
    python3 tests/mutate.py --gate           # THE GATE: every break on src/ lines changed since HEAD
    python3 tests/mutate.py --gate v1.0.0    # ... since another git ref
    python3 tests/mutate.py --gate --part 2/3    # every 3rd break from the 2nd (split a long run;
                                                 # the gate passes when every part passes)
    python3 tests/mutate.py --lua <luae.exe>     # the Lua 5.1 to run the tests with (else LUA51 / PATH)

Same command line, break operators and waivers as dcs-missions' tests/mutate.py, so the PC's
mutation queue (`testq mutate janus-iads --gate REF`) runs it directly.

How: copies the repo to a scratch folder, breaks one thing at a time in one src/janus_*.lua (flips
a comparison, swaps and/or, true/false, drops a `not`, flips + - *, multiplies a number by 10,
drops a return value), rebuilds dist/janus.lua and runs the tests/test_*.lua harnesses (all of them
load the whole build; test_perf is left out: it times the machine, not the code). A break a harness
notices is "caught" (stops at the first harness that fails, or one that runs over its time limit);
one none notices "survived" and is listed with file:line. A break that does not compile is skipped.
Before breaking anything the harnesses run on the unbroken code; if one fails, the check stops (exit 2).

--gate: only the src/ modules changed since REF (plus new, untracked ones), only their changed lines,
every break on them (no sampling). A survivor fails the gate (exit 1) unless its line carries
`-- mutate: ok <reason>` (every break on the line) or `-- mutate: ok[<op>] <reason>` (only that
operator: ok[or], ok[==], ok[n], ok[return], ...) - an equivalent or untestable break, the reason says why.

Left out: janus_units.lua (generated from the DCS datamine by tools/build_unitdb.py) and
janus_presets.lua (real-world battery data with sources, validated by tools/check_presets.py).
Nothing in the repo is touched.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

TESTS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TESTS)
sys.path.insert(0, os.path.join(REPO, 'tools'))
from build import find_lua51  # noqa: E402

SKIP_MODULES = ('janus_units.lua', 'janus_presets.lua')
SKIP_HARNESSES = ('test_perf.lua',)
HARNESS_TIMEOUT = 120          # s; a break that makes a harness hang counts as caught
COPY_IGNORE = shutil.ignore_patterns('.git', 'demo', 'bench', 'docs', '*.miz', '*.acmi', '__pycache__')

# (name, regex, replacement) - each match is one candidate break (the dcs-missions set)
OPERATORS = [
    ("==", re.compile(r"=="), "~="),
    ("~=", re.compile(r"~="), "=="),
    ("<=", re.compile(r"<="), ">"),
    (">=", re.compile(r">="), "<"),
    ("<", re.compile(r"<(?![=<\[])"), ">="),
    (">", re.compile(r"(?<![-=])>(?!=)"), "<="),
    ("and", re.compile(r"\band\b"), "or"),
    ("or", re.compile(r"\bor\b"), "and"),
    ("true", re.compile(r"\btrue\b"), "false"),
    ("false", re.compile(r"\bfalse\b"), "true"),
    ("not", re.compile(r"\bnot\s+"), ""),
    ("+", re.compile(r"(?<=[\w)\]]) \+ (?=[\w(])"), " - "),
    ("-", re.compile(r"(?<=[\w)\]]) - (?=[\w(])"), " + "),
    ("*", re.compile(r"(?<=[\w)\]]) \* (?=[\w(])"), " / "),
    # a number x10 (a unit or factor mistake); 0, a table key [n] and digits inside names are left alone
    ("n", re.compile(r"(?<![\w.\[])(?!0(?![.\d]))(\d+(?:\.\d+)?)(?![\w.\]])"), r"(\g<1>*10)"),
    # the value only, never an `end` / `else` that follows on the same line
    ("return", re.compile(r"\breturn\s+(?!(?:end|else|elseif|nil)\b)(?=[^\s;]).*?(?=\s+(?:end|else|elseif)\b|\s*$)"),
     "return nil"),
]
WAIVER = re.compile(r"--\s*mutate:\s*ok(?:\[([^\]]+)\])?")


def code_spans(line):
    """(start, end) of the parts of a line that are code: not inside a string, not after --."""
    spans, i, start, q = [], 0, 0, None
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q, start = None, i + 1
        elif c in "\"'":
            spans.append((start, i))
            q = c
        elif line.startswith("--", i):
            spans.append((start, i))
            return [s for s in spans if s[1] > s[0]]
        elif line.startswith("[[", i):
            spans.append((start, i))
            j = line.find("]]", i + 2)
            if j < 0:
                return [s for s in spans if s[1] > s[0]]
            i, start = j + 2, j + 2
            continue
        i += 1
    if not q:
        spans.append((start, len(line)))
    return [s for s in spans if s[1] > s[0]]


def waived(line, op):
    """True if the line waives this operator (or every operator)."""
    for m in WAIVER.finditer(line):
        ops = m.group(1)
        if ops is None or op in [o.strip() for o in ops.split(',')]:
            return True
    return False


def candidates(lines, only=None):
    """Every break on the given line indexes (all lines if only is None): (index, op, new line)."""
    out = []
    for i, line in enumerate(lines):
        if only is not None and i not in only:
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith('--'):
            continue
        if re.match(r'\s*(M\.info|M\.warn|M\.debug|log\()', line):     # log text: not behaviour
            continue
        for start, end in code_spans(line):
            seg = line[start:end]
            for name, rx, rep in OPERATORS:
                if waived(line, name):
                    continue
                for m in rx.finditer(seg):
                    new = line[:start] + seg[:m.start()] + m.expand(rep) + seg[m.end():] + line[end:]
                    if new != line:
                        out.append((i, name, new))
    return out


def modules(filters):
    found = []
    for f in sorted(os.listdir(os.path.join(REPO, 'src'))):
        if not (f.startswith('janus_') and f.endswith('.lua')) or f in SKIP_MODULES:
            continue
        if filters and not any(x in f for x in filters):
            continue
        found.append(f)
    return found


def git_changes(ref, names):
    """{module: set of changed 0-based line indexes} since ref; a new untracked module counts whole."""
    def git(*args):
        r = subprocess.run(['git', *args], cwd=REPO, capture_output=True, text=True)
        if r.returncode:
            sys.exit('git %s failed: %s' % (' '.join(args), r.stderr.strip()))
        return r.stdout
    changed = {}
    for f in names:
        rel = 'src/' + f
        tracked = git('ls-files', '--', rel).strip()
        if not tracked:
            with open(os.path.join(REPO, rel), encoding='utf-8') as fh:
                changed[f] = set(range(len(fh.read().split('\n'))))
            continue
        lines = set()
        for hunk in re.finditer(r'^@@ -\S+ \+(\d+)(?:,(\d+))? @@', git('diff', '-U0', ref, '--', rel), re.M):
            start, count = int(hunk.group(1)), int(hunk.group(2) if hunk.group(2) is not None else 1)
            lines.update(range(start - 1, start - 1 + count))
        if lines:
            changed[f] = lines
    return changed


def run_harnesses(lua, root, harnesses):
    """None = the build or Lua failed to load (skip), True = a harness failed (caught), False = all passed."""
    b = subprocess.run([sys.executable, os.path.join('tools', 'build.py')], cwd=root, capture_output=True, text=True)
    if b.returncode:
        return None
    chk = subprocess.run([lua, 'mutate_loads.lua'], cwd=root, capture_output=True, text=True)   # compiles?
    if chk.returncode:
        return None
    for h in harnesses:
        try:
            r = subprocess.run([lua, os.path.join('tests', h), 'dist/janus.lua'], cwd=root,
                               capture_output=True, text=True, timeout=HARNESS_TIMEOUT)
        except subprocess.TimeoutExpired:
            return True
        if r.returncode:
            return True
    return False


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('filter', nargs='*', help='only modules whose name contains one of these')
    ap.add_argument('--lua', help='Lua 5.1 interpreter (default: LUA51 or PATH)')
    ap.add_argument('--max', type=int, default=30, help='breaks per module in report mode (0 = all)')
    ap.add_argument('--show', type=int, default=30, help='survivors to list')
    ap.add_argument('--gate', nargs='?', const='HEAD', metavar='REF', help='every break on lines changed since REF')
    ap.add_argument('--part', metavar='K/N', help='only every N-th break starting at the K-th')
    a = ap.parse_args(argv)
    if a.lua:
        os.environ['LUA51'] = a.lua
    lua = find_lua51()
    if not lua:
        sys.exit('no Lua 5.1 interpreter found (pass --lua or set LUA51)')
    part = None
    if a.part:
        k, n = (int(x) for x in a.part.split('/'))
        if not 1 <= k <= n:
            sys.exit('--part K/N needs 1 <= K <= N')
        part = (k, n)

    names = modules(a.filter)
    if a.gate:
        changed = git_changes(a.gate, names)
        if not changed:
            print('MUTATION GATE PASS: no src module changed since %s' % a.gate)
            return 0
    jobs = []
    for f in names:
        with open(os.path.join(REPO, 'src', f), encoding='utf-8') as fh:
            lines = fh.read().split('\n')
        if a.gate:
            if f not in changed:
                continue
            cands = candidates(lines, changed[f])
        else:
            cands = candidates(lines)
            if a.max and len(cands) > a.max:            # an even spread over the file, not the first N
                step = len(cands) / float(a.max)
                cands = [cands[int(i * step)] for i in range(a.max)]
        jobs += [(f, lines, i, op, new) for i, op, new in cands]
    if part:
        jobs = jobs[part[0] - 1::part[1]]
    harnesses = sorted(h for h in os.listdir(TESTS)
                       if h.startswith('test_') and h.endswith('.lua') and h not in SKIP_HARNESSES)
    print('%d break(s) in %d module(s)%s' % (len(jobs), len({j[0] for j in jobs}),
                                              ' (part %d/%d)' % part if part else ''), flush=True)

    tmp = tempfile.mkdtemp(prefix='janus_mut_')
    root = os.path.join(tmp, 'r')
    try:
        shutil.copytree(REPO, root, ignore=COPY_IGNORE)
        with open(os.path.join(root, 'mutate_loads.lua'), 'w') as fh:     # no `lua -e` needed (DCS luae.exe)
            fh.write('assert(loadfile("dist/janus.lua"))\n')
        if run_harnesses(lua, root, harnesses) is not False:
            print('the tests fail on the unbroken code: fix them first')
            return 2
        tried = caught = skipped = 0
        survivors = []
        for f, lines, i, op, new in jobs:
            path = os.path.join(root, 'src', f)
            broken = list(lines)
            broken[i] = new
            with open(path, 'w', encoding='utf-8', newline='\n') as fh:
                fh.write('\n'.join(broken))
            res = run_harnesses(lua, root, harnesses)
            with open(path, 'w', encoding='utf-8', newline='\n') as fh:
                fh.write('\n'.join(lines))
            if res is None:
                skipped += 1
                continue
            tried += 1
            if res:
                caught += 1
            else:
                survivors.append('%s:%d [%s] %s' % (f, i + 1, op, lines[i].strip()[:110]))
        print('%d/%d caught (%d did not compile, skipped)' % (caught, tried, skipped))
        for s in survivors[:a.show]:
            print('SURVIVED', s)
        if len(survivors) > a.show:
            print('... and %d more' % (len(survivors) - a.show))
        if a.gate:
            if survivors:
                print('MUTATION GATE FAIL: %d break(s) survived%s' % (len(survivors),
                                                                     ' (part %d/%d)' % part if part else ''))
                return 1
            print('MUTATION GATE PASS%s' % (' (part %d/%d)' % part if part else ''))
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
