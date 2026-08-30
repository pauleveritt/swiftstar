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
import glob
import json
import os
import re
import subprocess
import sys

import campaign_common

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Overridable so a follow-up pre-registration runs against its own manifest and
# its own results file, without touching a completed and closed one.
MANIFEST = os.environ.get('EXP_MANIFEST',
                          os.path.join(ROOT, 'docs/superpowers/research/experiment-manifest.tsv'))
RESULTS = os.environ.get('EXP_RESULTS',
                         os.path.join(ROOT, 'docs/superpowers/research/experiment-results.tsv'))
BIN = os.path.join(ROOT, '.build/arm64-apple-macosx/debug/swiftstar-agenttest')
ANALYZER_BIN = os.environ.get(
    'ANALYZER_BIN',
    os.path.join(ROOT, '.build/arm64-apple-macosx/debug/swiftstar-analyze'))


def rows():
    out = []
    with open(MANIFEST) as manifest:
        for line in manifest:
            line = line.rstrip('\n')
            if not line or line.startswith(('#', 'fixture\t')):
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
    # Only a GRADED cell is closed. A `harness-void` row records a run the
    # harness could not use, so its cell must stay re-runnable — otherwise one
    # broken engine voids every remaining cell in seconds and permanently fixes
    # n at whatever ran before the breakage. (2026-08-28: a stale engine binary
    # did exactly that to a dry run; the classification was right and the
    # resume semantics would have made it permanent.)
    # Keyed on (fixture, rounds, seed, arm): the same cell run under a
    # different prompt arm is a DIFFERENT cell, not a repeat. Legacy 6-column
    # rows predate the arm column and are read as the shipped 'plural' arm.
    # See campaign_common.done_cells' docstring — same rule, shared code.
    return campaign_common.done_cells(
        RESULTS, [(0, None), (1, None), (2, None), (6, 'plural')])


def last_grade(cell):
    fs = sorted(glob.glob(os.path.join(cell, 'repair-round-*.json')),
                key=lambda p: int(re.search(r'(\d+)', os.path.basename(p)).group(1)))
    for f in reversed(fs):
        with open(f) as grade_file:
            g = json.load(grade_file).get('grade')
        if g:
            return g
    return None


def validate_capture(cell):
    try:
        p = subprocess.run(
            [ANALYZER_BIN, 'validate', cell],
            cwd=ROOT, capture_output=True, text=True, timeout=30, check=False)
    except subprocess.TimeoutExpired:
        return None, 'analyzer timed out'
    except OSError as exc:
        return None, f'analyzer unavailable: {exc}'
    if p.returncode != 0:
        detail = p.stderr.strip() or p.stdout.strip() or f'exit={p.returncode}'
        return None, f'analyzer failed: {detail[:120]}'
    try:
        result = json.loads(p.stdout)
    except json.JSONDecodeError as exc:
        return None, f'analyzer returned invalid JSON: {exc.msg}'
    if not isinstance(result, dict):
        return None, 'analyzer returned a non-object result'
    for name in ('v5', 'v6'):
        check = result.get(name)
        if not isinstance(check, dict) or check.get('status') not in {
                'pass', 'fail', 'unauditable'}:
            return None, f'analyzer result missing valid {name} status'
    return result, None


def classify(cell):
    result, error = validate_capture(cell)
    if error:
        return 'harness-void', error
    for name in ('v5', 'v6'):
        check = result[name]
        if check['status'] == 'fail':
            return 'harness-void', f'{name.upper()} {check.get("detail")}'
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
    campaign_common.ensure_header(
        RESULTS, ['fixture', 'rounds', 'seed', 'outcome', 'detail', 'capture', 'arm'])
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
                           env=env, capture_output=True, text=True, cwd=ROOT,
                           check=False)
        out = p.stdout + p.stderr
        m = re.search(r'capture=(\S+)', out)
        cell = m.group(1) if m else ''
        outcome, detail = ('harness-void', 'no capture produced') if not (cell and os.path.isdir(cell)) \
            else classify(cell)
        campaign_common.append_row(
            RESULTS, [fixture, rnd, seed, outcome, detail, os.path.basename(cell), arm])
        print(f'[done] {fixture}/{rnd}/{seed}/{arm} -> {outcome}: {detail}', flush=True)


if __name__ == '__main__':
    main()
