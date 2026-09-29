---
phase: P29
cycle: P29.1-4-honest-session
lifecycle: active
---

# P29.1–P29.4 honest session implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** every piece of session state SwiftStar shows is true, and quitting
always ends the engine.

**Architecture:** the rules move into Kit — `Severity`, `EngineSessionPhase`,
`EngineComposer`, and an `EngineSessionModel` that owns phase, transcript and
metrics and applies events, exit and quit. `EngineSession` gains the
stop → quit → SIGTERM → SIGKILL sequence. The app forwards and renders.

**Spec:** `docs/superpowers/specs/2026-09-28-p29-1-4-honest-session-design.md`
— its "Revisions after the design review" supersede the body. The review:
`docs/superpowers/research/2026-09-28-p28-deep-review.md` (A-ids).

## Global constraints

- Swift 6; the `SwiftStar` target keeps `.defaultIsolation(MainActor.self)`.
- Fast tier: no subprocess (FastTierGuard). Integration suites gated by
  `SWIFTSTAR_INTEGRATION=1`.
- Every "must fail on the old code" test records its red run in the report:
  red on existing API where possible, else "fails with the new rule
  reverted" (spec revision 7).
- Payloads for `terminal`, `mentions`, `steering_*`, `telemetry_error`,
  `compact*`, `clear` are hand-written from ds4-engine source (cite
  file:line in the test); no fixture has them (spec revision 6).
- Commit with `git commit -- <paths>`; attribution
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review focus

1. **A command prompt** (`/help`, `/clear`) → no pending row left behind,
   Stop stays disabled → Tasks 1, 2.
2. **Second Cmd-Q while quitting** → app waits, engine still ends → Tasks 3, 4.
3. **Engine killed externally mid-turn** → Stop disabled, exit shown → Tasks 1, 4.
4. **Quit during model load** → "Ending…", engine gone after the graces → Task 3.
5. **Stray stdout line after `ready`** → a notice, session continues → Task 2.

---

### Task 1: Kit state model (P29.1, P29.2)

**Files:**
- Create: `Sources/SwiftStarKit/Severity.swift` (moved from the app's
  `GaugeFormatting.swift`, plus `ofContext(used:size:)`)
- Create: `Sources/SwiftStarKit/EngineSessionModel.swift`
  (`EngineSessionPhase`, `EngineComposer`, `EngineSessionModel`)
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift` (pending marks, busy
  from `.prompt`, `end()`)
- Test: `Tests/SwiftStarKitTests/SeverityTests.swift`,
  `EngineSessionModelTests.swift`, `EngineTranscriptTests.swift`

**Interfaces (produces):**
- `public enum Severity { healthy, warning, critical; static func ofContext(used: Int?, size: Int?) -> Severity }`
- `public enum EngineSessionPhase: Equatable, Sendable { idle, starting, running, quitting, ended(EngineExit), notFound([String]); var isActive: Bool }` (active = starting|running|quitting)
- `public struct EngineComposer: Equatable { canType, canSend, canStop: Bool; label: String; static func state(phase:transcript:) -> EngineComposer }` — labels per spec revision 10.
- `public struct EngineSessionModel { phase; transcript; metrics; mutating func didStart(); apply(_: EngineEvent); didExit(_: EngineExit, directory: URL?); willQuit(); send(_ text: String) -> Bool; var composer: EngineComposer }`
- `EngineTranscript.end()`; `TranscriptRow.user` gains a queued/pending flag
  (shape is the implementer's; the view must be able to show "Queued").

- [ ] **Step 1: failing tests:**
  - `stopDisabledWhileQueued` — `appendUser("x")` alone → `canStop == false` (red today).
  - `busyStartsOnPromptEvent` — `appendUser` then `.prompt("x")` → `canStop == true`.
  - `commandRowIsNotLeftPending` — `appendUser("/help")`, `.notice`, `.awaitingInput` → no pending row.
  - `pendingClearsOnError` — `appendUser`, `.error("queue full")` → not pending, not busy.
  - `queuedMarksPendingRow` — `appendUser`, `.queued(1)` → row shows queued.
  - `busyClearsOnExit` — model: `.prompt`, then `didExit(...)` → `composer.canStop == false`, phase `.ended`.
  - `readyMovesToRunning`, `willQuitMovesToQuitting`, `sendRefusedWhileQuitting` (`send` returns false, no row added), `quittingIsActive`.
  - `composerLabels` — one assertion per label in spec revision 10.
  - `twentyThousandWindowReachesCritical` — `ofContext(used: 15000, size: 20000) == .critical`; 10000 → warning; 9999 → healthy; nil/0 size → healthy.
- [ ] **Step 2:** red → implement → `swift test` green → commit. (The app
  still compiles: keep the app's `GaugeFormatting` until Task 4, or
  typealias to the Kit type.)

### Task 2: Surface dropped wire events (P29.3, A7, A13)

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift`, `EngineWireParser.swift`,
  `EngineTranscript.swift`, `EngineMetrics.swift`
- Modify: `Sources/SwiftStarAppKit/EngineSession.swift` (post-`ready`
  undecodable line → notice, not SIGTERM)
- Test: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`,
  `EngineTranscriptTests.swift`, `EngineMetricsTests.swift`

**Interfaces (produces):** new `EngineEvent` cases `.turnEnded(outcome: String)`,
`.queued(count: Int)`, `.steering(applied: Bool, text: String?)`; `.answer`
keeps an optional `reason`; parser `parse` returns `.notice("Engine output: …")`
for any undecodable line after `ready` (≤ 200 chars) and `.protocolError`
only before it.

Rendering per spec body table as amended by revision 5 (`telemetry_error`
from `error`; `mentions` attached → notice, missing → error; `compacting` →
"Compacting…"; `compacted` → "Conversation compacted (<tokens> tokens)";
`clear` → "Conversation cleared"; empty answer → "No answer: <reason>" or
"No answer — the model stopped without answering").

- [ ] **Step 1: failing tests:** one parser test per new/changed kind with
  a payload cited from engine source; `emptyAnswerShowsReason` (red today:
  last row is an empty answer, not an error); `terminalShowsOutcome`;
  `clearRendersSentence` (replaces `noticeWithoutTextFallsBackToKind`);
  `undecodableAfterReadyIsNotice`, `undecodableBeforeReadyIsFatal`;
  `sessionEventSetsWindow` and `interruptedUpdatesContext` (metrics).
- [ ] **Step 2:** red → implement → both tiers green → commit.

### Task 3: Quit that ends a turn (P29.4, A12)

**Files:**
- Modify: `Sources/SwiftStarAppKit/EngineSession.swift` (quit sequence,
  idempotent `quit()`, `LocalizedError`, termination reason)
- Modify: `Sources/SwiftStarKit/EngineCommand.swift`
  (`EngineExit.describe` gains a termination-reason input and a
  "forced" flag)
- Modify: `fixtures/engine/fake-ds4-dogfood` (`FAKE_ENGINE_IGNORE_SIGTERM`)
- Test: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`,
  `Tests/SwiftStarKitTests/EngineCommandTests.swift`

**Interfaces (produces):** `EngineSession.init(..., stopGrace: Duration = .seconds(10), termGrace: Duration = .seconds(5), killGrace: Duration = .seconds(10))`; `quit()` (idempotent; returns immediately if already quitting); `EngineSessionError: LocalizedError`; `EngineExit.describe(code:stderrTail:sawReady:reason:forced:)` with `reason: EngineTermination` (`.exit`, `.signal`).

Sequence per spec revision 4: in a turn → `stop`, wait for
`.awaitingInput`/`.closed`/exit up to `stopGrace`; then `quit` + close
stdin; SIGTERM after `termGrace`; SIGKILL after `killGrace`.

- [ ] **Step 1: failing tests:**
  - `quitMidTurnEndsTheEngine` — spec revision 8 exactly (red today).
  - `quitMidTurnStopsFirst` — fake stdin log has `stop` before `quit`.
  - `quitIsIdempotent` — two `quit()` calls → one exit, one `onExit`.
  - `notRunningErrorIsReadable` — `EngineSessionError.notRunning.localizedDescription == "The engine is not running."`.
  - `signalExitReadsAsSignal` / `forcedExitReadsAsForced` (Kit) — describe with `.signal(9)` → "killed by signal 9 (SIGKILL)"; `forced: true` → "ended by force after the quit timed out".
- [ ] **Step 2:** red → implement → both tiers green (run the integration
  tier twice) → commit.

### Task 4: App forwards to the model (P29.1, P29.2)

**Files:**
- Modify: `Sources/SwiftStar/EngineController.swift` (owns
  `EngineSessionModel` + `EngineSession`; forwards events, exit, quit;
  `isActive` from the phase; `quit()` joins an in-flight quit)
- Modify: `Sources/SwiftStar/SwiftStarApp.swift` (`applicationShouldTerminate`:
  `.terminateLater` while active incl. quitting; reply once after exit)
- Modify: `Sources/SwiftStar/AgentView.swift`, `InspectorView.swift`,
  `AgentBubbles.swift` (read `composer`; "Queued" on pending rows; ring and
  inspector by `Severity.ofContext`)
- Delete: the app's `Severity`/`contextSeverity` (and `GaugeFormatting.swift`
  if nothing else remains)
- Modify: `BRIEF.md` binding rule 1 (display by fraction; findings absolute)

- [ ] **Step 1:** implement; the controller contains no state rule the model
  owns (grep: no `isBusy`/`canStop`/phase transitions computed in the app).
- [ ] **Step 2:** `swift build`, both test tiers, `just app`, `just lint-docs`
  green → commit.

### Task 5: Live check and close (controller)

- [ ] **Step 1:** Laguna XS (Settings Model empty): type during model load →
  "Queued", Stop disabled; long prompt, End session mid-turn → ends
  promptly, record `quitting → exit` seconds; Cmd-Q mid-turn → `pgrep`
  empty; `kill -9` the engine mid-turn → Stop disabled, exit shown.
  (Rendering itself is the owner's to eyeball — no screen access.)
- [ ] **Step 2:** ROADMAP: P29.1–P29.4 done, reconcile step text (spec
  revision 12), Backlog "Engine requests" group (rejected tool calls emit no
  event; `/resume`/`/model` `execv` second `ready`; `models --json`), P29.5
  notes the owed recapture; plan `## Result`, `lifecycle: closed`;
  `just lint-docs` green → commit.
