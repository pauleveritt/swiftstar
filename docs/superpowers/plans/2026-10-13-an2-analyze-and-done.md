# AN.2 Implementation Plan: Analyze and Done

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (name plus a one-line assertion). It doesn't paste code
> bodies. Load the `ui-loop` skill before Task 4.

**Goal:** an **Analyze** link on the last answer adds AN.1's report to the
transcript and asks the model about it. Follow-ups go through the same
composer, and **Done** rewinds the session to before the analysis.

**Architecture:**
- **Kit** learns the session directory from the checkpoint's `capture_path`,
  and holds the analysis state: where it started, how many prompts came
  before it, and Done's `/rewind N`.
- **Engine target:** `SessionReportLoader` runs the bundled
  `session_last.py`, over a `ProcessRunner` extracted from
  `EngineModelCatalogLoader`.
- **`EngineController`** gains `analyze()` and `doneAnalyzing()`.
- **Views** add the link, the report card, the banner and the composer tint.

The engine and the wire are unchanged: Done reuses `/rewind` and EN.1's
relaunch path.

**Tech stack:** Swift 6.2, SwiftPM, Swift Testing, SwiftUI (macOS 26), the
AN.1 script under `/usr/bin/python3`.

**Spec:** [`2026-10-13-an-session-analysis-design.md`](../specs/2026-10-13-an-session-analysis-design.md)
§3 and §5. AN.1 is [`2026-10-13-an1-session-report.md`](2026-10-13-an1-session-report.md);
its Result's deferred minors include "AN.2 should always pass `--session`".
`E/` is `../ds4-engine` at `5451cd7d`.

## Global Constraints

- **Builds:** warnings are errors (`Package.swift:13`); no new package
  dependencies.
- **Fast tier:** spawns nothing. `just test`'s grep refuses `Process(` in
  `Tests/SwiftStarKitTests`.
- **Tests:** every new test is shown to fail under a break of what it pins
  (BRIEF rule 2), and the break is recorded in `## Result`; a refusal has a
  success twin (rule 4); no source-text assertions (rule 3).
- **UI:**
  - every touched `#Preview` is rendered with `RenderPreview` on the
    `SwiftStarUI` scheme, and the image is looked at
  - previews never start the engine or run the script
  - controllers in previews come from `EngineController(model:)` (`ui-loop`)
- **Copy, exactly (spec §3.1):**
  - **link:** `Analyze`
  - **banner:** `Analyzing — Done discards everything below and returns to prompt k`
  - **button:** `Done`
  - **composer placeholder:** `Ask about the analysis…`
  - **divider:** `Analysis ended — back at prompt k`
  - **instruction:** `Explain each flagged step: what the model was trying to
    do, and why it failed or was wasted. Then propose remedies. Don't edit
    files.`
- **Out of scope:**
  - AN.3 (remedies)
  - AN.4 (moving into ds4-engine)
  - a chart card
  - the AN.1 deferred minors, except where a task names one

## Decisions (made while planning)

- **P1. The directory comes from the first `checkpoint`.**
  - `PauseMetrics` gains `capturePath`. The parser already reads the
    snapshot, which carries `capture_path` (`fixtures/engine/tool-read.ndjson`).
  - The model sets `sessionDirectory` to that path's parent.
  - `didStart` and `didRelaunch` clear it, because a relaunch is a new
    session directory.
  - Consequence: right after Done, Analyze stays hidden until the next
    prompt's checkpoint. The resumed session has no new data to report
    until then anyway.
- **P2. `k` is the count of `.user` rows when Analyze is clicked.**
  - Analyze needs an idle session, so every one of those prompts is
    answered.
  - Done sends `/rewind (user rows now − k)`. Because `/rewind N` is
    relative (`E/docs/tui.md`, "Rewinding a prompt"), this holds in a
    resumed session too.
- **P3. The prompt's bubble isn't the prompt's text.**
  - The engine gets the report plus the instruction.
  - The bubble reads `Analyze the session report above`, through
    `send(_:shown:)`.
  - The report is already on screen as the card, and the rebuild at Done
    drops both.
- **P4. Analysis ends at any rebuild.**
  - `.resumed` clears the analysis. If Done sent it, the divider is the
    analysis divider; otherwise, for example after a `/model` during
    analysis, it is the relaunch's usual one.
  - `didStart` and `didExit` clear it too.
- **P5. `ProcessRunner` is extracted from `EngineModelCatalogLoader`.**
  - It runs an argv with a timeout and returns stdout, stderr and the exit
    code, killing the child on timeout.
  - The catalog loader becomes a caller of it, and its existing integration
    tests are the regression check.
  - This avoids a second copy of ~70 lines of pipe and timeout code.
- **P6. The controller's report loader is injectable** (a closure with the
  real loader as default), so controller tests don't need a real session
  directory behind the fake engine.
- **P7. Gate outcomes (spec §3.4), decided before building:**
  - **Gate 1 fails** (repeated rewind is wrong): **stop after Task 1** and
    report to the owner with the evidence and a drafted ds4-engine request.
    Building Done on a rewind known to resume the wrong turns would lose
    the owner's conversation.
  - **Gate 2 fails** (the report can't read a live session): stop and
    report. The design needs a change.
  - **Gate 3:** "slow" means Done takes more than 10 s from sending
    `/rewind` to the engine's next `input`. Slow at large `ctx_used` does
    not stop AN.2; the limit is stated in the Result and an engine request
    for a KV-keeping fork is drafted.

## Review Focus

Most likely to bite first:
1. **Analyze while a prompt is queued, or while busy.** Hidden; nothing
   sent. Task 2 `cannotAnalyzeWhileBusy` and `cannotAnalyzeWithQueuedPrompt`.
2. **The script fails** (no `python3`, unreadable session, a timeout). One
   error row in the transcript; no analysis begins; the composer is usable.
   Task 4 `analyzeFailureAddsErrorAndNoAnalysis`.
3. **Done clicked twice, or Done while the analysis answer is still
   generating.** One `/rewind` sent; Done waits for idle. Task 2
   `doneOnlyOnceAndOnlyIdle`.
4. **A `/model` switch during analysis.** The analysis ends at the rebuild,
   with no banner left behind. Task 2 `otherRelaunchEndsAnalysis`.
5. **The app quits or the engine exits during analysis.** No banner on the
   next start. Task 2 `exitEndsAnalysis`.

---

### Task 1: The three gates (live, nothing committed but the Result)

**Files:**
- A throwaway live test in `Tests/SwiftStarIntegrationTests/`, gated on
  `SWIFTSTAR_LIVE=1`. It drives `EngineController` against the real
  `ds4-dogfood` on `qwen3.8-27b`, as EN.1's relaunch check did. It is
  deleted before commit.
- `just last --session <dir>` for gate 2.

**Steps:**
- [ ] **Gate 1, repeated rewind.**
  - Two prompts, then a third ("analysis"), then `/rewind 1`, waiting for
    the rebuild.
  - Another prompt, then `/rewind 1` again.
  - Each time, record the `relaunch` argv, `resumed.turns` and `rewound_to`.
  - **Pass:** the second rebuild shows exactly the turns before that
    rewind's prompt.
- [ ] **Gate 2, reading a live session.** At a pause, before any quit,
  run `just last --session <the dir from the checkpoint's capture_path>`.
  - **Pass:** exit 0, the prompts so far are present, and there is no
    warning except schema.
  - Record whether `receipt.json`'s `capture_path` named the
    `.partial.json` file at that moment.
- [ ] **Gate 3, Done's cost.** Time from sending `/rewind 1` to the next
  `input`, twice:
  - at a small `ctx_used` (under 5,000)
  - at a large one (a prompt that reads files until over 30,000)

  Record `candidate_ready` and the first `checkpoint`'s `sync_ms` in the new
  session.
- [ ] Write the three outcomes into `## Result`. Apply P7, and stop here if
  it says to. Delete the throwaway test. Commit the plan's Result only.

### Task 2: Kit — the session directory and the analysis state

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift:149-162`: `PauseMetrics`
  gains `capturePath: String?`
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift:95-103`: read
  `snapshot.capture_path`
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift:74-84`: a
  `case report(String)` row, plus `appendReport(_:)`;
  `appendUser(_:)` stays, and `send` passes the shown text to it
- Modify: `Sources/SwiftStarKit/EngineSessionModel.swift`:
  - `sessionDirectory`
  - `analysis`
  - `canAnalyze`
  - `beginAnalysis(report:)`
  - `analysisDoneCommand`
  - `markAnalysisEnding()`
  - `send(_:shown:)`
  - clearing on `didStart`, `didRelaunch` (directory only), `didExit` and
    `.resumed`
- Modify: `Sources/SwiftStarKit/EngineCommand.swift`: the report argv
- Test: `Tests/SwiftStarKitTests/EngineSessionModelTests.swift`,
  `EngineWireParserTests.swift`, `EngineCommandTests.swift`

**Interfaces:**
- `public struct EngineAnalysis: Equatable, Sendable { promptsBefore: Int; firstRow: Int; ending: Bool }`
- `EngineSessionModel.sessionDirectory: URL? { get }`
- `EngineSessionModel.analysis: EngineAnalysis? { get }`
- `EngineSessionModel.canAnalyze: Bool`: phase `.running`, transcript not
  busy, `pendingUserCount == 0`, a directory known, and `analysis == nil`
- `EngineSessionModel.beginAnalysis(report: String) -> String?`: appends
  the report row, records `k` and `firstRow`, and returns the prompt to
  send (the report plus the instruction). Nil when `!canAnalyze`.
- `EngineSessionModel.analysisDoneCommand: String?`: `/rewind N`, or nil
  when there is no analysis, it is already ending, or the transcript is busy
- `EngineSessionModel.markAnalysisEnding()`
- `EngineSessionModel.send(_ text: String, shown: String? = nil) -> Bool`
- `EngineSessionModel.analysisPrompt(report: String) -> String`, static
- `EngineCommand.reportArguments(script: URL, sessionDirectory: URL) -> (executable: String, arguments: [String])`.
  This gives `/usr/bin/python3` with `-I -B <script> --session <dir>`; at
  AN.4 it becomes `ds4-dogfood last`.

**Tests:**
- [ ] Write them:
  - `pauseCarriesCapturePath`: `tool-read.ndjson`'s first checkpoint
    parses with a `capturePath` ending `.partial.json`. Its twin: a
    snapshot without the field gives nil.
  - `directoryFromFirstCheckpoint`: after applying `tool-read.ndjson`,
    `sessionDirectory?.lastPathComponent == "20261013-112927-swiftstar"`
  - `relaunchClearsDirectory`: `didRelaunch` sets `sessionDirectory` to nil
  - `canAnalyzeWhenIdleWithDirectory`: true after one answered prompt and
    a checkpoint
  - `cannotAnalyzeWhileBusy`: false between `prompt` and `input`
  - `cannotAnalyzeWithQueuedPrompt`: false with a pending user row
  - `cannotAnalyzeWithoutDirectory`: false with no checkpoint seen
  - `beginAnalysisRecordsK`:
    - with 3 answered prompts, `analysis?.promptsBefore == 3`
    - the last row is `.report`
    - the returned prompt contains the instruction's first sentence
  - `doneRewindsAnalysisAndFollowUps`: `k` = 3, then the analysis prompt
    and two follow-ups answered, gives `analysisDoneCommand == "/rewind 3"`
  - `doneOnlyOnceAndOnlyIdle`: nil while busy, and nil after
    `markAnalysisEnding()`
  - `resumedAfterDoneUsesAnalysisDivider`: the divider is `Analysis ended —
    back at prompt 3`, and `analysis == nil`
  - `otherRelaunchEndsAnalysis`: a `.model` relaunch's `.resumed` gives
    the usual divider and `analysis == nil`
  - `exitEndsAnalysis`: `didExit` gives `analysis == nil`
  - `sendShownText`: `send("long", shown: "short")` appends `.user("short")`
  - `reportArgumentsShape`: the executable is `/usr/bin/python3`, and the
    arguments end `["--session", "/s/x"]`
- [ ] See each fail, then implement. `just test` passes. Commit.

### Task 3: Engine — `ProcessRunner` and `SessionReportLoader`

**Files:**
- Create: `Sources/SwiftStarEngine/ProcessRunner.swift`, extracted from
  `EngineModelCatalogLoader.swift:16-80` (`collect` moves with it)
- Modify: `Sources/SwiftStarEngine/EngineModelCatalogLoader.swift`: call
  `ProcessRunner.run`, with the same results and the same `CatalogError`s
- Create: `Sources/SwiftStarEngine/SessionReportLoader.swift`
- Test: `Tests/SwiftStarIntegrationTests/SessionReportLoaderTests.swift`
  (integration-gated, like its neighbours)

**Interfaces:**
- `public enum ProcessRunner { static func run(executable: String, arguments: [String], timeout: Duration, environment: [String: String]?) async -> Result<ProcessOutput, ProcessFailure> }`
- `ProcessOutput(stdout: Data, stderr: Data, code: Int32)`
- `enum ProcessFailure: Error, Equatable { case launch(String), timedOut }`
- `public enum SessionReportLoader`:
  - `static var bundledScript: URL?`, via `Bundle.module`
  - `static func load(sessionDirectory: URL, script: URL? = bundledScript, timeout: Duration = .seconds(10)) async -> Result<String, SessionReportFailure>`
- `public struct SessionReportFailure: Error, Equatable { public let message: String }`.
  The message is a one-liner for the transcript: the script's stderr tail,
  "timed out", or "report script not found".

**Tests:**
- [ ] Write them:
  - `reportFromFixtureSession`: `load(fixtures/sessions/20261013-123136-swiftstar)`
    succeeds, and the text starts with `**last**: 20261013-123136-swiftstar`
  - `bundledScriptExists`: `bundledScript` is non-nil and the file exists
  - `missingScriptFails`: a script URL that doesn't exist gives
    `.failure` containing `not found`
  - `badSessionFails`: an empty temporary directory gives `.failure`
    containing `receipt.json`
  - the existing `EngineModelCatalogLoaderTests` all pass unchanged
- [ ] See the new tests fail, then implement. `just integration` passes.
  `just app` builds, and the `.app`'s `SwiftStar_SwiftStarEngine.bundle`
  contains `session_last.py` (record the `ls`). Commit.

### Task 4: Controller and views

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - `analyze()` and `doneAnalyzing()`
  - `var reportLoader: (URL) async -> Result<String, SessionReportFailure>`, defaulting
    to `SessionReportLoader.load`
  - forwards `canAnalyze`, `analysis`
- Modify: `Sources/SwiftStarUI/Session/TranscriptView.swift`:
  - takes `analyzeAction: (() -> Void)?` and `analysisFirstRow: Int?`
  - passes the action to the last `.answer` row only
  - rows at or after `analysisFirstRow` get the tinted leading rule
- Modify: `Sources/SwiftStarUI/Session/TranscriptRowView.swift:22-35`:
  `Analyze` beside `answer.summary` when given an action, and a
  `case .report` card with Copy Markdown
- Create: `Sources/SwiftStarUI/Session/AnalysisBanner.swift`: the banner
  with `Done`
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift:15-21`: the banner
  above the transcript while analyzing
- Modify: `Sources/SwiftStarUI/Session/ComposerView.swift:26`: the
  placeholder and tint while analyzing
- Modify: `Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift`: an
  analyzing model and a report text (taken from the AN.1 fixture's output,
  inline)
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- `EngineController.analyze() async`:
  - `guard canAnalyze, let dir`
  - loader failure: `model.apply(.error("Analyze: \(message)"))`
  - success: `beginAnalysis`, then `send(prompt, shown:)`
- `EngineController.doneAnalyzing()`: `guard let cmd =
  model.analysisDoneCommand`, then `markAnalysisEnding()`, then
  `send(cmd)`
- `AnalysisBanner(promptsBefore: Int, done: () -> Void)`

**Tests:**
- [ ] Write them (controller over the fake engine with `tool-read.ndjson`
  and an injected loader):
  - `analyzeAppendsReportAndSends`:
    - after `analyze()`, the rows include `.report("R")` and
      `.user("Analyze the session report above")`
    - the fake engine received a prompt containing `R`
  - `analyzeFailureAddsErrorAndNoAnalysis`: a loader returning
    `.failure(SessionReportFailure(message: "boom"))` gives an `.error` row containing `boom`,
    `analysis == nil`, and the composer can send
  - `doneSendsRewind`: after the analysis answer, `doneAnalyzing()` sends
    `/rewind 1`
- [ ] See them fail, then implement.
- [ ] Previews:
  - `TranscriptRowView`: "Answer with Analyze" and "Report card"
  - `SessionView`: "Analyzing" (its own `EngineController(model:)`)
  - `ComposerView`: "Analyzing"

  Render each, plus every existing preview in the touched files, with
  `RenderPreview`, and look at each image. Record the preview names.
- [ ] `just test` and `just integration` pass. Commit.

### Task 5: Live, and AN.2 closes

- [ ] **Live, with the owner's go-ahead** (`just app`, the 27B, this repo):
  - two prompts; Analyze; the card, banner and tinted composer appear
  - the model answers about the flagged steps
  - one follow-up
  - Done: the rebuild shows the two original prompts, under the divider
    `Analysis ended — back at prompt 2`
  - a third prompt works
  - record Done's time
  - **if gate 1 passed:** a second Analyze → Done in the same session
  - **otherwise:** this step is skipped (P7)
- [ ] `/last` in a new Claude Code session (AN.1's open live check).
- [ ] **Close:**
  - write `## Result`: commits, the breaks, the gates, what diverged, and
    what was seen and not seen live
  - the AN.2 row shrinks to one line
  - `## Now` points at AN.3 (not brainstormed), or at the engine request
    if a gate stopped the cycle
  - `just lint-docs`, `just test`, `just integration`
  - commit once

## Result

**Stopped after Task 1, 2026-10-13: gate 1 failed** (P7, and the owner's
rule that Done must stay under 30 s). Tasks 2–5 were not started; no code
changed. The gates ran once, live, through `EngineController` on
`qwen3.8-27b` against this worktree, using a throwaway test (deleted). The
sessions are `20261013-153202`, `-153218` and `-153456`, all suffixed
`-session-last`, under `~/.local/state/ds4-engine/sessions/`.

**Gate 2, reading a live session: passed.** At a pause, the receipt named
the `.partial.json` capture, and `session_last.py --session` exited 0 with
both prompts, outcome `in-progress`, and no warning.

**Gate 3:** the first `/rewind 1`, at `ctx_used` 1,332, rebuilt in 2.8 s.
The large case is measured below.

**Gate 1, a second rewind in a rewound session: failed.**
- In session `153202`: "one", an `ls`, "three". `/rewind 1` gave `153218`
  with "one" and the `ls`: correct.
- In `153218`: a large read prompt, then `/rewind 1`, sent idle. Expected:
  "one" and the `ls`. Got (`153456`): `rewound_to 0`, divider "Rewound to
  prompt 0", and `resumed.turns` "one", the `ls` **and "three"**, a prompt
  the first rewind had removed. The read prompt was dropped, as it should be.
- This matches EN.1's finding, there with the `/rewind` queued behind a busy
  turn; here it was sent idle, so queueing is not the cause.
- **No hang, corrected.** The test reported 600 s without settling. Its
  wait was wrong, not the engine: it waited for the count of dividers to
  grow, but a rebuild *replaces* the rows with one divider. `153456`'s
  events end `candidate_ready` (2.3 s), `memory`, `where`, as `153218`'s do
  before a prompt, so the engine was most likely idle at `input` (not
  logged, so inferred). No lock or second engine was involved: ds4-engine
  has none, and `native.log` shows a normal load.

**A first rewind at large context, measured after (sessions `154825` →
`155435`):**
- The setup: a read prompt reaching `ctx_used` 37,744, then a short prompt
  (41,929).
- `/rewind 1` took **3.6 s** to rebuild.
- The next prompt took **243 s**: one sync prefilled 37,764 tokens in
  242.3 s, about 156 tok/s, with no `prefix_cache` event. The same prompt
  again took 1.5 s.
- So a rewind refills the whole restored conversation, at about 8× the
  owner's 30 s line at 37k.

**For AN:** Done can't be built on `/rewind`. Repeated rewind is wrong, and
a rewind refills from scratch, paid at the next prompt. Filed upstream with
the owner's approval.
