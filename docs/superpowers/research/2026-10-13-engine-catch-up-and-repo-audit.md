# Engine catch-up and repo audit (2026-10-13)

**Why:** ds4-engine landed 168 commits (`409267a9..5451cd7d`) and the owner
asked for a re-plan plus a deep dive into drift, fossils, over-engineering,
slimming and test consolidation. This is the evidence the re-plan in
`ROADMAP.md` rests on: §1 scopes EN.1, §2 and §3 scope SU.5, and §4 records
what the re-plan itself did to the docs.

**How:** three read-only sweeps covered the engine delta, SwiftStar's Swift
code and tests, and its docs and tooling. Each claim below names the check
behind it. "Read" means read in source; "ran" means executed. Repo paths are
relative to SwiftStar unless prefixed `E/` (`../ds4-engine` at `5451cd7d`).

## 1. The engine delta

### The "nothing touches the wire" note was wrong

The 2026-10-13 ROADMAP note said the `--ndjson` relay, `PROTOCOL` and the
`models --json` shape are unchanged, so nothing touches the wire contract.
- **The narrow part is true.** `E/src/ds4_engine/ndjson_process.py`,
  `json_events.py` and `tui_process.py` are byte-identical across the range
  (ran `git diff`). `PROTOCOL = 1` (`ndjson_process.py:28`) and
  `model_table()` (`tui_cli.py:180-206`) are unchanged.
- **The conclusion is false.** The relay forwards payloads untouched
  (`ndjson_process.py:64-65`). Those payloads are built in `tui_cli.py`,
  `operator.py`, `first_run.py`, `models.py` and the Rust driver, and all of
  them changed. Checking only the relay's own files measured the pipe, not
  what flows through it.

### What reaches SwiftStar

| Change | Evidence | SwiftStar today | Severity |
|---|---|---|---|
| Laguna, Mellum and DeepSeek ids removed; an explicit unknown `--model-id` exits 2 before `ready` | `E/src/ds4_engine/first_run.py:349-352`; commit `12a0289c` | Saved setting is `engineModelID = laguna-xs-2.1` (ran `defaults read`). `EngineCommand.swift:17` passes it. **Ran:** the engine exits 2 with `unknown model id 'laguna-xs-2.1'` and writes no stdout, so no session starts until a model is picked from the menu | **breaks** |
| Default model is `qwen3.8-27b`; the list is the 27B plus Flash Next Q4/Q2 | `E/src/ds4_engine/tui_cli.py:60`; ran `models --json` | "Engine default" now means the 27B | degrades |
| `tool_rejected` emitted more often: loop guards `repeated-call`/`call-cycle`, `tools-closed` | `E/crates/ds4-native/src/loop_guards.rs:65-66`; `driver.rs:3108,3446,3726` | `EngineWireParser.swift:57-143` has no case; it is not `_refused`, so it is dropped silently (read) | degrades |
| `answer.text` is `finish`'s summary on the 27B; text before the call arrives as `narration` | `E/crates/ds4-host/src/contract/mod.rs:306` (`4116f423`) | A narration row plus an answer row that may repeat it (read; not seen live) | degrades |
| `*_refused` carries a `relaunch` argv for `/model`, `/rewind` and `/resume` (TUI.34, already at `409267a9`) | `E/src/ds4_engine/tui_cli.py:343-362`; `E/docs/tui.md:1771-1810` | Shown as an error telling the front-end to restart; never acted on | degrades |
| New events: `candidate_ready`, `prefix_cache`, `index_primed` | `E/src/ds4_engine/operator.py:218-235,674-679` | Ignored by the parser's default case | opportunity |
| `session` gains `dflash` (on, label, reason, plan_gib, budget) and loses `mask_retries` | `E/src/ds4_engine/tui_cli.py:1063-1084`; `dflash.py:40-48` | Parser reads only id, model and context size | opportunity |
| Prefix-cache hits count about 944 cached tokens as prefilled | `E/src/ds4_engine/operator_telemetry.py:100-113` | `prefillTPS` (`EngineMetrics.swift:30`) inflated on fresh turns | cosmetic |
| DFlash on by default; still one eval per token | `E/crates/ds4-host/src/engine.rs:386-392` | Generation rate formula still valid, about 3x higher | none |
| New stderr start lines (DFlash on/off, "saved model no longer offered") | `E/src/ds4_engine/dogfood_cli.py:498`; `first_run.py:340-345` | Appear only in an exit's stderr tail | cosmetic |
| All recorded fixtures are Laguna at `9d96bee0`; `models-real.json` lists removed ids | `fixtures/engine/provenance.md` | Tests pass, but the fixtures no longer show the real wire | cosmetic |
| `just capture` hard-codes Laguna | `Tools/record-engine-fixture.py:38` | Exits 2 before recording anything | **breaks** (tooling) |

### SwiftStar's engine requests and Backlog items, re-checked

- **"Rejected tool calls emit no event": stale.** TUI.36 (`defaf034`, an
  ancestor of `409267a9`) emits `tool_rejected` with `name`, `reason`,
  `path` and `text` (`E/docs/tui.md:1739-1763`). The gap is SwiftStar's
  parser.
- **"`/resume`, `/model`, `/rewind` re-exec in place": stale.** Under
  `--ndjson` they never re-exec (TUI.34, `5bcfd2f2`). They are refused with
  a `relaunch` argv starting at `tui`. The front-end sends quit, waits for
  the exit, then spawns that argv. `/model` relaunches as
  `--resume <id> … --model-id X --new-conversation`.
- **"`session` lacks the candidate worktree": still open.** `session`
  reports `source` and `commit`. `candidate_ready` carries only timings.
  `where.worktree` names the linked worktree you are in, not the
  candidate's (`E/src/ds4_engine/place.py:69-99`), so it must not be read
  as the edited copy.
- **Session picker: the engine side exists** (TUI.18).
  - `ds4-dogfood sessions --json [--source] [--all] [--limit]` lists
    sessions (`E/src/ds4_engine/sessions.py:344-366`).
  - `tui --ndjson --resume ID` or `--continue` resumes one; `resumed.turns`
    rebuilds the transcript (`E/src/ds4_engine/tui_cli.py:535-560`).
  - Catches: drop `--commit` when resuming (`:758-759`); pass a different
    `--model-id` only with `--new-conversation` (`:510-518`). Laguna-era
    sessions adopt their own, now-refused model id, so only
    `--new-conversation` recovers their files.
- **Token streaming: still excluded upstream.** The seam is the pause, never
  a per-token callback (`E/PRODUCT_BRIEF.md:50-52`).

### Engine direction, as it bears on SwiftStar

- **The entry point is unchanged:** `ds4-dogfood tui --ndjson`
  (`E/pyproject.toml:13`), with no new binary.
- **The C engine follows antirez's upstream** plus carried commits (P41).
  The agent host stays the engine's own; upstream `ds4-agent` is a
  comparison target, not a replacement (`E/ROADMAP.md:36`; the 2026-10-12
  agent-gap screen).
- **One default model,** `qwen3.8-27b`, with Flash Next Q4/Q2 opt-in on
  64 GB+ Macs. The memory target is 32 GB, with 16 GB as the goal
  (`E/PRODUCT_BRIEF.md:115-131`).
- **The release shape names SwiftStar.** SwiftStar, later Satyrn Agent,
  runs `tui --ndjson` as a child. A resident socket service is a later idea
  (`E/PRODUCT_BRIEF.md:95-100`).
- **The Satyrn rename has not landed.** The command name is "still open"
  (`E/docs/tui.md:1267`), and `pyproject.toml` has only `ds4-dogfood`. A
  rename would touch `EngineCommand.executableName` (`EngineCommand.swift:9`)
  and the `~/.local/state/ds4-engine` and `~/.config/ds4-engine` paths.
- **New capabilities SwiftStar could show:** resume and session listing;
  `relaunch`; `session.dflash`; declined calls; start-up timings; and
  `plan_gib` and `size_bytes` per model.
  - The `@` file picker lives only in the Textual presenter. There is no
    wire message for it, so it needs an app-side listing or a new
    `files --json` command.

## 2. Code findings (scope for SU.5a)

**Check:** every Swift file under `Sources/` and `Tests/` read in full at
`e390796`. Nothing was built for this section. Bugs are labelled
*certain* (mechanism read end to end) or *plausible* (trigger not observed).

### The SU.5 spec's items at HEAD, with corrections

- **§3.1 dead code: valid,** with four corrections.
  - `EngineSessionModel.sessionDirectory` (`EngineSessionModel.swift:59,71,96`)
    loses its last reader with `EngineController.sessionDirectory`; delete
    both.
  - `canStop`'s four tests should point at `isBusy`, not be deleted.
  - Removing the executable's `resources:` (`Package.swift:64`) needs
    `exclude: ["Resources"]`, or SwiftPM warns about an unhandled file,
    which breaks warnings-as-errors.
  - `MarkdownText`'s `public` is blocked: `SwiftStarApp.swift:41` calls
    its self-test, which nothing ever runs. Delete the self-test or wire it
    into `Tools/make-app.sh`, then drop `public`.
- **§3.3 duplication: valid, but undercounted.**
  - Grace periods have a third copy at `EngineSessionTests.swift:39`.
  - `"Session artifacts:"` also appears in the fake (`fake-ds4-dogfood:182`).
  - There are five trims, not three (`ComposerView.swift:83`,
    `SessionView.swift:42` trims spaces only).
  - Duration formatting is missed: see B7.
- **§3.4: the defaults-observer fix is too narrow.** Every `@AppStorage`
  write from a view fires it: each keystroke in Settings' path field, each
  font-slider tick, each inspector toggle. Each firing walks `PATH`. Return
  early when the executable string is unchanged. The "theme built twice"
  note is overstated: `MarkdownText.swift:110` rebuilds per update; pass
  `view.theme`.
- **§3.5 Quick Look: the design is wrong.** `EngineTranscript.session` is
  nil after `.closed` and `end()` (`EngineTranscript.swift:106,181`), so a
  `source` stored there vanishes exactly when edits are reviewed. The
  controller already resolves the `--source` it passes
  (`EngineController.swift:222-223`). Keep that, past the session's end,
  and resolve with `appending(path:)`: `URL(fileURLWithPath:relativeTo:)`
  (`ToolCardView.swift:73`) drops the base's last component without a
  trailing slash.
- **§3.6 view logic into Kit: all seven sites still hold.** Two notes:
  - `EngineComposer.canType` always equals `canSend`
    (`EngineSessionModel.swift:30-48`); merge them.
  - The two `EngineController` tests need an ungated suite in the
    integration target, since Kit tests can't import `SwiftStarUI`.

### Bugs

- **B1, certain: markdown preparation corrupts code.** `deLaTeXed` deletes
  `\(`, `\)`, `\[`, `\]` and `$$` everywhere, including inside fences and
  code spans (`MarkdownPreprocess.swift:14`). So `echo $$` renders as
  `echo `. `stripTaggedBlocks` drops fenced lines starting with `<think>`.
  Both run on every answer, narration and thinking row
  (`MarkdownText.swift:39-40`). Skip fences and code spans; pin with Kit
  tests.
- **B3, plausible: exit is never reported if a grandchild holds a pipe
  open.** `finishIfComplete` waits for both pipes to close, without a limit
  (`EngineSession.swift:311-312`). The catalog loader already guards this
  (`EngineModelCatalogLoader.swift:64-65`). Add a short drain limit after
  the process exits.
- **B4, certain mechanism, plausible trigger: the app can stick in
  `.quitting`.** When the quit safety bound fires
  (`EngineController.swift:274-280`), it only releases waiters. The phase
  stays `.quitting` and the session stays set, so Start, the menus and
  `start()` all refuse. On the bound, end the session explicitly.
- **B6, certain: two fast tests depend on the locale.**
  `MetricsFormattingTests.swift:24-25` and `EngineTranscriptTests.swift:263`
  expect `,` grouping and fail under `de_DE`. Give the formatters a locale
  parameter.
- **B7, certain: two duration styles.** Answers use `%.1fs`
  (`EngineEvent.swift:46`); tool cards use `%.0fs` from 10 s
  (`EngineTranscript.swift:38-41`). Use one `MetricsFormatting.duration`.
- **B8, certain: a protocol error then reads as "interrupted".** SIGTERM
  after the error gives exit 130, matched before "refused to start"
  (`EngineCommand.swift:94-96`). This is pinned deliberately at
  `EngineSessionTests.swift:193`, but it reads badly.
- **B9, plausible: the catalog loader closes handles another thread may be
  blocked reading** (`EngineModelCatalogLoader.swift:80-83`). An async
  rewrite on `terminationHandler` and the session's `ChunkBytes` streams
  removes it.

### Dead code, fossils and slimming the spec missed

- **Dead:**
  - the `.runningSessionNoGPU` trait (`PreviewTraits.swift:27-33,41`)
  - `EngineSessionModel.didFailToLaunch`, which equals `didExit(_, directory: nil)`
  - `EngineTranscript.apply(.closed)` duplicating `end()` (`:179-185`)
  - `EngineSession.waitUntil`'s always-false condition (`:201,205`)
  - a second `sawReady` (`:42,248`)
  - a `deinit` cancel that can't run (`:171`)
  - `CatalogNoteGate`, a struct around `Set.insert`
  - `EngineSessionInfo.id`, and `.steering`'s text, both decoded and never read
- **Fossils:**
  - `stripTaggedBlocks` strips `<tool_call>`, `<tool_result>` and `<think>`
    from text the engine no longer sends with tags; confirm with the engine,
    then delete
  - `PathAbbreviation`, which no longer abbreviates; fold `leafName` into a
    `URL` extension
  - "The P28 argv" and `p28`/`p30` test names
  - stale paths in `PreviewFixtures.swift:34,61,66,69`
  - the Laguna example in `SessionView.swift:37`
- **The catalog decoder serves a shape that never shipped.** It reads
  `measured_contexts`, `runs_in_tui`, `family` and `default_model_id`; the
  shipped list sends none of them and does send `plan_gib`/`size_bytes`,
  which go unread. Decode what ships and drop the rest (SU.6).
- **Idioms:**
  - `@Entry` for the font-size environment value (16 to 4 lines)
  - `OSAllocatedUnfairLock` for the loader's two lock boxes
  - `signal(SIGPIPE, SIG_IGN)` once in `AppDelegate`, not per session
    (`EngineSession.swift:83`)
  - redundant `@MainActor` under default main-actor isolation
  - one `@AppStorage`/environment font source in `ComposerView`
  - expose the controller's `canChoose`, not a copy at `SessionToolbar.swift:52`
  - a generic `choiceMenu` for the two toolbar menus
- **File shape:**
  - move `EngineExit`/`EngineTermination` out of `EngineCommand.swift`
  - split the menu builders out of `EngineModelCatalog.swift` (250 lines)
- **Not worth collapsing:** the model, session and controller layering.
  Each layer has its own reason to exist.
- **MarkdownView fork to native rendering:** removes 7 packages including
  the inert SwiftMath, but needs a block renderer and loses highlighting.
  It stays an SU.6 decision.

## 3. Test consolidation (scope for SU.5b)

**Check:** `@Test` counted per file with `grep -c`. Today there are 143 fast
and 30 integration test functions, and none are parameterised. The "after"
column counts functions; most cases survive as `@Test(arguments:)` rows.

| File | Now | After | How |
|---|---|---|---|
| EngineCommandTests | 23 | 4 | argv, resolution and `EngineExit.describe` become tables with exact messages, not `.contains` |
| EngineWireParserTests | 25 | 6 | one "line → exact `EngineEvent`" table (`EngineEvent` is `Equatable`); one before-ready refusal table; keep the 3 fixture tests (rule 5) |
| EngineTranscriptTests | 35 | 22 | pending-clearing and pending-keeping tables; empty-answer and summary tables; tool-card format tables |
| EngineModelCatalogTests | 16 | 10 | drop the 3 tests of synthesised `==` and the `CatalogNoteGate` test; one decode table |
| EngineSessionModelTests | 10 | 7 | phase and label tables |
| TranscriptFontScaleTests, MarkdownPreprocessTests, MetricsFormattingTests, SeverityTests, PathAbbreviationTests, EngineMetricsTests | 29 | 12 | tables; `try #require` for force-unwraps; B1's code-fence cases added |
| DefaultsKeyTests, ProjectRootTests | 5 | 5 | keep |
| EngineSessionTests | 22 | 15 | see the owner call below |
| EngineModelCatalogLoaderTests, EngineControllerTests | 8 | 7 (+2 from §2) | merge the timeout pair |

**Shared support:**
- `Tests/SwiftStarKitTests/Fixtures.swift` replaces five copies of the
  fixtures root and two copies of `events(fromFixture:)`.
- `Tests/SwiftStarIntegrationTests/Support.swift` holds:
  - an `.integration` `ConditionTrait` with a skip reason, plus a tag and a
    suite `.timeLimit`, replacing three copies of the environment gate
  - one `eventually(within:)`, replacing a `Date`-based and a
    `ContinuousClock`-based poller
  - a temp-file helper
  - a `UserDefaults`-scoping trait
  - `startReady()` and `quitAndWait()`, steps about 18 tests repeat

**Owner call: fake-only tests.** These assert behaviour the fake produces,
not SwiftStar's: `emptyPromptIsRefused`, `stopWhileIdleIsRefused`,
`secondStopIsIdempotent` and `loadGapQueuesAndKeepsStopDisabled`. P31
added them for fake fidelity. Cutting them leaves about 45 lines of the
fake dead, so it drops from 369 to about 320 lines.

**Kept as is:** `confirmation` isn't clearer than the existing `Recorder`
for these callbacks.

## 4. Docs and process

**Check:** `git ls-files` and `wc -l` at `e390796`.

**Before the re-plan:**
- `docs/` held 54,221 lines in 216 tracked files, against 3,377 lines of
  Swift source and 1,978 of tests.
- About 48,000 doc lines described machinery removed before P28.
- Since P28, 66 of 126 commits (52%) touched only docs.
- Docs written against code changed:

  | Cycle | Code lines changed | Doc lines written |
  |---|---|---|
  | SU.1 | 62 | 313 |
  | SU.4 | 1,297 | 1,718 |

- Four Status cells sat within 4 characters of the 1,000 cap.
- The finish rule was written in five places.
- The Sphinx site was never published, and after this deletion it would show
  only `sdd` and `glossary`.

**What the re-plan did:**
- tagged `docs-before-slim`, then deleted the pre-P28 docs and Sphinx (P14
  declined), indexed in `docs/history.md`
- reshaped `ROADMAP.md`
- lightened `docs/sdd.md` and the lint
- fixed the false statements in `BRIEF.md`, `README.md`, the glossary and
  the `ui-loop` skill

**Still owed by EN.1:** `just capture` and the fixture recapture.
