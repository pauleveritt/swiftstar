# SwiftStar SU.2 design: extract view-adjacent logic into tested Kit types

**Date:** 2026-10-03
**Status:** design, re-verified against current code before writing
**Phase:** SU — cycle SU.2
**Source:** ROADMAP.md's SU.2 row: "Not a framework change — all [15] test
files already use Swift Testing, no XCTest. Extract more view-adjacent
logic into plain, testable types, continuing the `EngineSessionModel`/
`EngineComposer` pattern, and consider a feature-based reorg so views stay
thin enough that Previews cover what tests can't." The "framework change"
and "feature-based reorg" halves are resolved below (confirmed / declined);
"extract more view-adjacent logic" is where this cycle's real work is,
scoped against what is actually in `Sources/SwiftStar/` today.

## Goal

Close a concrete, evidence-based testing gap: several small pure functions
live in the `SwiftStar` view target, untested (the fast tier can't reach
them — they're not in `SwiftStarKit`), and two pairs are near-duplicates
across files. Move them to `SwiftStarKit`, add tests that would catch a
regression, leave the views thinner. No behavior change — every moved
function's output is pinned by a new test before the view is simplified to
call it.

## 0. Resolved without code: "framework change" and "reorg"

- **Test framework: already Swift Testing everywhere, confirmed.** 15 test
  files today (one more than the ROADMAP text's "14" — `DefaultsKeyTests`,
  added in P32 after the row was written); `grep -rl "import XCTest"
  Tests/` returns nothing. Nothing to do.
- **Feature-based reorg: declined for this cycle.** `Sources/SwiftStar/` is
  11 files, 1,338 lines total (`SessionView.swift` largest at 473). A
  feature-based directory split earns its cost once navigating by file name
  alone gets hard; it doesn't yet. Revisit if the target grows substantially
  past this — not a decision to make speculatively now.

## 1. Two near-duplicate formatting pairs, both untested

Re-verified by reading every `private func`/`private var` in
`SessionView.swift`, `InspectorView.swift`, `ToolCardView.swift`:

- **Rate formatting.** `InspectorView.rate(_:)` → `"%.1f tok/s"` or `"—"`.
  `SessionView.rateText(_:)` → `"%.1f"` or `"—"`, with its one call site
  (`bottomStatusText`) appending `" tok/s"` itself. Same core format, two
  copies, same inputs (`Double?`), zero test coverage for either.
- **Byte formatting.** `InspectorView.bytes(_:)` (`Int64?`) and
  `SessionView.memoryDisplay(_:)` (`Int64`, since both call sites already
  unwrap first) both wrap `.formatted(.byteCount(style: .memory))` with
  `"—"` for nil. Same wrapper, two copies, zero test coverage.

**Fix:** one new `SwiftStarKit/MetricsFormatting.swift`:
`rate(_:) -> String` (bakes in `" tok/s"`, matching `InspectorView`'s
current output exactly — `SessionView.bottomStatusText` drops its own
`" tok/s"` literal to avoid doubling it), `bytes(_:) -> String` (takes
`Int64?`, matching `InspectorView`'s broader signature). Both call sites
in both files switch to `MetricsFormatting.rate`/`MetricsFormatting.bytes`;
`InspectorView.rate`/`bytes` and `SessionView.rateText`/`memoryDisplay` are
deleted.

## 2. `SessionView.contextRingTooltip` — untested, no duplicate, still worth moving

Pure function of `(used: Int, size: Int)`, computing a percentage and
formatting a tooltip string. No second copy exists, but it has the same
"untestable from the fast tier" problem as `## 1`, and it's the same kind
of metrics-formatting logic. Moves to `MetricsFormatting.contextTooltip(used:size:)`
alongside `rate`/`bytes`. `SessionView.contextRingTooltip` is deleted.

## 3. `SessionView.answerSummary` — untested, belongs on `EngineAnswer`

`private static func answerSummary(_ answer: EngineAnswer) -> String?`
(lines 256-263) builds the small "1.2s · ctx 420 / 8192" line under an
answer, from `EngineAnswer`'s own fields alone. It is a pure function of
one `EngineEvent.swift` type, with no view dependency at all — the natural
home is `EngineAnswer` itself, not a `private static` tucked into the view
that happens to render it.

**Fix:** `EngineAnswer` (in `SwiftStarKit/EngineEvent.swift`) gains a
computed property `public var summary: String?` with the moved logic.
`SessionView`'s call site becomes `answer.summary`; `SessionView.answerSummary`
is deleted.

## 4. `ToolCardView`'s four static functions — untested, belong on `EngineToolCard`

`ToolCardView.swift` already pulled `headerText(_:)`, `metadataLine(_:)`,
`duration(_:)`, and `icon(for:)` out to `static func`s (not instance
methods) — someone already noticed these don't need the view's state. They
just never crossed into `SwiftStarKit`, so the fast tier still can't test
them, and `EngineToolCard` (where three of the four naturally belong) is
defined one target away in `EngineTranscript.swift`.

**Fix:** move all four onto `EngineToolCard` itself, as computed properties
(no need for a stored function slot — `headerText`, `metadataLine`, `icon`
are each worth computing from a card):
- `EngineToolCard.headerText: String` (was `ToolCardView.headerText(_:)`)
- `EngineToolCard.metadataLine: String` (was `ToolCardView.metadataLine(_:)`;
  keeps a private `duration(_:)` helper in the same file, not public — it's
  an implementation detail of the one line that uses it)
- `EngineToolCard.icon: String` (was `ToolCardView.icon(for:)`, which took
  `card.tool.op`; becomes an instance property reading `tool.op` itself,
  dropping the parameter)

`ToolCardView.swift` calls `card.headerText`, `card.metadataLine`,
`card.icon` instead; the four static functions and `quickLookEligibleOps`'s
neighbor `resolvedFileURL()` stay (the latter touches `FileManager` and a
view-owned `workspace`, not pure — correctly stays in the view target).

## Out of scope

`SessionView.noticeText`, `.sessionActionTitle/Icon/Help`, `.trimmedInput`
— each a one-line wrapper around a single `Bool`/`Phase` with no real logic
to test (re-verified by reading each; none does more than a `?:` or a
single-case switch). Moving these would be relocation for its own sake, not
closing a testing gap. `EngineController`'s private helpers
(`resolveExecutablePath`, `catalogCacheKey(forPath:)`, `defaultWorkspace`)
already delegate to Kit functions (`EngineCommand.resolveExecutable`,
`CatalogCacheKey`, `ProjectRoot.locate`) and are covered by
`EngineControllerTests` in the integration tier — already following the
pattern this cycle continues, nothing to change.

## Success criteria

1. `swift build`, `just test`, `just integration` green after every task.
2. Every moved/consolidated function has a `SwiftStarKitTests` test that
   pins its current output — confirmed, for each, that mutating the
   implementation (mentally or by trial) would fail the test.
3. `grep -rn "private func rate\|private func bytes\|private func
   rateText\|private func memoryDisplay\|private func contextRingTooltip\|
   private static func answerSummary\|private static func headerText\|
   private static func metadataLine\|private static func icon" Sources/SwiftStar/`
   returns nothing.
4. `SessionView.swift`'s line count drops meaningfully (currently 473); no
   other file grows by more than the lines it gained from moved logic.
