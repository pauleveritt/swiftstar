---
phase: SU
cycle: SU.2
lifecycle: active
---

# SU.2 testable view logic implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** move four small clusters of untested, view-adjacent pure logic
into `SwiftStarKit`, with tests that pin current output, then simplify the
views to call them. No behavior change. The "framework change" and
"feature-based reorg" parts of the ROADMAP's SU.2 row are resolved in the
spec without code (`## 0`), not plan tasks.

**Spec:** `docs/superpowers/specs/2026-10-03-su2-testable-view-logic-design.md`

## Global constraints

- `swift build`, `just test`, `just integration` green after each task.
- Every new test must be shown to catch a regression in the logic it pins
  (confirm by reasoning through what a wrong implementation would produce),
  per `BRIEF.md`'s binding rule — these are pinning tests for existing
  behavior, not red/green TDD, since nothing here changes behavior.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

1. **`MetricsFormatting.rate`'s `" tok/s"` suffix must not get doubled** —
   `SessionView.bottomStatusText` currently appends it itself; dropping that
   literal is part of Task 1, not incidental → Task 1.
2. **`EngineToolCard.metadataLine`'s private `duration` helper stays
   non-public** — it's a formatting detail of one computed property, not a
   general-purpose API → Task 3.
3. **No output changes** — every task's test pins the exact string the old
   code produced, read from the code before moving it, not re-derived.

---

### Task 1: `MetricsFormatting` — `rate`, `bytes`, `contextTooltip`

**Files:**
- New: `Sources/SwiftStarKit/MetricsFormatting.swift` (`public enum
  MetricsFormatting`, three `static func`s)
- Modify: `Sources/SwiftStar/InspectorView.swift` (delete `rate(_:)`,
  `bytes(_:)`; call sites → `MetricsFormatting.rate`/`MetricsFormatting.bytes`),
  `Sources/SwiftStar/SessionView.swift` (delete `rateText(_:)`,
  `memoryDisplay(_:)`, `contextRingTooltip(used:size:)`; call sites →
  `MetricsFormatting.rate`/`.bytes`/`.contextTooltip`; `bottomStatusText`
  drops its own `" tok/s"` literal — spec `## 1`)
- New: `Tests/SwiftStarKitTests/MetricsFormattingTests.swift`

**Interfaces (produces):**
```swift
public enum MetricsFormatting {
    public static func rate(_ value: Double?) -> String       // "12.3 tok/s" / "—"
    public static func bytes(_ value: Int64?) -> String       // ByteCountFormatStyle / "—"
    public static func contextTooltip(used: Int, size: Int) -> String
}
```

- [ ] **Step 1:** `rateFormatsOneDecimalWithUnit` — `rate(12.34) ==
  "12.3 tok/s"`; `rateIsEmDashForNil` — `rate(nil) == "—"`.
- [ ] **Step 2:** `bytesFormatsByteCount` — `bytes(1_048_576)` matches
  `Int64(1_048_576).formatted(.byteCount(style: .memory))`;
  `bytesIsEmDashForNil` — `bytes(nil) == "—"`.
- [ ] **Step 3:** `contextTooltipMatchesTodaysWording` — `contextTooltip(used:
  512, size: 2048)` equals the exact string `SessionView.contextRingTooltip`
  produces today for the same inputs (25% used).
- [ ] **Step 4:** implement `MetricsFormatting`; update both call sites;
  `swift build` clean; both test tiers green → commit.

### Task 2: `EngineAnswer.summary`

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift` (`EngineAnswer` gains
  `public var summary: String?`, the moved `answerSummary` logic)
- Modify: `Sources/SwiftStar/SessionView.swift` (delete `answerSummary`;
  call site → `answer.summary`)
- Modify: `Tests/SwiftStarKitTests/EngineMetricsTests.swift` or a new test
  (whichever existing suite already constructs `EngineAnswer`)

**Interfaces (produces):** `EngineAnswer.summary: String?`.

- [ ] **Step 1:** `summaryJoinsDurationAndContext` — an `EngineAnswer` with
  both `durationMs` and `contextUsed`/`contextSize` set produces
  `"1.2s · ctx 420 / 8192"` (today's exact join); `summaryIsNilWithNoFields`
  — all three nil → `summary == nil`.
- [ ] **Step 2:** implement; update the call site; `swift build` clean;
  both test tiers green → commit.

### Task 3: `EngineToolCard.headerText` / `.metadataLine` / `.icon`

**Files:**
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift` (`EngineToolCard`
  gains `public var headerText: String`, `public var metadataLine: String`,
  `public var icon: String`; a private `duration(_:)` helper for
  `metadataLine` — spec `## 4`)
- Modify: `Sources/SwiftStar/ToolCardView.swift` (delete `headerText(_:)`,
  `metadataLine(_:)`, `duration(_:)`, `icon(for:)`; call sites → `card.headerText`,
  `card.metadataLine`, `card.icon`; `resolvedFileURL()` and
  `quickLookEligibleOps` are unchanged — not pure, stay in the view)
- Modify: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`

**Interfaces (produces):** `EngineToolCard.headerText: String`,
`.metadataLine: String`, `.icon: String`.

- [ ] **Step 1:** `headerTextIncludesPathWhenPresent` /
  `headerTextIsOpAloneWithNoPath` (today's exact two branches);
  `metadataLineJoinsStateAndDuration` (`running`/`succeeded`/`failed` ×
  with/without a finite non-negative duration, today's exact `" · "` join
  and the `<10s`/`≥10s` decimal-place split); `iconMatchesEachKnownOp` (one
  assertion per case in today's switch, plus the `default` fallback).
- [ ] **Step 2:** implement; update the call sites; `swift build` clean;
  both test tiers green → commit.

### Task 4: Close

- [ ] **Step 1:** ROADMAP SU.2 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

_(filled at close)_
