---
phase: SU
cycle: SU.1
lifecycle: active
---

# SU.1 SwiftUI modernisation implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** four SwiftUI-modernisation items from the P28 deep review, carried
through P29.7 to SU.1. No behavior change except A8 (Option-Return inserting
at the caret) and the window-close-quits addition. `Sources/SwiftStar/`
only; no live engine needed for the fast/integration tiers, but Tasks 2 and 4
each need one manual check against the built `.app` (no automated test
drives window-close or keyboard modifier behavior).

**Spec:** `docs/superpowers/specs/2026-10-03-su1-swiftui-modernisation-design.md`

## Global constraints

- `swift build`, `just test`, `just integration` green after each task.
- No `SwiftStarKit`/`SwiftStarEngine` change; this cycle is `SwiftStar` only.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

1. **Task 2's live check is the gate, not a formality** — if Option-Return
   does not insert a newline at the caret on this macOS/Xcode version, stop
   and report back rather than improvising a different key convention.
2. **The `@Environment` injection must not change which view owns `engine`**
   — `SwiftStarApp` keeps the single `@State`; nothing else gains a second
   source of truth → Task 1.
3. **Window-close-quits must reuse the existing engine-quit-wait path**, not
   duplicate it → Task 4.

---

### Task 1: Inject `EngineController` via `@Environment`

**Files:**
- Modify: `Sources/SwiftStar/SwiftStarApp.swift` (`.environment(engine)` on
  the `Window` scene's content)
- Modify: `Sources/SwiftStar/MainView.swift` (drop the `let engine` property
  and the `MainView(engine: engine)` call site's argument; read
  `@Environment(EngineController.self) private var engine`)
- Modify: `Sources/SwiftStar/SessionView.swift` (drop `let controller`; read
  `@Environment(EngineController.self) private var controller`)
- Modify: `Sources/SwiftStar/InspectorView.swift` (drop `let engine`; read
  `@Environment(EngineController.self) private var engine`)

**Interfaces:** none; same type (`EngineController`), environment injection
instead of initializer parameters. `ToolCardView` is unchanged (see spec `## 1`).

- [ ] **Step 1:** implement; `swift build` clean; both test tiers green
  (no integration test touches SwiftUI views directly — this is a build
  correctness check, not new test coverage) → commit.

### Task 2: Composer — `.onSubmit`, Option-Return, launch focus

**Files:**
- Modify: `Sources/SwiftStar/SessionView.swift:306-313` (delete the
  `.onKeyPress` block; add `.onSubmit { send() }` to the composer
  `TextField`; add a launch-time `.task { inputFocused = true }` alongside
  the existing `.task { if controller.phase == .idle { controller.start() } }`)

**Interfaces:** none.

- [ ] **Step 1: live check, before implementing.** Build and run the
  `.app` (`just app`) against today's `.onKeyPress`-based composer swapped
  for a throwaway `TextField(axis: .vertical)` + `.onSubmit`, or directly
  against the real change once made: confirm plain Return submits and
  Option-Return inserts a newline at the caret (not the end), both on first
  launch (composer already focused) and mid-conversation. If Option-Return
  does not insert at the caret, stop and report back — do not substitute a
  different modifier key without checking in.
- [ ] **Step 2:** implement; `swift build` clean; both test tiers green;
  re-run the Step 1 live check against the real change → commit.

### Task 3: Transcript — `.defaultScrollAnchor(.bottom)`

**Files:**
- Modify: `Sources/SwiftStar/SessionView.swift:200-229` (delete the
  `ScrollViewReader`, the `.onChange(of: controller.transcript.rows)` block,
  and the `Transaction`/`proxy.scrollTo` dance; add
  `.defaultScrollAnchor(.bottom)` to the `ScrollView`)

**Interfaces:** none. Row ids stay `\.offset` (already stable — spec `## 3`).

- [ ] **Step 1:** implement; `swift build` clean; both test tiers green;
  live check (`just app`): the transcript stays pinned to the bottom as new
  rows append and as a tool card fills in place (no visible jump or lag
  versus the old behavior) → commit.

### Task 4: Window lifecycle — close quits, restoration disabled

**Files:**
- Modify: `Sources/SwiftStar/SwiftStarApp.swift` (`AppDelegate` gains
  `applicationShouldTerminateAfterLastWindowClosed(_:) -> Bool { true }`;
  the `Window` scene gains `.restorationBehavior(.disabled)`)

**Interfaces:** none; `applicationShouldTerminate` (already handles the
engine-quit wait) is unchanged and now also reached via this path.

- [ ] **Step 1:** implement; `swift build` clean; both test tiers green;
  live check (`just app`): close the window via its close button while
  idle — the app quits, `ps aux | grep -i ds4-dogfood` shows nothing; repeat
  mid-turn — the engine quits cleanly (same stdout/exit handling
  `EngineSessionTests`'s `quitMidTurnEndsTheEngine` pins) before the app
  exits → commit.

### Task 5: Close

- [ ] **Step 1:** ROADMAP SU.1 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

_(filled at close)_
