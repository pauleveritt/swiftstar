# Agent test telemetry — GLM 5.2 review + engine investigation (2026-08-23)

> **Superseded as a live finding** by [`2026-08-25-local-model-agency.md`](../2026-08-25-local-model-agency.md). Retained as the evidence record for the GLM 5.2 telemetry critique and the ctx_used/generatedTokens engine trace, plus the before/after bounding-fix measurements.

**Status:** the first live run's telemetry was reviewed adversarially by GLM 5.2
(`z-ai/glm-5.2`), and the suspect metrics were traced into the engine. The
verdict: the metrics as first reported were not trustworthy, and the analysis
made of them was selection, not analysis.

## GLM 5.2's findings (accepted)

1. **"turns = 1 per phase" is the harness's segmentation, not the agent's loop.**
   38 tool calls cannot be one turn in any meaningful sense. The right primitive
   is tool-call rounds, which we did not count.
2. **`generatedTokens` ≈ 393/393/351 is almost certainly a cap, not a measurement.**
   Two phases byte-identical at 393 is not coincidence. If the model is capped at
   ~393 tokens while making 38 tool calls, it cannot hold its own write contents
   in its output buffer — which reframes "re-read is verification" as "the model
   is losing its own writes."
3. **The ctx drop (15515 → 20595 → 5433) was unexplained and handwaved.** The
   "Phase 3 = learned the workspace" reading ignored the datapoint that falsifies
   it.
4. **"Exploration-heavy" misread the Phase 1 trace.** The first 19 and last 19
   tool calls are near-isomorphic — the model ran the same playbook twice (a
   recovery/retry/flush), not a linear exploration. The honest reading: "the
   model did Phase 1 twice and we charged it for one phase."

## Engine investigation (what the metrics actually are)

- **`ctx_used`** is `ds4_session_pos(w->session)` at turn end — the session's
  cumulative token position. The Phase 3 drop (5433 < 15515) is a **pre-turn
  compaction**: the reused worker session crosses a soft limit (~20k) and
  compacts, discarding the accumulated head. So the "fold-forward" of the model's
  *context* across phases is lossy at ~20k — the code folds forward via the
  checkout, but the model's memory of prior phases is compacted away.
- **`generated`** is a turn-scoped local in `worker_run_turn`; `last_turn_generated`
  is captured at turn end. The uniform ~393 needs a further look but is consistent
  with a concise model emitting mostly tool-call syntax.

## Fixes applied

- Harness reports **tool-call count** (not "turns") as the granular metric, and
  labels ctx as `ctx_pos` (session position), not a per-phase total.
- `PoolOrchestrator` gained a **read cache** (unchanged re-read answers "unchanged
  since last read" — the don't-re-read lever) and a **vetted `bash`** (the packet's
  validation command is the only shell the worker may run — the feedback loop).
- The harness sets `validationCommand` to a light import check so the worker can
  self-check its code mid-turn.

## Second look (2026-08-23, after the fixes)

**The bounding fixes worked.** Re-running the easy spec with the read cache +
vetted bash + bounding prompt + 16k ctx + 30-tool budget: **elapsed 708s → 107s**,
Phase 1 tool calls 38 → ~10, re-reads ~10 → 1, ctx bounded at ~9.7k (no
compaction), acceptance still green. The analyzer now prints per-phase rounds,
distribution, repeated-identical calls, and re-reads mechanically.

**A real bug found by the capture.** The captured wire carries BOTH `tool`
transcript events (175) and `tool_request` execution events (20) for the same
calls, and `TurnOutcomeBuilder.finish()` concatenated both — double-counting
(harness said 40 tool calls, the wire has 20). Fixed: host-tools mode prefers the
`tool_request` view. This also fixes the app's `lastTurnOutcome` telemetry.

**Model variance, observed.** The implementer's tool-call count varies widely
across runs (Phase 1: ~5, ~19, and >30 tool calls). A thrashing run now hits the
30-tool budget and returns `budgetExceeded` — the correct budget-or-receipt
behavior (D8), and the reason n=4 will matter once we're happy with the
instrument.
