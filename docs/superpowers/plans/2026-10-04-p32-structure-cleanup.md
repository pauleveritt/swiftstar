---
phase: P
cycle: P32-structure-cleanup
lifecycle: active
---

# P32 structure and dead-code cleanup implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** seven build/structure/dead-code cleanups, no behavior change. Each
task ends with a full green build and both test tiers — this cycle is risky
precisely because "no behavior change" is easy to get wrong silently.

**Spec:** `docs/superpowers/specs/2026-10-04-p32-structure-cleanup-design.md`

## Global constraints

- No new tests except where a task removes a symbol a test exercises (the
  test goes with it) — this cycle is structure, not behavior; the existing
  137 fast / 31 integration tests are the regression net for every task.
- `swift build`, `just test`, `just integration` green after **each** task,
  not just at the end — a structural change that silently breaks something
  is exactly the risk this cycle exists to avoid introducing.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

1. **The stream-plumbing rewrite must not change observable timing** (the
   "pipe held open by a grandchild" bound, EOF handling) → Task 1.
2. **FastTierGuard's grep replacement must catch the same four patterns**
   it did → Task 2.
3. **Every deleted symbol has zero remaining callers** → Task 4.
4. **The DefaultsKey enum must not change a persisted key's string value**
   (existing user defaults would silently stop resolving) → Task 6.

---

### Task 1: Stream plumbing — DONE, see spec `## 1`

First attempt rewrote `EngineSession.swift` to `FileHandle.bytes.lines`;
built clean, passed in two isolated standalone experiments, then stalled
~10 real seconds under `swift test` with zero lines delivered before
flooding the entire conversation through in under 10ms. Reverted via
`git checkout --`. Delegated root-cause diagnosis to a fresh agent (Fable),
which found via thread-sampling that `FileHandle.bytes` shares one
process-wide blocking IO actor across all pipes on Darwin, starving
`EngineSession`'s two concurrent `.bytes.lines` readers. Applied the fix:
keep the `readabilityHandler`-fed `AsyncStream<Data>`, wrap it in a new
private `ChunkBytes: AsyncSequence<UInt8>`, call `.lines` on that. Deleted
`LineBuffer.swift` and its test (no remaining callers). Verified via 5
repeated full-suite runs, both tiers green, no stalls. Committed as
`6be894c`.

### Task 2: FastTierGuard → one grep line

**Files:**
- Modify: `Justfile` (`test` recipe gains the grep line from the spec)
- Modify: `Package.swift` (remove `FastTierGuardTool` target, `FastTierGuard`
  plugin, and `plugins: ["FastTierGuard"]` from `SwiftStarKitTests`)
- Delete: `Plugins/FastTierGuard/`, `Sources/FastTierGuardTool/`

**Interfaces:** none.

- [ ] **Step 1:** implement; confirm the grep line actually fails
  (temporarily add a `Process(` literal to a Kit test file, run `just test`,
  watch it fail, remove the literal) → `just test` green → commit.

### Task 3: Rename `SwiftStarAppKit` → `SwiftStarEngine`

**Files:**
- Rename: `Sources/SwiftStarAppKit/` → `Sources/SwiftStarEngine/`
- Modify: `Package.swift` (target name, both dependency lists),
  `Sources/SwiftStarEngine/EngineSession.swift`,
  `Sources/SwiftStarEngine/EngineModelCatalogLoader.swift`,
  `Sources/SwiftStar/EngineController.swift`,
  `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`,
  `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`,
  `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift` (every
  `import`/`@testable import SwiftStarAppKit` → `SwiftStarEngine`)

**Interfaces:** none; pure rename.

- [ ] **Step 1:** implement; `grep -rn "SwiftStarAppKit"` returns nothing;
  full build + both test tiers green → commit.

### Task 4: Dead code

**Files:**
- Modify: `Sources/SwiftStarKit/PathAbbreviation.swift` (delete `abbreviate`),
  `Sources/SwiftStarKit/MarkdownPreprocess.swift` (delete `fenced`,
  `language(forPath:)`), `Sources/SwiftStarKit/EngineEvent.swift` (delete
  `outputTokens` from `PauseMetrics`/`EngineMetricsSnapshot` and
  `resultKind` from `EngineToolResult`), `Sources/SwiftStarKit/EngineWireParser.swift`
  (drop the now-dead write sites for those two fields),
  `Sources/SwiftStarEngine/EngineSession.swift` (delete `interrupt()`),
  `Sources/SwiftStar/ValueGaugeView.swift` (delete `text`/`textFontSize`
  parameters and the dead `if let text` branch), `Sources/SwiftStar/MainView.swift`
  and `Sources/SwiftStar/InspectorView.swift` (read `engine.metrics` directly;
  delete `MetricsModel`'s construction/passing), `Sources/SwiftStar/AgentView.swift`
  (delete the now-redundant `fixedWidth` helper, confirm `.monospacedDigit()`
  alone reproduces the old alignment)
- Delete: `Sources/SwiftStar/MetricsModel.swift`, `Tools/make-icon.swift`,
  `.claude/commands/goal.md`, `docs/2026-08-26-old-ui-element-inventory.md`,
  `docs/old_ui.png`
- Modify: `docs/index.md` (remove the old-UI doc's toctree entry),
  corresponding test files for every deleted symbol (`PathAbbreviationTests.swift`,
  `MarkdownPreprocessTests.swift`, `EngineSessionTests.swift`'s
  `interrupt()`-based tests — check which still make sense via `stop()`/`0x03`
  instead)

**Interfaces:** removes `PauseMetrics.outputTokens`, `EngineToolResult.resultKind`,
`EngineSession.interrupt()`, `ValueGaugeView.text`/`textFontSize`,
`MetricsModel`; no replacements.

- [ ] **Step 1:** implement one symbol at a time (easiest to bisect if a
  deletion surfaces a hidden caller); `grep` confirms zero remaining
  references per symbol; full build + both test tiers green → commit.

### Task 5: Rename `Agent*` views

**Files:**
- Rename: `Sources/SwiftStar/AgentView.swift` → `SessionView.swift`,
  `Sources/SwiftStar/AgentBubbles.swift` → `PromptBubble.swift`,
  `Sources/SwiftStar/AgentToolCardView.swift` → `ToolCardView.swift`
- Modify: every file referencing `AgentView`/`AgentPromptBubble`/
  `AgentToolCardView` by type name (`MainView.swift` at minimum; `grep` for
  the rest)

**Interfaces:** `AgentView` → `SessionView`, `AgentPromptBubble` →
`PromptBubble`, `AgentToolCardView` → `ToolCardView`; `ThinkingDisclosure`
(same file as `PromptBubble`) keeps its name.

- [ ] **Step 1:** implement; `grep -rn "AgentView\|AgentPromptBubble\|AgentToolCardView"`
  returns nothing outside git history; full build + both test tiers green
  → commit.

### Task 6: One `DefaultsKey` enum

**Files:**
- New: `Sources/SwiftStarKit/DefaultsKey.swift` (`enum DefaultsKey: String`,
  one case per key, `rawValue` exactly matching today's string so no
  persisted default silently stops resolving)
- Modify: `Sources/SwiftStar/EngineController.swift` (replace the five
  `static let *DefaultsKey` constants with `DefaultsKey` cases),
  `Sources/SwiftStar/AgentView.swift`/`SessionView.swift` (depending on Task
  5's ordering), `Sources/SwiftStar/MainView.swift`,
  `Sources/SwiftStar/SettingsView.swift` (each `@AppStorage("...")` →
  `@AppStorage(DefaultsKey.x.rawValue)`)

**Interfaces (produces):** `DefaultsKey: String, CaseIterable` with cases
`workspace`, `executable`, `modelID`, `contextSize`, `recentWorkspaces`,
`inspectorPresented`, `transcriptFontSize` (raw values unchanged from
today's literals).

- [ ] **Step 1: failing test:** `defaultsKeyRawValuesMatchToday` — each
  case's `rawValue` equals the literal it replaces (pins against an
  accidental rename that would orphan existing users' saved settings).
- [ ] **Step 2:** red → implement → `grep` confirms no bare key string
  literal remains for any case; full build + both test tiers green →
  commit.

### Task 7: SwiftMath — document, no code change

**Files:**
- Modify: `BRIEF.md` (note SwiftMath is an inert transitive dependency of
  the pinned `MarkdownView` fork, not a SwiftStar dependency choice;
  `deLaTeXed` strips LaTeX before rendering, by design, per the owner's
  2026-10-04 decision in the P32 spec)

**Interfaces:** none; doc only.

- [ ] **Step 1:** implement; `just lint-docs` green → commit.

### Task 8: Close

- [ ] **Step 1:** ROADMAP P32 row → "done"; `## Now` reflects Phase P fully
  closed and Phase SU beginning; plan `## Result`, `lifecycle: closed`;
  `just lint-docs` green; commit.

## Result

_(filled at close)_
