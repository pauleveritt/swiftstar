#!/usr/bin/env python3
"""Summarise a campaign results TSV into rates with intervals.

Reads the Block A and Block B results files and prints, per cell family, the
pass rate with a Wilson 95% interval. Deliberately small: no plotting, no
policy, no reclassification. What it will not do is quietly absorb
`harness-void` rows into the denominator — those are runs where the harness
could not produce a usable measurement, and pooling them with model failures
is exactly the mistake that made the original 0/40 Mellum result describe the
harness rather than the model.

Usage:
    python3 Tools/campaign-report.py                # both blocks, default paths
    python3 Tools/campaign-report.py <results.tsv>  # one file
"""
import csv
import math
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESEARCH = os.path.join(ROOT, 'docs/superpowers/research')
DEFAULTS = [
    os.path.join(RESEARCH, 'experiment-results-editing-n20.tsv'),
    os.path.join(RESEARCH, 'experiment-results-orchestrate.tsv'),
]


def wilson(passes: int, n: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson score interval. Correct at small n, where the normal
    approximation is not — which is the whole reason this campaign exists."""
    if n == 0:
        return (0.0, 0.0)
    p = passes / n
    d = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (max(0.0, centre - half), min(1.0, centre + half))


def load(path: str) -> list[dict]:
    with open(path) as fh:
        return list(csv.DictReader(fh, delimiter='\t'))


def report(path: str) -> None:
    if not os.path.exists(path):
        print(f'  (no results file yet: {os.path.basename(path)})\n')
        return
    rows = load(path)
    if not rows:
        print(f'  (empty: {os.path.basename(path)})\n')
        return

    # Block B keys on fixture; Block A is one family keyed on spec.
    key = 'fixture' if 'fixture' in rows[0] else 'spec'
    families: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        families[r[key]].append(r)

    print(f'  {os.path.basename(path)} — {len(rows)} cells recorded')
    total_p = total_n = 0
    for name, rs in sorted(families.items()):
        counts = Counter(r['outcome'] for r in rs)
        voids = counts['harness-void'] + counts.get('timeout', 0)
        n = len(rs) - voids            # graded cells only
        p = counts['pass']
        total_p += p
        total_n += n
        if n:
            lo, hi = wilson(p, n)
            line = f'{p}/{n} = {p / n:.0%}  [{lo:.0%}, {hi:.0%}]'
        else:
            line = 'no graded cells'
        extra = f'  ({voids} void/timeout excluded)' if voids else ''
        print(f'    {name:24s} {line}{extra}')

    if len(families) > 1 and total_n:
        lo, hi = wilson(total_p, total_n)
        print(f'    {"POOLED":24s} {total_p}/{total_n} = {total_p / total_n:.0%}  [{lo:.0%}, {hi:.0%}]')

    # Failure taxonomy — the half of the deliverable that is not a rate.
    fails = [r for r in rows if r['outcome'] not in ('pass',)]
    if fails:
        print('    failure modes:')
        for outcome, n in Counter(r['outcome'] for r in fails).most_common():
            print(f'      {outcome:14s} {n}')
        details = Counter(r.get('detail', '') for r in fails if r.get('detail'))
        for detail, n in details.most_common(8):
            print(f'        {n:3d}x  {detail[:88]}')
        # Block A carries structured columns instead of a detail string.
        if 'dispatches' in rows[0]:
            # Only graded failures can be said to have dispatched nothing. A
            # timeout or void row has blank columns because it was never
            # graded, which is not the same claim at all.
            nodispatch = [r for r in fails
                          if r['outcome'] == 'fail' and r.get('dispatches') == '0']
            if nodispatch:
                print(f'        {len(nodispatch)} graded failure(s) never dispatched a phase')
    print()


def main() -> None:
    paths = sys.argv[1:] or DEFAULTS
    print('\n=== campaign report ===\n')
    for p in paths:
        report(p)
    print('Pre-registration: docs/superpowers/research/'
          '2026-08-28-overnight-campaign-preregistration.md')


if __name__ == '__main__':
    main()
