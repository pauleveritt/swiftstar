# SwiftStar P6 design: Diagnostics that can't lie

**Date:** 2026-08-22
**Status:** approved by delegation ("go through the spec and plan yourself; take your
own recommendations"). The phase list and architecture are settled by `BRIEF.md` /
`ROADMAP.md`; the inputs are the P5 capture format; the canonical finding is
`BRIEF.md`'s "diagnostics surface has a concrete first job."
**Phase:** P6 — Diagnostics that can't lie.

This spec is the authority on *how* P6 is done. It does not reopen the phase list, the
architecture, or the engine seam.

## Problem

P5 landed the inputs: the wire carries a handshake and a monotonic `ts`, and the capture
format includes the engine's `--trace` channel (compaction rebuild stats + per-turn
prefix-cache hits). P6 consumes them to build the deterministic analyzer behind the
Diagnostics tab.

`BRIEF.md` states the surface's concrete first job:

> tell the user they are at 92K, that prefill is 44 tok/s, that this is ~7x off their
> own session's baseline, and that compaction will not fix it because the prefix cache
> is already healthy.

And its operating rule:

> **Diagnostics computes deterministically; the model only phrases.** Swift computes the
> findings from a capture; the model's only job is turning a structured finding into a
> sentence.

Three facts shape P6's scope, all established in earlier phases:

1. **There is no model yet.** The model arrives with P7 (agent) / P8 (skills). So the
   "model only phrases" half cannot ship in P6; the deterministic *compute* half can, and
   it ships with a deterministic phrase renderer plus a seam a model can later replace.
2. **There is no live engine.** The Diagnostics tab is fixture-driven exactly like P4's
   Metrics tab: it runs the analyzer over a committed capture. Live `ds4-agent` wiring is
   P7 (the agent migration), and P6 must not spawn `ds4-agent` live (same reason as P4's
   sequencing note — the safety surface lands in P7).
3. **No new engine patch is needed.** Everything the analyzer needs is already on the
   wire (`status`/`ready` + `ts`) and in the trace (`compacted`, `prefill sync done`) —
   see the P11 research note's "P6" line and P5's D3.

## Gardenable facts (with citations)

- **The wire `status` event** carries `ctx_used`, `ctx_size`, `prefill_tps`, `gen_tps`,
  and `ts`; emitted at most once per 200 ms, immediately on state change, exact-repeat
  deduped (`external/ds4/docs/json-events.md`; `Sources/SwiftStarKit/WireEventParser.swift`
  already parses `StatusSnapshot`). The `ready` event carries the session memory budget.
- **The per-turn prefix-cache hit line** is on the trace, two shapes
  (`external/ds4/ds4_agent.c`):
  - the agent turn loop, `:12071`:
    `prefill sync done tool_round=%d prompt=%d cached=%d suffix=%d rc=%d %.3f ms`
  - the older sync site, `:5622`:
    `prefill sync done prompt=%d cached=%d suffix=%d rc=%d %.3f ms`
  `cached / prompt` is the prefix-cache hit fraction for that prefill. The committed
  `fixtures/agent/golden.trace` shows two healthy turns: `cached=958/1026` (93%) and
  `cached=1120/1138` (98%).
- **The compaction line** is on the trace only (deliberately suppressed on the wire),
  `ds4_agent.c:11769`:
  `compacted reason="<reason>" old=<bottom> new=<compacted.len> tail_start=<tail_start> tail=<bottom-tail_start>`
  where `old` is the pre-compaction transcript length, `new` the rebuilt length
  (system prompt + summary + tail), and `tail` the retained verbatim tail. `reason` is
  escaped by `agent_trace_escaped` (`ds4_agent.c:1509`: `"` → `\"`, newline → `\n`, …).
- **The measured curve** (`docs/harvest/telemetry-findings.md`): per-turn prefill
  throughput ~300–360 tok/s at `ctx_used` ≈ 3,400 down to ~41–46 tok/s at ≈ 92,500 —
  ~7x, compute-bound (98.0% GPU), and **distinct from the prefix cache**, which stays
  healthy across growth and across a real compaction. "A prefix cache does not fix it,
  and compaction only helps by making the context smaller."
- **Absolute anchoring** (learning #1, already encoded in `DialLogic`): the degradation
  tracks *absolute* `ctx_used`, not a fraction of `ctx_size`. `DialLogic`'s
  `contextWarningTokens` (37,500) and `contextCriticalTokens` (75,000) are the depth
  anchors; P6's own constants follow the same re-anchor discipline.
- **Facts work, rules of conduct do not** (`BRIEF.md`, from `local-ai-pi`): a computed
  fact phrased by a small model is good; "analyze this telemetry and recommend
  improvements" produces fluent, plausible, unfalsifiable prose. P6 ships computed facts
  and a deterministic phrase; the model is explicitly *not* asked for judgment.

## Decisions

### D1 — The analyzer is pure; findings are typed values; phrasing is a separate seam

A new `DiagnosticsAnalyzer` (SwiftStarKit, pure, `Sendable`) turns parsed inputs into a
typed `[Finding]`. `Finding` is an enum with associated values carrying the computed
numbers — testable by value, never by grepping a rendered sentence (binding rule 3). A
separate `DeterministicPhraser` renders a `Finding` to a sentence. That split *is* the
BRIEF's "compute vs. phrase" line: the `Finding` is the computed part, the phraser is the
phrasing part, and a model phraser later implements the same protocol without touching the
analyzer.

```swift
public struct DiagnosticsAnalyzer: Sendable {
    public init() {}
    public func analyze(
        events: [WireEvent],
        trace: [TraceEvent]
    ) -> [Finding]
}
```

The analyzer does not re-parse the wire — it consumes the already-parsed `[WireEvent]`
(`WireEventParser` exists). Reusing the production parser, not a re-reader, is the same
compose-don't-copy rule `swiftstar-drive` follows.

### D2 — What the analyzer computes (the findings)

Each finding is a pure function of the folded inputs; severity reuses `DialLogic.Severity`
(`healthy` / `warning` / `critical`).

| Finding | Emitted when | Computed facts | Severity |
|---|---|---|---|
| `.contextPosition` | always (latest status) | latest `ctx_used`, `ctx_size` | `DialLogic.contextSeverity(ctxUsed)` |
| `.prefillThroughput` | any prefill sample exists | current prefill rate (last `prefill_tps > 0`) | `.healthy` (informational) |
| `.baselineDrift` | `ratio ≥ degradationWarningRatio` | baseline rate, current rate, `ratio = baseline / current` | `.critical` if `ratio ≥ degradationCriticalRatio`, else `.warning` |
| `.prefixCache` | any `prefillSync` parsed | `hitFraction = cached / prompt` (most recent) | `.healthy` if `≥ prefixCacheHealthyFraction`, else `.warning` |
| `.compactionObserved` | one per parsed `compaction` | `old`, `new`, `tail` | `.healthy` (informational) |
| `.compactionVerdict` | deep **and** degraded (below) | a `CompactionVerdict` | matches the degradation severity |

**Baseline = the session's own early prefill rate.** Among `StatusSnapshot`s with
`prefill_tps > 0` and `ctx_used ≤ baselineWindowTokens`, take the maximum rate. **Current
= the last `prefill_tps > 0`.** Every session starts at small context, so a baseline
exists from the first turn; the ratio is the session measuring itself, not an external
calibration.

**The "would compaction help" rule** (`compactionVerdict`) fires only when the session is
both deep (`ctx_used ≥ DialLogic.contextWarningTokens`) and degraded
(`ratio ≥ degradationWarningRatio`). Its answer is then deterministic:

```swift
public enum CompactionVerdict: Equatable, Sendable {
    case willNotFixRate(cacheHitFraction: Double)  // cache healthy → size is the cause
    case mayRecoverCache(cacheHitFraction: Double) // cache missing → rebuild may help
    case unknown                                    // no prefillSync sample to judge
}
```

- `willNotFixRate` when the most recent `prefillSync` shows `hitFraction ≥
  prefixCacheHealthyFraction`: the slowdown is context size, not cache misses; compaction
  shrinks context but costs a full rebuild and does not fix the rate.
- `mayRecoverCache` when `hitFraction < prefixCacheHealthyFraction`: a rebuild could
  recover cache hits — the case the measurement says does *not* occur in practice, but the
  analyzer must still distinguish it, because the finding's whole point is telling the two
  apart.
- `unknown` when no `prefillSync` line was parsed (the trace is present but silent on
  cache).

This is the first job, mechanized: "at 92K, 44 tok/s, ~7x off baseline, and compaction
won't fix it *because the prefix cache is already healthy*" is exactly
`.contextPosition` + `.prefillThroughput` + `.baselineDrift` + `.compactionVerdict(.willNotFixRate)`.

### D3 — `TraceParser` and `TraceEvent` (SwiftStarKit)

A new streaming parser shaped like `WireEventParser`: feed one trace line, get a typed
event or nil. It is forward-compatible the same way — anything unrecognized is
`.ignored`, never a refusal (the trace is a diagnostic side-channel, not the
handshake-guarded wire).

```swift
public enum TraceEvent: Equatable, Sendable {
    case compaction(reason: String, old: Int, new: Int, tailStart: Int, tail: Int)
    case prefillSync(prompt: Int, cached: Int, suffix: Int, rc: Int, ms: Double)
    case ignored(String)
}
```

Each trace line is `YYYY-MM-DD HH:MM:SS.mmm <message>` (`agent_trace_time`, then a
space). The parser strips the 23-char wall-clock prefix and matches the message:

- `compacted reason="<escaped>" old=<n> new=<n> tail_start=<n> tail=<n>` — read the quoted
  reason until the closing unescaped `"`, then the four `key=<int>` fields.
- `prefill sync done [tool_round=<n>] prompt=<n> cached=<n> suffix=<n> rc=<n> <ms> ms` —
  `tool_round` is optional (two call sites above); the analyzer needs `prompt` and
  `cached`; the other fields are carried for fidelity.
- anything else (token dumps, `sysprompt kv hit`, `tokens label=…`, user/prompt echoes) →
  `.ignored`.

Trace timestamps are deliberately **not** carried: the analyzer's findings are
session-level (did compaction happen; what is the latest cache hit), and trace-internal
order suffices. No wire↔trace time correlation is needed by any finding.

### D4 — Constants, re-anchorable (SwiftStarKit)

Depth thresholds are reused from `DialLogic` (absolute, already reviewed). P6's own
constants live in `DiagnosticsLogic` as named constants, following the same "re-anchor
before trusting far from where it was measured" rule the brief mandates:

```swift
public enum DiagnosticsLogic {
    public static let baselineWindowTokens = 8_192     // ctx_used ceiling for baseline samples
    public static let degradationWarningRatio = 2.0
    public static let degradationCriticalRatio = 3.5
    public static let prefixCacheHealthyFraction = 0.5  // cached/prompt floor for "healthy"
}
```

`degradationCriticalRatio = 3.5` is deliberately below the measured ~7x: the analyzer
should flag a real problem long before it is catastrophic, and the exact ratio travels in
the finding's payload regardless of threshold.

### D5 — The surface: `DiagnosticsModel` + `DiagnosticsView`, fixture-driven

Replace the Diagnostics `PlaceholderView`. `DiagnosticsModel` (SwiftStar, `@Observable`,
`@MainActor` — the same shape as `MetricsModel`) loads the bundled capture, runs it through
`WireEventParser` + `TraceParser` + `DiagnosticsAnalyzer`, and exposes `[Finding]`. The
view renders a severity-colored list, one row per finding, with the deterministic phrase as
the headline and the typed facts beneath. A banner states the results are computed from a
recorded capture, not a live engine (the same honesty rule P4's `isReplayingWire` enforces).

To feed the analyzer its two inputs from a bundled capture, `SwiftStarAppKit` bundles
`golden.trace` beside the existing `golden.ndjson` and gains a small loader that returns
`(events: [WireEvent], trace: [TraceEvent])`. The loader composes the production parsers;
it does not re-read. (No finding needs the capture manifest — every fact it reports comes
from the wire or the trace — so the manifest is not plumbed through unused.)

### D6 — Evidence floor and fixtures (binding rule 6)

Binding rule 6: no analyzer is done until it has accepted a known-good capture and
rejected a known-broken one, each asserted by naming the fixture.

- **Accept known-good:** the committed `fixtures/agent/golden.ndjson` + `golden.trace`
  (two shallow turns, 93%/98% cache hits, no compaction). The analyzer over the real
  capture must emit **no** `.critical` and **no** `.baselineDrift`/`.compactionVerdict`
  (it never got deep or degraded).
- **Reject known-broken:** a committed **synthetic** pathological capture — clearly labeled
  synthetic, its numbers reproducing the measured curve from `telemetry-findings.md` —
  under `fixtures/diagnostics/pathological.ndjson` + `pathological.trace` + a
  `provenance.md` stating the label and the citation. The analyzer must emit
  `.contextPosition(.critical)`, `.baselineDrift(.critical)`, and
  `.compactionVerdict(.willNotFixRate)`. The synthetic fixture is **not** a fake engine
  (binding rule "fakes are generated from captures" is about fake *binaries* that simulate
  the wire); it is typed test input to a pure decision function, exactly like the
  synthetic sequences already used by `DialLogicTests`. It is labeled and cited so it can
  never be mistaken for a verbatim capture.

The fast tier (no subprocess, no network) reads fixtures by `#filePath`-relative path, the
same way `WireEventParserTests` already reads `golden.ndjson`. No new live capture is
required: the canonical 7x finding cannot be reproduced at the everyday 150,000 setting
anyway (the brief's own caveat — compaction was never observed there across two attempts),
so its evidence is, and can only be, the documented curve.

### D7 — Scope discipline

P6 does **not** ship: live `ds4-agent` (P7), model phrasing (deterministic only — the
`DeterministicPhraser` is the shipped renderer; a model phraser lands when a model exists),
telemetry-to-disk / `MachineSnapshot` capture (still deferred from P5 D6 — the analyzer
works on wire + trace, not OS machine stats), `ds4-server` capture (chat SSE is not the
diagnostics wire), any engine patch (none needed), or automated live capture in CI
(`just capture` stays manual, never-in-CI).

## Done when

1. **`TraceParser` + `TraceEvent` (fast tier):** both `prefill sync done` shapes parse;
   `compacted` parses with an escaped `reason`; unrecognized lines are `.ignored`; the
   parser runs over `fixtures/agent/golden.trace` without refusing. Every new test shown
   to fail first.
2. **`DiagnosticsAnalyzer` (fast tier):** each finding's rule is a tested pure function —
   baseline/current extraction, degradation ratio and severity, prefix-cache health,
   compaction verdict (all three branches), depth severity. Assertions are on the typed
   `Finding` values, never on rendered strings (binding rule 3).
3. **`DeterministicPhraser` (fast tier):** renders each finding to a sentence built only
   from the finding's own numbers; a model phraser can later replace it without touching
   the analyzer.
4. **Evidence floor:** the analyzer over the real `golden` capture accepts (no
   critical/degradation findings) and over the synthetic `pathological` fixture rejects
   (`contextPosition(.critical)`, `baselineDrift(.critical)`,
   `compactionVerdict(.willNotFixRate)`), each test naming the fixture.
5. **Surface:** the Diagnostics tab is a real view driven by `DiagnosticsModel`,
   fixture-driven, with the recorded-capture banner. No live engine, no model.
6. **ROADMAP** marks P6 complete; concept budget reviewed — **finding**, **baseline**, and
   **diagnostic** earn definitions; nothing else enters.
