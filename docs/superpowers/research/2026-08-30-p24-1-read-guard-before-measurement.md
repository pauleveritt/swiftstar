# P24.1 read-guard — the "before" measurement (2026-08-30)

The read-guard (`don't-re-read`) is P24's first feature cycle. This note
commits the *before* number — the re-read tax the guard attacks — as a
reproducible measurement, not prose. It pairs with the already-committed
[1809 prefill-tail findings](2026-08-27-1809-prefill-tail-findings.md),
which named the culprit and priced it from the trace; this note re-derives the
*count* from the wire with a committed tool, and cross-references the *token
cost* rather than recomputing it.

## Method

New `swiftstar-analyze` verb, `rereads [DIR|--latest]`, added this day. It
parses the capture's `wire.ndjson` with the production `PoolWireParser`
(no engine, no model — seconds), collects every `read`/`more` tool_request
per worker, and reports call counts, distinct paths, and redundant re-reads
(`calls − distinct`). `more` carries no `path` (it continues the file the
session last read), so it is attributed to that path and flagged windowed.

Run:

```
swift run swiftstar-analyze rereads live/20260827-200648
```

## Result

```
worker 0: 76 read/more call(s) across 21 distinct path(s) — 55 redundant re-read(s)
   34  Sources/SwiftStar/AgentView.swift  (windowed: 29)
   11  ROADMAP.md  (windowed: 10)
    5  docs/superpowers/plans/2026-08-24-p12-reliable-agency.md  (windowed: 4)
    4  Sources/SwiftStar/AgentController.swift  (windowed: 1)
    … (16 more paths at multiplicity 2)
```

- **76 read-family calls** (`read` 74 + `more` 2) across **21 distinct paths** →
  **55 redundant re-reads**. A perfect guard that short-circuited every
  re-read would have eliminated 55 of 76 read results from re-entering KV.
- **The enemy is named, not diffuse:** `AgentView.swift` alone is 34 of the 76
  calls (32 `read` + 2 `more`, both `more` confirmed to follow `AgentView.swift`
  reads) → **33 redundant**, 29 of them windowed. `ROADMAP.md` adds 11/10.
  Those two files are 45 of the 55 redundant reads.
- The findings' "31 reads / re-read 31×" is a prose conflation; the wire's
  ground truth is **32 `read` calls of `AgentView.swift` = 31 re-reads**, plus
  the 2 `more` continuations.

## Token cost (trace-derived, not re-derived here)

The [1809 findings](2026-08-27-1809-prefill-tail-findings.md) priced the
`AgentView.swift` re-reads from `agent.trace`: **30 prefill syncs with suffix
exactly 1,809 tokens, 29 of them tied to the `AgentView.swift` re-reads** =
54,270 tokens = **37.5% of the session's Σsuffix (144,631)**, 5.7 of the 12.7
prefill minutes. The `rereads` verb establishes the *multiplicity*; the trace
establishes the *price per re-read*. Together: 55 redundant reads, the top file
costing ~1,809 suffix tokens a re-read.

## Two facts the design must not lose

1. **"Redundant" is a ceiling, not the short-circuit count.** A re-read is
   short-circuitable only when the content is unchanged between the two reads.
   Here that holds everywhere: `outcomes.ndjson` records `mutations: []` and
   `validationRan: false` on all three outcomes — the session wrote nothing, so
   every redundant read is of unchanged content.
2. **Window coverage is the hard part.** 29 of `AgentView.swift`'s 34 reads are
   windowed (`start_line`/`max_lines`), and the findings show overlapping —
   not identical — windows ("250–350, 252–332"). The guard's answer "unchanged
   since turn N" is only honest when the model already holds the content it is
   asking for. A re-read of a *never-seen* window of an unchanged file must
   still be served (the model genuinely lacks those lines) — but the tax is
   then the small window result, not the ~1,809-token full-file tail. So the
   guard's rule needs *coverage* state per file (what the model has actually
   seen), not just an mtime/hash. This is P24.1's central design question.

## The "after" measurement

Same verb, plus a replay that marks which of the 55 redundant reads the guard
short-circuits under its coverage rule. Expected: the 33 `AgentView.swift`
re-reads → ≈ 52k suffix tokens avoided, to be confirmed at cycle end by the
paired-bill guardrail (`swiftstar-analyze diff`) on a live session, not by
self-report.
