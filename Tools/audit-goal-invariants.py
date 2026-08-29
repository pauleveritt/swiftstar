#!/usr/bin/env python3
"""Audit agenttest captures against P16's frozen validity invariants V5-V6.

The provenance of every number in `docs/superpowers/research/goal-ledger.md`.
Lives in the repo, not a scratchpad, so those numbers stay reproducible.

2026-08-29: V1-V4 (the repair-loop invariants) were removed. P16 closed
2026-08-26, superseded by v3, and the apparatus they audited -- the phased
repair loop -- was demoted along with it; goal-ledger.md's V1-V4 numbers are
a closed historical record, not a target this script still measures against.
V5 (packet deliverability) and V6 (harvest faithfulness) are still live: they
back `Tools/run-experiment.py`'s `harness-void` classification, which `exec`s
this module's body above its CLI entry point and pulls `check_v5`/`check_v6`
directly out of its namespace. See
docs/superpowers/research/2026-08-29-eval-system-audit-and-later-work.md for
the fuller audit this trim was scoped from.

Two rules this file exists to enforce on itself, both learned the hard way
(2026-08-26, Fable review):

  1. **Check the artifact the invariant names.** The evidence a check reads
     must be the artifact the invariant actually names (the packet the model
     was dispatched, `repair-packet-N.json`), not some other artifact that
     merely looks related (a post-hoc grade recorded after the round ran,
     `repair-round-N.json`). A retired V1-V4 check once conflated the two --
     off-by-one in both directions -- and certified a cell VALID whose
     round-1 packet contained the exact string it was meant to forbid.

  2. **Every check is validated against a known-bad and a known-good cell**
     before its output may be trusted -- `--self-test`. A check that has never
     fired is an untested claim, not a passing grade. A retired V1-V4 check
     once shipped in a state where it could never fire under any input.

A check that cannot be evaluated from the captures returns UNAUDITABLE, which
is NOT a pass. Silently passing an unevaluable check is how one retired V1-V4
check reported "0 blocked" for a defect that was never looked for.
"""
import csv, json, glob, os, re, sys

# Overridable so a /goal measure batch can be audited from its own manifest
# without editing this file. Plumbing only -- no check reads this.
MANIFEST = os.environ.get('GOAL_MANIFEST', '/tmp/overnight-manifest.tsv')

PASS, FAIL, UNAUDITABLE = 'pass', 'fail', 'unauditable'


def resolve(d):
    if not os.path.isdir(d):
        d = os.path.join('captures/agenttest', os.path.basename(d.rstrip('/')))
    return d


WRITABLE = {'app.py', 'models.py', 'templates/base.html', 'templates/home.html',
            'templates/complaints.html', 'tests/test_app.py'}


def _heading(line):
    """The path a heading line names, or None. Mirrors LabeledBlockParser."""
    t = line.strip()
    if not t.startswith('#'):
        return None
    r = t.lstrip('#').strip()
    if r.startswith('`') and r.endswith('`') and len(r) >= 2:
        r = r[1:-1]
    return r or None


def turns(cell):
    """Model emissions, segmented by the engine's `ready` events.

    Returns None when there is no wire to read, so callers can report
    UNAUDITABLE rather than silently passing.
    """
    w = os.path.join(cell, 'wire.ndjson')
    if not os.path.exists(w):
        return None
    out, cur = [], []
    for line in open(w, errors='replace'):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d.get('t') == 'text':
            cur.append(d.get('s', ''))
        elif d.get('t') == 'ready':
            out.append(''.join(cur))
            cur = []
    if cur:
        out.append(''.join(cur))
    return out


# --- invariants -------------------------------------------------------------

def check_v5(cell, loop=None):
    """Every packet must have been deliverable."""
    w = os.path.join(cell, 'wire.ndjson')
    if not os.path.exists(w):
        return UNAUDITABLE, 'no wire.ndjson'
    text = open(w).read()
    if 'exceeds context' in text:
        return FAIL, 'exceeds context'
    if 'turnDidNotEnd' in text:
        return FAIL, 'turnDidNotEnd'
    for line in text.splitlines():
        m = re.search(r'"stop_reason"\s*:\s*"(\w+)"', line)
        if m and m.group(1) in ('limit', 'contextFull'):
            return FAIL, f'stop_reason={m.group(1)}'
    return PASS, None


def _discarded_fences(cell):
    """Headings whose fenced code the lenient path discarded in favour of prose.

    The 20260826-104811 shape: heading, blank line, commentary, THEN the real
    fenced block. The lenient body loop stopped at the fence, so the prose was
    harvested and the fence was skipped as "no accepted heading". Reported per
    (turn, path) so a cell can say how much of the model's code it lost.
    """
    ts = turns(cell)
    if ts is None:
        return None
    out = []
    for ti, t in enumerate(ts):
        lines = t.split('\n')
        for i, ln in enumerate(lines):
            h = _heading(ln)
            if not h or h not in WRITABLE:
                continue
            j = i + 1
            if j < len(lines) and not lines[j].strip():
                j += 1
            if j < len(lines) and lines[j].strip().startswith('```'):
                continue                      # correct form: fence follows the heading
            k = j
            while k < len(lines):
                if lines[k].strip().startswith('```'):
                    out.append((ti, h))       # a fence was there and was discarded
                    break
                nh = _heading(lines[k])
                if nh and nh in WRITABLE:
                    break                     # next heading's span; not this one's
                k += 1
    return out


def check_v6(cell, loop=None):
    """No file content may be harvested in place of code the model fenced.

    v2 (2026-08-26) wrote the model's own prose into six source files: Mellum
    emitted six headings, prose under each, and NOT ONE fenced block, ending
    "Now I'll create all the missing files with the appropriate content:".
    `LabeledBlockParser`'s lenient path took each heading's prose as that
    file's contents, so `app.py` became English and every later round repaired
    the model's commentary. 3 of 8 cells across the two n=4 batches.

    Evidence, not inference: a packet's shown file body is matched back
    verbatim against the text of a zero-fence turn. If it is found there, that
    content demonstrably came from an unfenced emission.

    Bodies under 40 bytes are skipped -- a short body can coincide with prose
    by accident, and every real instance of this defect is a paragraph.
    """
    discarded = _discarded_fences(cell)
    if discarded is None:
        return UNAUDITABLE, 'no wire.ndjson'
    if discarded:
        paths = sorted({p for _, p in discarded})
        return FAIL, (f'{len(discarded)} heading(s) had fenced code discarded in favour of '
                      f'commentary: {paths}')
    # The zero-fence clause was WITHDRAWN (v3 iteration 3, human ruling). It
    # marked P15's correct zero-fence harvests invalid: three of the four frozen
    # fixtures are zero-fence emissions carrying real code, and the check could
    # not tell commentary from code. Any V6 count that clause produced is void.
    return PASS, None


PER_CELL = {'V5': check_v5, 'V6': check_v6}


def audit(cell_dir):
    cell = resolve(cell_dir)
    blocked, unaud = {}, {}
    for name, fn in PER_CELL.items():
        st, why = fn(cell)
        if st == FAIL:
            blocked.setdefault(name, []).append(why)
        elif st == UNAUDITABLE:
            unaud.setdefault(name, []).append(why)
    return {'dir': os.path.basename(cell), 'valid': not blocked,
            'blocked': blocked, 'unauditable': unaud}


# --- self-test --------------------------------------------------------------

FIXTURES = [
    # (check, cell, expected, why this cell is the fixture)
    ('V5', '20260826-055741-roadmap', FAIL, 'known-bad: context overflow'),
    ('V5', '20260826-060458-roadmap', PASS, 'known-good: clean wire'),
    ('V6', '20260826-104811-roadmap', FAIL,
     'known-bad (widened clause): all 6 headings had their fenced code discarded '
     'in favour of commentary -- zero-fence detection alone passed this cell'),
    ('V6', '20260826-105529-roadmap', PASS,
     'known-good: every harvested file came from a fenced block'),
]


def self_test():
    ok = True
    for name, cell, expected, why in FIXTURES:
        # resolve() already prefixes captures/agenttest for a bare cell name and
        # leaves an existing directory alone, so a fixture path works too.
        c = resolve(cell)
        got, detail = PER_CELL[name](c)
        good = got == expected
        ok &= good
        print(f"  [{'ok' if good else 'FAIL'}] {name} {cell}: "
              f"expected {expected}, got {got}   ({why})")
        if not good and detail:
            print(f"        detail: {detail}")
    print(f"\nself-test: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def main():
    if '--self-test' in sys.argv:
        sys.exit(self_test())
    rows = list(csv.DictReader(open(MANIFEST), delimiter='\t'))
    extra = [a for a in sys.argv[1:] if not a.startswith('-')]
    by_model = {}
    for r in rows:
        by_model.setdefault(r['model'], []).append((r, audit(r['capture'])))
    for model, rs in sorted(by_model.items()):
        valid = [a for _, a in rs if a['valid']]
        bc, uc = {}, {}
        for _, a in rs:
            for k in a['blocked']:
                bc[k] = bc.get(k, 0) + 1
            for k in a['unauditable']:
                uc[k] = uc.get(k, 0) + 1
        print(f"=== {model}: {len(valid)} valid / {len(rs)} total ===")
        print(f"    blocked:     {bc}")
        print(f"    unauditable: {uc}   (NOT passes)")
    for cell in extra:
        a = audit(cell)
        print(f"\n=== {a['dir']}: {'VALID' if a['valid'] else 'BLOCKED'} ===")
        for k, v in sorted(a['blocked'].items()):
            print(f"    {k}: {v[0]}")
        for k, v in sorted(a['unauditable'].items()):
            print(f"    {k}: UNAUDITABLE — {v[0]}")


if __name__ == '__main__':
    main()
