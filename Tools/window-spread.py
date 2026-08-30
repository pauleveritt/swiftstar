#!/usr/bin/env python3
"""P24.1 falsifier: the window distribution per path in a capture.

The pre-registered failure condition (spec, Live validation) is:
    many distinct windows clustered on one region of one file.
That is the signature of the starvation loop. This prints, per path, the
read/more call count and every distinct (start_line/max_lines) window with its
multiplicity -- the same table the spec's Problem section shows for the 1809
baseline, so the two are directly comparable.
"""
import json, sys, collections

path_arg = sys.argv[1]
calls = collections.defaultdict(list)   # path -> [(start,count) or ('more',n)]
for line in open(path_arg + "/wire.ndjson"):
    try:
        e = json.loads(line)
    except Exception:
        continue
    if e.get("t") != "tool_request":
        continue
    name = e.get("name")
    if name not in ("read", "more"):
        continue
    params = {p.get("name"): p.get("value") for p in e.get("params", []) or []}
    if name == "more":
        calls["<more>"].append(("more", params.get("count", "-")))
        continue
    calls[params.get("path", "?")].append(
        (params.get("start_line", "-"), params.get("max_lines", "-")))

print(f"capture: {path_arg}")
total = sum(len(v) for v in calls.values())
print(f"{total} read/more call(s) across {len(calls)} distinct path(s)\n")
for p, ws in sorted(calls.items(), key=lambda kv: -len(kv[1])):
    distinct = collections.Counter(ws)
    print(f"  {len(ws):3d}  {p}   [{len(distinct)} distinct window(s)]")
    for w, n in distinct.most_common():
        start, mx = w
        print(f"          {n}x  start_line={start} max_lines={mx}")
    # The falsifier: many distinct windows on one file is the loop.
    if p != "<more>" and len(distinct) >= 5 and len(ws) >= 8:
        print(f"      ** FALSIFIER TRIPPED for {p}: "
              f"{len(distinct)} distinct windows over {len(ws)} calls **")
    print()
