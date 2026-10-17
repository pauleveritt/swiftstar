# AN.4: the report from ds4-engine

Analyze's report comes from `ds4-dogfood report <dir> --json`
(`ds4-session-report/1`, ds4-engine #231 and #233). SwiftStar decodes it
and renders it as Markdown. `session_last.py`, its tests and its math go.

The owner's call (2026-10-15): switch to `report --json` once the engine
stack is merged, and drop SwiftStar's own math. What the report lacks is
filed as [ds4-engine#246](https://github.com/pauleveritt/ds4-engine/issues/246),
so it isn't recomputed here. The work is on the branch `an4-engine-report`. It
runs against the installed engine, built from the top of the stack
(`1732611c`), and waits for the stack to merge.

## Decisions

- **D1. The seam stays a Markdown string.** `reportLoader` still returns
  the text that the report card shows and the fork's model reads, so
  `EngineAnalysis`, the model and the views don't change. Only the text's
  source changes. The rendering is in Kit, so it's tested in the fast tier.
- **D2. Render, don't compute.** Each figure is printed as the engine sent
  it, and each label sits next to its figure. Dropped: the per-pause
  first / median / last rates, the R1 slow-prefill rule (10 s), F3, U2's
  write rule, and the guard-notice match. The flagged steps are the
  report's: failed calls (`ok: false`), digest call flags, refused calls,
  compactions and loop-guard labels.
- **D3. Syncs with nothing to prefill are counted, not listed.** A prompt
  has dozens of 0-token syncs, labelled "nothing new to prefill". Every
  sync with tokens is listed, with its label or none. That's where the
  unlabelled 45-token sync at 57 tok/s shows (#246, item 1).
- **D4. An unknown schema fails.** A `schema` other than
  `ds4-session-report/1` is a failure. Analyze says so and doesn't
  guess at the fields. Missing optional fields render as "—".
- **D5. `just last` and `/last` use the engine.** They find the newest
  session with `sessions --json --limit 1`, then print `ds4-dogfood report`'s
  own text. An id or directory argument skips the lookup.
- **D6. An engine without `report`** shows `CatalogError.commandMissing`'s
  "this ds4-dogfood has no `report` command (update ds4-engine)".

## Tasks

1. **Kit: `SessionReport`.** New `Sources/SwiftStarKit/SessionReport.swift`
   - `struct SessionReport: Decodable, Equatable, Sendable`
   - `static let schema`
   - `static func decode(_: Data) -> Result<SessionReport, CatalogError>`
   - `var markdown: String`

   New `Tests/SwiftStarKitTests/SessionReportTests.swift`, over
   `fixtures/engine/report.json`:
   - `headerNamesSessionModelAndOutcome`: the first line is
     `**report**: 20261013-123136-swiftstar, qwen3.8-flash-next, …, answered`.
   - `failedAndRefusedCallsAreFlagged`: the flagged steps hold `run` failed
     and `refused: unknown-tool`, both under prompt 2.
   - `loopGuardLabelIsFlagged`: `loop guard fired: already_shown x2`.
   - `syncsWithTokensAreListedWithLabels`: the 45-token row has no label;
     a 32-token row reads `short batch, fixed cost`.
   - `emptySyncsAreCounted`: the 0-token rows aren't listed; their count is.
   - `otherSchemaFails`: `ds4-session-report/2` gives `.malformed` naming it.
   - `cellsEscapePipesAndNewlines`: a prompt text with `|` and a newline
     stays one cell.
2. **Engine: the loader.** `SessionReportLoader.load(executable:sessionDirectory:timeout:environment:)`
   runs `EngineCommand.reportArguments(sessionDirectory:)`
   (`["report", dir, "--json"]`) through `EngineJSONCommand`.
   - Delete `Resources/session_last.py` and its `Package.swift` resource.
   - `EngineController.reportLoader` becomes `(String, URL) async -> …`,
     and `analyze()` resolves the executable first.
   - The fake engine gains a `report` mode: it prints `FAKE_ENGINE_REPORT`,
     or refuses with "invalid choice" when that's unset.

   Tests:
   - `reportArgumentsAreExact`: `["report", "/s/x", "--json"]`.
   - `reportFromFakeEngine`: the Markdown starts `**report**: 20261013-123136-swiftstar`,
     and the fake got that argv.
   - `engineWithoutReportSaysUpdate`: the message contains "no `report` command".
3. **Tools and docs.**
   - The `just last` recipe, `test-tools` without `test_session_last.py`,
     and `.claude/commands/last.md`.
   - The provenance of `report.json` and of the session fixture.
   - `PreviewFixtures.previewReport` in the new shape, rendered with
     `RenderPreview`.
   - ROADMAP, CHANGELOG, `just lint-docs`, both tiers.

## Result

Built 2026-10-15 on the branch `an4-engine-report` and not merged: the
engine's `report` lives on ds4-engine's open stack (#231, #233).

- **Commits:**
  - `e1bceb4`, Task 1: `SessionReport` and the `report.json` fixture
  - `10fe3a5`, Task 2: the loader, the controller and the fake engine's
    `report` mode; `session_last.py` and its tests deleted
  - this commit, Task 3: tools, docs and close
- **Tests:**
  - Every new test failed when the behavior it pins was broken: the seven
    Kit tests, `reportArgumentsAreExact`, `reportFromFakeEngine` and
    `engineWithoutReportSaysUpdate`.
  - `just test`: 177 tests. `just integration`: 86, in 65 s, against the
    usual 13–19 s. The machine was busy, and no test failed.
- **Previews:**
  - TranscriptRowView's "Report card" renders the new report, with the
    Prefill table scrolling sideways (SU.13).
  - TranscriptView's "Analyzing" renders its tables with empty cells. That
    is old: the same render with `main`'s fixture is empty too.
  - SessionView's "Analyzing" shows the first frame of a bottom-anchored
    stack, which is blank (AN.2).
- **`just last`:**
  - Works on a directory, and with `--turn 2`.
  - Without an argument in this worktree, it says no session was found,
    because sessions are kept by checkout.
  - From the main checkout, the newest session (`20261014-090744`) is
    empty, and the engine refuses it ("holds neither operator-events.jsonl
    nor a run-*.json capture"). Telling #246 about it is an option.
- **Diverged from the plan:** none.
- **For the owner:**
  - D2's cuts: R1, the per-pause spread, F3 and U2's write rule.
  - A live Analyze, once the stack merges.
  - Merging the branch.

## Revision, 2026-10-17: `ds4-session-report/2`

The stack merged (#225 through #244), and #247 answered #246 as
`ds4-session-report/2`, which is `/1` with keys added. So AN.4 finishes on
`/2` before it merges.

- **D4, revised.** SwiftStar reads only `/2`. Koudai's schema rule is that a
  reader needing the new keys checks for `/2`, so a `/1` engine now fails
  with a clear message.
- **D2, revised.** These flags are back, as the engine's data:
  - a prompt with no answer (`answered`, with `interrupted` or `reason`)
  - engine errors per prompt (`errors[]`)
  - the call each loop-guard notice hit (`loop_guard`)
- **D7.** The session table gains:
  - Start-up: candidate ready and index primed
  - Continues: `earlier[]`, nearest first, with how many prompts are kept.
    This closes the AN follow-up "the report follows `resumed_from`".
  - Rewound
  - Ending: files changed, closed, telemetry and engine errors
  - DFlash: the label
  - Conversation state: per event, with its size and load time
  - Prefix cache: per event, with its prompt. The engine's label already
    carries the time saved or spent and, on a miss, what changed.

  A raw Signals section and the notes follow the prefill table.
- **D8. No slow-sync threshold.** The engine's spec leaves one to
  SwiftStar, but the owner's call is to drop SwiftStar's own math. A slow
  sync with no label shows as one.
- **Fixture.** `report.json` was re-recorded on `a84b79bd`. It now carries
  the two-tile label (45, 55 and 33 tokens). Its session predates key
  records, so its miss says "what changed was not recorded".
  `conversation_state`, an unanswered prompt and an engine error are
  tested on edited copies of it in the tests.

### Task 4: `/2`

- **Files:**
  - `Sources/SwiftStarKit/SessionReport.swift`: the new keys and rows
  - `Tests/SwiftStarKitTests/SessionReportTests.swift`: 14 tests
  - `fixtures/engine/report.json`
  - `PreviewFixtures.previewReport`
- **New tests, each with its assertion:**
  - `loopGuardNoticesAreFlaggedOnTheirCalls`: the Severity read under
    prompt 4.
  - `unansweredPromptIsFlagged`: `no answer (interrupted)`.
  - `engineErrorsAreFlagged`: the error's label.
  - `sessionRowsShowChainStartupAndState`: the Continues, Start-up, Ending
    and DFlash rows.
  - `prefixCacheRowIsTheEngineLabel`: the label, with its prompt.
  - `conversationStateIsShown`: label, size and load time.
  - `signalsAreRaw`: the result bytes and constraint lines.
  - `notesAreShown`: the engine's note.
  - `otherSchemaFails`: `/1` is refused.

### Result, Task 4

- **Mutation checks:** each new behavior was broken and its test failed,
  11 of 11. The errors and signals mutants first failed to compile, and
  were caught once rewritten so they did.
- **Tests:** `just test` (184) and `just integration` (86) pass.
- **Correction:** Task 3's Result put the 65 s integration run down to a busy
  machine. It is the same with nothing else running. The time is in older
  tests, such as SU.17's `aStaleReportIsDropped` at 12 s. AN.4's own tests
  take under 2 s. ROADMAP's "13–19 s" dates from SU.5.
- **Orphan:** a fake engine from a test run three days earlier had ignored
  SIGTERM. It was killed with SIGKILL. `FakeEngine.remove()` kills only
  `tui` processes, so this is worth a look if it happens again.
- **Previews:** the Report card renders the `/2` rows. The two "Analyzing"
  previews show the same first-frame limits as before.
