# AN.2 Implementation Plan (second attempt): fork and return

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (name plus a one-line assertion). It doesn't paste code
> bodies. Load the `ui-loop` skill before Task 5.

**Goal:** **Analyze** on the last answer forks the session by resuming it,
shows AN.1's report and asks the model about it in the fork. **Done**
resumes the original, so the main context comes back as it was.

**Architecture:**
- **Kit** holds the analysis state: forking, then analyzing, then
  returning. It learns the session directory from the checkpoint's
  `capture_path`, and builds the fork's argv and Done's `/resume <id>`.
- **The engine target** runs the bundled report through a `ProcessRunner`
  extracted from the catalog loader.
- **The controller** forks with EN.1's `relaunch(_:)`, sends the analysis
  prompt once the fork is at `input`, and sends Done's `/resume`.
- **The views** add the link, the card, the banner and the composer tint.

The wire and the engine are unchanged.

**Tech stack:** Swift 6.2, SwiftPM, Swift Testing, SwiftUI (macOS 26),
stdlib Python.

**Spec:** [`2026-10-13-an-session-analysis-design.md`](../specs/2026-10-13-an-session-analysis-design.md),
§3 **as revised by its `## Revision, 2026-10-13`** (D4, §3.1, §3.4 and the
AN.1 additions). The first attempt and its measurements are in
[`2026-10-13-an2-analyze-and-done.md`](2026-10-13-an2-analyze-and-done.md)'s
Result. `E/` is `../ds4-engine` at `5451cd7d`.

## Global Constraints

- **Builds:** warnings are errors (`Package.swift:13`); no new dependencies.
- **Fast tier:** spawns nothing (`just test`'s grep).
- **Tests:** each new test is shown to fail under a break, recorded in
  `## Result` (BRIEF rule 2); a refusal has a success twin (rule 4); no
  source-text assertions (rule 3).
- **UI:** every touched `#Preview` is rendered with `RenderPreview` on the
  `SwiftStarUI` scheme and looked at. Previews never start the engine or
  run the script (`ui-loop`).
- **Copy, exactly (the revision's §3.1):**
  - **link:** `Analyze`
  - **while forking:** `Starting analysis…`
  - **fork divider:** `Analysis — a copy of this session`
  - **banner:** `Analyzing a copy — Done returns to the session as it was`
  - **button:** `Done`
  - **placeholder:** `Ask about the analysis…`
  - **prompt bubble:** `Analyze the session report above`
  - **return divider:** `Analysis ended — back at prompt k`
  - **instruction:** `Explain each flagged step: what the model was trying to
    do, and why it failed or was wasted. Then propose remedies. Don't edit
    files.`
- **Out of scope:** AN.3, AN.4, a chart card, and making `/rewind` keep
  saved state.

## Decisions (made while planning)

- **P1. The fork's argv** is `["tui", "--resume", <main dir>, "--source",
  <source>, "--ndjson"]`.
  - This is `restart_argv`'s shape for a start with no extra flags
    (`E/src/ds4_engine/tui_cli.py:412-416`), with the wire flag last
    (TUI.34). SwiftStar starts with no extra flags (`EngineCommand.swift:13-19`).
  - The model and context size are the resumed session's own, so none are
    passed.
- **P2. Done is `/resume <main id>`,** where the id is the main directory's
  name, as `resumed.session` reports it. The engine's own `relaunch` argv
  runs it, through EN.1's path.
- **P3. The report is loaded before forking,** from the main directory at
  its pause, which gate 2 showed works. It is held in the analysis state
  until the fork reaches `input`.
- **P4. The states** (`EngineAnalysis.Stage`):
  - `.forking(main, report)`
  - then `.analyzing(main, firstRow)` on the fork's `.resumed`
  - then `.returning(main)` when Done is sent
  - cleared on the return's `.resumed`

  Any other `.resumed`, a `didExit`, or a `didStart` clears it.
  `didRelaunch` keeps it, since both the fork and the return are relaunches.
- **P5. The analysis prompt is sent once.** It goes when the fork is at
  `input`, through `takeAnalysisPrompt()`, which returns the prompt once and
  then nil.
- **P6.** `ProcessRunner` is extracted from `EngineModelCatalogLoader`; its
  existing tests are the regression check. The controller's report loader
  is injectable.
- **P7. Stop rule:** if Task 1's loop check fails any pass line in the
  revision's §3.4, stop after Task 1 and report.

## Review Focus

Most likely to bite first:
1. **Analyze while busy or with a queued prompt:** hidden, nothing
   happens. Task 3 `cannotAnalyzeWhileBusy` and `cannotAnalyzeWithQueuedPrompt`.
2. **The script fails:** one error row, no fork, the session untouched.
   Task 5 `analyzeFailureDoesNotFork`.
3. **The fork refuses to start** (the engine exits before `ready`): the
   analysis state is cleared, and the error says the main session can be
   resumed. Task 3 `exitWhileForkingEndsAnalysis`.
4. **Done twice, or Done while the analysis is generating:** one `/resume`,
   sent only when idle. Task 3 `doneOnlyOnceAndOnlyIdle`.
5. **`/model` during analysis:** the analysis ends with that relaunch's
   divider, and no banner remains. Task 3 `otherRelaunchEndsAnalysis`.

---

### Task 1: The loop, live (nothing committed but the Result)

**Files:** a throwaway stdlib driver in the plan's ignored workspace
(`.superpowers/sdd/<plan>/`), speaking `--ndjson` to
`~/.local/bin/ds4-dogfood` on `qwen3.8-27b`, with this worktree as source.

**Steps:**
- [ ] Main session (`tui --ndjson --source <root> --model-id qwen3.8-27b`):
  two short prompts, then `quit`. Record its directory.
- [ ] Fork: start P1's argv. Record the time to `input`, then one question
  and its first checkpoint's `sync_ms`.
- [ ] Return: send `/resume <main id>`. Record the `resume_refused` event's
  `relaunch` argv, then quit and start that argv.
- [ ] For the return, record:
  - the time to `input`
  - `resumed.turns`, which must be the main's two only
  - one prompt and its `sync_ms`
  - whether the main directory's `conversation.kv` still exists
- [ ] Apply P7. Write the measurements into `## Result` and commit.

### Task 2: AN.1 additions (Python)

**Files:**
- Modify: `Sources/SwiftStarEngine/Resources/session_last.py`
- Modify: `.claude/commands/last.md`
- Test: `Tools/tests/test_session_last.py`

**Interfaces:**
- `SLOW_SYNC_MS = 10_000`
- A rule `R1`, slow sync, on a prompt: a `checkpoint` whose `sync_ms` delta
  is over `SLOW_SYNC_MS`. The evidence is `prefill N tokens in S s`.
- `CHECKS` becomes `("F1", "F2", "F3", "U1", "U2", "R1")`.

**Tests:**
- [ ] Write them:
  - `test_slow_sync_flagged`: two inline checkpoints, with Δ`sync_ms`
    242,274 over 37,764 tokens, give R1 with evidence containing `37,764`
  - `test_fast_sync_not_flagged`: Δ`sync_ms` 393 gives no R1
  - `test_no_flags_names_checks` is updated to list R1
- [ ] See them fail, then implement. Also add to `last.md`: "the
  conversation the model saw is `conversation.json` in the session
  directory." `just test-tools` passes. Commit.

### Task 3: Kit — directory, analysis state, argv

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift:149-162`: `PauseMetrics.capturePath: String?`
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift:95-103`: read
  `snapshot.capture_path`
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift:74-84`:
  `case report(String)`, plus `appendReport(_:)`
- Modify: `Sources/SwiftStarKit/EngineSessionModel.swift`: the state and
  methods below; `send(_:shown:)`
- Modify: `Sources/SwiftStarKit/EngineCommand.swift`: `forkArguments`,
  `reportArguments`
- Test: `Tests/SwiftStarKitTests/EngineSessionModelTests.swift`,
  `EngineWireParserTests.swift`, `EngineCommandTests.swift`

**Interfaces:**
- `public struct EngineAnalysis: Equatable, Sendable { enum Stage: Equatable, Sendable { case forking(main: URL, report: String), analyzing(main: URL, firstRow: Int, promptSent: Bool), returning(main: URL) }; var stage: Stage }`
- `EngineSessionModel.sessionDirectory: URL? { get }`, set from the first
  `.pause` that has a `capturePath`, and cleared by `didStart` and
  `didRelaunch`
- `EngineSessionModel.analysis: EngineAnalysis? { get }`
- `EngineSessionModel.canAnalyze: Bool`: `.running`, not busy, nothing
  pending, a directory known, and `analysis == nil`
- `EngineSessionModel.beginAnalysis(report: String, source: URL) -> EngineRelaunch?`:
  sets `.forking`, appends a `Starting analysis…` system row, and returns
  the fork relaunch (`kind: .resume`, P1's argv). Nil if `!canAnalyze`.
- `EngineSessionModel.takeAnalysisPrompt() -> (text: String, shown: String)?`:
  only in `.analyzing` with `promptSent == false` and the transcript at
  `input`. It appends the report row, marks the prompt sent, and returns
  the report plus the instruction.
- `EngineSessionModel.analysisDoneCommand: String?`: `/resume <main dir
  name>` in `.analyzing` when idle; otherwise nil
- `EngineSessionModel.markAnalysisReturning()`
- `.resumed` handling: `.forking` becomes `.analyzing` with the fork
  divider; `.returning` clears the state with the return divider
  (`k = turns.count`); any other stage clears it with the usual divider
- `EngineSessionModel.send(_ text: String, shown: String? = nil) -> Bool`
- `EngineCommand.forkArguments(sessionDirectory: URL, source: URL) -> [String]`
- `EngineCommand.reportArguments(script: URL, sessionDirectory: URL) -> (executable: String, arguments: [String])`:
  `/usr/bin/python3 -I -B <script> --session <dir>`

**Tests:**
- [ ] Write them:
  - `pauseCarriesCapturePath`: `tool-read.ndjson`'s first checkpoint
    ends `.partial.json`; its twin, a snapshot without the field, gives nil
  - `directoryFromFirstCheckpoint`: after `tool-read.ndjson`, the directory
    is `20261013-112927-swiftstar`
  - `relaunchClearsDirectory`
  - `canAnalyzeWhenIdleWithDirectory`
  - `cannotAnalyzeWhileBusy`, `cannotAnalyzeWithQueuedPrompt`,
    `cannotAnalyzeWithoutDirectory`
  - `beginAnalysisReturnsForkRelaunch`: the argv equals
    `["tui", "--resume", dir, "--source", src, "--ndjson"]`, the kind is
    `.resume`, and the stage is `.forking`
  - `forkResumedStartsAnalyzing`: the divider is the fork divider, and the
    stage is `.analyzing`
  - `analysisPromptOnceAtInput`: nil before `input`; then the prompt
    (containing the report and the instruction's first sentence) with the
    last row `.report`; then nil
  - `doneResumesMain`: gives `/resume 20261013-112927-swiftstar`
  - `doneOnlyOnceAndOnlyIdle`: nil while busy, and nil after
    `markAnalysisReturning()`
  - `returnResumedEndsAnalysis`: three turns give the divider `Analysis
    ended — back at prompt 3`, and `analysis == nil`
  - `otherRelaunchEndsAnalysis`: a `.resumed` in `.analyzing` gives the
    usual divider and `analysis == nil`
  - `exitWhileForkingEndsAnalysis`: `didExit` in `.forking` gives
    `analysis == nil`
  - `sendShownText`: `send("long", shown: "short")` appends
    `.user("short")`
  - `forkAndReportArguments`: both shapes, exactly
- [ ] See each fail, then implement. `just test` passes. Commit.

### Task 4: Engine — `ProcessRunner` and `SessionReportLoader`

**Files:**
- Create: `Sources/SwiftStarEngine/ProcessRunner.swift`, extracted from
  `EngineModelCatalogLoader.swift:16-80` (with `collect`)
- Modify: `EngineModelCatalogLoader.swift`: call it, with the same
  `CatalogError`s
- Create: `Sources/SwiftStarEngine/SessionReportLoader.swift`
- Test: `Tests/SwiftStarIntegrationTests/SessionReportLoaderTests.swift`

**Interfaces:**
- `public enum ProcessRunner { static func run(executable: String, arguments: [String], timeout: Duration, environment: [String: String]?) async -> Result<ProcessOutput, ProcessFailure> }`
- `ProcessOutput(stdout: Data, stderr: Data, code: Int32)`
- `enum ProcessFailure: Error, Equatable { case launch(String), timedOut }`
- `public struct SessionReportFailure: Error, Equatable { public let message: String }`
- `public enum SessionReportLoader`:
  - `static var bundledScript: URL?`
  - `static func load(sessionDirectory: URL, script: URL? = bundledScript, timeout: Duration = .seconds(10)) async -> Result<String, SessionReportFailure>`

  It builds its argv with `EngineCommand.reportArguments`.

**Tests:**
- [ ] Write them:
  - `reportFromFixtureSession`: the text starts with `**last**:
    20261013-123136-swiftstar`
  - `bundledScriptExists`
  - `missingScriptFails`: the message contains `not found`
  - `badSessionFails`: an empty directory gives a message containing
    `receipt.json`
  - the existing `EngineModelCatalogLoaderTests` pass unchanged
- [ ] See the new ones fail, then implement. `just integration` passes;
  `just app` builds, and the `.app`'s engine bundle contains
  `session_last.py` (record the `ls`). Commit.

### Task 5: Controller and views

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - `analyze()` and `doneAnalyzing()`
  - an injectable `reportLoader`
  - after each event in `handle(_:)`, send `takeAnalysisPrompt()` if it
    returns one
- Modify: `TranscriptView.swift`: the Analyze action on the last `.answer`
  only; a tinted leading rule from `firstRow`
- Modify: `TranscriptRowView.swift:22-35`: `Analyze` beside the summary,
  and a `.report` card with Copy Markdown
- Create: `Sources/SwiftStarUI/Session/AnalysisBanner.swift`
- Modify: `SessionView.swift:15-21` (the banner) and `ComposerView.swift:26`
  (the placeholder and tint)
- Modify: `PreviewSupport/PreviewFixtures.swift`: an analyzing model, and a
  report text written inline
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- `EngineController.analyze() async`:
  - `guard canAnalyze, let dir, let source`
  - load the report; on failure, `.error("Analyze: …")` and return
  - otherwise `relaunch(beginAnalysis(...))`
- `EngineController.doneAnalyzing()`:
  `guard let cmd = model.analysisDoneCommand`, then
  `markAnalysisReturning()`, then `send(cmd)`
- `AnalysisBanner(done: () -> Void)`

**Tests:**
- [ ] Write them (the fake engine and an injected loader; the fake must
  honour `--resume` by replaying `resumed.ndjson`, which it already does
  for relaunch):
  - `analyzeForksThenSendsPrompt`:
    - the second spawn's argv contains `--resume`
    - after `input`, the rows include `.report("R")`
    - the fake received a prompt containing `R`
  - `analyzeFailureDoesNotFork`: `.failure(SessionReportFailure(message:
    "boom"))` gives one spawn, an `.error` row containing `boom`, and
    `analysis == nil`
  - `doneSendsResumeMain`: after the analysis answer, the fake's input log
    contains `/resume <main dir name>`. The fake answers only `/rewind` and
    `/model` with a relaunch (`fake-ds4-dogfood:327`), so the return
    itself is checked live in Task 6.
- [ ] See them fail, then implement.
- [ ] Previews:
  - `TranscriptRowView`: "Answer with Analyze" and "Report card"
  - `SessionView`: "Analyzing" (its own `EngineController(model:)`)
  - `ComposerView`: "Analyzing"

  Render them, plus every existing preview in the touched files, and look
  at each. `just test` and `just integration` pass. Commit.

### Task 6: Live, and AN.2 closes

- [ ] **Live, with the owner's go-ahead** (`just app`, the 27B, this repo):
  - two prompts; Analyze; `Starting analysis…`, then the fork divider, the
    card and the banner; the model answers
  - one follow-up
  - Done gives the return divider with the two original prompts; a next
    prompt answers quickly
  - record both resume times, and that the main's `conversation.kv`
    survives
  - Analyze → Done a second time in the same session
- [ ] `/last` in a new Claude Code session (AN.1's open check).
- [ ] **Close:**
  - `## Result`
  - the AN.2 row shrinks to one line, and `## Now` points at AN.3 (not
    brainstormed)
  - `just lint-docs`, `just test`, `just integration`
  - commit once

## Result

Not started.
