---
name: telemetry
description: How to read SwiftStar session telemetry (captures, the analyze CLI, the wire's units and fields). Run `swiftstar-analyze` first; grep raw NDJSON only when the CLI cannot answer.
---

# Telemetry

How to answer "what happened in that session?" fast. The default workflow is
`swiftstar-analyze` — the parsers and the math live in production code
(`SwiftStarKit`), not in ad-hoc grep/jq.

## Rule 0: run `swiftstar-analyze` first

From the checkout:

```bash
swift run swiftstar-analyze list               # capture dirs, newest first, unusable ones flagged
swift run swiftstar-analyze summary --latest   # per-turn: decode avg, tokens, ctx, tools, Σsuffix
swift run swiftstar-analyze trace  --latest    # prefill syncs + compactions
swift run swiftstar-analyze diff A B           # paired-bill comparison (Σsuffix only)
```

Grep raw NDJSON only when the CLI cannot answer (a field the CLI doesn't
surface, a cross-tree question). The CLI reads all three trees.

## Where captures live and which shape each tree uses

| Tree | Producer | Shape |
|---|---|---|
| `captures/live/<ts>/` | the app (each session) | `wire.ndjson`, `agent.trace`, `agent.stderr`, `provenance.md`, `outcomes.ndjson` (one `TurnOutcome` JSON per finished turn) |
| `captures/agenttest/<ts>-*/` | `swiftstar-agenttest` | `wire.ndjson` (fixture tier); `run-config.json` for provenance |
| `captures/evidence/` | rescued `/tmp` evidence | the app's shape, copied verbatim |
| `captures/` root | `swiftstar-drive` | `wire.trace` + `CaptureWriter` output |

`captures/` is gitignored — the evidence is on disk, not in the repo.

## The wire's units (verified against ds4_agent.c)

- `ts` is **microseconds since boot** (`CLOCK_MONOTONIC`) — NOT nanoseconds.
  Deltas only; `provenance.md` anchors wall-clock. The decode average divides
  by 1_000_000.
- `generated` is a per-turn counter (resets each turn).
- `power` is the engine's **throttle percent (0-100)**, not watts.
- `status.error` is the engine's own error string (empty when healthy).
- Emitted but not surfaced by the CLI today: `prefill_done`/`prefill_total`,
  `ready.kv_bytes`/`scratch_bytes`/`model_bytes`, `tool.finish.calls`.

## The Σsuffix rule (matters for any cache/eval arithmetic)

In a prefill sync, `prompt == cached + suffix`, and `prompt` is **cumulative**
across syncs. So:

- Σprompt double-counts — it is a work metric, not a bill.
- Σcached/Σprompt is NOT a cache-hit rate.
- **Only Σsuffix is additively meaningful** — design evals and diffs around it.

## Notes

- `TurnOutcome` is Codable; `outcomes.ndjson` is one JSON line per finished
  turn (appended at turn end, only when session capture is enabled).
- The decode-average math (µs unit, first-`generating` baseline, prefill
  excluded) is pinned by `TurnSummaryTests.goldenReplayDecodeAveragesTrackEngineRates`
  — if it drifts from the engine's `gen_tps`, fix the math, not the test.
- Metrics/Diagnostics tabs are wired live from the session (the bundled golden
  capture is only the pre-spawn placeholder).
