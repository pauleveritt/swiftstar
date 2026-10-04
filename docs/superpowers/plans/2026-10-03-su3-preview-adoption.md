---
phase: SU
cycle: SU.3
lifecycle: closed
---

# SU.3 Preview adoption implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** a `#Preview` for each of the 8 views named in the ROADMAP row,
each showing a representative, fixture-backed state. One new
`EngineController` initializer makes the fixture states possible without
spawning a real process. No test-tier change; previews are verified by
rendering (`RenderPreview` MCP tool), not `#Test`.

**Spec:** `docs/superpowers/specs/2026-10-03-su3-preview-adoption-design.md`
(see its 2026-10-04 amendment: views move to a `SwiftStarUI` library target).

**Amended 2026-10-04.** Task 2's first `RenderPreview` failed: previewing an
*executable* target requires the Xcode-only `ENABLE_DEBUG_DYLIB` build
setting, which a bare SwiftPM package has no way to set (no project editor,
nothing in `Package.swift`; Apple's forum answer, thread 812649, confirms it
and recommends moving views to a library target). New Task 2 does that split;
the old Tasks 2–5 are now 3–6, with paths moved from `Sources/SwiftStar/` to
`Sources/SwiftStarUI/`.

## Global constraints

- `swift build`, `just test`, `just integration` green after each task.
- Every `#Preview` confirmed to actually render (not just compile) via the
  `RenderPreview` MCP tool before its task is considered done.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

0. **The split is a pure move plus access control** — no logic change, and
   `Tools/make-app.sh` output still launches and passes the markdown
   resource self-test → Task 2.

1. **Fixture transcripts must go through `EngineSessionModel.apply`**, the
   same fold a real session uses — not a hand-built `EngineTranscript` that
   could drift from what `apply` actually produces → Task 1.
2. **The new `EngineController(model:)` initializer must not read
   `UserDefaults` or install the catalog-reload observer** — previews must
   not have a side effect on the real app's persisted settings → Task 1.

---

### Task 1: `EngineController(model:)` and `PreviewFixtures.swift`

**Files:**
- Modify: `Sources/SwiftStar/EngineController.swift` (new `init(model:
  EngineSessionModel)`)
- New: `Sources/SwiftStar/PreviewFixtures.swift` (`EngineController.previewIdle`,
  `.previewRunning`; `EngineToolCard.previewRunning`, `.previewSucceeded`,
  `.previewFailed`)

**Interfaces (produces):**
```swift
extension EngineController {
    init(model: EngineSessionModel)
    static var previewIdle: EngineController { get }
    static var previewRunning: EngineController { get }
}
extension EngineToolCard {
    static var previewRunning: EngineToolCard { get }
    static var previewSucceeded: EngineToolCard { get }
    static var previewFailed: EngineToolCard { get }
}
```

- [x] **Step 1:** implement; `swift build` clean; both test tiers green
  (no test-tier surface added, this is a build-correctness check) → commit
  (`92dfc59`).

### Task 2: Split views into a `SwiftStarUI` library target

**Files:**
- Modify: `Package.swift:10` (`.library(name: "SwiftStarUI")` product —
  Xcode makes package schemes per product, and previews need the
  `SwiftStarUI` scheme active), `Package.swift:31` (new `.target(name: "SwiftStarUI")` with the
  executable's current dependencies and `swiftSettings`; `SwiftStar` keeps
  `resources: [.process("Resources")]` and depends only on `SwiftStarKit` +
  `SwiftStarUI`), `Package.swift:49` (integration tests depend on
  `SwiftStarUI` instead of `SwiftStar`)
- Move (`git mv`): every file in `Sources/SwiftStar/` except
  `SwiftStarApp.swift` and `Resources/` → `Sources/SwiftStarUI/`
- Modify: `Sources/SwiftStarUI/EngineController.swift:10` (`public` class,
  `init()`, `isActive`, `beginTerminating()`, `quit()`),
  `MainView.swift`, `SettingsView.swift` (`public` type + `init` + `body`),
  `MarkdownText.swift` (`public` `runResourceSelfTestIfRequested()`)
- Modify: `Sources/SwiftStar/SwiftStarApp.swift` (`import SwiftStarUI`)
- Modify: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift:3`
  (`@testable import SwiftStarUI`)

**Interfaces (produces):** module `SwiftStarUI`; `public` only what
`SwiftStarApp.swift` touches (listed above), everything else stays internal.

**Proves it:** `RenderPreview` on `SessionView`'s `#Preview` returns an image,
not the `ENABLE_DEBUG_DYLIB` error; `just app` then
`DS4_SELFTEST_MARKDOWN=1 .build/SwiftStar.app/Contents/MacOS/SwiftStar
--markdown-selftest` prints `DS4_SELFTEST_MARKDOWN: OK`.

- [x] **Step 1:** commit the move alone. `git mv` keeps the three
  uncommitted Task 3 `#Preview` blocks (`SessionView`, `MainView`,
  `InspectorView`) unstaged, and they ride along to the new paths.
  `swift build`, `just test`, `just integration` green; the `RenderPreview`
  check above uses the in-tree `SessionView` block → commit (`42f9707`,
  `0e0de4a`). Proof ran on `InspectorView`: `SessionView` gets past the dylib
  error but crashes the preview agent (see Task 3).

### Task 3: `SessionView`, `MainView`, `InspectorView` previews

**Files:**
- Modify: `Sources/SwiftStarUI/SessionView.swift`, `Sources/SwiftStarUI/MainView.swift`,
  `Sources/SwiftStarUI/InspectorView.swift` (one `#Preview` each, using
  `EngineController.previewRunning` via `.environment(...)`)

**Interfaces:** none.

**Known at start:** with the `SwiftStarUI` scheme active, `SessionView`'s
preview crashes `XCPreviewAgent`: a Swift cast failure in SwiftUI's
`DebugReplaceableViewStorage` around `HStack<ValueGaugeView, Text>` +
`NativeTooltipModifier`. `InspectorView`'s preview renders.

- [x] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering (not blank, no crash) via `RenderPreview` → commit (`40d598a`,
  `78739be`, `2e6dc6a`). The crash was the fixture, not the view:
  `previewRunning` never left `.idle`, so `SessionView`'s auto-start wiped
  it; fixed with `didStart()`. Fixture controllers also skip the catalog
  load (no `ds4-dogfood` spawn) and add the user row via `send`. Still open:
  the memory widget's lone-`if` may hit the same crash in Xcode Debug runs
  of the real app when GPU metrics disappear (view change, out of scope).

### Task 4: `SettingsView`, `PromptBubble`/`ThinkingDisclosure`, `ValueGaugeView` previews

**Files:**
- Modify: `Sources/SwiftStarUI/SettingsView.swift` (one `#Preview`)
- Modify: `Sources/SwiftStarUI/PromptBubble.swift` (two `#Preview`s for
  `PromptBubble` — plain and `queued: true` — one for `ThinkingDisclosure`)
- Modify: `Sources/SwiftStarUI/ValueGaugeView.swift` (three `#Preview`s, one
  per `Severity` case)

**Interfaces:** none.

- [x] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering via `RenderPreview` → commit (`1ff466b`).

### Task 5: `ToolCardView`, `MarkdownText` previews

**Files:**
- Modify: `Sources/SwiftStarUI/ToolCardView.swift` (three `#Preview`s —
  `running`/`succeeded`/`failed`, using `EngineToolCard.previewRunning`/
  `.previewSucceeded`/`.previewFailed`)
- Modify: `Sources/SwiftStarUI/MarkdownText.swift` (one `#Preview` with a
  short sample mixing a heading, code block, and inline emphasis)

**Interfaces:** none.

- [x] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering via `RenderPreview` → commit (`48757dd`).

### Task 6: Close

- [x] **Step 1:** ROADMAP SU.3 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

All five build tasks landed; `swift build`, `just test` (143) and
`just integration` (30) green after every task; every preview confirmed
rendering through Xcode's `RenderPreview` MCP, driven over `xcrun
mcpbridge` with the `SwiftStarUI` scheme active.

1. **Task 1** (`92dfc59`): `EngineController(model:)` and `PreviewFixtures.swift`.
2. **Task 2** (`42f9707`, `0e0de4a`): added mid-cycle (amendment `6ed38a6`).
   An executable target of a bare package can't be previewed (Xcode-only
   `ENABLE_DEBUG_DYLIB`), so every view, `EngineController` and the fixtures
   moved to a `SwiftStarUI` library target. It also needed a library
   product: Xcode generates package schemes per product only.
3. **Task 3** (`40d598a`, `78739be`, `2e6dc6a`): `SessionView`'s preview
   crash was the fixture, not the view. `previewRunning` never left `.idle`,
   so the auto-start wiped it; fixed with `didStart()`. Fixture also gains
   the user row via `send`, as a real turn does.
4. **Tasks 4–5** (`1ff466b`, `48757dd`): the remaining previews; 14 blocks
   across the 8 views in all.
5. **Final review fixes** (`47207d0`): fixture controllers neither load the
   catalog nor start the engine (`isFixture` guard), so no preview spawns
   `ds4-dogfood`; `BRIEF.md` targets updated to four; stale fixture path;
   the fixture doc comment reworded so success criterion 2's grep is exact.

**Diverged from "additive only":** the target split and `public` modifiers
(per the spec amendment), and the `isFixture` guards in
`loadCatalogIfNeeded()` and `start()`, which are production-code logic.
They're inert in the real app because only `init(model:)` sets the flag.

**Descoped:** `ThinkingDisclosure` previews collapsed only (expanded state
is private `@State`). The memory widget's debug-only crash shape, a test
pinning `start()`'s fixture guard, and the gauge snapshot flake went to the
ROADMAP Backlog ("SU.3's deferred items").
