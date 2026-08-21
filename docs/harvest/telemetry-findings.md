# Harvest: the telemetry findings

**Source:** `docs/superpowers/specs/2026-08-21-agent-telemetry-findings.md`,
committed at `b7cc10a` in the `feat/agent-mode-laguna` worktree of
`~/projects/ds4-control`. Live-measured against the real `ds4-agent` and Laguna
S 2.1 on this hardware, using the driver described in
[capture-driver.md](capture-driver.md).

This is the single most important input to SwiftStar's design. It is the reason
the metrics surface leads with context rather than memory, the reason the
diagnostics surface exists at all, and the mechanism behind the subagent-pool
isolation hypothesis.

## The headline finding

**Per-turn prefill throughput degrades roughly 7x as accumulated context
grows.**

| `ctx_used` | prefill throughput |
|---:|---|
| ≈ 3,400 | ~300–360 tok/s |
| ≈ 92,500 (62% of a 150,000 session) | ~41–46 tok/s |

It is **compute-bound, not overhead**: the high-context session averaged
**98.0% GPU utilization** against **35.9%** for the low-context one, with CPU
under 7% in both.

It is **distinct from the prefix cache**, which the same investigation
independently confirmed stays healthy across sustained growth *and* across a
real compaction rewrite — a 1,371 → 60 token collapse, about as clean a
confirmation as this kind of measurement gets.

The mechanism is consistent with attention cost scaling with total context
length regardless of how little of it is new. A prefix cache does not fix it,
and compaction only helps by making the context smaller.

The findings document states the design consequence directly: if the project
wants a dial that predicts thermal and power cost, **context size over prefill
throughput is the one with a real, measured, growing cost curve behind it.**
Round-trip count and idle draw were both measured and both look fine.

## What else was checked, and came back clean

- **Prefix cache health** across compaction — confirmed.
- **Idle cost** — genuinely near-nil, well under 1W average. The claim that the
  poll loop blocks for free holds up.
- **Round-trip counts** — no evidence of waste, though on a small sample.
- **Memory** — no overshoot; actual resident and footprint stayed well under
  the planned budget in every session captured.

**The document's own recommendation:** no urgent code change is justified by
this data. Waste, where it exists at all, is not the kind fixable by a targeted
patch — it is the physics of prefilling a large context on this hardware, which
the next phase's dials should *surface* rather than try to fix.

## Limits that must travel with the finding

Quoting the number without these is misuse.

- **Compaction was never reached at the everyday ctx 150,000 setting**, across
  two real attempts. It was observed only at ctx 32,768, whose soft limit is
  one third the growth needed. Both failures trace to the same measured cause:
  at 150,000 ctx, a single dense read starts costing minutes, and no per-turn
  timeout the investigation set was generous enough to outrun the fifth
  consecutive turn's climbing cost.
- **No concurrent desktop load.** Every capture ran on an otherwise-idle
  machine. A real machine would likely show higher idle watts and different
  GPU-contention effects.
- **No organic think-time.** The driver sends the next prompt the instant a turn
  reports ready. Real sessions spend more wall time idle.
- **Narrow workload.** Single-topic technical file-reading plus one reasoning
  puzzle. Mixed real sessions may distribute differently.
- **Short duration.** The longest capture was ~24.5 minutes. Thermal and
  memory-pressure effects emerging over an hour or more were not observed.

## What the predecessor's UI prototype learned, before it was retired

Between 2026-08-21 and this project's start, DS4 Control prototyped the dials
this finding implies. Four commits (`352da22`, `c3a3545`, `d635b01`,
`995589b`) produced results worth more than the code, and SwiftStar inherits
the results rather than the widgets.

- **Fraction is the wrong anchor, and this was caught rather than shipped.**
  The context dial first colored by `ctx_used / ctx_size` with thresholds shaped
  from the curve above (warning at 25%, critical at 50% — deliberately not the
  generic 70/90). A review found the anchor unsound: the degradation tracks
  *absolute* `ctx_used`, and `ctx_size` ranges 256k–1M by RAM and variant plus
  any user override, so the same percentage is a different token count on a
  different machine. It fires late on a big context and early on a small one.
  The prototype documented the caveat rather than silently trusting it.
  **SwiftStar anchors on absolute tokens.**
- **A live numeric readout jitters unless it is fixed-width.** Embedding a rate
  in a variable-length string moves the whole line left and right on every tick.
  The fix was structural: the numbers get a fixed-width prefix and only the
  trailing message moves. Same reasoning made the dial a fixed-size ring —
  jitter-proof by construction rather than by positioning.
- **The wire reports one rate at a time.** `prefillTPS` and `genTPS` are never
  both non-zero, so a readout showing both must ratchet — hold the last non-zero
  value for each — or it flickers to zero every other tick. **This is a wire
  fact and belongs in the parser's model, not in a view.**
- **A stroked ring is almost unhoverable by default.** SwiftUI hit-tests a
  stroked `Circle` on the stroke line itself, not the enclosed area, so a 15pt
  ring's tooltip is nearly unreachable until the hit region is widened to the
  whole frame.
- **Memory and context want different thresholds.** The prototype's second dial
  — child footprint against planned budget — deliberately kept generic severity
  thresholds, and has a test asserting it does *not* inherit the context ring's
  curve-shaped ones. Two dials, two anchors, on purpose.
- **"Prompt" and "Decode" are the user-facing words** for prefill and
  generation.

One structural note worth more than any of them: every one of these behaviors
was tested as a **pure function** — threshold color, fraction, ratchet, tooltip
text, fixed-width formatting — with no view instantiated. That is the
`SwiftStarKit` split working before the split existed, and it is the strongest
available evidence that the split is right.

## What SwiftStar does about it

1. **Metrics (P4)** leads with `ctx_used` and prefill throughput, alongside
   memory, GPU, CPU, and power.
2. **Diagnostics (P6)** computes, deterministically: where you are in your
   context, what your prefill throughput is, how far off your own session's
   baseline that is, and whether compaction would help. The model phrases the
   finding; it does not compute it.
3. **Anything that keeps context small becomes a performance feature** —
   cheap fresh sessions, condensing tool results before they enter KV (P9),
   context-isolated subagents (P11).
4. **The isolation hypothesis gets a mechanism, not just a motivation.** A
   single long-lived orchestrator session pays a compounding tax as its context
   grows; N subagents each working in a small isolated context do not. That is
   why P11's own measurement gate asks whether any wall-clock win correlates
   with subagent context staying small — confirming it would upgrade
   "isolation seems to help" to "isolation helps for a known, measured reason."
