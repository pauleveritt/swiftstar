---
phase: P28
cycle: P28-ds4-engine-cutover-a
lifecycle: closed
---

# P28 ds4-engine cut-over, plan A: the engine seam

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** new, fully tested SwiftStarKit/AppKit types that speak
`ds4-dogfood tui --ndjson`, landed beside the old engine code. Plan B
(`2026-09-28-p28-ds4-engine-cutover-app.md`) switches the app and removes
the old code.

**Architecture:** a pure `EngineWireParser` turns stdout lines into
`EngineEvent`s; `EngineTranscript` and `EngineMetricsReducer` fold them into
view state; `EngineSession` owns the process.

**Spec:** `docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`
— read "Revisions after the design review" first; it supersedes the body.

## Global constraints

- Swift language mode 6. Wire: `tui --ndjson`, `protocol == 1` only.
- argv is exactly `tui --ndjson --source <git root> --commit HEAD`.
- Executable resolution: Settings path → `PATH` → `~/.local/bin/ds4-dogfood`.
- Fast tier (`SwiftStarKitTests`): no subprocess/network/model
  (`FastTierGuard`); fixtures read via `#filePath`.
- Integration suites: `@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))`.
- New files only; do not modify or import the old wire types
  (`AgentWireParser`, `AgentEvent`, `WireEvent`, `AgentSession`).
- Commit with `git commit -- <paths>` (a docs lane commits in parallel);
  attribution `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review focus

1. **Engine exits before `ready`** (no model, source not a repo): a
   start-refusal exit with the stderr reason, never a protocol error → Tasks 3, 5.
2. **Partial checkpoint snapshot** (`{"status":"unavailable"}`, nulls):
   ignored or nil fields, never a crash or a protocol error → Task 2.
3. **Slash commands** (`/help`, `/apply`): a visible notice or refusal, not
   silence → Tasks 2, 4.
4. **Stop while idle**: never sent; Stop is disabled outside a turn → Task 4.
5. **New upstream event kinds or fields**: `.ignored`; only a bad handshake
   or a non-JSON line is fatal → Task 2.

---

### Task 1: Record engine fixtures — done (`371a7f2`)

`Tools/record-engine-fixture.py`, `fixtures/engine/{tool-read,stop,error}.ndjson`,
`fixtures/engine/provenance.md`, Justfile `capture SCENARIO`. Checked:
`tool-read` has two `read` tool results and one `answer`; `stop` has
`stopping` and `interrupted` and no `answer`; `error` has one `error` line.

### Task 2: `EngineEvent` and `EngineWireParser`

**Files:**
- Create: `Sources/SwiftStarKit/EngineEvent.swift`,
  `Sources/SwiftStarKit/EngineWireParser.swift`
- Test: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`

**Interfaces (produces):**
- `public struct EngineTool: Equatable, Sendable { op: String; path: String? }`
- `public struct EngineToolResult: Equatable, Sendable { tool: EngineTool;
  resultKind: String; preview: String; truncated: Bool }`
- `public struct EngineAnswer: Equatable, Sendable { text: String;
  contextUsed: Int?; contextSize: Int?; durationMs: Double? }`
- `public struct PauseMetrics: Equatable, Sendable { prefillTokens: Int?;
  prefillMs: Double?; evalCount: Int; evalMs: Double?; outputTokens: Int? }`
  from `checkpoint.snapshot` keys `prefill_tokens`, `sync_ms`, `eval_count`,
  `eval_ms`, `output_tokens`.
- `public struct EngineMemory: Equatable, Sendable { allocatedBytes: Int64?;
  budgetBytes: Int64?; planGiB: Double? }` (`gpu_allocated_bytes`,
  `gpu_budget_bytes`, `engine_plan.total_gib`).
- `public struct EngineSessionInfo: Equatable, Sendable { id: String;
  modelID: String?; contextSize: Int? }`
- `public enum EngineEvent: Equatable, Sendable`: `ready`, `loading(String)`,
  `session(EngineSessionInfo)`, `generating(Bool)`, `prompt(String)`,
  `narration(String)`, `thinking(String)`, `toolStart(EngineTool)`,
  `toolEnd(EngineTool, ok: Bool, durationMs: Double?)`,
  `toolResult(EngineToolResult)`, `answer(EngineAnswer)`,
  `pause(PauseMetrics)`, `memory(EngineMemory)`, `interrupted`,
  `notice(String)`, `refused(String)`, `awaitingInput`, `error(String)`,
  `closed(capturePath: String?)`, `protocolError(String)`, `ignored`.
- `public struct EngineWireParser: Sendable { public init();
  public mutating func parse(_ line: String) -> EngineEvent }`.

**Mapping.** Top level: `ready` → `.ready` (protocol ≠ 1 → `.protocolError`
naming it); `status` → `.loading(text)`; `input` → `.awaitingInput`;
`error` → `.error(text)`; `close` → `.closed(capturePath: nil)`;
`diagnostic`, `queued`, `stopping`, `quitting` → `.ignored`. `event` by
`event.kind`: `session`, `prompt`, `narration`, `thinking`, `tool_start`,
`tool_end` (`ok` ⇔ `status == "ok"`), `tool_result`, `answer`,
`checkpoint` (no `eval_count` → `.ignored`), `memory`, `interrupted`,
`native_start` → `.generating(true)`, `native_end` → `.generating(false)`,
`closed` → `.closed(capturePath:)`; `help`, `status_report`, `clear`,
`exported`, `models` → `.notice(text)`; any `*_refused` → `.refused(text)`.
Take `text`/`reason` from the payload as `ds4-engine`'s emit sites define
them (`src/ds4_engine/tui_cli.py:97-281`, `operator.py:159-390` in
`../ds4-engine`) — read those before writing the notice text. Any other
`kind` → `.ignored`. Missing optional fields → `nil`. A line that is not a
JSON object → `.protocolError`. A line before `ready` other than `ready`
→ `.protocolError`.

- [ ] **Step 1: failing tests** (`EngineWireParserTests`):
  - `firstLineMustBeReady` — fresh parser, `{"kind":"input"}` →
    `.protocolError` containing `input`.
  - `protocolTwoIsRefused` — `{"kind":"ready","protocol":2}` →
    `.protocolError` containing `protocol 2`.
  - `nonJSONIsProtocolError` — `garbage` after ready → `.protocolError`.
  - `unknownEventKindIsIgnored` — `event.kind` `flux_capacitor` → `.ignored`.
  - `toolReadFixtureDecodes` — `tool-read.ndjson`: two `.toolResult` with
    `op == "read"`, `path == "Package.swift"`, non-empty preview; one
    `.answer` with `contextUsed > 0`; ≥1 `.pause` with `evalCount > 0`;
    last non-ignored event is `.closed`.
  - `stopFixtureHasInterrupted` / `errorFixtureHasError` — `stop.ndjson`
    contains `.interrupted`; `error.ndjson` contains `.error` with `bogus`.
  - `unavailableSnapshotIsIgnored` — checkpoint with
    `snapshot: {"status":"unavailable"}` → `.ignored`.
  - `nullSnapshotFieldsAreNil` — snapshot with `eval_count: 8`,
    `sync_ms: null` → `.pause` with `prefillMs == nil`.
  - `missingOptionalFieldsAreNil` — `answer` with only `text` → all
    optionals `nil`.
  - `refusalBecomesRefused` — `event.kind` `apply_refused` → `.refused`.
  - `helpBecomesNotice` — `event.kind` `help` → `.notice`, non-empty.
  - `nativeEventsAreGenerating` — `native_start`/`native_end` →
    `.generating(true)`/`.generating(false)`.
- [ ] **Step 2:** red (`swift test --filter EngineWireParserTests`) →
  implement → full `swift test` green → commit.

### Task 3: `EngineCommand` and `EngineExit`

**Files:**
- Create: `Sources/SwiftStarKit/EngineCommand.swift`
- Test: `Tests/SwiftStarKitTests/EngineCommandTests.swift`

**Interfaces (produces):**
- `public enum EngineCommand { static let executableName = "ds4-dogfood";
  static func arguments(source: URL) -> [String];
  static func resolveExecutable(settingsPath: String?, pathEnv: String?,
  home: URL, isExecutable: (String) -> Bool) -> EngineResolution;
  static func applyCommand(sessionDirectory: URL) -> String }`
- `public enum EngineResolution: Equatable, Sendable { case found(String);
  case notFound(searched: [String]) }`
- `public struct EngineExit: Equatable, Sendable { code: Int32;
  message: String; static func describe(code: Int32, stderrTail: String,
  sawReady: Bool) -> EngineExit }`

Messages (spec revision 1): 0 → contains `ended`; 1 → contains
`without a clean answer` and the stderr tail; 2 → `refused to start: ` +
the last non-empty stderr line; 130 → contains `interrupted`; other → the
code and stderr tail. Any code with `sawReady == false` and code ≠ 0 is
worded as a start refusal.

- [ ] **Step 1: failing tests:**
  - `argumentsAreExact` — `/tmp/r` →
    `["tui","--ndjson","--source","/tmp/r","--commit","HEAD"]`.
  - `settingsPathWins`, `emptySettingsFallsToPATH` (`""` settings, `PATH`
    `/a:/b`, only `/b/ds4-dogfood` executable → `.found("/b/ds4-dogfood")`),
    `fallsBackToLocalBin`, `notFoundListsEverySearchedPlace`.
  - `exitTwoQuotesArgparse` — stderr `"…\nds4-dogfood tui: error: no model
    on this Mac\n"` → message == `refused to start: ds4-dogfood tui: error:
    no model on this Mac`.
  - `exitOneIsNotClean`, `exitZeroEnded`, `exit130Interrupted`,
    `unknownCodeShowsCode` (42 → contains `42`).
  - `applyCommandUsesDirectoryName` — `/x/sessions/20260928-101010-repo`
    → `ds4-dogfood apply 20260928-101010-repo`.
- [ ] **Step 2:** red → implement → green → commit.

### Task 4: `EngineTranscript` and `EngineMetricsReducer`

**Files:**
- Create: `Sources/SwiftStarKit/EngineTranscript.swift`,
  `Sources/SwiftStarKit/EngineMetrics.swift`
- Test: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`,
  `Tests/SwiftStarKitTests/EngineMetricsTests.swift`

**Interfaces:**
- Consumes: Task 2 types.
- Produces:
  - `public struct EngineToolCard: Equatable, Sendable { tool: EngineTool;
    ok: Bool?; durationMs: Double?; result: EngineToolResult? }`
  - `public enum TranscriptRow: Equatable, Sendable { case user(String),
    narration(String), thinking(String), tool(EngineToolCard),
    answer(EngineAnswer), system(String), error(String) }`
  - `public struct EngineTranscript: Equatable, Sendable { rows:
    [TranscriptRow]; isBusy: Bool; isGenerating: Bool; isAwaitingInput:
    Bool; var canStop: Bool { isBusy }; mutating func apply(_: EngineEvent);
    mutating func appendUser(_: String); mutating func appendSystem(_: String) }`
  - `public struct EngineMetricsState: Equatable, Sendable { prefillTPS:
    Double?; generationTPS: Double?; contextUsed: Int?; contextSize: Int?;
    gpuAllocatedBytes: Int64?; gpuBudgetBytes: Int64?; planGiB: Double? }`
  - `public enum EngineMetricsReducer { static func reduce(_: inout
    EngineMetricsState, _: EngineEvent) }`

Rules: `appendUser` adds a user row and sets `isBusy`; `.prompt` sets
`isBusy` but adds no row (the controller already did); `.awaitingInput`
clears `isBusy`/`isGenerating`, sets `isAwaitingInput`; `appendUser` clears
`isAwaitingInput`; `.generating(b)` sets `isGenerating` only; `toolStart`
appends a card; `toolEnd`/`toolResult` fill the most recent card with the
same `op`+`path` still missing that field; `.interrupted` →
`.system("Stopped.")`; `.notice` → `.system`; `.refused`/`.error` →
`.error`; `.closed` clears all three flags. Metrics: tok/s = tokens /
(ms / 1000), `nil` when either is nil or ms ≤ 0; context from `.answer`,
GPU from `.memory`.

- [ ] **Step 1: failing tests:**
  - `toolReadFixtureBuildsRows` — replay `tool-read.ndjson` after
    `appendUser`: two `.tool` cards each with `ok == true` and non-nil
    `result`, one `.answer`, and all flags false after `.closed`.
  - `repeatedReadsGetOwnResults` — two start/end/result triples for the
    same path → two cards, each filled once.
  - `promptEventDoesNotDuplicateUserRow` — `appendUser("x")` +
    `apply(.prompt("x"))` → one `.user` row.
  - `busyAcrossToolCalls` — during `tool-read.ndjson`, `isBusy` stays true
    from the prompt until `.awaitingInput`, although `isGenerating` flips.
  - `stopDisabledWhenAwaitingInput` — after `.awaitingInput`,
    `canStop == false`; after `appendUser`, `canStop == true`.
  - `interruptedAddsStoppedRow` — replay `stop.ndjson`: the last
    non-system row precedes a `.system("Stopped.")` row, and there is no
    `.answer`.
  - `noticeAndRefusalRows` — `.notice("h")` → `.system("h")`;
    `.refused("r")` → `.error("r")`.
  - `pauseComputesRates` — prefill 682 tok / 827.3 ms ≈ 824 tok/s;
    eval 8 / 61.2 ms ≈ 130.7 tok/s (±0.5).
  - `missingDurationGivesNil` — `evalMs: 0` or `nil` → `generationTPS == nil`.
  - `answerAndMemoryFillContextAndGPU` — from `tool-read.ndjson`:
    `contextUsed > 0`, `contextSize == 20000`, `gpuBudgetBytes > 0`,
    `planGiB > 0`.
- [ ] **Step 2:** red → implement → green → commit.

### Task 5: `EngineSession` and the fake engine

**Files:**
- Create: `Sources/SwiftStarAppKit/EngineSession.swift`
- Create: `fixtures/engine/fake-ds4-dogfood` (Python 3, executable),
  `fixtures/engine/bad-handshake.ndjson` (one line: `{"kind":"input"}`)
- Test: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 3.
- Produces: `@MainActor public final class EngineSession` —
  `init(executable: String, arguments: [String], environment:
  [String: String]? = nil, workingDirectory: URL? = nil)`;
  `var onEvent: ((EngineEvent) -> Void)?`; `var onExit: ((EngineExit,
  URL?) -> Void)?` (exit + session directory); `func start() throws`;
  `func send(prompt: String) throws`; `func stop() throws`;
  `func interrupt() throws` (writes `0x03`); `func quit(timeout: Duration
  = .seconds(5))`; `var isRunning: Bool`; `private(set) var
  sessionDirectory: URL?`.
- Uses `Process`/`Pipe`/`LineBuffer` like `AgentSession` (read it for the
  pattern; do not call it). Pipe handlers hop to the main actor. Keeps the
  last 4 KiB of stderr. Session directory: parent of `closed.capture_path`
  resolved against the working directory, else `Session artifacts: <dir>`
  from stderr. `onExit` fires once, after both stdout and stderr reach EOF
  and the process has exited. On `.protocolError` it sends SIGTERM.
  `quit` writes `{"kind":"quit"}`, closes stdin, and sends SIGTERM if the
  process is still running at the timeout.

**Fake engine** (env-driven): `FAKE_ENGINE_FIXTURE` (path); writes lines up
to and including each `input`, **pausing after every `tool_start` line**
until a stdin line arrives or `FAKE_ENGINE_PACE_MS` (default 300) elapses;
`prompt` → resume; `stop` or `0x03` while replaying → emit an
`interrupted` event then `input`; `stop` while idle → `{"kind":"error",
"text":"no turn is running"}`; `quit`/EOF → `quitting`, `close`, then
`Session artifacts: /tmp/fake-session` on stderr, exit `FAKE_ENGINE_EXIT`
(default 0). `FAKE_ENGINE_EXIT` set at start with
`FAKE_ENGINE_REFUSE=1` → print `ds4-dogfood tui: error: no model on this
Mac` to stderr, no stdout, exit 2. `FAKE_ENGINE_IGNORE_QUIT=1` ignores
`quit` and EOF. `FAKE_ENGINE_LOG` → append each stdin line. SIGTERM → exit 130.

- [ ] **Step 1: failing tests** (`EngineSessionTests`, integration-gated):
  - `promptRoundTrip` — `tool-read`: first `.awaitingInput`, `send`, then
    `.answer` and `.awaitingInput`; `quit()` → `onExit` code 0,
    `isRunning == false`.
  - `stopMidTurn` — `stop()` right after the first `.toolStart` →
    `.interrupted` arrives before the next `.awaitingInput`.
  - `badHandshakeTerminates` — `bad-handshake.ndjson` → `.protocolError`,
    then `onExit` within 5 s.
  - `refusalBeforeReady` — `FAKE_ENGINE_REFUSE=1` → no `.protocolError`;
    `onExit` message == `refused to start: ds4-dogfood tui: error: no
    model on this Mac`.
  - `sessionDirectoryKnownAtExit` — `onExit`'s URL path == `/tmp/fake-session`.
  - `quitAfterTimeoutSendsSIGTERM` — `FAKE_ENGINE_IGNORE_QUIT=1`,
    `quit(timeout: .seconds(1))` → `onExit` code 130 within 3 s.
  - `sendWhileBusyIsForwarded` — second `send` while paused after a
    `tool_start` → both prompts in `FAKE_ENGINE_LOG`.
- [ ] **Step 2:** red (`SWIFTSTAR_INTEGRATION=1 swift test --filter
  EngineSessionTests`) → implement → green → commit.

## Result

Closed 2026-09-28, executed subagent-driven (Sonnet implementers, per-task
review, Opus for Task 5's review, Fable for the final whole-branch review).

- **Commits:** `371a7f2` (T1), `44039a0` (T2), `9b830a0` (T3), `2c39579`
  (T4), `850effa` + `442c742` (T5 + review fix), `1d0dadc` (final-review
  fixes touching this plan's types).
- **Diverged:** Tasks 2 and 3 were one dispatch and one review. `EngineWireParser`
  also joins a `lines` array for `help`/`models`, renders `status_report` as
  one line and `exported` as "Exported to <path>" (final review, checked
  against a live payload). `EngineTranscript` gained `loadingText`.
  `EngineSession` gained `EngineSessionError`, an isolated `deinit`, a
  one-shot `start()`, and a `resolve(_:)` fix for relative capture paths.
- **Added tests beyond the plan:** `interruptByteMidTurn`,
  `droppedSessionTerminatesTheEngine`, `closedCapturePathResolvesSessionDirectory`,
  `startIsOneShot`, `loadingTextClearedOnFirstInput`, `exportedNamesThePath`,
  `statusReportIsOneReadableLine`.
- **Descoped:** nothing. Deferred minors are in the final review record.
