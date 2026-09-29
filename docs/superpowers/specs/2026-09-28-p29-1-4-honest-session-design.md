# SwiftStar P29.1–P29.4 design: an honest session

**Date:** 2026-09-28  
**Status:** design, for review  
**Phase:** P29 — Make the front-end honest (steps P29.1–P29.4)  
**Source:** [P28 deep review](../research/2026-09-28-p28-deep-review.md), findings A1–A7, A12, A13.

## Goal

Make every piece of session state SwiftStar shows true: Stop is live only
when the engine is in a turn, the composer reflects starting/quitting, the
context gauge can leave green, a turn that ends without an answer says why,
and quitting — idle or mid-turn — always ends the engine.

## Principle: state rules live in Kit

The app target has no tests. Every rule below that decides what the UI shows
is a pure function or value type in `SwiftStarKit` with fast-tier tests; the
views and `EngineController` only read it.

## P29.1 Truthful session state (A1, A2, A3)

1. **Busy is engine-acknowledged.** `appendUser` adds the user row and marks
   it *pending*; it no longer sets `isBusy`. `isBusy` becomes true on the
   engine's `.prompt` event (the relay acknowledged and started the turn) and
   false on `.awaitingInput` or on `end()`. A prompt the relay queued
   (top-level `{"kind":"queued","count":n}`, decoded in P29.3) stays pending
   and its row shows "Queued" until the matching `.prompt` or a
   `steering_applied` event.
2. **`canStop` = `isBusy` and the session is running.** Stop is never
   enabled for a queued prompt, during model load, while quitting, or after
   exit.
3. **`EngineTranscript.end()`** clears `isBusy`, `isGenerating`,
   `isAwaitingInput`, loading text and pending marks. The controller calls it
   when the process exits (`handleExit`).
4. **Session phase moves to Kit.** `EngineSessionPhase` (`idle`, `starting`,
   `running`, `quitting`, `ended(EngineExit)`, `notFound([String])`) replaces
   the app's `EngineController.Phase`. `quit()` and `restart()` set
   `quitting` before touching the session.
5. **Composer rules in Kit.** `EngineComposer.state(phase:transcript:)`
   returns `canType`, `canSend`, `canStop`, and a short status label.
   `canType`/`canSend` are false in `idle`, `starting` before `ready`,
   `quitting`, `ended`, `notFound`. The toolbar's End/Start button and the
   status bar read the same state.
6. **Readable errors.** `EngineSessionError` conforms to `LocalizedError`
   (`notRunning` → "The engine is not running.", `alreadyStarted`, `encoding`).

## P29.2 Context gauge by fraction (A5)

1. `ContextSeverity.of(used:size:)` in Kit: `healthy` below 50 %, `warning`
   from 50 %, `critical` from 75 % of the wire's `context_size`; `nil` size →
   `healthy`. The ring, the inspector and the status bar use it;
   `contextSeverity(ctxUsed:)` and its absolute thresholds are deleted.
2. BRIEF binding rule 1 is amended: findings about context stay absolute
   (`ctx_used` in tokens), the *display* is the fraction of the window the
   engine reports.

## P29.3 Surface the dropped wire events (A6, A7, A13)

New `EngineEvent` cases and their transcript rows (exact payload fields are
the engine's; the implementer cites them from `ds4-engine` source):

| Wire | Event | Transcript |
| --- | --- | --- |
| `event.terminal {outcome}` | `.turnEnded(outcome)` | error row "Turn ended: <outcome>" |
| `event.answer` with empty `text` | `.answer` (text empty) + `reason` | error row "No answer: <reason>", or "No answer — the model stopped without answering" when `reason` is absent |
| top-level `queued {count}` | `.queued(count)` | marks the latest pending user row "Queued" |
| `event.steering_applied` / `steering_unconfirmed` | `.steering(applied: Bool)` | notice "Queued message delivered" / "Queued message not confirmed" |
| `event.mentions` with missing paths | `.refused` | error row "Not found: <paths>" |
| `event.compacting` / `compacted` / `compact_failed` | `.notice` / `.notice` / `.refused` | as named |
| `event.telemetry_error` | `.notice` | "Telemetry error: <text>" |
| `event.clear` | `.notice` | "Conversation cleared" (replaces the kind-name fallback) |

- **Metrics (A13):** fold `session.context_size` (the window before the first
  answer) and `interrupted.context_used`/`context_size` (context after Stop).
- **A7:** only the handshake is fatal. After `ready`, a line that is not a
  JSON object becomes `.notice("Engine output: <line>")` (truncated to 200
  characters); the session continues. Blank lines stay skipped.
- **Known gap (engine side):** a tool call the engine rejects before
  execution (unknown tool, malformed) emits no event today, so SwiftStar
  cannot show it; recorded as a ds4-engine Backlog item. The turn's
  `no-answer` ending is shown via the rules above.

## P29.4 Quit that ends a turn (A4, A12)

1. **Quit sequence in `EngineSession.quit()`**: if a turn is in progress
   (the session saw `.prompt` without a later `.awaitingInput`), write
   `{"kind":"stop"}` and wait for `.awaitingInput` up to `stopGrace`
   (default 10 s); then write `{"kind":"quit"}` and close stdin; SIGTERM at
   `termGrace` (5 s) after that; SIGKILL at `killGrace` (5 s) after SIGTERM.
   All three durations are init parameters so tests can shrink them.
2. **App quit waits for exit.** `applicationShouldTerminate` holds
   `.terminateLater` until `onExit`. The fixed 10 s outer bound is replaced by
   a safety bound of `stopGrace + termGrace + killGrace + 5 s`, reached only if
   SIGKILL itself fails.
3. **Exit descriptions (A12).** `EngineExit.describe` takes the termination
   reason: an uncaught signal reads "killed by signal <n> (<name>)"; a launch
   failure reads "could not launch <path>: <reason>" without "exit -1".

## Testing

- **Fast tier (Kit):** busy only after `.prompt`; queued row; `end()` clears
  everything; composer state for every phase × busy × pending combination
  that matters (including `stopDisabledWhileQueued`,
  `sendRefusedWhileQuitting`); `ContextSeverity` boundaries (49.9 %, 50 %,
  75 %, a 20,000 window reaching critical); each new parser case with a
  payload shaped like the engine's; non-JSON after `ready` is a notice and
  before `ready` a protocol error; metrics fold `session`/`interrupted`;
  exit descriptions for signal and launch failure.
- **Integration tier:** fake flag `FAKE_ENGINE_IGNORE_SIGTERM=1`;
  `quitMidTurnEndsTheEngine` — quit while the fake is paused mid-turn and
  ignoring SIGTERM: process gone within the three graces (shrunk in tests);
  `quitMidTurnStopsFirst` — the fake's stdin log shows `stop` before `quit`;
  `busyClearsOnExit` via the real session path (kill the fake mid-turn).
- **Tests that must fail on the old code:** `busyClearsOnExit`,
  `stopDisabledWhileQueued`, `sendRefusedWhileQuitting`,
  `twentyThousandWindowReachesCritical`, `emptyAnswerShowsReason`,
  `quitMidTurnEndsTheEngine` — the implementer records the red run.
- **Live:** app with Laguna XS: Stop disabled during model load with a
  queued prompt; End session mid-turn ends promptly as a clean quit; Cmd-Q
  mid-turn leaves no `ds4-dogfood` (`pgrep`).

## Out of scope

P29.5 (full fake fidelity: queueing, `stopping`, deferred quit, load gap),
P29.6–P29.8, the minors A8–A11 and A14 (they stay in the review for later
steps), and the ds4-engine prompt fix for Qwen.

## Revisions after the design review (2026-09-28)

An adversarial review (Fable, `.superpowers/p29-1-4-spec-review.md`,
checked against ds4-engine source and live sessions) found five majors and
six minors. These supersede the body where they conflict.

1. **Pending marks clear without matching.** All pending user rows are
   cleared by the next `.prompt`, `.steering`, `.awaitingInput`, `.closed`,
   `.error`/`.refused`, or `end()`; `.queued`, `.loading`, `.generating`,
   `.pause`, `.memory` leave them. Turnless commands (`/clear`, `/status`,
   `/help`, `/export`, `/apply`, `commands.py:39`) never emit `prompt`;
   queued prompts are joined with `"\n\n"` into one `prompt`/`steering_*`
   text, so no row is matched by text. Test `commandRowIsNotLeftPending`.
2. **A Kit session model owns the calls.** `EngineSessionModel` (Kit) holds
   phase, transcript and metrics and exposes `apply(_ event:)`,
   `didExit(_:)`, `willQuit()`, `didStart()`, and the composer state.
   `.ready → running`, exit → `end()`, quit → `quitting` happen there and are
   fast-tested; `EngineController` only owns the `EngineSession` and forwards.
3. **`isActive` includes `quitting`.** `applicationShouldTerminate` while
   quitting returns `.terminateLater` and joins the in-flight quit;
   `EngineSession.quit()` is idempotent; `start()`/`restart()` refuse while
   quitting. Reply-once guard kept.
4. **Quit sequence details.** The stop wait ends on `.awaitingInput`,
   `.closed`, or exit (after `terminal` no `input` comes). Quit during model
   load reaches SIGKILL (SIGTERM is deferred inside the native load) and
   drops a queued prompt — acceptable before the first answer; the UI says
   "Ending…". `killGrace` defaults to 10 s until the live check measures
   `quitting → exit` (model unload ~19 GiB overlaps `termGrace`). After our
   own escalation the exit reads "ended by force after the quit timed out",
   not a crash. `processExited` receives `Process.TerminationReason`.
5. **Wire facts for P29.3** (all cited in the review):
   `terminal` = `{outcome, capture_path, duration_ms}`, outcomes `answered`,
   `cancelled`, `tool-limit`, `no-answer`, …; it is followed by `close` and
   exit 1, never `input`. `telemetry_error` text is in `error`.
   `mentions` = `{attached, missing}`, emitted when either is non-empty —
   error row only for `missing`; `attached` renders a notice "Attached:
   <paths>". `steering_*` carry `text`, emitted after the next `resume`.
   `compacting` has only nullable `focus` → notice "Compacting…";
   `compacted` renders "Conversation compacted (<tokens> tokens)" (not the
   summary text). Empty-answer `reason` exists only for `laguna-xs-chat`, so
   the no-reason fallback is the common path.
6. **Hand-written payloads, owed recapture.** No live session contains
   `terminal`, `mentions`, `steering_*`, `telemetry_error`, `compact*` or
   `clear`; their tests use payloads written from engine source, and a
   fixture recapture is owed (ROADMAP P29.5 note).
7. **Red runs.** "Must fail on the old code" means: red on existing API where
   possible (e.g. `stopDisabledWhileQueued` as "`appendUser` alone →
   `canStop == false`"; `emptyAnswerShowsReason`; `quitMidTurnEndsTheEngine`),
   otherwise "fails with the new rule reverted", recorded by the implementer.
8. **`quitMidTurnEndsTheEngine` reaches SIGKILL.** Fake flags
   `FAKE_ENGINE_IGNORE_QUIT=1` + new `FAKE_ENGINE_IGNORE_SIGTERM=1` (SIG_IGN) +
   `FAKE_ENGINE_PIDFILE`, pace 30000; prompt, wait for `.toolStart`, `quit()`
   with graces 0.3 s; assert `kill(pid, 0) != 0` within 2 s.
   `quitMidTurnStopsFirst` uses today's fake (pace 30000). No P29.5
   dependency remains.
9. **One severity type.** `Severity` moves to Kit with
   `Severity.ofContext(used:size:)` using integer thresholds
   (`used*4 >= size*3` critical, `used*2 >= size` warning, `size <= 0` →
   healthy); the app copy is deleted.
10. **Composer labels.** idle "Not started" · starting "Starting…" ·
    running+loading "Loading model…" (+ "· n queued") · running+busy
    "Working…" · running idle "Ready" · quitting "Ending…" · ended the exit
    message · notFound "ds4-dogfood not found". ("starting before ready" is
    dropped: `running` begins on `.ready`.)
11. **A7 scope.** After `ready`, any line the parser cannot decode (non-JSON,
    or a JSON object without `kind`) becomes a notice. `/resume`, `/model`,
    `/rewind` print and `execv` in place (same pid, a second `ready`):
    recorded as a Backlog item, not handled here.
12. **Drift.** ROADMAP steps are reconciled at close (test names, A12 now
    mandatory, `compacting`/`telemetry_error`); the engine-side "rejected
    tool calls emit no event" gap goes in the ROADMAP Backlog under a new
    "Engine requests" group.

## Success criteria

1. After the engine dies mid-turn, Stop is disabled and the status reads
   the exit.
2. A prompt typed during model load shows "Queued"; Stop stays disabled
   until the engine starts the turn.
3. At a 20,000 window the ring turns amber at 10,000 and red at 15,000.
4. A turn ending in `no-answer` shows a visible reason row.
5. Quit mid-turn ends the engine (stop → quit → SIGTERM → SIGKILL), and the
   app never exits leaving `ds4-dogfood` running.
6. `swift test`, `SWIFTSTAR_INTEGRATION=1 swift test`, `just app`,
   `just lint-docs` green.
