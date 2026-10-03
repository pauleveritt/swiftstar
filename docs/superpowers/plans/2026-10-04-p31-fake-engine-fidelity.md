---
phase: P
cycle: P31-fake-engine-fidelity
lifecycle: closed
---

# P31 fake-engine fidelity implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** make `fixtures/engine/fake-ds4-dogfood`'s `tui` mode match
ds4-engine's relay (`src/ds4_engine/ndjson_process.py`, read directly from the
`../ds4-engine` checkout for this plan) by default, make every B2-listed test
assert a contract or delete it, and fix the B3 doc items. The real-engine
fixture recapture (spec section 3) is **out of scope** — Backlog, GPU-gated.

**Spec:** `docs/superpowers/specs/2026-09-28-p29-5-fake-fidelity-design.md`
(sections 1, 2, 4 — section 3 deferred).

## Decisions beyond the spec's wording, grounded in the real relay source

1. **"Quitting" emits immediately, always** — confirmed from `Relay.quit()`:
   `{"kind":"quitting"}` fires the instant `quit` arrives, mid-turn or idle;
   only `close` (and our synthetic `Session artifacts:` line and exit) wait
   for the turn's next pause. The spec's one-sentence summary reads
   ambiguously on this point; the real source is unambiguous and wins.
2. **Exact refusal texts**, copied from `Relay.prompt()`/`Relay.stop()`:
   empty/whitespace prompt text → `"a prompt needs a non-empty text"`; a
   prompt once quitting → `"the session is quitting"`; stop while idle or no
   turn running → `"no turn is running"`; a non-JSON stdin line →
   `"the line is not JSON"`; JSON that isn't an object →
   `"the line is not a JSON object"`. A blank wire line (not a blank prompt
   *field* — a genuinely empty line) is silently ignored, not refused,
   per `from_frontend`'s `if not text.strip(): return Step()`.
3. **The "Loading model" status text** is the exact line this session
   captured from a live `ds4-dogfood tui --ndjson` run earlier today:
   `"Loading model — input resumes at the next pause"`. `EngineWireParser`
   already decodes any `{"kind":"status",...}` line as `.loading(text)`
   regardless of its exact text, so this is for fidelity, not a decode
   requirement.
4. **Steering mid-turn delivery is scoped down.** The spec's "delivered as
   steering (a `steering_applied` event in the replay)" path depends on the
   `steering` scenario fixture, which section 3 (out of scope here) would
   record. This plan implements the ack-on-queue contract
   (`{"kind":"queued","count":n}`, always on, `FAKE_ENGINE_QUEUE` removed)
   and queued-becomes-next-turn delivery (the existing `run_queued` path,
   kept), but not fabricating a `steering_applied` event against fixtures
   that don't contain one. Tracked in the Backlog entry already covering the
   section-3 recapture.

## Global constraints

- `tui` mode only; `models --json` mode (P29.10) is untouched.
- `FAKE_ENGINE_QUEUE` is removed — queueing is the only behavior.
- `FAKE_ENGINE_IGNORE_QUIT` stays, for the SIGKILL-escalation test.
- `FAKE_ENGINE_LOAD_MS` (default `0`) must not change timing for any existing
  test that doesn't set it.
- Commit with the attribution line `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.

## Review focus

1. **A prompt while busy is acked with `queued`, not silently dropped or
   forwarded** → Task 1.
2. **Stop and quit refusal/idempotency texts match the real relay exactly**
   → Task 1.
3. **Every B2-named test asserts a contract it can be shown to fail**
   → Task 2.
4. **No test asserts `code == 130` as the point of the test**, only as
   supporting detail where 130 itself is what's being tested → Task 2.

---

### Task 1: Fake relay fidelity (`tui` mode)

**Files:**
- Modify: `fixtures/engine/fake-ds4-dogfood` (`tui` mode state machine:
  `accepting`/`quitting`/`stop_requested`/`pending`, replacing the current
  ad hoc `queue_mode`/`ignore_quit` flags; refusal texts per the Decisions
  above; the post-`ready` load-gap status line and `FAKE_ENGINE_LOAD_MS`
  sleep, during which prompts are queued, not dropped)

**Interfaces:** no Swift-side signature changes — `EngineWireParser` already
decodes `queued`, `stopping`, `status` generically.

- [x] **Step 1: failing tests** (`Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`
  unless noted):
  - `sendWhileBusyIsQueued` (replaces `sendWhileBusyIsForwarded`) — a second
    prompt during a `tool_start` pause gets `{"kind":"queued","count":1}`,
    the row reads "Queued", and it arrives as the next turn's prompt once the
    current one ends.
  - `emptyPromptIsRefused` — a `{"kind":"prompt","text":""}` (or whitespace)
    line gets `"a prompt needs a non-empty text"`.
  - `nonJSONLineIsRefused` — a raw non-JSON stdin line gets
    `"the line is not JSON"`.
  - `stopWhileIdleIsRefused` — `stop` before any prompt gets
    `"no turn is running"`.
  - `secondStopIsIdempotent` — two `stop`s in the same turn: the second is a
    silent no-op (no second `"stopping"` or error).
  - `quitEmitsQuittingAtOnceMidTurn` — `quit` mid-turn: `"quitting"` arrives
    immediately; `"close"` and exit wait for the turn's next pause; a queued
    prompt sent after `quit` is dropped, not delivered.
  - `loadGapQueuesAndKeepsStopDisabled` (A2) — with `FAKE_ENGINE_LOAD_MS` set,
    a prompt sent before the gap elapses is queued (not forwarded), and
    `EngineComposer`'s stop stays disabled until `input` finally arrives.
- [x] **Step 2:** red → implement → `swift test` and
  `SWIFTSTAR_INTEGRATION=1 swift test` (twice) green → commit.

### Task 2: B2 test rewrites

**Re-audited against current code, not just the spec's 2026-09-28 wording**
(the codebase moved a lot in P29.1–4/9/10 since the spec was written):
`argumentsAreExact` and `exitZeroEnded` (`EngineCommandTests.swift`) and
`fourAscendingSizes`/`defaultIsThirdSlotNextToLargest`
(`TranscriptFontScaleTests.swift`) already assert real contracts today —
`EngineCommandTests.swift` in particular already has a thorough set of
individually-named tests covering every `EngineExit.describe` case the
spec's proposed table would have (`exitTwoQuotesArgparse`, `exitOneIsNotClean`,
`exit130Interrupted`, `unknownCodeShowsCode`, `signalExitReadsAsSignal`,
`ownSigtermReadsAsQuitTimeout`, `ownSigtermExit130ReadsAsQuitTimeout`,
`forcedExitReadsAsForced`, …) — separately-named failures are more debuggable
than one parameterized table, so these four tests are left exactly as they
are, no rename, matching the spec's own "or asserts a contract" branch.
`leafNameFallsBackToRootPath` likewise stays untouched.

**Files:**
- Modify: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`:
  - `stopMidTurn`/`interruptByteMidTurn` currently assert
    `!rec.has(isToolEnd)` — incidental to how the `stop` fixture happens to be
    laid out, not a contract about `stop` itself. Rewrite to assert the
    `interrupted` → `awaitingInput` sequence and that `EngineComposer.canStop`
    is `false` once `awaitingInput` arrives (`stopping` itself decodes as
    `.ignored` today — confirmed in `EngineWireParser.swift:44` — so there is
    nothing wire-level to assert about it beyond its presence not breaking
    anything; `canStop` tracks `busy`, not `stopping`, per
    `EngineComposer.swift:42`).
  - `badHandshakeTerminates`/`quitAfterTimeoutSendsSIGTERM` currently assert
    `rec.exit?.code == 130` as the primary check. Both scenarios exit 130 by
    different paths (immediate self-terminate vs. SIGTERM-induced); switch
    to asserting `rec.exit?.message` (`"ended after the quit timed out"` for
    the SIGTERM case per `EngineCommand.swift:73`), which disambiguates them.
  - `sendWhileBusyIsForwarded` → `sendWhileBusyIsQueued`: with queueing now
    the default (Task 1), a second prompt mid-turn gets
    `{"kind":"queued","count":1}` (already decoded,
    `EngineWireParser.swift:36-37`), the row reads "Queued", and the text
    arrives as the next turn's prompt — not forwarded into the log mid-turn.
  - `quitWithQueuedPromptEndsPromptly`: drop `FAKE_ENGINE_QUEUE: "1"` from
    `extra` (queueing is unconditional now); assertions otherwise unchanged —
    it already tests exactly the contract this cycle makes universal: a
    quit drops a queued prompt rather than delivering it.
  - Add `exitOneReportsStderrTailAtProcessLevel` — `FAKE_ENGINE_EXIT=1` with
    stderr content: `rec.exit?.message` contains both "Ended without a clean
    answer." and the stderr tail, at the `EngineSession` level (the pure
    `EngineExit.describe` version of this is already covered by
    `exitOneIsNotClean`; this one proves the process-level wiring).
  - Add `unmatchedToolEndIsIgnored`/`unmatchedToolResultIsIgnored` — a
    `tool_end`/`tool_result` with no preceding `tool_start` for that id is
    dropped, not crashed on or shown as a phantom card.
  - Add a metrics nil-overwrite test — a `checkpoint` missing a field (e.g.
    no `sync_ms`) does not clobber the previous pause's value for that field
    with `nil`.

**Interfaces:** none new; test names and assertions only.

- [x] **Step 1:** for each rewritten/renamed test, confirm it is red against
  the pre-Task-1 fake (where applicable) or against current production code
  (for the three new additions), then green after.
- [x] **Step 2:** both test tiers green → commit.

### Task 3: Docs (B3)

**Files:**
- Modify: `BRIEF.md` (state plainly that pause snapshots are
  session-cumulative, so prefill/generation rates are session averages)
- Modify: `Sources/SwiftStar/AgentView.swift:444-445`,
  `Sources/SwiftStar/InspectorView.swift:31-32` ("Prefill"/"Generation" →
  "Prefill avg"/"Generation avg", or equivalent wording matching BRIEF's)
- Modify: `README.md` ("Swift 6" → "Swift 6.2 / Xcode 26"; add a short
  "Build and run" section: `swift build`, `just app`, the `ds4-dogfood`
  Settings path)
- Modify: `docs/glossary.md` ("context used" row: cite `answer`,
  `interrupted`, `status_report` and `session` as sources, not just `answer`;
  add an "agent" term — the model acting in the engine session, the UI's
  word)
- Modify: `fixtures/engine/provenance.md:12` ("macOS 27.0" → "macOS 26",
  matching the "macOS 26 or later" wording used everywhere else; Darwin 27 is
  the kernel version, not the marketing name)

**Interfaces:** none; docs and two UI label strings only.

- [x] **Step 1:** implement; `just lint-docs`, `just docs`, `swift build`
  green → commit.

### Task 4: Close

- [x] **Step 1:** ROADMAP P31 row → "done"; plan `## Result`,
  `lifecycle: closed`; `just lint-docs` green; commit.

## Result

Closed 2026-10-04. All three tasks landed; two genuine races and one
real, previously-untested metrics bug found by testing rather than
inspection.

- **Commits:** `845c9be` (Task 1), `3534eaf` (Task 2), `d66ad84` (Task 3).
- **Task 1 — the fake's `tui` mode rewritten as a Relay-like state machine**
  (`accepting`/`quitting`/`stop_requested`/`pending`), read directly against
  `../ds4-engine`'s `src/ds4_engine/ndjson_process.py`. Queueing is
  unconditional now (`FAKE_ENGINE_QUEUE` removed); stop and quit refuse and
  idempotency-check with the relay's exact texts; the load gap pauses after
  the fixture's own recorded "Loading model" status line (every committed
  fixture already has it — the first design draft wrongly planned a
  synthetic one, caught before implementing it).
  - Two real races, both found by running the suite repeatedly, not by
    reasoning alone: (1) the original tool_start pause didn't loop, so a
    queued ack fell through to blind replay instead of waiting for a real
    decision; (2) a second message sent back-to-back with the first
    (`stop()`+`stop()`, or `quit()`'s `stop()`+`quit()`) can race the reader
    thread — `reach_pause()` now drains the inbox and gives one 50ms grace
    window, with `turn_running`/`stop_requested` reset *after* the drain so a
    genuinely idempotent second `stop` still sees the turn it duplicates.
    Confirmed stable across 5 full-suite runs after each fix.
  - Scoped down from the spec: non-JSON-line refusal and quit's immediate
    `"quitting"` emission aren't testable through `EngineSession`'s public
    API (no raw-write entry point; `"quitting"` still decodes as `.ignored`)
    — documented inline rather than silently dropped. Steering mid-turn
    delivery stays out of scope per the plan's own Decision 4 (needs the
    section-3 recapture).
- **Task 2 — re-audited against current code before touching anything,
  not just the spec's 2026-09-28 wording.** `argumentsAreExact`,
  `exitZeroEnded`, `fourAscendingSizes`, `defaultIsThirdSlotNextToLargest`
  and `leafNameFallsBackToRootPath` already asserted real contracts —
  left untouched. Rewrote `stopMidTurn`/`interruptByteMidTurn` (dropped the
  incidental "no tool_end" check, kept the real interrupted-before-awaiting
  ordering), `badHandshakeTerminates`/`quitAfterTimeoutSendsSIGTERM`
  (message, not bare code 130 — printed the actual values before writing the
  assertions rather than guessing), and `sendWhileBusyIsForwarded` →
  `sendWhileBusyIsQueued`. Added `exitOneReportsStderrTailAtProcessLevel`
  (needed `FAKE_ENGINE_EXIT_STDERR`, a small fixture addition),
  `unmatchedToolEndAndResultAreIgnored` (already-correct behavior, new
  coverage), and `pauseMissingFieldsKeepThePriorRate` — which **failed
  against production code**: `EngineMetricsReducer`'s `.pause` case
  unconditionally overwrote `prefillTPS`/`generationTPS`, unlike every other
  case, which falls back to the prior value on a missing field. A checkpoint
  omitting prefill/eval fields was blanking a rate the UI already knew.
  Fixed with the same `?? state.x` pattern; confirmed red before, green
  after.
- **Task 3 — confirmed the session-cumulative claim** against
  `../ds4-engine`'s `json_events.py` (it deltas the same fields for its own
  terminal display) rather than trusting the spec's prose; labeled both UI
  sites "avg" and said so in `BRIEF.md`. README got Swift 6.2/Xcode 26 and a
  Build and run section. `glossary.md` gained an "agent" term and a
  corrected "context used" row — the first draft claimed `status_report` and
  `session` as sources too, which `EngineMetricsReducer` doesn't support;
  caught by reading the reducer directly instead of the ROADMAP's paraphrase.
  `provenance.md`'s "macOS 27.0" was the Darwin kernel version mislabeled.
- **Out of scope, as planned:** the real-engine fixture recapture (spec
  section 3) — Backlog, GPU-gated.
- Both test tiers green throughout: 137 fast, 31 integration (up from 132
  and 26 at P30's close). `just lint-docs` and `just docs` green.
