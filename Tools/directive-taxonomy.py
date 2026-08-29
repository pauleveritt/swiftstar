#!/usr/bin/env python3
"""Per-capture failure taxonomy for Block A (directive/orchestrate) runs.

`swiftstar-analyze summary` reports 0 turns for a directive capture — the
directive driver writes no `outcomes.ndjson`, and the pooled wire does not
reduce the way the CLI expects. Per the telemetry skill's Rule 0, that is the
case where reading `wire.ndjson` directly is the right move rather than the
lazy one.

What it reports per capture, split by worker (0 = orchestrator, 1 = the
dispatched worker), because folding pooled sessions together produces a merged
fiction:

    dispatches      how many times the orchestrator called the `dispatch` tool
    tools           tool calls by name
    think/text      event counts, as a coarse reasoning-volume proxy
    errors          non-empty engine `status.error` strings

Usage:
    python3 Tools/directive-taxonomy.py                    # every Block A capture
    python3 Tools/directive-taxonomy.py <capture-dir> ...  # specific ones
"""
import glob
import json
import os
import sys
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def scan(capture: str) -> dict:
    wire = os.path.join(capture, 'wire.ndjson')
    if not os.path.exists(wire):
        return {'error': 'no wire.ndjson'}

    tools: dict[int, Counter] = defaultdict(Counter)
    events: dict[int, Counter] = defaultdict(Counter)
    errors: Counter = Counter()
    unparsable = 0

    with open(wire) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except Exception:
                unparsable += 1
                continue
            w = o.get('worker', 0)
            t = o.get('t', '?')
            events[w][t] += 1
            if t == 'tool_request':
                tools[w][o.get('name', '<unnamed>')] += 1
            elif t == 'status':
                err = (o.get('error') or '').strip()
                if err:
                    errors[err] += 1

    return {
        'tools': tools,
        'events': events,
        'errors': errors,
        'unparsable': unparsable,
        'dispatches': tools[0].get('dispatch', 0),
    }


def render(capture: str) -> None:
    name = os.path.basename(capture.rstrip('/'))
    r = scan(capture)
    print(f'== {name}')

    cfg = os.path.join(capture, 'campaign.json')
    if os.path.exists(cfg):
        with open(cfg) as fh:
            c = json.load(fh)
        print(f'   seed={c.get("seed")} think={c.get("think_budget")} '
              f'outcome={c.get("outcome")} {c.get("seconds")}s')

    if 'error' in r:
        print(f'   {r["error"]}\n')
        return

    print(f'   dispatches: {r["dispatches"]}')
    for w in sorted(r['events']):
        ev, tl = r['events'][w], r['tools'][w]
        role = 'orchestrator' if w == 0 else f'worker {w}'
        tool_s = ', '.join(f'{n}x{c}' for n, c in tl.most_common()) or 'none'
        print(f'   {role:14s} think={ev.get("think", 0):5d} text={ev.get("text", 0):4d} '
              f'tool_requests={sum(tl.values()):3d}  [{tool_s}]')
    if r['errors']:
        print('   engine errors:')
        for err, n in r['errors'].most_common(5):
            print(f'     {n:4d}x {err[:90]}')
    if r['unparsable']:
        print(f'   WARNING: {r["unparsable"]} unparsable wire line(s)')
    print()


def main() -> None:
    args = sys.argv[1:]
    if not args:
        args = sorted(glob.glob(os.path.join(ROOT, 'captures/agenttest/*-directive')))
    if not args:
        print('no directive captures found')
        return
    for c in args:
        render(c)


if __name__ == '__main__':
    main()
