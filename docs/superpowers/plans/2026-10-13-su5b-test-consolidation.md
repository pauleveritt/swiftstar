# SU.5b Implementation Plan: test consolidation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (a name plus a one-line assertion). It doesn't paste code
> bodies.

**Goal:**
- Turn the near-duplicate tests into `@Test(arguments:)` tables and share
  the helpers that are copied between files today.
- Gate the integration tier with one trait.
- Cut the four tests that only check the fake engine.
- Close the test gaps that 5a and EN.1 deferred.

No production behaviour changes.

**Architecture:**
- **Two support files:**
  - `Tests/SwiftStarKitTests/Fixtures.swift` for the fast tier.
  - `Tests/SwiftStarIntegrationTests/Support.swift` for the integration
    tier: a gate trait, a poller, temp paths, a defaults scope, and the
    fake-engine wrapper.
- **One file at a time** is rewritten into labelled argument tables. Each
  row names the old test it replaces.

**Tech stack:** Swift Testing (Swift 6.2), SwiftPM. The fake engine is
stdlib Python.

**Spec:** [`2026-10-04-su5-cleanup-and-test-modernisation-design.md`](../specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md)
`## Revision, 2026-10-13`, where D2 is superseded and replaced by a sweep.
**Evidence:** [the audit](../research/2026-10-13-engine-catch-up-and-repo-audit.md)
§3, and the deferred test items in the Results of
[EN.1](2026-10-13-en1-engine-catch-up.md),
[5a1](2026-10-13-su5a1-bugs-and-plumbing.md) and
[5a2](2026-10-13-su5a2-kit-moves-and-tidy.md).

**Owner decision (2026-10-13):** cut `emptyPromptIsRefused`,
`stopWhileIdleIsRefused`, `secondStopIsIdempotent` and
`loadGapQueuesAndKeepsStopDisabled`, and trim the fake behaviour that only
they use.

## Global Constraints

- **No production code changes.** `Sources/` changes only if a test exposes
  a bug, and then with a ledger ruling and a failing test first.
- **No case is lost.** Before a file is rewritten, list its `@Test` names.
  Afterwards, each old name appears as a row label in a table, or as a
  test name, or in the task's "dropped, and why" line.
- **Every table must be able to fail.** Break one implementation line per
  table, watch at least one row fail, then restore it (BRIEF rule 2). The
  expected values are literals, never computed with the code under test.
- **Locale and time.** Formatted numbers pass `Locale(identifier: "en_US")`.
  No row depends on the clock or the machine's locale.
- **Gating.** The fast tier spawns nothing: `just test`'s grep still covers
  `Tests/SwiftStarKitTests`. The integration tier runs only with
  `SWIFTSTAR_INTEGRATION=1`.
- **Counts.** Record test functions and test cases for both tiers before
  and after each task, in the commit message.

## Review Focus

Most likely to bite first:
1. **A case silently dropped in folding.** Each task maps old test names to
   rows; the reviewer checks the map against `git show BASE:<file>`.
2. **A table that can't fail,** because its expected value is computed by
   the code under test (for example the old `bytesFormatsByteCount`). Each
   task's break check covers this.
3. **The `.integration` trait skipping everything, or running in the fast
   tier.** Task 1 checks that the suite counts with and without the env var
   match today's: 45 run with it, and 45 skipped without it.
4. **A `.timeLimit` that flakes.** The limit is per test, and set at four
   times the slowest current test.
5. **A shared helper that hides a test's intent,** such as a fake wrapper
   that silently sets an env var. Helpers take every setting explicitly.

---

### Task 1: Shared support, and the gate as one trait

**Files:**
- Create: `Tests/SwiftStarKitTests/Fixtures.swift`
- Create: `Tests/SwiftStarIntegrationTests/Support.swift`
- Modify, to use them:
  - `EngineWireParserTests.swift:6-17`
  - `EngineTranscriptTests.swift:6-12`
  - `EngineModelCatalogTests.swift:6-13`
  - `EngineMetricsTests.swift`
  - `EngineSessionTests.swift:8-58`
  - `EngineControllerTests.swift:11-160` (and the fake wrapper at about `:225-265`)
  - `EngineModelCatalogLoaderTests.swift:7-12`
  - `ProjectRootTests.swift`: a temp-tree helper

**Interfaces:**
- **`Fixtures.swift`:**
  - `enum Fixtures { static let root: URL }`, which is `fixtures/engine`
  - `static func events(_ name: String) throws -> [EngineEvent]`
  - `static func modelList(_ name: String) throws -> EngineModelList`
- **`Support.swift`, the gate and timing:**
  - `extension Trait where Self == ConditionTrait { static var integration: Self }`
    — enabled only when `SWIFTSTAR_INTEGRATION=1`, with the comment "set
    SWIFTSTAR_INTEGRATION=1"
  - `extension Tag { @Tag static var integration: Self }`
  - `func eventually(within: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool`
- **`Support.swift`, files and defaults:**
  - `func tempPath(_ name: String) -> String`
  - `func withDefaults(_ values: [DefaultsKey: String?], _ body: () async throws -> Void) async rethrows`
    — saves, sets or removes, and restores each key
- **`Support.swift`, the fake engine:**
  - `struct FakeEngine { let script, spawns, inputs: String; init(fixture:resumeFixture:models:refuseResume:extra:) throws; var spawnArgv: [[String]]; var prompts: [String]; func remove() }`
  - This moves the controller tests' wrapper unchanged. Every setting is a
    parameter.
- **Each integration suite** becomes
  `@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))`.

- [ ] Record the baseline: `swift test` gives 185 fast tests and 45
  skipped; `SWIFTSTAR_INTEGRATION=1 swift test` gives 185 plus 45 passed.
- [ ] Add both files and move every suite onto them. Delete the copies:
  - five fixture roots
  - two `events(fromFixture:)`
  - three env gates
  - two pollers (`wait`, `poll`)
  - the inline defaults save and restore blocks
- [ ] The counts match the baseline in both modes. `just test`'s grep still
  passes. Break check: point the trait at the wrong env var name, and
  `SWIFTSTAR_INTEGRATION=1` then skips all 45. Restore it.
- [ ] Commit.

### Task 2: `EngineCommandTests` and `EngineWireParserTests` as tables, plus the missing refusal rows

**Files:**
- Modify: `Tests/SwiftStarKitTests/EngineCommandTests.swift`, 26 tests,
  about 6 after
- Modify: `Tests/SwiftStarKitTests/EngineWireParserTests.swift`, 30 tests,
  about 10 after

**EngineCommandTests, the tables:**
- **`argumentsRows`:** argv, model and context combinations, with each row
  checked against the exact array. This replaces the six `arguments`
  tests, including the duplicate `argumentsAreExact` /
  `emptySettingsKeepTheBaseArgv` pair.
- **`resolveRows`:** the Settings path, `PATH` order, `~/.local/bin`, and
  not-found with the list of places searched. Replaces four tests.
- **`describeRows`:** (code, stderr, sawReady, reason, forced, terminated,
  afterProtocolError) mapped to the exact message. Replaces 14 or so
  `EngineExit.describe` tests, and turns the loose `.contains` checks into
  exact messages.
- **Keeps:** `applyCommand`, and `launchFailure`.

**EngineWireParserTests, the tables:**
- **`afterReadyRows`:** one line maps to one exact `EngineEvent`, using `==`
  instead of `guard case … Issue.record`. About 18 tests fold in.
  - **New rows** (an EN.1 minor):
    - `model_refused` with `relaunch` gives `.relaunch(kind: .model)`
    - `resume_refused` with `relaunch` gives `.relaunch(kind: .resume)`
    - `apply_refused` with a `relaunch` array stays `.refused`, since no
      relaunch kind exists for it
- **`beforeReadyRows`:** each gives `.protocolError` with the exact message
  — `firstLineMustBeReady`, `protocolTwoIsRefused`,
  `undecodableBeforeReadyIsFatal`.
- **Keeps as named tests:**
  - the fixture tests (binding rule 5): `toolReadFixtureDecodes`,
    `toolRejectedFixtureDecodes`, `rewindRefusedWithRelaunchDecodes`,
    `resumedFixtureDecodes`
  - `undecodableAfterReadyIsNotice`
  - `statusReportIsOneReadableLine` (en_US)

- [ ] For each file, list its old names, then convert. The three new
  parser rows pin behaviour the parser already has, so break-check them by
  swapping `.model` and `.resume` in the parser's switch.
- [ ] Break check per table: change one message in `EngineExit.describe`,
  and one decode in the parser. Restore. Commit.

### Task 3: `EngineTranscriptTests` as tables

**Files:** `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`, 46 tests,
about 24 after.

**Tables:**
- **`clearsPendingRows`:** `.error`, `.closed`, `.refused`, `.awaitingInput`,
  `.prompt`, `.steering`, `.relaunch`. Each clears pending.
- **`keepsPendingRows`:** `.loading`, `.generating`, `.pause`, `.memory`.
  Pending is kept.
- **`emptyAnswerRows`:** a reason, or none, maps to the exact error row.
- **`summaryRows`:** duration and context combinations give the exact
  summary (en_US).
- **`cardTextRows`:** (op, path, ok, duration, rejection) gives the exact
  `headerText`, `metadataLine` and `icon`, absorbing the seven formatting
  tests and the declined-card tests.
- **`fileURLRows`:** absorbs the three `fileURL` tests.
- **Dropped:** `stopDisabledWhileQueued`, which is a strict subset of
  `stopDisabledWhenAwaitingInput`.
- **Kept as named tests:**
  - the fixture folds (`toolReadFixtureBuildsRows`, `transcriptKeepsSessionInfo`)
  - the `resumed` rebuild tests
  - `declinedCardDoesNotTakeAnotherCallsEnd`

- [ ] List the old names, convert, and break-check two tables: drop
  `clearPending()` from `.refused`, and change `duration`'s threshold.
  Restore. Commit.

### Task 4: The rest of the fast tier

**Files and targets:**

| File | Now | After |
|---|---|---|
| `EngineModelCatalogTests.swift` | 23 | about 14 |
| `EngineSessionModelTests.swift` | 16 | about 11 |
| `EngineMetricsTests.swift` | 7 | about 6 |
| `MarkdownPreprocessTests.swift` | 10 | about 4 |
| `MetricsFormattingTests.swift` | 10 | about 5 |
| `TranscriptFontScaleTests.swift` | 8 | about 3 |
| `SeverityTests.swift` | 2 | 1 |
| `DefaultsKeyTests.swift` | 1 | 1 |

**What changes:**
- **Catalog:**
  - a decode table over `models.json`, `models-real.json` and inline JSON
  - a `validated` table; the four `validated*` tests become rows
  - a `ModelMenu.label` / `ContextMenu.label` / `parseCustom` table
  - drop the three `CatalogCacheKey` tests, which test the compiler's
    synthesised `==`
- **Session model:**
  - a phase-and-label table (`readyMovesToRunning`,
    `generatingLabelComesFromComposer`, `willStartShowsStarting`, …)
  - a `composerButtonStates` table
- **Markdown:**
  - a `deLaTeXed` prose table
  - a code-is-verbatim table, covering fences, tilde fences, longer fences,
    a bare-line close, single and double spans, and a lone backtick across
    paragraphs
- **Formatting:**
  - drop `bytesFormatsByteCount`, which compares the formatter with itself
  - a number, GiB and duration table with explicit locales
- **Metrics:** `try #require` replaces the force unwraps at
  `EngineMetricsTests.swift:9-10,27-30`, and the loop at `:14` becomes
  arguments.

- [ ] For each file: list the old names, convert, break-check one table,
  restore. Commit once, with the per-file counts.

### Task 5: The integration tier: cuts, merges, the fake, and the deferred tests

**Files:**
- Modify: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`
- Modify: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`
- Modify: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`
- Modify: `fixtures/engine/fake-ds4-dogfood`: remove `FAKE_ENGINE_LOAD_MS`
  and `load_gap()`, and the empty-prompt refusal. First grep the tests to
  confirm nothing else uses them; the stop and non-JSON handling stay,
  because remaining tests drive them.

**Cut** (owner decision):
- `emptyPromptIsRefused`
- `stopWhileIdleIsRefused`
- `secondStopIsIdempotent`
- `loadGapQueuesAndKeepsStopDisabled`
- `notRunningErrorIsReadable`, which pins only an error string; the
  string's Kit home is enough

**Merges:**
- `quitMidTurnStopsFirst` folds into `quitWithQueuedPromptEndsPromptly`
  (a superset).
- `sessionDirectoryKnownAtExit` and `closedCapturePathResolvesSessionDirectory`
  become one table.
- The loader's two timeout tests become one table.

**New, from the deferred items** (each shown failing first):
- `relaunchSkippedWhenQuitHitTheBound`: a relaunch whose quit hit the
  safety bound posts "Relaunch skipped: the engine did not exit." and
  spawns nothing. Break check: drop the bound check from `relaunch(_:)`.
- `startShowsStartingWhileTheListLoads`: with a `models --json` that
  sleeps 0.5 s, the composer reads "Starting…" before the spawn. Break
  check: drop `model.willStart()`.

**Faster:**
- `relaunchIgnoredWhileTerminating` polls for up to 1 s for a second
  spawn instead of waiting 10 s for `.ended`, then quits its fake.
- Every test that starts a fake that ignores quit or SIGTERM ends it before
  returning. A full run leaves no orphaned `fake-ds4-dogfood` (ppid 1).
  This is pinned by a final check in Task 6.

- [ ] Make the cuts and merges. Write the two new tests, see them fail
  against their break, restore. Run the integration tier: about 38 tests,
  noticeably faster than today's 25–30 s. Commit with the before and after
  counts and times.

### Task 6: Close SU.5

- [ ] Confirm both tiers pass and that a full run leaves no orphaned fake:
  `ps -axo ppid,args | grep fake-ds4-dogfood | awk '$1==1'` prints nothing.
- [ ] Write this plan's `## Result`: per-file counts before and after, the
  dropped list, and the break checks. Update `ROADMAP.md`:
  - the SU.5 row reads done, linking the spec and the three plans
  - `## Now` points at SU.6
  - SU.6's punch list gains the 5a deferred minors that aren't tests
  - the Backlog loses SU.3's leftover, since its test landed in 5a1
- [ ] Run `just lint-docs`. Commit.

## Result

**Commits:** `f1dd031`..this close, on `main`. Suite: 91 fast, 39
integration (from 185 and 45). The integration tier takes 13–19 s, down from
about 29 s, and a full run leaves no `fake-ds4-dogfood` behind.

| File | Before | After |
|---|---|---|
| `EngineCommandTests` | 26 | 4 |
| `EngineWireParserTests` | 30 | 11 |
| `EngineTranscriptTests` | 46 | 27 |
| `EngineModelCatalogTests` | 23 | 15 |
| `EngineSessionModelTests` | 16 | 10 |
| `MarkdownPreprocessTests` | 10 | 2 |
| `MetricsFormattingTests` | 10 | 5 |
| `TranscriptFontScaleTests` | 8 | 3 |
| `EngineMetricsTests`, `SeverityTests` | 7, 2 | 6, 1 |
| `EngineSessionTests` | 24 | 17 |
| `EngineControllerTests` | 15 | 17 |
| `EngineModelCatalogLoaderTests` | 6 | 5 |

The counts are `@Test` functions; a table counts once, whatever its rows.
Every old name survives as a row label or a comment, checked per task
against the task's base commit.

**Dropped:**
- Two transcript tests in Task 3: `stopDisabledWhileQueued` and
  `busyStartsOnPromptEvent`.
- The three `cacheKey*` tests and `bytesFormatsByteCount`, which compared
  generated code with itself.
- The owner's integration cuts: four fake-only tests and
  `notRunningErrorIsReadable`.

**Break checks:** one table per file, plus each new test, failed with one
implementation line broken. Three checks found holes, now closed:
- the longer-fence row never exercised the fence-length rule
- the loader's timeout rows stayed green without the SIGKILL fallback
- `relaunchIgnoredWhileTerminating` stayed green without its guard

**Diverged:**
- `withDefaults { }` became `DefaultsScope` plus `defer`. With Swift 6.4, a
  closure inside `#expect(...)` and a sibling closure of the same type in
  one enclosing closure can share an identity, so one body runs for the
  other. This was probed, and is noted in `Support.swift`.
- Task 1 introduced that closure form. Whether a Task 1–4 assertion was
  actually skipped wasn't checked one by one.
- `FakeEngine.remove()` SIGKILLs the `tui` processes it started, since
  `EngineSession`'s deinit sends only SIGTERM.
- Two quit-bound tests use a 1 s kill grace, down from 2–3 s.
