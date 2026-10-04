---
phase: SU
cycle: SU.1
lifecycle: closed
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

- [x] **Step 1:** implement; `swift build` clean; both test tiers green
  (no integration test touches SwiftUI views directly — this is a build
  correctness check, not new test coverage) → commit. Done: `84ba4a2`.
  Live-launched the built `.app`: starts and quits cleanly, confirming the
  environment resolves at runtime.

### Task 2: Composer — `.onSubmit`, Option-Return, launch focus

**Files:**
- Modify: `Sources/SwiftStar/SessionView.swift:306-313` (delete the
  `.onKeyPress` block; add `.onSubmit { send() }` to the composer
  `TextField`; add a launch-time `.task { inputFocused = true }` alongside
  the existing `.task { if controller.phase == .idle { controller.start() } }`)

**Interfaces:** none.

- [x] **Step 1: live check, before implementing.** The real composer
  disables while idle/not-found in this environment (no `ds4-dogfood`, no
  GPU here), so verified in a standalone scratch harness instead: plain
  Return submits, Option-Return inserts `\n` at the caret. Confirmed by the
  owner, screenshot reviewed.
- [x] **Step 2:** implement; `swift build` clean; both test tiers green;
  re-ran the Step 1 live check against the real `.onSubmit` code (same
  scratch harness, since the real composer still can't type without an
  engine here) → commit. Done: `5093ae9`.

### Task 3: Transcript — `.defaultScrollAnchor(.bottom)`

**Files:**
- Modify: `Sources/SwiftStar/SessionView.swift:200-229` (delete the
  `ScrollViewReader`, the `.onChange(of: controller.transcript.rows)` block,
  and the `Transaction`/`proxy.scrollTo` dance; add
  `.defaultScrollAnchor(.bottom)` to the `ScrollView`)

**Interfaces:** none. Row ids stay `\.offset` (already stable — spec `## 3`).

- [x] **Step 1:** implement; `swift build` clean; both test tiers green;
  live check: no live engine here to grow the real transcript, so verified
  in a standalone scratch harness (`ScrollView`/`LazyVStack`/`ForEach` +
  `.defaultScrollAnchor(.bottom)`, same append-only shape) — new rows
  appear already scrolled into view with no manual scrolling, confirmed by
  the owner across several additions → commit. Done: `dad78fe`.

### Task 4: Window lifecycle — close quits, restoration disabled

**Files:**
- Modify: `Sources/SwiftStar/SwiftStarApp.swift` (`AppDelegate` gains
  `applicationShouldTerminateAfterLastWindowClosed(_:) -> Bool { true }`;
  the `Window` scene gains `.restorationBehavior(.disabled)`)

**Interfaces:** none; `applicationShouldTerminate` (already handles the
engine-quit wait) is unchanged and now also reached via this path.

- [x] **Step 1:** implement; `swift build` clean; both test tiers green;
  live check (`just app`): closing the window via its close button while
  idle ends the process (confirmed via `ps aux`, gone after the close) →
  commit. Done: `de0e15b`. **Not verified:** the mid-turn case (no
  `ds4-dogfood`/GPU in this environment to start a real turn) — `quit()`'s
  existing mid-turn handling is exercised by `EngineSessionTests`, but this
  specific window-close trigger calling into it was only checked idle.

### Task 5: Close

- [x] **Step 1:** ROADMAP SU.1 row → "done"; `## Now` updated; plan
  `## Result`, `lifecycle: closed`; `just lint-docs` green; commit.

## Result

All four items landed, each its own commit, build and both test tiers
green after every task (129 fast / 30 integration throughout — no test
count change, since this cycle touches `SwiftStar` only, which the fast/
integration tiers don't exercise directly).

1. **`@Environment` injection** (`84ba4a2`) — `SwiftStarApp` keeps the one
   `@State`; `MainView`/`SessionView`/`InspectorView` read
   `@Environment(EngineController.self)`. The "manual `onChange` copy"
   this item was originally paired with (`MetricsModel`'s sync) was already
   deleted in P32 Task 4; nothing left to remove.
2. **Composer `.onSubmit`** (`5093ae9`) — drops the hand-rolled
   `.onKeyPress` that caused A8 (newline always at the end, not the caret).
   Adds a launch-time focus task.
3. **Transcript `.defaultScrollAnchor(.bottom)`** (`dad78fe`) — drops the
   `ScrollViewReader`/`onChange`/`Transaction` dance. Row ids stay
   `\.offset`: confirmed stable by reading `EngineTranscript.swift` (rows
   are append-only), contrary to the original deep review's "give it a
   UUID" suggestion.
4. **Window lifecycle** (`de0e15b`) — `applicationShouldTerminateAfterLastWindowClosed`
   returns `true`, reusing the existing `applicationShouldTerminate`
   engine-quit-wait path rather than duplicating it; `.restorationBehavior(.disabled)`
   added.

**Live verification, with an honest gap.** This environment has no
`ds4-dogfood`/GPU, so the real composer stays disabled
(`EngineComposer.canType == false` while idle/not-found) and the real
transcript never grows. Items 2 and 3 were verified in standalone scratch
harnesses isolating just the SwiftUI behavior in question (not committed —
built in `/tmp`, deleted after use); the owner confirmed both by eye,
including a screenshot for item 2. Item 4 was verified against the real
built `.app`, idle only — closing the window ended the process, confirmed
via `ps aux`. The mid-turn case for item 4 is **not** live-verified;
moved to the ROADMAP Backlog ("Process and tooling") to reopen when the
GPU is free.
