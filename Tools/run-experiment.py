#!/usr/bin/env python3
"""Run rows of a fixture-tier manifest and record one outcome per cell.

Generic instrument, deliberately small: construct a cell from a manifest row,
run it, classify it by the two surviving validity checks plus the final graded
round, append the row. No experiment-specific policy lives here — that belongs
in the ledger that reads these results, not in the runner that produces them.

Reads a TSV of `fixture<TAB>rounds<TAB>seed` rows (override paths with
EXP_MANIFEST / EXP_RESULTS). A row that already has a result is NEVER re-run.

Outcome per cell:
  pass         final graded round exit == 0 (13/13)
  fail         final graded round exit != 0, OR the round ended in a state with
               no grade at all (e.g. contractNotFollowed) — the harness could
               not use the model's output, which is a failure, not a void
  harness-void one of the two surviving validity checks failed (V5 delivered,
               V6 harvest-faithful); the cause is recorded with it

2026-08-26: reverted to this shape after /goal v5's policy-specific branches
(a `stalled-runaway` reclassification, a `contractNotFollowed` reclassification
referencing an undefined `cell_dir`) were retired along with v5. See
docs/superpowers/research/goal-ledger-v5.md entry (closure) for why.
"""
import csv, glob, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Overridable so a follow-up pre-registration runs against its own manifest and
# its own results file, without touching a completed and closed one.
MANIFEST = os.environ.get('EXP_MANIFEST',
                          os.path.join(ROOT, 'docs/superpowers/research/experiment-manifest.tsv'))
RESULTS = os.environ.get('EXP_RESULTS',
                         os.path.join(ROOT, 'docs/superpowers/research/experiment-results.tsv'))
BIN = os.path.join(ROOT, '.build/arm64-apple-macosx/debug/swiftstar-agenttest')

sys.path.insert(0, os.path.join(ROOT, 'Tools'))
_aud = open(os.path.join(ROOT, 'Tools/audit-goal-invariants.py')).read().split('def main()')[0]
_ns = {'__name__': 'aud'}
exec(compile(_aud, 'audit-goal-invariants.py', 'exec'), _ns)
check_v5, check_v6 = _ns['check_v5'], _ns['check_v6']


def rows():
    out = []
    for line in open(MANIFEST):
        line = line.rstrip('\n')
        if not line or line.startswith('#') or line.startswith('fixture\t'):
            continue
        out.append(line.split('\t'))
    return out


def done():
    if not os.path.exists(RESULTS):
        return set()
    # Only a GRADED cell is closed. A `harness-void` row records a run the
    # harness could not use, so its cell must stay re-runnable — otherwise one
    # broken engine voids every remaining cell in seconds and permanently fixes
    # n at whatever ran before the breakage. (2026-08-28: a stale engine binary
    # did exactly that to a dry run; the classification was right and the
    # resume semantics would have made it permanent.)
    return {tuple(r[:3]) for r in csv.reader(open(RESULTS), delimiter='\t')
            if r and r[0] != 'fixture' and len(r) > 3 and r[3] in ('pass', 'fail')}


def last_grade(cell):
    fs = sorted(glob.glob(os.path.join(cell, 'repair-round-*.json')),
                key=lambda p: int(re.search(r'(\d+)', os.path.basename(p)).group(1)))
    for f in reversed(fs):
        g = json.load(open(f)).get('grade')
        if g:
            return g
    return None


def classify(cell):
    v5, why5 = check_v5(cell)
    if v5 == 'fail':
        return 'harness-void', f'V5 {why5}'
    v6, why6 = check_v6(cell)
    if v6 == 'fail':
        return 'harness-void', f'V6 {why6}'
    g = last_grade(cell)
    if g is None:
        return 'fail', 'no graded round recorded (e.g. contractNotFollowed)'
    if g['exit'] == 0:
        return 'pass', '13/13'
    tail = [l for l in g['output'].strip().splitlines() if l.strip()]
    return 'fail', (tail[-1].strip()[:70] if tail else f"exit={g['exit']}")


def main():
    sel = dict(a.split('=') for a in sys.argv[1:] if '=' in a)
    have = done()
    if not os.path.exists(RESULTS):
        with open(RESULTS, 'w') as fh:
            fh.write('fixture\trounds\tseed\toutcome\tdetail\tcapture\n')
    for fixture, rnd, seed in rows():
        if sel.get('fixture') and fixture != sel['fixture']:
            continue
        if sel.get('rounds') and rnd != sel['rounds']:
            continue
        if (fixture, rnd, seed) in have:
            print(f'[skip] {fixture}/{rnd}/{seed} already recorded')
            continue
        env = dict(os.environ, AGENTTEST_SEED=seed, AGENTTEST_REPAIR_ROUNDS=rnd)
        print(f'[run ] {fixture}/rounds={rnd}/seed={seed}', flush=True)
        p = subprocess.run([BIN, '--fixture', fixture, '--variant', 'mellum-2.1'],
                           env=env, capture_output=True, text=True, cwd=ROOT)
        out = p.stdout + p.stderr
        m = re.search(r'capture=(\S+)', out)
        cell = m.group(1) if m else ''
        outcome, detail = ('harness-void', 'no capture produced') if not (cell and os.path.isdir(cell)) \
            else classify(cell)
        with open(RESULTS, 'a') as fh:
            fh.write(f'{fixture}\t{rnd}\t{seed}\t{outcome}\t{detail}\t{os.path.basename(cell)}\n')
        print(f'[done] {fixture}/{rnd}/{seed} -> {outcome}: {detail}', flush=True)


if __name__ == '__main__':
    main()
