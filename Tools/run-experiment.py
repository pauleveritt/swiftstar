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
        parts = line.split('\t')
        # An optional 4th column names the ARM, which selects a prompt variant
        # via env. Manifests without it are unaffected — the arm defaults to
        # 'plural', the shipped behaviour. This exists so two wordings can be
        # interleaved on ONE binary: comparing a new arm against a frozen
        # baseline leaves a binary-drift confound and caps power at the old
        # baseline's n, whatever n the new arm uses.
        if len(parts) == 3:
            parts.append('plural')
        out.append(parts[:4])
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
    # Keyed on (fixture, rounds, seed, arm): the same cell run under a
    # different prompt arm is a DIFFERENT cell, not a repeat. Legacy 6-column
    # rows predate the arm column and are read as the shipped 'plural' arm.
    closed = set()
    for r in csv.reader(open(RESULTS), delimiter='\t'):
        if not r or r[0] == 'fixture' or len(r) <= 3:
            continue
        if r[3] not in ('pass', 'fail'):
            continue
        closed.add((r[0], r[1], r[2], r[6] if len(r) > 6 else 'plural'))
    return closed


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
            fh.write('fixture\trounds\tseed\toutcome\tdetail\tcapture\tarm\n')
    for fixture, rnd, seed, arm in rows():
        if sel.get('fixture') and fixture != sel['fixture']:
            continue
        if sel.get('rounds') and rnd != sel['rounds']:
            continue
        if sel.get('arm') and arm != sel['arm']:
            continue
        if (fixture, rnd, seed, arm) in have:
            print(f'[skip] {fixture}/{rnd}/{seed}/{arm} already recorded')
            continue
        env = dict(os.environ, AGENTTEST_SEED=seed, AGENTTEST_REPAIR_ROUNDS=rnd)
        if arm == 'singular':
            env['AGENTTEST_SINGULAR_FOLLOWUP'] = '1'
        else:
            env.pop('AGENTTEST_SINGULAR_FOLLOWUP', None)
        print(f'[run ] {fixture}/rounds={rnd}/seed={seed}/arm={arm}', flush=True)
        p = subprocess.run([BIN, '--fixture', fixture, '--variant', 'mellum-2.1'],
                           env=env, capture_output=True, text=True, cwd=ROOT)
        out = p.stdout + p.stderr
        m = re.search(r'capture=(\S+)', out)
        cell = m.group(1) if m else ''
        outcome, detail = ('harness-void', 'no capture produced') if not (cell and os.path.isdir(cell)) \
            else classify(cell)
        with open(RESULTS, 'a') as fh:
            fh.write(f'{fixture}\t{rnd}\t{seed}\t{outcome}\t{detail}\t{os.path.basename(cell)}\t{arm}\n')
        print(f'[done] {fixture}/{rnd}/{seed}/{arm} -> {outcome}: {detail}', flush=True)


if __name__ == '__main__':
    main()
