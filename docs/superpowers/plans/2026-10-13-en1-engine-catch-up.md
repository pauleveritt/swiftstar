# EN.1 Implementation Plan: catch up to ds4-engine `5451cd7d`

> **For agentic workers:** REQUIRED SUB-SKILL: use
> superpowers:subagent-driven-development or superpowers:executing-plans.
> Steps use checkboxes. This plan follows `docs/sdd.md`'s local rule: each
> task names its files, interfaces (signatures only) and tests (a name plus a
> one-line assertion). It doesn't paste bodies.

**Goal:** SwiftStar starts a session when the saved model is gone, shows
declined calls, and honours `/model`, `/rewind` and `/resume` through the
engine's `relaunch` contract, all checked against fixtures recorded on
`qwen3.8-27b`.

**Architecture:**
- **Kit** gains the decoding (`.toolRejected`, `.relaunch`, `.resumed`) and
  the pure rules: model validation, menu action, divider text and the
  transcript rebuild.
- **`EngineController`** gains an async `start(arguments:)` and a relaunch
  path built on the existing `quit()`.
- **The fake engine** learns the refusal-with-relaunch reply and replays a
  `resumed` fixture.

**Tech stack:** Swift 6.2, SwiftPM, Swift Testing, SwiftUI (macOS 26),
stdlib Python for the recorder and the fake.

**Spec:** [`2026-10-13-en1-engine-catch-up-design.md`](../specs/2026-10-13-en1-engine-catch-up-design.md). Read it with this plan.

## Global Constraints

- **Warnings are errors** on our own targets (`Package.swift:13`).
- **No new package dependencies.**
- **The fast tier spawns nothing.** `just test`'s grep refuses `Process(` and
  the like in `Tests/SwiftStarKitTests`.
- **Every new test is shown to fail first** (BRIEF binding rule 2). A refusal
  test has a success twin (rule 4). Parser and transcript tests name their
  fixture (rule 5).
- **Fixtures are recorded from the real engine.** A hand-written payload is
  listed as hand-written in `fixtures/engine/provenance.md`.
- **Previews.** Any change under `Sources/SwiftStarUI/` renders every
  touched `#Preview` with `RenderPreview`; load the `ui-loop` skill first.
- **The relaunch argv is used exactly as the engine gives it:** no
  `--commit`, nothing added.

## Deviations from the spec (for review)

- **§2.3, D3, the fallback.** A `model_refused` *without* `relaunch` is
  shown as the engine's refusal, with no fresh-restart fallback. The engine
  refuses that way only when the model cannot run (unknown, or not on this
  Mac), so a fresh start would fail for the same reason. A menu pick while
  no session runs still starts fresh.
- **§3.2, the fake's `tool_rejected` switch.** Dropped. The fake already
  replays any fixture, so the recorded `tool-rejected.ndjson` (Task 1)
  covers it.

## Review Focus

Most likely to bite first:
1. **A relaunch whose start is refused** (exit 2, for example a Laguna-era
   `/resume`) must end in `.ended` with the engine's reason, not leave the
   old rows looking live. Pinned by Task 5's `relaunchRefusedEndsCleanly`.
2. **A `.relaunch` that arrives after app termination has begun** must not
   spawn anything. Pinned by Task 5's `relaunchIgnoredWhileTerminating`.
3. **The model list loads slowly, or fails, at launch.** The start still
   goes ahead after the loader's timeout, keeping the saved id. Pinned by
   Task 2's `validatedKeepsIdWithoutList` and `startProceedsWhenCatalogFails`.
4. **A `resumed` with empty `turns`** (`/model` starts a new conversation,
   or `/rewind 0`) shows the divider only. Pinned by Task 4's
   `resumedWithNoTurnsShowsDividerOnly`.
5. **A `tool_rejected` with an empty `name` and a null `path`** reads "a
   call", not a blank card. Pinned by Task 3's `declinedCardWithoutName`.

---

### Task 1: The recorder, and recordings on the 27B (needs the GPU and the owner's go-ahead)

**Files:**
- Modify: `Tools/record-engine-fixture.py`
  - `:8-14`: the docstring
  - `:33`: the scenario list
  - `:37-41`: the argv
- Modify: `Justfile`, the `capture` recipe: add `MODEL="qwen3.8-27b"` and
  drop the "BROKEN until EN.1" comment
- Re-record: `fixtures/engine/tool-read.ndjson`, `stop.ndjson`,
  `error.ndjson`, `models-real.json`
- Create: `fixtures/engine/relaunch-rewind.ndjson`, `resumed.ndjson`,
  `tool-rejected.ndjson`
- Modify: `fixtures/engine/provenance.md`: commit `5451cd7d`, the model,
  the context, the machine, the new rows, and the stale note removed
- Modify: tests whose fixture-derived expectations change; expect at least
  `EngineWireParserTests`, `EngineTranscriptTests`, `EngineMetricsTests`
  and `EngineModelCatalogTests`

**The recorder:**
- **Arguments:** `record-engine-fixture.py <exe> <source> <scenario> <out> [seed] [model]`.
- **The model** goes in as `--model-id`, defaulting to `qwen3.8-27b`.
- **The context** stays 20,000.
- **`relaunch-rewind`:**
  - First run: two prompts, then the line `/rewind 1`. Wait for
    `rewind_refused`, then send `quit`.
  - Second run: spawn `exe` with that event's `relaunch` argv, add
    `--capture-dir`, and record its stdout to `resumed.ndjson`. Send `quit`
    at the first `input`.
- **`tool-rejected`:** a prompt that asks for a tool named `list_files`,
  tried at seeds 1–6. Keep the first recording that contains
  `tool_rejected`. If none does, write the single event line from
  `../ds4-engine/docs/tui.md:1748` and list it as hand-written.

- [ ] Get the owner's go-ahead that the GPU is free.
- [ ] Run `just capture` for each of the six scenarios, and
  `ds4-dogfood models --json > fixtures/engine/models-real.json`. Anonymise
  home paths as before.
- [ ] Check each fixture's "must contain" column by hand:
  - `relaunch-rewind` has `rewind_refused` with a non-empty `relaunch`
    array that starts with `tui` and contains `--ndjson`
  - `resumed` has `session` and then `resumed`, with `turns.count == 1`
- [ ] **D4, narration against the answer:** in `tool-read.ndjson`, compare
  every `narration` text with the turn's `answer.text`. Write the verdict
  (repeats / doesn't) and the line numbers into `provenance.md`. This
  decides whether Task 6 runs.
- [ ] Run `just test` and `just integration`. Fix the expectations that
  moved with the fixtures, and only those; if a fixture contradicts the
  parser, stop and report.
- [ ] Commit the recorder, the fixtures, `provenance.md` and the updated
  tests.

### Task 2: A stale model is cleared before the spawn (D1)

**Files:**
- Modify: `Sources/SwiftStarKit/EngineModelCatalog.swift:143` (`ModelMenu`)
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - `:205-243`: `start()` becomes `async`, and gains `arguments:`
  - `:191-200`: `restart()` awaits it
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift:30-31`: one
  `.task` awaits `loadCatalogIfNeeded()`, then `start()`
- Modify: `Sources/SwiftStarUI/Session/SessionToolbar.swift:27`: `Task { await controller.start() }`
- Test: `Tests/SwiftStarKitTests/EngineModelCatalogTests.swift`
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- Produces:
  - `ModelMenu.validated(saved: String, list: EngineModelList?) -> (modelID: String, notice: String?)`
  - `EngineController.start(arguments override: [String]? = nil) async`
- Behaviour of `start()`:
  - The fixture guard stays the first line.
  - With no override, it awaits `loadCatalogIfNeeded()`, then applies
    `validated`.
  - When the id changes, it writes `DefaultsKey.modelID` and calls
    `model.apply(.notice(...))` after `didStart()`.
  - With an override, it skips validation and builds the session with the
    override argv.

- [ ] Write the fast tests:
  - `validatedKeepsOfferedId`: `validated(saved: "qwen3.8-27b", list: real)` returns `("qwen3.8-27b", nil)`
  - `validatedClearsDroppedId`: `validated(saved: "laguna-xs-2.1", list: real)` returns `("", "laguna-xs-2.1 is no longer offered; using the engine default")`
  - `validatedKeepsEmpty`: saved `""` returns `("", nil)`
  - `validatedKeepsIdWithoutList`: saved `"laguna-xs-2.1"` with `list: nil` returns `("laguna-xs-2.1", nil)`

  `real` is `models-real.json` from Task 1.
- [ ] Run them and see each fail. Implement `validated`. They pass.
- [ ] Write the integration tests:
  - `staleModelClearedBeforeSpawn`: with `FAKE_ENGINE_MODELS = models-real.json`, a saved `laguna-xs-2.1` and `FAKE_ENGINE_ARGV_LOG`, the logged argv has no `--model-id`, and the defaults key reads `""`
  - `startProceedsWhenCatalogFails`: with `FAKE_ENGINE_MODELS_FAIL=1`, the logged argv contains `--model-id laguna-xs-2.1` (today's behaviour)

  Reuse the defaults save/restore pattern at `EngineControllerTests.swift:51-60`.
- [ ] Watch both fail. Make `start` async and update its callers. Both pass.
- [ ] Run `just test` and `just integration`.
- [ ] Render the `SessionView` and `SessionToolbar` previews; they must be
  unchanged.
- [ ] Commit.

### Task 3: Declined calls

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift`:
  - add `EngineToolRejection`
  - add `case toolRejected(EngineToolRejection)` near `:105`
  - fix the comment at `:30` ("only `laguna-xs-chat`")
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift:57-143`: a
  `"tool_rejected"` case, placed before the `_refused` suffix case
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift`:
  - `EngineToolCard` (`:3-55`) gains `rejection: EngineToolRejection?`
  - `headerText`, `metadataLine` and `icon` account for a declined card
  - `apply` appends a declined card
- Modify: `Sources/SwiftStarUI/Transcript/ToolCardView.swift`: the declined
  card is drawn greyed, with no disclosure; add a `#Preview("Declined")`
- Test: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`,
  `EngineTranscriptTests.swift`

**Interfaces:**
- Produces:
  - `public struct EngineToolRejection: Equatable, Sendable { name: String; reason: String; path: String?; text: String }`
  - `EngineToolRejection.label: String`, which maps:
    - `repeated-call` to "repeated"
    - `call-cycle` to "loop"
    - `unknown-tool` to "unknown tool"
    - `path-refused` to "path refused"
    - anything else to itself
- A declined card reads:
  - `headerText`: `name`, with the path appended as today, or "a call"
  - `metadataLine`: "declined · \(label)"
  - `icon`: `"xmark.circle"`

- [ ] Write the tests:
  - `toolRejectedFixtureDecodes`: the `tool_rejected` line in `tool-rejected.ndjson` parses to `.toolRejected` with that line's `name` and `reason`
  - `refusedStillRefused`: a `rewind_refused` without `relaunch` still parses to `.refused` (the success twin)
  - `declinedCardText`: a `repeated-call` rejection named `read` gives `headerText == "read"`, `metadataLine == "declined · repeated"` and `icon == "xmark.circle"`
  - `declinedCardWithoutName`: empty `name` and nil `path` give `headerText == "a call"`
- [ ] Watch them fail, implement, and watch them pass.
- [ ] Load `ui-loop`. Render the new `ToolCardView` preview and the existing
  ones.
- [ ] Commit.

### Task 4: Decoding `relaunch` and `resumed`, and the transcript rebuild (D2)

**Files:**
- Modify: `Sources/SwiftStarKit/EngineEvent.swift`:
  - add `EngineRelaunch` and `EngineResumed`
  - add `case relaunch(EngineRelaunch)` and `case resumed(EngineResumed)`
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift`:
  - in the `_refused` case at `:139`, a non-empty `relaunch` array gives
    `.relaunch`
  - a new `"resumed"` case
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift`:
  - `TranscriptRow` gains `case divider(String)`
  - `apply(.resumed)` replaces `rows` and resets `pendingUserRows` and
    `queuedUserRows`
  - rewrite the invariant comment at `:67-70`: rows are append-only
    *except* `.resumed`, which replaces them and clears the pending
    indices
- Modify: `Sources/SwiftStarKit/EngineSessionModel.swift`:
  - `pendingRelaunch: EngineRelaunch?` is set by `apply(.relaunch)`,
    survives `didStart()` (`:68-73`), and is consumed when `.resumed` is
    applied
  - remove `didFailToLaunch` (`:80-84`) and point its caller at
    `didExit(_:directory: nil)`; it is identical
- Modify: `Sources/SwiftStarUI/Session/TranscriptRowView.swift`: draw
  `.divider`; add a `#Preview("Rebuilt after rewind")` and a `#Preview("Switched model")`
- Modify: `Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift`: the
  fixture models above. Also fix `:31`'s Laguna id and the stale paths at
  `:34,61,66,69`
- Test: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`,
  `EngineTranscriptTests.swift`, `EngineSessionModelTests.swift`

**Interfaces:**
- Produces:
  - `public struct EngineRelaunch: Equatable, Sendable { kind: Kind; argv: [String]; reason: String }`,
    with `enum Kind { case resume, model, rewind }` and `var modelID: String?` (the value after `--model-id` in `argv`)
  - `public struct EngineResumed: Equatable, Sendable { sessionID: String; turns: [Turn]; rewoundTo: Int?; filesChanged: Int?; contextUsed: Int? }`,
    with `struct Turn: Equatable, Sendable { prompt: String; answer: String?; stopped: Bool }`
  - `EngineResumed.divider(after relaunch: EngineRelaunch?) -> String`
- Divider text:
  - for `.rewind`: "Rewound to prompt \(rewoundTo)"
  - for `.model`: "Switched to \(modelID): new conversation, files kept"
  - otherwise: "Resumed session \(sessionID)"

- [ ] Write the tests:
  - `rewindRefusedWithRelaunchDecodes`: the `rewind_refused` line in `relaunch-rewind.ndjson` gives `.relaunch` with `kind == .rewind`, `argv.first == "tui"` and `argv.contains("--ndjson")`
  - `resumedFixtureDecodes`: `resumed.ndjson`'s `resumed` line gives `turns.count == 1` and `rewoundTo == 1`
  - `relaunchModelIdFromArgv`: argv `[... "--model-id", "qwen3.8-flash-next", "--new-conversation", "--ndjson"]` gives `modelID == "qwen3.8-flash-next"`
  - `dividerTextPerKind`: three cases, one per divider text above
  - `resumedReplacesRows`: a transcript with five rows and one pending user row, after `.resumed` with one turn, has rows `[.divider, .user, .answer]` and `pendingUserCount == 0`
  - `resumedWithNoTurnsShowsDividerOnly`: empty `turns` gives `rows == [.divider(...)]`
  - `stoppedTurnShowsStopped`: a turn with `stopped: true` and `answer: nil` gives `.system("Stopped.")` after its `.user` row
  - `pendingRelaunchSurvivesDidStart`: `apply(.relaunch)`, then `didStart()`, then `apply(.resumed)` gives a divider that starts with "Rewound"
- [ ] Watch them fail, implement, and watch them pass.
- [ ] Load `ui-loop`. Render the two new previews and every preview of
  `TranscriptRowView`.
- [ ] Commit.

### Task 5: The controller relaunches, and the model menu uses `/model` (D3)

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - `:232`: `onEvent` calls a new `handle(_:)`
  - `:113-120`: `select(modelID:)` branches on `ModelMenu.selectionAction`
  - add `relaunch(_:)`
- Modify: `Sources/SwiftStarKit/EngineModelCatalog.swift`, `ModelMenu`:
  add `selectionAction`
- Modify: `fixtures/engine/fake-ds4-dogfood`, the `handle` function
  (`:254-307`):
  - a prompt whose text is `/rewind N` or `/model X` emits that kind's
    refusal, carrying `relaunch` and the recorded shape
  - started with `--resume`, it replays `FAKE_ENGINE_RESUME_FIXTURE`
    instead of `FAKE_ENGINE_FIXTURE`
  - document both in the header at `:17-27`
- Test: `Tests/SwiftStarKitTests/EngineModelCatalogTests.swift`,
  `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- Consumes: `EngineRelaunch` and `EngineResumed` (Task 4);
  `start(arguments:) async` (Task 2).
- Produces:
  - `enum ModelMenuAction { case sendModelCommand, restart }`
  - `ModelMenu.selectionAction(phase: EngineSessionPhase) -> ModelMenuAction`:
    `.running` gives `.sendModelCommand`, every other phase `.restart`
  - `EngineController.relaunch(_ r: EngineRelaunch) async`:
    1. `await quit()`
    2. stop here if `isTerminating`
    3. if `r.kind == .model`, persist `r.modelID`
    4. `await start(arguments: r.argv)`
- The menu path:
  - `.sendModelCommand` sends `/model \(id)` and does *not* persist; the
    relaunch persists.
  - `.restart` is today's write-then-restart.
- Not allowed: adding `--commit` to the argv, or rebuilding it.

- [ ] Write the fast test `selectionActionPerPhase`: `.running` gives `.sendModelCommand`; `.idle`, `.ended(...)` and `.notFound` give `.restart`.
- [ ] Watch it fail, implement it, and watch it pass.
- [ ] Write the integration tests; the fake replays `tool-read.ndjson`, with
  `FAKE_ENGINE_RESUME_FIXTURE = resumed.ndjson`:
  - `rewindRelaunches`: after `send("/rewind 1")`, the second spawn's logged argv equals the fake's refusal `relaunch` exactly, and `transcript.rows.first` is `.divider("Rewound to prompt 1")`
  - `modelMenuSendsModelCommand`: while running, `select(modelID: "qwen3.8-flash-next")` puts the line `/model qwen3.8-flash-next` in the fake's log, and after the relaunch the defaults key reads `qwen3.8-flash-next`
  - `modelMenuIdleRestartsFresh`: while `.idle`, a pick writes the key, and the logged argv has `--model-id` and `--commit HEAD`
  - `relaunchRefusedEndsCleanly`: with `FAKE_ENGINE_REFUSE=1` on the second spawn, the phase is `.ended`, and the transcript's last row carries the refusal message, not old rows only
  - `relaunchIgnoredWhileTerminating`: `beginTerminating()` before the refusal arrives means exactly one spawn is logged

  The second spawn's argv goes through a per-spawn `FAKE_ENGINE_ARGV_LOG`
  suffix, or an append-mode log; pick one and document it in the fake's
  header.
- [ ] Watch them fail, implement, and watch them pass.
- [ ] Run `just test` and `just integration`. Render the `SessionToolbar`
  previews.
- [ ] Commit.

### Task 6: Drop narration that repeats the answer (only if Task 1 found it does)

**Files:**
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift`, `apply(.answer)`:
  remove a trailing `.narration` row in the same turn whose trimmed text
  equals, or is contained in, the trimmed answer
- Test: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`

- [ ] Write the tests:
  - `narrationRepeatingAnswerDropped`: folding `tool-read.ndjson` leaves no `.narration` row whose text is in the answer
  - `distinctNarrationKept`: a narration of "Reading Package.swift." before a different answer is kept

  These are the refusal and success twins.
- [ ] Watch them fail, implement, and watch them pass.
- [ ] Commit.
- [ ] If Task 1 found no repetition, skip this task and record that in
  `## Result`.

### Task 7: Stale copy, live checks, and closing EN.1

**Files:**
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift:37`: the alert
  example becomes `qwen3.8-27b`
- Modify: tests that still use Laguna ids as data, moved to `qwen3.8-27b`
  where the fixtures allow: `EngineModelCatalogTests`,
  `EngineTranscriptTests`, `EngineModelCatalogLoaderTests`
- Modify: `ROADMAP.md`:
  - close EN.1 in one line
  - `## Now` points at SU.5a
- Modify: this plan: add `## Result`

- [ ] Make the copy and test-data changes. Run `just test` and
  `just integration`.
- [ ] Render the touched `SessionView` preview.
- [ ] **Live, by the owner or with the owner's go-ahead.** Build the app
  with `just app`, keeping `engineModelID = laguna-xs-2.1` saved.
  - It starts on the 27B, the notice shows, and afterwards
    `defaults read com.pauleveritt.SwiftStar engineModelID` prints an empty
    string.
  - Two prompts, then `/rewind 1`: the transcript shows "Rewound to prompt
    1" and one turn.
  - A model-menu pick mid-session gives "Switched to …: new conversation,
    files kept", and the toolbar shows the new model.
  - Record what was seen and what wasn't.
- [ ] Write `## Result` (commits, divergences, what was descoped), close the
  EN.1 row, and point `## Now` at SU.5a. Run `just lint-docs`. Commit once.

## Result

**Commits** `eae4a83`..`ccefc16` on `main`: Tasks 1–5 and 7, a live-found
race fix (`e0a4866`) and the final-review fixes (`ccefc16`). Suite: 163 fast,
37 integration.
**Diverged:** `tool-rejected.ndjson` is hand-written (no rejectable call from
the 27B at seeds 1–6 with either prompt). Task 6 was skipped: D4 found the
narration is the full reply and the answer its summary, so no repeats.
`start(arguments:)` became `start(relaunch:)`. A relaunch now keeps the rows
until `resumed` (`didRelaunch`), and the divider names the relaunch that ran.
The live check found `start()` didn't wait for an in-flight model-list load.
**Live 2026-10-13:** with `laguna-xs-2.1` saved, the built app cleared it,
spawned without `--model-id`, ran `qwen3.8-27b`, and quit with no orphan.
Not seen: the notice (no screen access); `staleModelClearedBeforeSpawn` pins
it. **Owed by the owner, in the GUI:** `/rewind 1` (also queued behind a busy
turn) and a mid-session model-menu switch.
**Deferred minors** (ledger, for SU.5): a 10 s test; no notice when a relaunch
is abandoned at the quit bound; no Kit test of `model_refused` or
`resume_refused`; the "Other model" alert copy; the recorder overwriting its
fixture before checking it; a second queued model pick dropped silently; no
sign of activity while the launch waits for `models --json`.
