# SwiftStar P32 design: structure and dead-code cleanup

**Date:** 2026-10-04  
**Status:** design, approved in chat by the owner (2026-10-04)  
**Phase:** P — cycle P32 (phase P's last cycle)  
**Source:** ROADMAP.md's P29.6 step, carried to P32 in the P30/P31/P32 split;
re-verified against current code before writing this (a lot landed since
P29.6 was first scoped: P29.9, P29.10, P30, P31).

## Goal

Seven cleanup items from the P28 deep review, all build/structure/dead-code,
no behavior change, no live engine needed. Each is re-verified against
current code below — two of the original seven sub-claims had already been
resolved by later work and are dropped from scope.

## 1. Stream plumbing

`EngineSession.swift`'s `stream(from:)` (lines 187-200) still uses
`FileHandle.readabilityHandler` + `AsyncStream` + a hand-rolled
`LineBuffer` (`Sources/SwiftStarKit/LineBuffer.swift`) to frame stdout/stderr
into lines. `FileHandle.bytes.lines` (`AsyncLineSequence`) is unused anywhere
in the repo. Replace the stream/buffer pair with `FileHandle.bytes.lines`,
one `Task` per pipe reading lines directly; delete `LineBuffer` once nothing
calls it. This is the one item with real regression risk (process I/O
timing) — the existing 31 integration tests are the safety net; add none
new, since this is a pure refactor of already-tested behavior.

## 2. FastTierGuard

`Package.swift` declares `FastTierGuardTool` (an executable) and the
`FastTierGuard` build-tool plugin, attached only to `SwiftStarKitTests`. It
scans each test file's text for `Process(`, `URLSession`, `NWConnection`,
`posix_spawn`, `Darwin.`, `socket(` and fails the build on a hit. Replace
with one line in the `test` Justfile recipe:
`! grep -rn 'Process(\|URLSession\|NWConnection\|posix_spawn\|Darwin\.\|socket(' Tests/SwiftStarKitTests`
(exit nonzero — i.e. a hit — fails `just test`). Delete the plugin, the
tool target, and `plugins: ["FastTierGuard"]` from `SwiftStarKitTests`.

## 3. Rename `SwiftStarAppKit` → `SwiftStarEngine`

Two files today: `EngineSession.swift`, `EngineModelCatalogLoader.swift`
(added by P29.10). Rename the directory and the `Package.swift` target
(3 occurrences: the target declaration, `SwiftStar`'s dependency list,
`SwiftStarIntegrationTests`'s dependency list) and every
`import SwiftStarAppKit`/`@testable import SwiftStarAppKit`.

## 4. Dead code

Two of the original B5 items are stale (already resolved by P29.9's work)
and are **dropped from scope**: `EngineSessionInfo`/`.session` is read at
`AgentView.swift:138,162` now; it is not dead. `EngineTranscript.isAwaitingInput`
is read only by tests, not the app — left alone (test-only use is not the
same claim as the others below, and removing it would cost test coverage for
no gain).

Delete, each confirmed zero production call sites beyond the declaration and
its own test:
- `PathAbbreviation.abbreviate` (its sibling `leafName` is used; keep the type)
- `MarkdownPreprocess.fenced`, `MarkdownPreprocess.language(forPath:)`
- `PauseMetrics.outputTokens` / `EngineMetricsSnapshot.outputTokens` (write-only)
- `EngineToolResult.resultKind` (write-only)
- `EngineSession.interrupt()` (no app call site; `AgentView.swift:220`'s
  comment mentions interrupting but never calls it — Stop uses `stop()`)
- `ValueGaugeView.text`/`textFontSize` (every call site passes `nil`/`0`)
- `MetricsModel` (`Sources/SwiftStar/MetricsModel.swift`) — not literally
  unused, but a redundant copy of `engine.metrics` refreshed by `onChange`;
  `InspectorView` should read `engine.metrics` directly, then delete the type
- `fixedWidth` (now a private func in `AgentView.swift:454-457`) — redundant
  given `Text(bottomStatusText)` already has `.monospacedDigit()`
- `Tools/make-icon.swift` (a one-shot `.icns` generator, not invoked by
  `Tools/make-app.sh` or any build step)
- `.claude/commands/goal.md` (already marked "retired 2026-08-26" in its own
  text; delete the file itself)
- `docs/2026-08-26-old-ui-element-inventory.md`, `docs/old_ui.png`, and their
  entry in `docs/index.md`'s toctree (~line 29-34)

Deleting field-level dead code (`outputTokens`, `resultKind`) removes the
corresponding `EngineWireParser` write sites too, where they become
unused-assignment warnings otherwise.

## 5. Rename `Agent*` views

| Current | File | New |
|---|---|---|
| `AgentView` | `AgentView.swift` | `SessionView` (file → `SessionView.swift`) |
| `AgentPromptBubble` | `AgentBubbles.swift` | `PromptBubble` (file → `PromptBubble.swift`) |
| `AgentToolCardView` | `AgentToolCardView.swift` | `ToolCardView` (file → `ToolCardView.swift`) |

`ThinkingDisclosure` (also in `AgentBubbles.swift`) keeps its name — it was
never `Agent`-prefixed, it just lives in the same file being renamed.
`AgentController`/`AgentStatusText` named in the original review don't exist
under those names today (checked — zero hits); nothing to do for them.

## 6. One `DefaultsKey` enum

`EngineController`'s five `static let *DefaultsKey` constants
(`workspaceDefaultsKey = "agentWorkspace"`, `executableDefaultsKey =
"engineExecutable"`, `modelIDDefaultsKey`, `contextSizeDefaultsKey`,
`recentWorkspacesDefaultsKey`) and three bare `@AppStorage` string literals
become one `enum DefaultsKey` in `SwiftStarKit` (plain `String`-backed cases,
so both `UserDefaults.standard.string(forKey: DefaultsKey.x.rawValue)` and
`@AppStorage(DefaultsKey.x.rawValue)` can use it). Three confirmed
duplicates, not just the one ROADMAP named:

| Key | Duplicated in |
|---|---|
| `"appShellInspectorPresented"` | `AgentView.swift:9`, `MainView.swift:6` |
| `"transcriptFontSize"` | `AgentView.swift:13`, `SettingsView.swift:6` |
| `"engineExecutable"` | `EngineController.executableDefaultsKey`, `SettingsView.swift:5` (independent literal) |

## 7. SwiftMath — dropped, documented, no code change

`MarkdownText.swift:38-41` runs `MarkdownPreprocess.deLaTeXed` before
rendering, which strips all LaTeX delimiters and converts common commands to
plain text/Unicode — by the time text reaches the `MarkdownView` fork's
renderer, there is no LaTeX left for SwiftMath to detect. SwiftMath is not a
direct `Package.swift` dependency; it arrives transitively via the pinned
`MarkdownView` fork (`Package.resolved`), so there is no dependency line to
remove. **Owner decision (2026-10-04): drop, not wire** — keep stripping
(no behavior change; the crash history noted in `MarkdownText.swift`'s
resource-bundle comment stays avoided), and document in `BRIEF.md` that
SwiftMath's bundle is accepted, inert weight carried by the fork rather than
a SwiftStar dependency choice.

## Out of scope

Everything else P29.6's original bullet named that turned out to already be
resolved (see "Dead code" above). No new tests beyond confirming the full
build and both test tiers stay green after each task — this cycle changes
structure, not behavior.

## Success criteria

1. `swift build`, `just test`, `just integration`, `just app` all green after
   every task, not just at the end.
2. No symbol named in "Dead code" above has a remaining caller; `grep` for
   each confirms zero hits outside version control history.
3. `SwiftStarAppKit` does not appear anywhere in `Package.swift` or source.
4. Exactly one `DefaultsKey` enum; no bare UserDefaults/`@AppStorage` string
   literal remains for any of its cases.
5. `just lint-docs` and `just docs` green (the deleted old-UI doc's toctree
   entry must go with it, or the docs build breaks).
