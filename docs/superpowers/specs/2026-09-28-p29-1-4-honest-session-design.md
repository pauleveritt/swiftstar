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
