#!/usr/bin/env python3
"""Stall rate: fraction of repair rounds that are provable replays.

Definition (v5 contract, made precise): round N+1 is a STALL when its dispatched
packet is byte-identical to round N's. The packet is a deterministic function of
the tree and grade after the previous round, and the engine re-seeds identically
per prompt, so an identical packet guarantees an identical emission -- the fixed
point `f(x) = x`.

Reads `repair-packet-N.json`, which maps 1:1 to rounds. An earlier version
compared consecutive wire turns and was WRONG: each round emits two turns (the
answer plus an emissionFollowUp), so it was comparing answers to follow-ups and
reported 0% where the true figure differs.
"""
import csv, glob, hashlib, json, os, re, sys

def packets(cell):
    d = os.path.join('captures/agenttest', os.path.basename(cell))
    fs = sorted(glob.glob(os.path.join(d, 'repair-packet-*.json')),
                key=lambda p: int(re.search(r'(\d+)', os.path.basename(p)).group(1)))
    out = []
    for f in fs:
        try:
            out.append(hashlib.sha256(json.load(open(f))['taskText'].encode()).hexdigest())
        except Exception:
            pass
    return out

rows = [r for r in csv.reader(open(sys.argv[1]), delimiter='\t')
        if r and r[0] != 'fixture' and not r[0].startswith('#')]
tot = stall = 0
detail = []
for r in rows:
    hs = packets(r[5])
    for i in range(1, len(hs)):
        tot += 1
        if hs[i] == hs[i - 1]:
            stall += 1
            detail.append(f'{r[0]}/{r[1]}/{r[2]} round {i+1}')
pct = f'{100*stall/tot:.0f}%' if tot else 'n/a'
print(f'stalled rounds: {stall}/{tot} = {pct}')
for d in detail:
    print(f'   {d}')
