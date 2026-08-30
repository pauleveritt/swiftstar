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
    if p == "<more>" or len(ws) < 5:
        print()
        continue

    # The falsifier is "many distinct windows CLUSTERED ON ONE REGION" — which
    # is two measurements, not one. Distinct windows alone are healthy: a model
    # walking a file asks for a different range each time and never repeats.
    # The starvation loop has both of these instead:
    #
    #   repeat rate  -- the same window asked again, because the answer never
    #                   contained what was asked for (baseline: 1.45)
    #   concentration -- the asks pile onto one narrow band of one file, the
    #                   region the model cannot reach (baseline: 14/22 in a
    #                   single 100-line band)
    repeat_rate = len(ws) / len(distinct)
    starts = [int(s) for s, _ in ws if str(s).isdigit()]
    concentration, band = 0.0, None
    if starts:
        for lo in range(min(starts), max(starts) + 1, 10):
            n = sum(1 for s in starts if lo <= s < lo + 100)
            if n / len(starts) > concentration:
                concentration, band = n / len(starts), (lo, lo + 100)
    print(f"      repeat rate   {repeat_rate:.2f} calls/window "
          f"({len(ws)} calls, {len(distinct)} distinct)")
    print(f"      concentration {concentration:.0%} of windowed asks in "
          f"lines {band[0]}-{band[1]}" if band else "      concentration n/a")
    if repeat_rate >= 1.3 and concentration >= 0.5:
        print(f"      ** FALSIFIER TRIPPED for {p}: windows repeat AND cluster "
              f"on one region — the starvation loop **")
    else:
        print(f"      -- no loop signature (needs repeat >=1.30 AND "
              f"concentration >=50%)")
    print()
