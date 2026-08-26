#!/usr/bin/env python3
"""Stall rate: fraction of repair rounds whose emission is byte-identical to the
previous round's. A stalled round is a re-run of the one before it -- the defect
/goal v5 exists to fix."""
import csv, hashlib, json, os, sys

def turns(cell):
    out, cur = [], []
    p = os.path.join('captures/agenttest', os.path.basename(cell), 'wire.ndjson')
    if not os.path.exists(p):
        return []
    for line in open(p, errors='replace'):
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
            out.append(''.join(cur)); cur = []
    return [t for t in out if t.strip()]

rows = [r for r in csv.reader(open(sys.argv[1]), delimiter='\t') if r and r[0] != 'fixture' and not r[0].startswith('#')]
tot = stall = 0
for r in rows:
    hs = [hashlib.sha256(t.encode()).hexdigest() for t in turns(r[5])]
    for i in range(1, len(hs)):
        tot += 1
        if hs[i] == hs[i - 1]:
            stall += 1
print(f'stalled rounds: {stall}/{tot}' + (f'  = {100*stall/tot:.0f}%' if tot else ''))
