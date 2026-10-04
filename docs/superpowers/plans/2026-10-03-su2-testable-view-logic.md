---
phase: SU
cycle: SU.2
lifecycle: closed
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

- [x] **Step 1:** `rateFormatsOneDecimalWithUnit` — `rate(12.34) ==
  "12.3 tok/s"`; `rateIsEmDashForNil` — `rate(nil) == "—"`.
- [x] **Step 2:** `bytesFormatsByteCount` — `bytes(1_048_576)` matches
  `Int64(1_048_576).formatted(.byteCount(style: .memory))`;
  `bytesIsEmDashForNil` — `bytes(nil) == "—"`.
- [x] **Step 3:** `contextTooltipMatchesTodaysWording` — `contextTooltip(used:
  512, size: 2048)` equals the exact string `SessionView.contextRingTooltip`
  produces today for the same inputs (25% used).
- [x] **Step 4:** implement `MetricsFormatting`; update both call sites;
  `swift build` clean; both test tiers green → commit. Done: `2a805a1`.

### Task 2: `EngineAnswer.summary`

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift` (`EngineAnswer` gains
  `public var summary: String?`, the moved `answerSummary` logic)
- Modify: `Sources/SwiftStar/SessionView.swift` (delete `answerSummary`;
  call site → `answer.summary`)
- Modify: `Tests/SwiftStarKitTests/EngineMetricsTests.swift` or a new test
  (whichever existing suite already constructs `EngineAnswer`)

**Interfaces (produces):** `EngineAnswer.summary: String?`.

- [x] **Step 1:** `summaryJoinsDurationAndContext` — an `EngineAnswer` with
  both `durationMs` and `contextUsed`/`contextSize` set produces
  `"1.2s · ctx 420 / 8,192"` (today's exact join, with grouping); `summaryIsNilWithNoFields`
  — all three nil → `summary == nil`.
- [x] **Step 2:** implement; update the call site; `swift build` clean;
  both test tiers green → commit. Done: `f5ba94c`.

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

- [x] **Step 1:** `headerTextIncludesPathWhenPresent` /
  `headerTextIsOpAloneWithNoPath` (today's exact two branches);
  `metadataLineRunningHasNoDuration` / `metadataLineSucceededUnderTenSecondsUsesOneDecimal`
  / `metadataLineFailedAtOrOverTenSecondsUsesNoDecimal` /
  `metadataLineIgnoresNegativeOrNonFiniteDuration` (today's exact `" · "`
  join and the `<10s`/`≥10s` decimal-place split); `iconMatchesEachKnownOp`
  (one assertion per case in today's switch, plus the `default` fallback).
- [x] **Step 2:** implement; update the call sites; `swift build` clean;
  both test tiers green → commit. Done: `6923a5c`.

### Task 4: Close

- [x] **Step 1:** ROADMAP SU.2 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

All three code tasks landed, each its own commit, build and both test
tiers green after every task. Test count grew from 129 fast / 30
integration (at SU.1's close) to 143 fast / 30 integration — 14 new tests,
all pinning behavior that existed before this cycle and was previously
untestable from the fast tier.

1. **`MetricsFormatting`** (`2a805a1`) — consolidates `InspectorView.rate`/
   `bytes` and `SessionView.rateText`/`memoryDisplay` (near-duplicate,
   both untested) plus `SessionView.contextRingTooltip` (untested, no
   duplicate) into `rate`/`bytes`/`contextTooltip`. Output confirmed
   identical, including `bottomStatusText`'s `" tok/s"` placement.
2. **`EngineAnswer.summary`** (`f5ba94c`) — moves `SessionView.answerSummary`
   onto the type it was already a pure function of.
3. **`EngineToolCard.headerText`/`.metadataLine`/`.icon`** (`6923a5c`) —
   moves four `ToolCardView` statics (already pulled out of instance
   context, just never crossed into `SwiftStarKit`) onto `EngineToolCard`.
   `icon` drops its `for op:` parameter.

Line counts dropped as expected: `SessionView.swift` 473 → 448,
`ToolCardView.swift` 114 → 77, `InspectorView.swift` 72 → 64.

The ROADMAP row's other two halves were resolved without code in the spec
(`## 0`): the test-framework claim confirmed (15 files, all Swift Testing);
the feature-based reorg explicitly declined as premature for an 11-file,
1,268-line view target — revisit if that target grows substantially.

Live-checked the built `.app` after each code task: launches and stays
running with no crash (no live engine available in this environment to
exercise the changed rendering paths with real data).
