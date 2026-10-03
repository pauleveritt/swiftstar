# SwiftStar P29.5 design: a fake engine that behaves like the relay

**Date:** 2026-09-28  
**Status:** design, for review  
**Phase:** P29 — Make the front-end honest (step P29.5)  
**Source:** [P28 deep review](../research/2026-09-28-p28-deep-review.md) B1, B2, B3; P29.3's owed fixture recapture.

## Goal

The integration tier tests SwiftStar against `fixtures/engine/fake-ds4-dogfood`.
Today the fake diverges from ds4-engine's relay (`src/ds4_engine/ndjson_process.py`)
in ways the tests lean on, so some tests prove the fake's quirks rather than
the engine contract. Make the fake follow the relay's documented behaviour by
default, make every test assert a contract or delete it, record real fixtures
for the events P29.3 tested from hand-written payloads, and fix the docs the
review found wrong.

## 1. Fake fidelity (B1)

The fake's default behaviour becomes the relay's. Each rule cites the relay
line it copies; the implementer reads `ndjson_process.py` (and `tui_cli.py`
for the parent) and quotes the exact texts.

1. **Queueing is the default.** A `prompt` while a turn runs is queued (up to
   the relay's limits) and answered `{"kind":"queued","count":n}`. At the next
   pause the queued text is delivered as steering (a `steering_applied` event
   in the replay) or, if the turn ends first, it becomes the next `prompt`.
   `FAKE_ENGINE_QUEUE` is removed (it becomes the only behaviour).
2. **Stop.** A `stop` (or `0x03`) during a turn emits `{"kind":"stopping"}`,
   then the synthetic `interrupted` event and `input` at the next pause; a
   `stop` while idle is refused with the relay's error text.
3. **Quit is state-based.** `quit` (or stdin EOF) while a turn runs sets
   "quitting"; the turn ends at its next pause, queued prompts are dropped,
   then `quitting`, `close`, the `Session artifacts:` stderr line, exit. A
   `quit` while idle does the same at once. (`FAKE_ENGINE_IGNORE_QUIT` stays
   for the SIGKILL test.)
4. **Refusals.** An empty or whitespace prompt and a non-JSON stdin line get
   the relay's error texts; the session continues.
5. **Model-load gap.** After `ready`, the fake emits the `status` "Loading
   model — …" line and waits `FAKE_ENGINE_LOAD_MS` (default 0) before the
   fixture's first `input`. Prompts sent during the gap are queued (rule 1).
   This makes A2 reproducible: Stop stays disabled for a prompt typed while
   loading.
6. **SIGTERM** keeps exiting 130 by default (the real parent turns SIGTERM
   into an interrupt that exits 130, `tui_cli.py` Termination), but no test
   asserts 130 as the reason for passing unless it is testing that mapping.

Out of scope for the fake: the two-process shape (parent + presenter
grandchild); it does not change what SwiftStar observes on the pipe.

Kept as is: P29.10's `models --json` mode (`argv[1] == "models"`) and its
`FAKE_ENGINE_MODELS*` variables, which the catalog loader tests rely on. The
rules above apply to the `tui` mode only.

## 2. Tests that can fail (B2)

Every test named by B2 either asserts a contract or is deleted:

- `argumentsAreExact` stays — the argv is the engine's CLI contract — but is
  renamed `argvMatchesEngineCLI` and cites `docs/tui.md`'s option names.
- `exitZeroEnded` becomes part of a table-driven `exitDescriptions` test over
  every mapping (0, 1 → "Ended without a clean answer." + stderr tail, 2,
  130 ours / not ours, signal, forced, launch failure).
- `fourAscendingSizes`, `defaultIsThirdSlotNextToLargest`: delete unless they
  pin a behaviour a view depends on; if so, rewrite to assert that behaviour.
- `leafNameFallsBackToRootPath` stays: P29.10's folder menu labels items with
  `PathAbbreviation.leafName`.
- `stopMidTurn`/`interruptByteMidTurn` assert the contract (`stopping`, then
  `interrupted`, then `input`; Stop disabled afterwards), not "no tool_end".
- `badHandshakeTerminates` and `quitAfterTimeoutSendsSIGTERM` assert that the
  process is gone and the exit message's meaning, not `code == 130`.
- `sendWhileBusyIsForwarded` becomes `sendWhileBusyIsQueued`: the fake answers
  `queued`, the row shows Queued, and the text arrives as steering.

New tests B2 lists as missing (some owed from P29.1–4's deferred minors):
unmatched `toolEnd`/`toolResult`; metrics nil-overwrite rules; exit 1 with
the stderr tail at process level (`FAKE_ENGINE_EXIT=1`); `loadGapQueuesAndKeepsStopDisabled`
(A2 in the integration tier); quit while a prompt is queued drops it.

## 3. Real fixtures for P29.3's events

Extend `Tools/record-engine-fixture.py` with scenarios recorded from the real
engine (main ds4-engine checkout, Laguna XS, context 20,000):

| Scenario | Produces |
| --- | --- |
| `clear` | `/clear` → `clear` event |
| `mentions` | a prompt with `@README.md` and `@no-such-file` → `mentions` |
| `steering` | a long prompt, a second prompt mid-turn → `queued`, `steering_*` |
| `compact` | two prompts then `/compact` → `compacting`, `compacted` |
| `tool-limit` | `--max-tool-calls 1` with a prompt needing two reads → `terminal` |

`telemetry_error` cannot be provoked on purpose; it stays hand-written, noted
in `provenance.md`. Parser/transcript tests for these events gain a
fixture-driven variant; the hand-written payload tests stay as the minimal
cases.

Recording loads Laguna XS (~24 GiB); it must not run while the app has Qwen
loaded (~80 GiB) — the recorder refuses if a `ds4-dogfood tui` is already
running, unless `--allow-concurrent`.

## 4. Docs (B3)

- Metrics: the snapshot's timings are session-cumulative, so the status bar
  and inspector label prefill/generation as session averages ("avg"), and
  BRIEF says so. (Per-pause deltas are P29.8.)
- `README.md`: Swift 6.2 / Xcode 26, and a short build-and-run section
  (`swift build`, `just app`, `ds4-dogfood` on the Settings path).
- `docs/glossary.md`: context-used sources (`answer`, `interrupted`,
  `status_report`, `session`); define "agent" as the model acting in the
  engine session (the UI's word).
- `fixtures/engine/provenance.md`: "macOS 26" (Darwin 27), and the new
  scenarios.

## Success criteria

1. The fake's default behaviour matches the relay for queue, stop, quit,
   refusals and load gap; each rule cites its relay line.
2. Every B2 test asserts a contract or is gone; the new tests exist and
   fail when their rule is reverted.
3. Five new fixtures are recorded from the real engine with provenance; the
   events they contain decode as P29.3's tests expect.
4. `swift test`, `SWIFTSTAR_INTEGRATION=1 swift test` (twice), `just app`,
   `just lint-docs`, `just docs` green.
