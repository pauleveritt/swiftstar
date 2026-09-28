---
phase: P28
cycle: P28-ds4-engine-cutover
lifecycle: active
---

# P28 ds4-engine cut-over implementation plan

> **For agentic workers:** execute with superpowers:subagent-driven-development.
> Local plan rule (`docs/sdd.md`): tasks name files, interfaces and tests; no bodies.

**Goal:** SwiftStar drives ds4-engine as a child process over
`ds4-dogfood tui --ndjson`, and every trace of the ds4 fork, the host-tools
agent loop, the pool, and the two CLIs is gone.

**Architecture:** A pure `EngineWireParser` (SwiftStarKit) turns stdout lines
into `EngineEvent`s; `EngineTranscript` and `EngineMetricsReducer` fold those
into view state; `EngineSession` (SwiftStarAppKit) owns the process; a thin
`EngineController` (app) binds it to the existing transcript views. New code
lands beside the old first, the app switches over, then the old code is
deleted in one pass the compiler polices.

**Tech stack:** Swift 6.2, Swift Testing, macOS 26; Python 3 (recorder,
fake engine); ds4-engine's `ds4-dogfood`. **Spec:** `docs/superpowers/specs/2026-09-28-p28-ds4-engine-cutover-design.md`

## Global constraints

- Swift language mode 6 everywhere; the `SwiftStar` target keeps
  `.defaultIsolation(MainActor.self)`.
- Wire: `tui --ndjson` only, `protocol == 1`. Never `--json-events`.
- argv is exactly `tui --ndjson --source <project root> --commit HEAD`;
  model, context size, capture dir are left to ds4-engine.
- Executable resolution order: Settings path → `PATH` → `~/.local/bin/ds4-dogfood`.
- Fast tier (`SwiftStarKitTests`): no subprocess, no network, no model — the
  `FastTierGuard` plugin enforces it. Fixtures are read via `#filePath`.
- Integration tests are gated by
  `@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))`.
- No Apply button, no model chooser, no session picker, no host sampling.
- Commit after each task with the attribution line
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review focus

1. **`ds4-dogfood` not found** (fresh Mac, GUI `PATH`). Expect a visible
   message naming the three places searched, not a silent no-op → Task 3.
2. **Engine exits during startup** (no model on this Mac → exit 2; bad
   install → exit 1). Expect the mapped message plus the stderr tail in the
   transcript, and the prompt field disabled → Task 5.
3. **Prompt sent while busy.** Expect it forwarded (engine queues it), shown
   as a user row, and no second "busy" state → Tasks 4, 5.
4. **Window closed / app quit mid-turn.** Expect `quit`, stdin closed,
   SIGTERM after the timeout, and no orphaned `ds4-dogfood` → Task 5.
5. **Upstream adds an event kind or field.** Expect `.ignored`, never a
   protocol error; only a bad handshake or non-JSON line is fatal → Task 2.

## Execution lanes

**Code** (Tasks 1–7, sequential: a TDD red step breaks the shared build)
runs in parallel with **docs** (Task 8, Markdown and `.claude/` only, no
`swift build`); Task 9 joins them. Stage explicit paths; retry on `index.lock`.

---

### Task 1: Record engine fixtures (live, no Swift)

**Files:**
- Create: `Tools/record-engine-fixture.py`
- Create: `fixtures/engine/tool-read.ndjson`, `fixtures/engine/stop.ndjson`,
  `fixtures/engine/error.ndjson`, `fixtures/engine/provenance.md`
- Modify: `Justfile` — replace the `capture` recipe body

**Interfaces:**
- Produces: raw stdout lines of `ds4-dogfood tui --ndjson`, one JSON object
  per line, unwrapped (no timestamps added), consumed by Tasks 2, 4, 5.
- CLI: `record-engine-fixture.py <ds4-dogfood> <source> <scenario> <out.ndjson>`
  with scenarios `tool-read` (prompt: "Use the read tool on Package.swift,
  then answer in English: what targets does it declare?", seed 7),
  `stop` (prompt asking to read and summarize every file under
  `Sources/SwiftStarKit/` one at a time; sends `{"kind":"stop"}` after the
  first `tool_result`), `error` (sends `{"kind":"bogus"}` at the first
  `input`, then `quit`). All scenarios end with `quit` at the next `input`.
- `just capture SCENARIO` runs the recorder with `ds4-dogfood` from `PATH`
  or `$DS4_DOGFOOD`, source = repo root, capture dir under a temp dir.

- [ ] **Step 1:** Write the recorder (model it on the scratch probe: Popen,
  write each stdout line verbatim to the output, drive stdin per scenario,
  `--model-id laguna-xs-2.1 --context-size 20000 --seed <n>` plus
  `--capture-dir` in a `tempfile.mkdtemp()` subdirectory).
- [ ] **Step 2:** Record all three scenarios. Check by hand: first line is
  `{"kind":"ready","protocol":1}`; `tool-read` has ≥1 `tool_result` with
  `op` `read` and an `answer`; `stop` has an `interrupted` event; `error`
  has a `{"kind":"error"}` line. Re-record `tool-read` with another seed if
  it contains no tool call.
- [ ] **Step 3:** `provenance.md` (ds4-engine commit, model, context,
  seed, machine, date, command; "re-record when ds4-engine bumps protocol
  or schema_version"); rewrite the `capture` recipe; commit.

### Task 2: `EngineEvent` and `EngineWireParser`

**Files:**
- Create: `Sources/SwiftStarKit/EngineEvent.swift`
- Create: `Sources/SwiftStarKit/EngineWireParser.swift`
- Test: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`

**Interfaces (produces):**
- `public struct EngineTool: Equatable, Sendable { op: String; path: String? }`
- `public struct EngineToolResult: Equatable, Sendable { tool: EngineTool;
  resultKind: String; preview: String; truncated: Bool }`
- `public struct EngineAnswer: Equatable, Sendable { text: String;
  contextUsed: Int?; contextSize: Int?; durationMs: Double? }`
- `public struct PauseMetrics: Equatable, Sendable { prefillTokens: Int;
  prefillMs: Double; evalCount: Int; evalMs: Double; outputTokens: Int }`
  (from `checkpoint.snapshot`: `prefill_tokens`, `sync_ms`, `eval_count`,
  `eval_ms`, `output_tokens`)
- `public struct EngineMemory: Equatable, Sendable { allocatedBytes: Int64;
  budgetBytes: Int64; planGiB: Double? }`
- `public struct EngineSessionInfo: Equatable, Sendable { id: String;
  modelID: String?; contextSize: Int? }`
- `public enum EngineEvent: Equatable, Sendable` with cases `ready`,
  `loading(String)`, `session(EngineSessionInfo)`, `busy`, `idle`,
  `prompt(String)`, `narration(String)`, `thinking(String)`,
  `toolStart(EngineTool)`, `toolEnd(EngineTool, ok: Bool, durationMs: Double?)`,
  `toolResult(EngineToolResult)`, `answer(EngineAnswer)`,
  `pause(PauseMetrics)`, `memory(EngineMemory)`, `interrupted`,
  `awaitingInput`, `error(String)`, `closed(capturePath: String?)`,
  `protocolError(String)`, `ignored`.
- `public struct EngineWireParser: Sendable { public init();
  public mutating func parse(_ line: String) -> EngineEvent }` — stateful
  only in "have I seen `ready`".

Mapping: `ready` → `.ready` (protocol ≠ 1 → `.protocolError`); `status` →
`.loading(text)`; `input` → `.awaitingInput`; `error` → `.error(text)`;
`close` → `.closed(capturePath: nil)`; `event` by `event.kind`:
`session`, `prompt`, `narration`, `thinking`, `tool_start`, `tool_end`
(`status == "ok"`), `tool_result`, `answer`, `checkpoint`, `memory`,
`interrupted`, `native_start` → `.busy`, `native_end` → `.idle`, `closed`
→ `.closed(capturePath:)`; every other `kind`, and `diagnostic`, `queued`,
`stopping`, `quitting` → `.ignored`. A missing optional field yields `nil`,
never an error.

- [ ] **Step 1: failing tests** (all in `EngineWireParserTests`):
  - `firstLineMustBeReady` — `parse("{\"kind\":\"input\"}")` on a fresh
    parser is `.protocolError` whose text contains `input`.
  - `protocolTwoIsRefused` — `{"kind":"ready","protocol":2}` →
    `.protocolError` containing `"protocol 2"`.
  - `nonJSONIsProtocolError` — `"garbage"` after a valid ready →
    `.protocolError`.
  - `unknownEventKindIsIgnored` — `{"kind":"event","event":{"kind":"flux_capacitor"}}`
    → `.ignored`.
  - `toolReadFixtureDecodes` — over `fixtures/engine/tool-read.ndjson`:
    events contain `.toolResult` with `tool.op == "read"`,
    `tool.path == "Package.swift"`, non-empty preview; exactly one `.answer`
    with `contextUsed > 0`; ≥1 `.pause` with `evalCount > 0`; last
    non-ignored event is `.closed`.
  - `stopFixtureHasInterrupted` — `stop.ndjson` contains `.interrupted`.
  - `errorFixtureHasError` — `error.ndjson` contains `.error`.
  - `missingOptionalFieldsAreNil` — an `answer` event with only `text` →
    `EngineAnswer(text:, contextUsed: nil, contextSize: nil, durationMs: nil)`.
- [ ] **Step 2:** red (`swift test --filter EngineWireParserTests`) →
  implement (total over input) → full `swift test` green → commit.

### Task 3: `EngineCommand` and `EngineExit`

**Files:**
- Create: `Sources/SwiftStarKit/EngineCommand.swift`
- Test: `Tests/SwiftStarKitTests/EngineCommandTests.swift`

**Interfaces (produces):**
- `public enum EngineCommand { static let executableName = "ds4-dogfood";
  static func arguments(source: URL) -> [String];
  static func resolveExecutable(settingsPath: String?, pathEnv: String?,
  home: URL, isExecutable: (String) -> Bool) -> EngineResolution }`
- `public enum EngineResolution: Equatable, Sendable { case found(String);
  case notFound(searched: [String]) }`
- `public struct EngineExit: Equatable, Sendable { code: Int32;
  message: String; public static func describe(code: Int32,
  stderrTail: String) -> EngineExit }`

- [ ] **Step 1: failing tests:**
  - `argumentsAreExact` — `arguments(source: /tmp/r)` ==
    `["tui","--ndjson","--source","/tmp/r","--commit","HEAD"]`.
  - `settingsPathWins` — settings path executable → `.found(settingsPath)`
    even when `PATH` also has one.
  - `emptySettingsFallsToPATH` — `settingsPath: ""` and `PATH` `/a:/b` with
    only `/b/ds4-dogfood` executable → `.found("/b/ds4-dogfood")`.
  - `fallsBackToLocalBin` — nothing on `PATH` → `.found("<home>/.local/bin/ds4-dogfood")`.
  - `notFoundListsEverySearchedPlace` — nothing executable →
    `.notFound(searched:)` contains the settings path, each `PATH` entry
    joined with the name, and the `.local/bin` path.
  - `exitMessages` — code 0 message contains `"ended"`; 1 contains the
    stderr tail; 2 contains `"no model"`; 130 contains `"interrupted"`;
    42 contains `"42"`.
- [ ] **Step 2:** red → implement → green → commit.

### Task 4: `EngineTranscript` and `EngineMetricsReducer`

**Files:**
- Create: `Sources/SwiftStarKit/EngineTranscript.swift`
- Create: `Sources/SwiftStarKit/EngineMetrics.swift`
- Test: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`,
  `Tests/SwiftStarKitTests/EngineMetricsTests.swift`

**Interfaces:**
- Consumes: Task 2 types.
- Produces:
  - `public struct EngineToolCard: Equatable, Sendable { tool: EngineTool;
    ok: Bool?; durationMs: Double?; result: EngineToolResult? }`
  - `public enum TranscriptRow: Equatable, Sendable { case user(String);
    narration(String); thinking(String); tool(EngineToolCard);
    answer(EngineAnswer); system(String); error(String) }`
  - `public struct EngineTranscript: Equatable, Sendable { rows:
    [TranscriptRow]; isBusy: Bool; isAwaitingInput: Bool;
    mutating func apply(_: EngineEvent); mutating func appendUser(_: String);
    mutating func appendSystem(_: String) }`
  - `public struct EngineMetricsState: Equatable, Sendable { prefillTPS:
    Double?; generationTPS: Double?; contextUsed: Int?; contextSize: Int?;
    gpuAllocatedBytes: Int64?; gpuBudgetBytes: Int64?; planGiB: Double? }`
  - `public enum EngineMetricsReducer { static func reduce(_: inout
    EngineMetricsState, _: EngineEvent) }`

Rules: `toolStart` appends a card; `toolEnd`/`toolResult` fill the most
recent card with the same `op`+`path` still missing that field; `.prompt`
events are ignored (the user row is appended by the controller at send
time, so queued prompts appear once); `.error` → `.error` row; `.busy` /
`.idle` / `.awaitingInput` set flags only; `.interrupted` → `.system("Stopped.")`.
Metrics: tok/s = tokens / (ms / 1000), `nil` when ms ≤ 0.

- [ ] **Step 1: failing tests:**
  - `toolReadFixtureBuildsRows` — replaying `tool-read.ndjson` gives ≥1
    `.tool` card with `ok == true` and a non-nil `result`, then exactly one
    `.answer`, and ends with `isAwaitingInput == false` after `.closed`.
  - `toolResultJoinsItsCard` — two consecutive reads of the same path each
    get their own result (no double-fill).
  - `promptEventDoesNotDuplicateUserRow` — `appendUser("x")` then
    `apply(.prompt("x"))` → one `.user` row.
  - `interruptedAddsStoppedRow` — `stop.ndjson` ends with a
    `.system("Stopped.")` row before the last answer/close.
  - `pauseComputesRates` — `PauseMetrics(prefillTokens: 682, prefillMs:
    827.3, evalCount: 8, evalMs: 61.2, …)` → prefill ≈ 824 tok/s,
    generation ≈ 130.7 tok/s (±0.5).
  - `zeroDurationGivesNil` — `evalMs: 0` → `generationTPS == nil`.
  - `answerAndMemoryFillContextAndGPU` — from `tool-read.ndjson` the final
    state has `contextUsed > 0`, `contextSize == 20000`,
    `gpuBudgetBytes > 0`.
- [ ] **Step 2:** red → implement → green → commit.

### Task 5: `EngineSession` and the fake engine

**Files:**
- Create: `Sources/SwiftStarAppKit/EngineSession.swift`
- Create: `fixtures/engine/fake-ds4-dogfood` (Python 3, `chmod +x`)
- Test: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`

**Interfaces:**
- Consumes: Tasks 2, 3.
- Produces: `public final class EngineSession: @unchecked Sendable` with
  `init(executable: String, arguments: [String], environment:
  [String: String]? = nil, workingDirectory: URL? = nil)`,
  `var onEvent: (@Sendable (EngineEvent) -> Void)?`,
  `var onExit: (@Sendable (EngineExit) -> Void)?`,
  `func start() throws`, `func send(prompt: String) throws`,
  `func stop() throws`, `func interrupt() throws`,
  `func quit(timeout: Duration = .seconds(5))`,
  `private(set) var sessionDirectory: URL?`, `var isRunning: Bool`.
  Follow `AgentSession`'s existing `Process`/`Pipe`/`LineBuffer` handling;
  do not import anything from the old wire. On `.protocolError` it sends
  SIGTERM and reports `EngineExit` with the protocol message. Keeps the last
  4 KiB of stderr for `EngineExit.describe`, and parses
  `Session artifacts: <dir>` from stderr into `sessionDirectory`.
- Fake engine: env `FAKE_ENGINE_FIXTURE` (path) and optional
  `FAKE_ENGINE_EXIT` (code, default 0). Writes fixture lines up to and
  including each `{"kind":"input"}`, then reads stdin: `prompt` → continue
  replay; `stop` or byte `0x03` → emit an `interrupted` event and `input`;
  `quit` or EOF → emit `quitting`, `close`, exit with the code. Prints
  `Session artifacts: /tmp/fake-session` to stderr at start. On SIGTERM
  exits 130.

- [ ] **Step 1: failing tests** (`EngineSessionTests`, integration-gated):
  - `promptRoundTrip` — fixture `tool-read`: after `start()` and first
    `.awaitingInput`, `send(prompt:)` yields `.answer` then `.awaitingInput`;
    `quit()` → `onExit` code 0, `isRunning == false`.
  - `stopMidTurn` — `stop()` after the first `.toolStart` → `.interrupted`
    observed.
  - `badHandshakeTerminates` — fixture whose first line is
    `{"kind":"input"}` → `.protocolError`, then `onExit` whose message
    names the protocol problem; process gone within 5 s.
  - `exitTwoIsNoModel` — fake with `FAKE_ENGINE_EXIT=2` quitting at once →
    `EngineExit.message` contains `"no model"`.
  - `sessionDirectoryFromStderr` — `sessionDirectory?.path == "/tmp/fake-session"`.
  - `quitAfterTimeoutSendsSIGTERM` — fake variant that ignores `quit`
    (env `FAKE_ENGINE_IGNORE_QUIT=1`): `quit(timeout: .seconds(1))` →
    process gone, exit code 130.
  - `sendWhileBusyIsForwarded` — two `send(prompt:)` calls before the next
    `.awaitingInput`: the fake records received prompts to
    `FAKE_ENGINE_LOG`; both appear there.
- [ ] **Step 2:** red (`SWIFTSTAR_INTEGRATION=1 swift test --filter
  EngineSessionTests`) → implement → green → commit.

### Task 6: Switch the app to the engine

**Files:**
- Create: `Sources/SwiftStar/EngineController.swift`
- Modify: `Sources/SwiftStar/SwiftStarApp.swift`, `MainView.swift`,
  `InspectorView.swift`, `AgentView.swift`, `AgentBubbles.swift`,
  `AgentToolCardView.swift`, `MetricsModel.swift`, `MetricsView.swift`,
  `SettingsView.swift`
- Delete: `Sources/SwiftStar/AgentController.swift`,
  `AgentPoolTurnLoop.swift`, `ActiveWorkerTurn.swift`,
  `DiagnosticsModel.swift`, `DiagnosticsView.swift`

**Interfaces:**
- Consumes: Tasks 2–5.
- Produces: `@Observable final class EngineController` with
  `transcript: EngineTranscript`, `metrics: EngineMetricsState`,
  `phase: Phase` (`.idle`, `.starting`, `.running`, `.ended(EngineExit)`,
  `.notFound([String])`), `sessionDirectory: URL?`, `func start()`,
  `func send(_ text: String)` (appends the user row, then forwards),
  `func stop()`, `func quit()`. Engine callbacks hop to the main actor.
  Settings key `engineExecutable` (`@AppStorage`), empty by default.

Behaviour: start resolves via `EngineCommand.resolveExecutable`
(`PATH` from `ProcessInfo`), source = `ProjectRoot` for the chosen project;
`.notFound` shows the searched list; on `.ended` the transcript gains a
system row with the exit message and, if known, the session directory and
`ds4-dogfood apply <id>`. The prompt field is enabled whenever the process
runs (queueing is the engine's job). Stop button → `stop()`. App
termination and window close → `quit()`. Metrics view shows only
`EngineMetricsState` fields (prefill/generation tok/s, context gauge, GPU
memory); drop power/CPU/resident gauges and the Diagnostics inspector tab.

- [ ] **Step 1:** Write `EngineController`; rewire views (drop branches for
  removed rows: `consulted`, `compaction`, `WorkerId`); delete the five files.
- [ ] **Step 2:** `swift build` and `swift test` green (old Kit/AppKit
  files may still compile unused); commit.

### Task 7: Remove everything else

**Files (delete unless noted):**
- `external/ds4` (`git rm`), `.gitmodules`.
- `Sources/swiftstar-eval/`, `Sources/swiftstar-agenttest/`.
- `Sources/SwiftStarAppKit/`: all but `EngineSession.swift`,
  `SubprocessRunner.swift` (keep only if something kept uses it; else
  delete), and `Resources/` removed with `golden.*`.
- `Sources/SwiftStarKit/`: every file in the spec's "Removed" list; then
  any file no kept file references (verify by `grep` of its public types).
  Old `AgentTranscript.swift`, `AgentWireParser.swift`, `MetricsReducer.swift`,
  `TurnOutcome.swift`, `TurnSummary.swift`, `DialLogic.swift` go unless a
  view still needs a helper — move such a helper into the view file.
- `Tests/SwiftStarKitTests/`, `Tests/SwiftStarIntegrationTests/`: every
  test of a deleted unit, `FakeAgentHarness.swift`,
  `FakeProcessHarness.swift` (if only download tests used it),
  `GitFixtureRepo.swift`, `PollingLineReader*` (if unused).
- `fixtures/agent/`, `fixtures/agenttest/`, `fixtures/diagnostics/`.
- `Tools/`: everything except `make-app.sh`, `make-icon.swift`,
  `record-engine-fixture.py`.
- Modify `Package.swift`: remove the two CLI targets, the `IOReport`
  linker setting, AppKit `resources:` if the directory is gone.
- Modify `Justfile` (drop `engine`, `eval`) and `Tools/make-app.sh` (drop
  removed resources, if bundled).

- [ ] **Step 1:** Delete in bulk; fix `swift build` only by deleting orphans.
- [ ] **Step 2:** Orphan sweep: for each remaining `SwiftStarKit` file,
  confirm a kept source or test references one of its types; delete those
  that are not.
- [ ] **Step 3:** Success check (spec criterion 1):
  `git grep -il -e ds4-agent -e external/ds4 -e submodule -- Sources Tests Package.swift Justfile`
  prints nothing, and `.gitmodules` does not exist.
- [ ] **Step 4:** both test tiers green; `just app` builds; commit.

### Task 8: Docs (parallel lane)

**Files:**
- Modify: `BRIEF.md` ("What we are building", "Architecture, settled",
  "The fork" → "The engine", "Testing", "Practical environment", "Where to
  start"), `ROADMAP.md`, `README.md`, `docs/glossary.md`, `CLAUDE.md`
  (drop "Session telemetry"), any `docs/*.md` page that documents a removed
  CLI or the fork.
- Delete: `.claude/skills/telemetry/`, and any `.claude/skills/` entry that
  drives a removed CLI.

Rules: rewrite, don't annotate; BRIEF describes post-P28 SwiftStar, cites
the spec, and records the reopening in one dated sentence. ROADMAP: P28 row
(Status "in progress", caps 900/1,000), `## Now`, a one-line Status note on
each row whose machinery P28 removes, Backlog entries that assumed the fork
closed or re-homed. `docs/superpowers/` history is not edited.

- [ ] **Step 1:** Edit; `just lint-docs` green; `just docs` green (fix any
  broken cross-reference to a removed page); commit (docs paths only).

### Task 9: Live verification and close (joins both lanes)

- [ ] **Step 1:** `just app`, launch `.build/SwiftStar.app` with
  `ds4-dogfood` installed and Laguna XS present. Check spec success
  criterion 3: a `read` tool card with preview, an answer, metrics after
  the pause, Stop mid-turn, quit leaves no `ds4-dogfood` (`pgrep`), and the
  session directory + apply command is shown.
- [ ] **Step 2:** Whole-branch review and fixes; plan `## Result` +
  `lifecycle: closed`; ROADMAP P28 Status; `just lint-docs` green; commit.
