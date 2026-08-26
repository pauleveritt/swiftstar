#!/usr/bin/env python3
"""Run rows of the pre-registered manifest and record one outcome per cell.

Reads docs/superpowers/research/experiment-manifest.tsv, runs the rows selected
by --fixture/--rounds/--seed, and appends to experiment-results.tsv. A row that
already has a result is NEVER re-run -- the contract forbids re-running a
recorded cell.

Outcome per cell:
  pass         final graded round exit == 0 (13/13)
  fail         final graded round exit != 0
  harness-void one of the two surviving validity checks failed (V5 delivered,
               V6 harvest-faithful); the cause is recorded with it
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
    return {tuple(r[:3]) for r in csv.reader(open(RESULTS), delimiter='\t') if r and r[0] != 'fixture'}


def last_grade(cell):
    fs = sorted(glob.glob(os.path.join(cell, 'repair-round-*.json')),
                key=lambda p: int(re.search(r'(\d+)', os.path.basename(p)).group(1)))
    for f in reversed(fs):
        g = json.load(open(f)).get('grade')
        if g:
            return g
    return None


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
        outcome, detail = 'harness-void', 'no capture produced'
        if cell and os.path.isdir(cell):
            v5, why5 = check_v5(cell)
            v6, why6 = check_v6(cell)
            if v5 == 'fail':
                outcome, detail = 'harness-void', f'V5 {why5}'
            elif v6 == 'fail':
                outcome, detail = 'harness-void', f'V6 {why6}'
            else:
                g = last_grade(cell)
                if g is None:
                    # The v5 policy table: ambiguous model-vs-harness attribution
                    # defaults to MODEL with a `disputed` flag. A round ending
                    # `contractNotFollowed` produced output the harvester could
                    # not use -- model or parser, genuinely unclear -- so it is a
                    # failure, not a void. The runner used to call it a void,
                    # which disagreed with the contract it implements.
                    receipts = []
                    for rf in sorted(glob.glob(os.path.join(cell_dir(cell), 'repair-round-*.json'))):
                        try:
                            r = json.load(open(rf)).get('receipt')
                        except Exception:
                            continue
                        if isinstance(r, dict):
                            receipts += list(r.keys())
                    if 'contractNotFollowed' in receipts:
                        outcome, detail = 'fail', 'contractNotFollowed (disputed: model per policy)'
                    else:
                        outcome, detail = 'harness-void', 'no graded round recorded'
                elif g['exit'] == 0:
                    outcome, detail = 'pass', '13/13'
                else:
                    tail = [l for l in g['output'].strip().splitlines() if l.strip()]
                    outcome, detail = 'fail', (tail[-1].strip()[:70] if tail else f"exit={g['exit']}")
        with open(RESULTS, 'a') as fh:
            fh.write(f'{fixture}\t{rnd}\t{seed}\t{outcome}\t{detail}\t{os.path.basename(cell)}\n')
        print(f'[done] {fixture}/{rnd}/{seed} -> {outcome}: {detail}', flush=True)


if __name__ == '__main__':
    main()
