"""Minimal parser for serialized Lua table literals (as in the DCS Lua datamine).

Handles: nested tables, `key = value`, `["key"] = value`, `[0] = value`, positional
entries, strings ('..', "..", [[..]]), numbers (incl. 1e5, hex), true/false/nil,
comments (-- and --[[ ]]), and a leading `_G[...]... = ` assignment.

Pure Python, no dependencies: this keeps the Janus build tool runnable on any PC.
"""
import re

_TOKEN = re.compile(r'''
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<eq1>=*)\[.*?\](?P=eq1)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<eq2>=*)\[(?P<lbody>.*?)\](?P=eq2)\])
  | (?P<dstring>"(?:\\.|[^"\\])*")
  | (?P<sstring>'(?:\\.|[^'\\])*')
  | (?P<number>-?(?:0[xX][0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<funcref><function\s+\d+>)
  | (?P<tabref><table\s+(?P<tid>\d+)>)
  | (?P<tblref><(?P<mid>\d+)>)
  | (?P<punct>[{}\[\]=,;()])
''', re.S | re.X)

_ESC = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", 'a': '\a',
        'b': '\b', 'f': '\f', 'v': '\v', '\n': '\n'}


def _unescape(s):
    out = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            if n in _ESC:
                out.append(_ESC[n]); i += 2; continue
            if n.isdigit():
                j = i + 1
                while j < len(s) and j < i + 4 and s[j].isdigit():
                    j += 1
                out.append(chr(int(s[i + 1:j]))); i = j; continue
            out.append(n); i += 2; continue
        out.append(c); i += 1
    return ''.join(out)


def tokenize(src):
    pos = 0
    n = len(src)
    while pos < n:
        m = _TOKEN.match(src, pos)
        if not m:
            raise SyntaxError('bad token at %d: %r' % (pos, src[pos:pos + 30]))
        pos = m.end()
        kind = m.lastgroup
        if kind in ('ws', 'comment', 'lcomment'):
            continue
        if kind == 'lstring':
            yield ('string', m.group('lbody'))
        elif kind in ('dstring', 'sstring'):
            yield ('string', _unescape(m.group(kind)[1:-1]))
        elif kind == 'number':
            t = m.group('number')
            if t.lower().startswith(('0x', '-0x')):
                yield ('number', int(t, 16))
            else:
                v = float(t)
                yield ('number', int(v) if v.is_integer() and 'e' not in t.lower() and '.' not in t else v)
        elif kind == 'name':
            yield ('name', m.group('name'))
        elif kind == 'funcref':          # serializer marker for a function value
            yield ('name', 'nil')
        elif kind == 'tabref':           # `<table N>`: reference to the table marked `<N>{`
            yield ('tabref', int(m.group('tid')))
        elif kind == 'tblref':           # `<N>{ ... }`: mark the next table with id N
            yield ('mark', int(m.group('mid')))
        else:
            yield ('punct', m.group('punct'))


class _P:
    def __init__(self, src):
        self.toks = list(tokenize(src))
        self.i = 0
        self.marked = {}

    def peek(self, k=0):
        j = self.i + k
        return self.toks[j] if j < len(self.toks) else ('eof', None)

    def take(self, kind=None, val=None):
        t = self.peek()
        if kind and t[0] != kind or (val is not None and t[1] != val):
            raise SyntaxError('expected %s %r, got %r (tok %d)' % (kind, val, t, self.i))
        self.i += 1
        return t

    def value(self):
        k, v = self.peek()
        if k == 'mark':
            self.i += 1
            t = self.value()
            self.marked[v] = t
            return t
        if k == 'tabref':
            self.i += 1
            return self.marked.get(v, '<lua:table %d>' % v)
        if k == 'punct' and v == '{':
            return self.table()
        if k in ('string', 'number'):
            self.i += 1
            return v
        if k == 'name':
            self.i += 1
            if v == 'true':
                return True
            if v == 'false':
                return False
            if v == 'nil':
                return None
            # bare identifier / expression reference (rare): keep as marker string
            return '<lua:%s>' % v
        if k == 'punct' and v == '(':
            self.i += 1
            inner = self.value()
            self.take('punct', ')')
            return inner
        raise SyntaxError('unexpected %r at tok %d' % ((k, v), self.i))

    def table(self):
        self.take('punct', '{')
        d = {}
        pos = 1
        while True:
            k, v = self.peek()
            if k == 'punct' and v == '}':
                self.i += 1
                break
            if k == 'punct' and v == '[':
                self.i += 1
                key = self.value()
                self.take('punct', ']')
                self.take('punct', '=')
                d[key] = self.value()
            elif k == 'name' and self.peek(1) == ('punct', '='):
                self.i += 2
                d[v] = self.value()
            else:
                d[pos] = self.value()
                pos += 1
            k, v = self.peek()
            if k == 'punct' and v in (',', ';'):
                self.i += 1
        # convert pure arrays to lists
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[i] for i in range(1, len(d) + 1)]
        return d


def parse_file(path):
    """Parse a datamine file: `_G[...]...["#Index"] = { ... }` → dict. Returns (path_keys, table)."""
    with open(path, encoding='utf-8', errors='replace') as f:
        src = f.read()
    p = _P(src)
    keys = []
    if p.peek() == ('name', '_G'):
        p.i += 1
        while p.peek() == ('punct', '['):
            p.i += 1
            keys.append(p.value())
            p.take('punct', ']')
        p.take('punct', '=')
    return keys, p.value()


def parse_literal(src):
    return _P(src).value()
