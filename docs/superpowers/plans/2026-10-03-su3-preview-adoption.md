---
phase: SU
cycle: SU.3
lifecycle: active
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

## Global constraints

- `swift build`, `just test`, `just integration` green after each task.
- Every `#Preview` confirmed to actually render (not just compile) via the
  `RenderPreview` MCP tool before its task is considered done.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

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

- [ ] **Step 1:** implement; `swift build` clean; both test tiers green
  (no test-tier surface added, this is a build-correctness check) → commit.

### Task 2: `SessionView`, `MainView`, `InspectorView` previews

**Files:**
- Modify: `Sources/SwiftStar/SessionView.swift`, `Sources/SwiftStar/MainView.swift`,
  `Sources/SwiftStar/InspectorView.swift` (one `#Preview` each, using
  `EngineController.previewRunning` via `.environment(...)`)

**Interfaces:** none.

- [ ] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering (not blank, no crash) via `RenderPreview` → commit.

### Task 3: `SettingsView`, `PromptBubble`/`ThinkingDisclosure`, `ValueGaugeView` previews

**Files:**
- Modify: `Sources/SwiftStar/SettingsView.swift` (one `#Preview`)
- Modify: `Sources/SwiftStar/PromptBubble.swift` (two `#Preview`s for
  `PromptBubble` — plain and `queued: true` — one for `ThinkingDisclosure`)
- Modify: `Sources/SwiftStar/ValueGaugeView.swift` (three `#Preview`s, one
  per `Severity` case)

**Interfaces:** none.

- [ ] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering via `RenderPreview` → commit.

### Task 4: `ToolCardView`, `MarkdownText` previews

**Files:**
- Modify: `Sources/SwiftStar/ToolCardView.swift` (three `#Preview`s —
  `running`/`succeeded`/`failed`, using `EngineToolCard.previewRunning`/
  `.previewSucceeded`/`.previewFailed`)
- Modify: `Sources/SwiftStar/MarkdownText.swift` (one `#Preview` with a
  short sample mixing a heading, code block, and inline emphasis)

**Interfaces:** none.

- [ ] **Step 1:** implement; `swift build` clean; each preview confirmed
  rendering via `RenderPreview` → commit.

### Task 5: Close

- [ ] **Step 1:** ROADMAP SU.3 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

_(filled at close)_
