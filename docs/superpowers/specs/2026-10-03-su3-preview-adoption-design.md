# SwiftStar SU.3 design: Preview adoption

**Date:** 2026-10-03
**Status:** design, re-verified against current code before writing
**Phase:** SU — cycle SU.3
**Source:** ROADMAP.md's SU.3 row: "`#Preview` on all 8 existing views
(`SessionView`, `MainView`, `SettingsView`, `InspectorView`, `PromptBubble`,
`ToolCardView`, `MarkdownText`, `ValueGaugeView`) — none exist today — with
fixture-backed states." (This row's view names were already updated to
post-SU.1 names at P32's close; re-verified below, still accurate.)

## Goal

A `#Preview` for each of the 8 named views, each rendering a real,
representative state — not an empty shell. `grep -rn "#Preview"
Sources/SwiftStar/` returns nothing today; confirmed.

## The blocker: `EngineController.model` is `private(set)`

Three of the eight (`SessionView`, `InspectorView`, indirectly `MainView`)
need an `EngineController` with transcript rows and metrics already
present. `EngineController`'s state lives in `model: EngineSessionModel`
(`private(set)`, read-only outside the class) and is normally reached only
by spawning a real subprocess through `start()` — not something a
`#Preview` should do (previews re-render on every canvas change; a real
process per render is slow and leaves orphans).

`EngineSessionModel` is already a `public struct` with `public mutating
func apply(_ event: EngineEvent)` and `public init()` — the exact same fold
`EngineSession`'s real event stream drives. The fix is one more
`EngineController` initializer:

```swift
/// Preview/test fixture construction: starts from a given model state,
/// skipping init()'s UserDefaults reads and the live catalog-reload
/// observer (previews don't restart a session).
init(model: EngineSessionModel) {
    self.model = model
    self.workspace = nil
    self.modelID = ""
    self.contextSize = 0
    self.recentWorkspaces = []
}
```

This lets a preview build state through the *same* `EngineEvent`/`apply`
path real sessions use — `.toolStart`/`.toolEnd`/`.toolResult` fill a card
in place exactly as `EngineTranscript.swift`'s `fillLastCard` already does
for a real session (confirmed by reading it: matched by `tool`, the same
sequence any real wire transcript produces) — not a hand-built
`EngineTranscript` that could drift from what the fold actually produces.

## Fixture construction: one shared file, not eight hand-rolled ones

`Sources/SwiftStar/PreviewFixtures.swift` (new, `#if DEBUG`-unguarded —
`#Preview` blocks are already compiled out of release builds by the
toolchain, so no extra guard is needed): two `EngineController` static
fixtures (`previewIdle`, `previewRunning` — the latter built via `.apply`
calls: `ready` → `session` → `prompt` → `toolStart`/`toolEnd`/`toolResult`
→ `answer` → `pause` → `awaitingInput`, the same order a real transcript
fixture follows) and three standalone `EngineToolCard` fixtures (`running`,
`succeeded`, `failed`) for `ToolCardView`'s own preview, which doesn't need
a whole controller.

## The eight previews

1. **`SessionView`** — `#Preview { SessionView().environment(EngineController.previewRunning) }`.
2. **`MainView`** — same environment injection; `MainView` has no other
   dependency (re-verified: `SU.1`'s `@Environment` injection already
   removed its `let engine` parameter).
3. **`SettingsView`** — `#Preview { SettingsView() }`; no dependency beyond
   `@AppStorage` (re-verified by reading the file — confirmed, nothing
   else to inject).
4. **`InspectorView`** — same environment injection as `SessionView`.
5. **`PromptBubble`** — two previews (plain and `queued: true`); no
   environment dependency beyond `transcriptFontSize`, which already has a
   sane `EnvironmentKey` default (re-verified in `TranscriptFontSize.swift`).
   `ThinkingDisclosure` (same file, not separately named in the ROADMAP row
   — it predates the `Agent*`→current rename and was never `Agent`-prefixed)
   gets its own preview too, since it's a second, materially different view
   in the same file.
6. **`ToolCardView`** — three previews (`running`, `succeeded`,
   `failed`), using the three `EngineToolCard` fixtures — the view's three
   visually distinct states are cheap to show side by side and worth
   differentiating, unlike the single-state views above.
7. **`MarkdownText`** — one preview with a short sample mixing a heading,
   a code block, and inline emphasis — enough to exercise the renderer
   without duplicating its own resource-bundle self-test.
8. **`ValueGaugeView`** — three previews across `Severity`'s three cases
   (healthy/warning/critical), reusing `Severity.color` — the whole point
   of the view is the severity-driven color, so one state would hide that.

## Out of scope

Verifying previews render via the `RenderPreview` MCP tool and writing
that up as a house rule is SU.4's job (next cycle), not this one's — the
tool is already available and this cycle uses it informally to confirm
each preview actually renders, but formalizing it as policy is a separate,
later decision. No source logic changes; this cycle is additive only
(`#Preview` blocks plus the one new `EngineController` initializer).

## Success criteria

1. `swift build`, `just test`, `just integration` green (previews add no
   test-tier surface; they're verified by rendering, not `#Test`).
2. `grep -rln "#Preview" Sources/SwiftStar/` lists exactly the 8 named view
   files — `PreviewFixtures.swift` supplies fixtures but has no `#Preview`
   block of its own.
3. Every `#Preview` renders without a runtime crash or an empty/blank
   canvas, confirmed via the `RenderPreview` MCP tool, one view at a time.

## Amendment, 2026-10-04: views move to a `SwiftStarUI` library target

The first `RenderPreview` attempt (`SessionView`) failed. Xcode reports that
previewing in an executable target needs `ENABLE_DEBUG_DYLIB = YES` "or break
out your preview code into a separate framework". That setting is Xcode-only:
a bare SwiftPM package has no project editor to set it in, and `Package.swift`
cannot express it (`.define`/`unsafeFlags` don't work). Apple's answer on the
Developer Forums (thread 812649) says the same and recommends the split. The
Xcode 27 release notes don't change this.

Decision: every view, `EngineController` and `PreviewFixtures` move to a new
`SwiftStarUI` library target. The `SwiftStar` executable keeps only
`SwiftStarApp.swift` (`@main` + `AppDelegate`) and `Resources/` (the icon
`Tools/make-app.sh` copies by path). Rejected: wrapping the package in an
`.xcodeproj` just to flip one setting, because it adds a second build
description to keep in sync with `Package.swift`.

Success criterion 2 now reads `Sources/SwiftStarUI/` in place of
`Sources/SwiftStar/`. Still additive only, apart from the move and the
`public` modifiers the app shell needs.
