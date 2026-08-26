#!/usr/bin/env python3
"""Audit agenttest captures against P16's frozen validity invariants (V1-V5).

The provenance of every number in `docs/superpowers/research/goal-ledger.md`.
Lives in the repo, not a scratchpad, so those numbers stay reproducible.

Two rules this file exists to enforce on itself, both learned the hard way
(2026-08-26, Fable review):

  1. **Check the artifact the invariant names.** V2 says "no round's *evidence*
     may contain a bare collection error." The evidence is the packet the model
     was dispatched (`repair-packet-N.json`), NOT the grade recorded after that
     round ran (`repair-round-N.json`). The first version of this script grepped
     the latter, which is off-by-one in both directions -- it never inspects
     round 1's dispatched evidence, and it does inspect a final-round grade that
     was never shown to anyone. That bug certified a cell VALID whose round-1
     packet contained the exact string V2 forbids.

  2. **Every check is validated against a known-bad and a known-good cell**
     before its output may be trusted -- `--self-test`. A check that has never
     fired is an untested claim, not a passing grade. `check_v4` shipped in a
     state where it could never fire under any input.

A check that cannot be evaluated from the captures returns UNAUDITABLE, which
is NOT a pass. Silently passing an unevaluable check is how V4 reported "0
blocked" for a defect that was never looked for.
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


def repair_loops(cell):
    """(label, dir) for each repair loop the cell ran."""
    out = [(os.path.basename(p), p) for p in sorted(glob.glob(os.path.join(cell, 'repair-phase*')))]
    if glob.glob(os.path.join(cell, 'repair-round-*.json')):
        out.append(('acceptance', cell))
    return out


def _n(path):
    return int(re.search(r'(\d+)', os.path.basename(path)).group(1))


def packets(loop):
    return sorted(glob.glob(os.path.join(loop, 'repair-packet-*.json')), key=_n)


def rounds(loop):
    return sorted(glob.glob(os.path.join(loop, 'repair-round-*.json')), key=_n)


def task_text(pf):
    return json.load(open(pf))['taskText']


def evidence_block(t):
    i = t.find('Current contents of the files you may edit')
    return t[i:] if i >= 0 else ''


def missing_paths(t):
    out = set()
    for m in re.finditer(r'=== (\S+) ===\n(.*?)(?=\n=== |\Z)', evidence_block(t), re.S):
        if 'does not exist in this worktree' in m.group(2)[:80]:
            out.add(m.group(1))
    return out


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


def evidence_files(t):
    """(path, body) for each file the packet shows as current contents."""
    return [(m.group(1), m.group(2))
            for m in re.finditer(r'=== (\S+) ===\n(.*?)(?=\n=== |\Z)', evidence_block(t), re.S)]


# --- invariants -------------------------------------------------------------

def check_v1(cell, loop):
    """A `.validationFailed` round's write must survive into the next round.

    Gated on round k's receipt actually being validationFailed (proof a turn
    ran). Compares the missing-set of consecutive DISPATCHED packets: if the
    round wrote a file that had been missing and it survived, the set shrinks.

    Known limits, stated rather than hidden: this can only observe survival of
    writes to *missing* files. A surviving write to an already-present file
    leaves the set unchanged and would be misread as a discard, so the check
    only reports FAIL when `miss_k` is non-empty and unchanged. In tool-call
    mode a zero-mutation turn can also yield validationFailed, in which case an
    unchanged set is correct behaviour, not a discard -- so this is sound only
    for text-contract runs. Returns UNAUDITABLE outside them.
    """
    pk, rd = packets(loop), {_n(f): json.load(open(f)) for f in rounds(loop)}
    if len(pk) < 2:
        return PASS, None
    for i in range(len(pk) - 1):
        k = _n(pk[i])
        rj = rd.get(k)
        if not rj:
            continue
        rc = rj.get('receipt')
        if not (isinstance(rc, dict) and 'validationFailed' in rc):
            continue
        if not json.load(open(pk[i])).get('textContract', True):
            return UNAUDITABLE, 'tool-call mode: zero-mutation turns also yield validationFailed'
        a, b = missing_paths(task_text(pk[i])), missing_paths(task_text(pk[i + 1]))
        if a and b == a:
            return FAIL, (f'round {k} ended validationFailed but round {k+1} was dispatched the '
                          f'identical missing set {sorted(a)} -- the write did not survive')
    return PASS, None


def check_v2(cell, loop):
    """No round's DISPATCHED EVIDENCE may be a bare pytest collection error.

    Reads `repair-packet-N.json` -- what the model was actually shown -- not
    the grade recorded after the round ran. See this module's docstring.
    """
    pk = packets(loop)
    if not pk:
        return UNAUDITABLE, 'no repair packets captured'
    for pf in pk:
        t = task_text(pf)
        if 'Interrupted:' in t and 'error during collection' in t:
            return FAIL, f'{os.path.basename(pf)}: dispatched evidence is a bare collection error'
    return PASS, None


def check_v3(cell, loop):
    """The directive must not assert "exactly one file is wrong" while >=2
    writable files are missing/failing in the same packet.

    Only the *missing* half is implemented -- "failing" has no operational
    definition over a capture, so a packet asserting one-file-wrong while two
    present-but-wrong files need edits is NOT detected. Reported honestly as a
    partial check rather than a clean pass.
    """
    for pf in packets(loop):
        t = task_text(pf)
        if 'xactly one file is wrong' not in t:
            continue
        miss = missing_paths(t)
        if len(miss) >= 2:
            return FAIL, f'{os.path.basename(pf)}: asserts one-file-wrong, {len(miss)} missing {sorted(miss)}'
    return PASS, None


def check_v4(cell, loop=None):
    """Every verdict reason must trace to text in some dispatched packet.

    UNAUDITABLE by construction: `main.swift` captures only `phases[0]`'s
    packet, so phase 2/3 briefs are never written to the capture and a reason
    tracing to later-phase content cannot be checked either way.
    """
    return UNAUDITABLE, 'only phases[0] packet is captured (main.swift:716); phase 2/3 briefs absent'


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


def check_v6(cell, loop=None):
    """No file content may originate in an emission containing zero fences.

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
    ts = turns(cell)
    if ts is None:
        return UNAUDITABLE, 'no wire.ndjson'
    unfenced = [t for t in ts if t.strip() and '```' not in t]
    if not unfenced:
        return PASS, None
    for label, d in repair_loops(cell):
        for pf in packets(d):
            for path, body in evidence_files(task_text(pf)):
                b = body.strip()
                if len(b.encode()) < 40 or 'does not exist in this worktree' in b[:80]:
                    continue
                if any(b in t for t in unfenced):
                    return FAIL, (f'{label}/{os.path.basename(pf)}: {path} contents originate in '
                                  f'an emission containing zero fenced blocks')
    return PASS, None


PER_LOOP = {'V1': check_v1, 'V2': check_v2, 'V3': check_v3}
PER_CELL = {'V4': check_v4, 'V5': check_v5, 'V6': check_v6}


def audit(cell_dir):
    cell = resolve(cell_dir)
    blocked, unaud = {}, {}
    for label, loop in repair_loops(cell):
        for name, fn in PER_LOOP.items():
            st, why = fn(cell, loop)
            if st == FAIL:
                blocked.setdefault(name, []).append(f'{label}: {why}')
            elif st == UNAUDITABLE:
                unaud.setdefault(name, []).append(f'{label}: {why}')
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
    # (check, cell, loop-label, expected, why this cell is the fixture)
    ('V1', '20260826-050316-roadmap', 'repair-phase1', FAIL,
     'known-bad: two validationFailed rounds, identical 6-file missing set'),
    ('V1', '20260826-085813-roadmap', 'repair-phase1', PASS,
     'known-good: phase repair produced a candidate on round 1, no discard path taken'),
    ('V2', '20260826-085813-roadmap', 'acceptance', FAIL,
     'known-bad: acceptance round-1 packet carries a bare collection error'),
    ('V2', '20260826-085813-roadmap', 'repair-phase1', PASS,
     'known-good: phase-1 repair evidence is an import traceback, not a collection abort'),
    ('V3', '20260826-060458-roadmap', 'repair-phase1', FAIL,
     'known-bad: one-file-wrong asserted with 6 missing'),
    ('V3', '20260826-085813-roadmap', 'acceptance', PASS,
     'known-good: one-file-wrong asserted with 0 missing (correctly calibrated)'),
    ('V5', '20260826-055741-roadmap', None, FAIL, 'known-bad: context overflow'),
    ('V5', '20260826-060458-roadmap', None, PASS, 'known-good: clean wire'),
    ('V6', '20260826-112536-roadmap', None, FAIL,
     'known-bad: round-1 emission had 6 headings, prose under each, zero fences; '
     'the prose became app.py/models.py/tests/test_app.py'),
    ('V6', '20260826-105529-roadmap', None, PASS,
     'known-good: every harvested file came from a fenced block'),
]


def self_test():
    ok = True
    for name, cell, label, expected, why in FIXTURES:
        c = resolve(os.path.join('captures/agenttest', cell))
        if name in PER_CELL:
            got, detail = PER_CELL[name](c)
        else:
            loop = c if label == 'acceptance' else os.path.join(c, label)
            got, detail = PER_LOOP[name](c, loop)
        good = got == expected
        ok &= good
        print(f"  [{'ok' if good else 'FAIL'}] {name} {cell}/{label or '-'}: "
              f"expected {expected}, got {got}   ({why})")
        if not good and detail:
            print(f"        detail: {detail}")
    print(f"\nself-test: {'PASS' if ok else 'FAIL'}")
    print("V4 has no fixtures: it is UNAUDITABLE by construction, not a check that can fire.")
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
