# SU.5a1 Implementation Plan: bugs and plumbing

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (name plus a one-line assertion). It doesn't paste code
> bodies.

**Goal:** the audit's bugs are fixed (B1, B3, B4, B6–B9), formatting, grace
periods and trimming each have one home, and the controller's quit, relaunch
and defaults edges hold (EN.1 minors 2, 6, 7). SU.5a is split under the
400-line cap: [5a2](2026-10-13-su5a2-kit-moves-and-tidy.md) follows, with
the Kit moves, Quick Look, dead code and UI tidy.

**Architecture:**
- **No new layers.** Kit gains a few pure functions:
  - formatting, in `MetricsFormatting`
  - the toolbar menus, split into their own file
  - the composer button state
  - Quick Look URL resolution
- **`EngineSession` and the catalog loader** get their pipe and timeout
  handling fixed.
- **`EngineController`** gets its quit, relaunch and defaults edges fixed.

**Tech stack:** Swift 6.2, SwiftPM, Swift Testing, SwiftUI (macOS 26),
stdlib Python (the recorder).

**Spec:** [`2026-10-04-su5-cleanup-and-test-modernisation-design.md`](../specs/2026-10-04-su5-cleanup-and-test-modernisation-design.md),
including its `## Revision, 2026-10-13`. **Evidence:**
[the audit](../research/2026-10-13-engine-catch-up-and-repo-audit.md) §2,
and the deferred minors in EN.1's [plan Result](2026-10-13-en1-engine-catch-up.md).

## Global Constraints

- **Builds:** warnings are errors on our own targets (`Package.swift:13`), and
  there are no new package dependencies.
- **Fast tier:** spawns nothing. `just test`'s grep refuses `Process(` and the
  like in `Tests/SwiftStarKitTests`.
- **Tests:**
  - Every new test is shown to fail first, and every bug fix is shown to fail
    with the fix removed (BRIEF rule 2).
  - A refusal test has a success twin (rule 4).
- **Deleting code:** each deletion is grep-verified, with no caller left in
  `Sources/` or `Tests/`.
- **UI files:** any change under `Sources/SwiftStarUI/` renders every touched
  `#Preview` with `RenderPreview`. Load the `ui-loop` skill first.
- **Out of scope (SU.5b):**
  - test consolidation (tables, shared `Fixtures.swift` and `Support.swift`)
  - the 10 s `relaunchIgnoredWhileTerminating` test
  - Kit tests for `model_refused` and `resume_refused` (EN.1 minors)

  This plan only edits tests whose subject changes.
- **Out of scope (SU.6):** the catalog's never-sent fields, `plan_gib`, and
  the "agent" UI copy.

## Deviations from the spec (for review)

- **§3.1 `isAwaitingInput` is kept.** EN.1's integration tests poll it as the
  exact "the engine is at `input`" signal (`EngineControllerTests`), which
  `isBusy` can't give before the first prompt.
- **`stripTaggedBlocks` is deleted, not fixed** (audit §2, fossil). ds4-engine's
  host parser consumes `<think>` and `<tool_call>` itself
  (`../ds4-engine/crates/ds4-host/src/contract/`), and no recording contains
  either tag. If one ever leaks, it shows as text rather than hiding the rest
  of the row.
- **The markdown self-test is wired into `Tools/make-app.sh`, not deleted.** It
  is the only check that the `MarkdownView` resource bundles reached the
  `.app`. It moves to a small public `MarkdownSelfTest`, so `MarkdownText` can
  become internal as §3.1 wants.

## Review Focus

Most likely to bite first:
1. **Code in an answer**, such as `echo $$` or `grep '\(a\)'`, in a fence or an
   inline span, must render verbatim. Task 1 `codeIsNotDeLaTeXed`.
2. **A grandchild process (a tool's `sleep &`) holding stdout** after the
   engine exits must not hide the exit. Task 4 `exitReportedWhenGrandchildHoldsPipe`.
3. **An engine that never exits on quit** must not leave the app stuck at
   "Ending…"; Start works again. Task 6 `quitBoundEndsTheSession`.
4. **A German-locale Mac** gets its own grouping, and the tests still pass.
   Task 2 `formattingFollowsLocale`.

---

### Task 1: Markdown preparation leaves code alone (B1), and `stripTaggedBlocks` goes

**Files:**
- Modify: `Sources/SwiftStarKit/MarkdownPreprocess.swift:12-33` (`deLaTeXed`)
  and `:35-82` (delete `stripTaggedBlocks` and `strippedTags`)
- Modify: `Sources/SwiftStarUI/Transcript/MarkdownText.swift:39-40`: stop
  calling `stripTaggedBlocks`
- Test: `Tests/SwiftStarKitTests/MarkdownPreprocessTests.swift`; delete the
  `stripTaggedBlocks` tests along with the function

**Interfaces:** `MarkdownPreprocess.deLaTeXed(_:) -> String` is unchanged in
signature. It now transforms only text outside fenced blocks
(` ``` `/`~~~`) and inline code spans.

- [ ] Write the tests:
  - `codeIsNotDeLaTeXed`: ``deLaTeXed("```sh\necho $$\ngrep '\\(a\\)'\n```")`` returns its input unchanged
  - `inlineCodeIsNotDeLaTeXed`: `` deLaTeXed("run `echo $$` now") `` is unchanged
  - `proseStillDeLaTeXed`: `deLaTeXed(#"\(x \to y\)"#) == "x → y"` (the success twin)
- [ ] See them fail (the first two). Implement by splitting on fences and code
  spans and transforming only the prose segments. See them pass.
- [ ] Delete `stripTaggedBlocks`, its tests and its call. Grep shows no
  `stripTaggedBlocks` anywhere. Render `MarkdownText`'s previews. Commit.

### Task 2: One home for formatting, trimming and the grace periods (B6, B7, §3.3)

**Files:**
- Modify: `Sources/SwiftStarKit/MetricsFormatting.swift`: add `number`, `gib`
  and `duration`
- Create: `Sources/SwiftStarKit/EngineGraces.swift`
- Modify, the callers:
  - `EngineEvent.swift:137,140` (`EngineAnswer.summary`)
  - `EngineTranscript.swift`: `metadataLine` and its private `duration`
  - `EngineWireParser.swift:186-196` (`gib`)
  - `EngineModelCatalog.swift:135-141` (`trimmed`, `grouped`)
  - `Sources/SwiftStarUI/Inspector/InspectorView.swift:21-22,39`
- Modify: `EngineCommand.swift:22-25`, `EngineController.swift` (`select`
  trims), `ComposerView.swift:83`, `SessionView.swift:46`: use one
  `String.trimmedOrNil`
- Test: `Tests/SwiftStarKitTests/MetricsFormattingTests.swift`,
  `EngineTranscriptTests.swift:263` (pass `en_US` explicitly)

**Interfaces:**
- `MetricsFormatting.number(_ n: Int, locale: Locale = .current) -> String`
- `MetricsFormatting.gib(_ bytes: Int64, locale: Locale = .current) -> String` returns, for example, `"6.0 GiB"`
- `MetricsFormatting.duration(seconds: Double) -> String` gives `%.1fs` under 10 s, then `%.0fs`
- `extension String { var trimmedOrNil: String? }`: trims whitespace and newlines; nil when empty
- `public struct EngineGraces: Sendable { stop, term, kill: Duration; var safetyBound: Duration; static let standard }`.
  The standard values are 10, 5 and 10 s, and the safety bound is their sum
  plus 5 s, as at `EngineController.swift:52-56`.
- `public enum EngineSessionConstants { static let stderrTailLimit = 4096; static let sessionArtifactsMarker = "Session artifacts:" }`,
  in the same file. Used by `EngineSession`, `EngineModelCatalogLoader` and
  `EngineExit.describe`.
- `EngineAnswer.summary(locale:)` and `EngineToolCard.metadataLine(locale:)`
  default to `.current`.

- [ ] Write the tests:
  - `formattingFollowsLocale`: `number(8192, locale: de_DE) == "8.192"` and `number(8192, locale: en_US) == "8,192"`
  - `durationOneStyle`: `duration(seconds: 75) == "75s"` and `duration(seconds: 1.83) == "1.8s"`
  - `answerSummaryUsesDuration`: a 75 000 ms answer's `summary(locale: en_US)` starts with `"75s"`
  - `trimmedOrNil`: `"  \n".trimmedOrNil == nil` and `" a ".trimmedOrNil == "a"`
  - The two existing locale-bound tests (`MetricsFormattingTests.swift:24-25`,
    `EngineTranscriptTests.swift:263`) pass `en_US`.
- [ ] See them fail, then move every caller. See them pass in both tiers.
- [ ] Render `InspectorView`'s previews. Commit.

### Task 3: Exit mapping: a protocol error doesn't read "interrupted" (B8)

**Files:**
- Create: `Sources/SwiftStarKit/EngineExit.swift`: move `EngineTermination`
  and `EngineExit` from `EngineCommand.swift:49-110`
- Modify: `EngineExit.describe`, adding `afterProtocolError: Bool = false`
- Modify: `Sources/SwiftStarEngine/EngineSession.swift`: pass it when the
  parser returned `.protocolError`
- Test: `Tests/SwiftStarKitTests/EngineCommandTests.swift`, and
  `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift:193` (update the
  deliberately pinned "interrupted")

**Interfaces:** `EngineExit.describe(code:stderrTail:sawReady:reason:forced:terminated:afterProtocolError:)`.

- [ ] Write the tests:
  - `protocolErrorExitReadsAsSuch`: `describe(code: 130, …, terminated: true, afterProtocolError: true).message == "ended after a protocol error"`
  - `plainInterruptStillInterrupted`: code 130, not terminated, `afterProtocolError: false`, gives `"interrupted"` (the success twin)
- [ ] See them fail, implement, see them pass, and update the integration
  expectation. Commit.

### Task 4: `EngineSession` internals (B3 and the dead code in it)

**Files:**
- Modify: `Sources/SwiftStarEngine/EngineSession.swift`:
  - `:311-323` (`finishIfComplete`): add a drain limit
  - `:42,248`: drop the second `sawReady`; read the parser's
  - `:201-219`: `waitUntil(_, { false })` becomes `Task.sleep`
  - `:170-172`: delete the `deinit` cancel, which can't run
  - `:82-83`: move `signal(SIGPIPE, SIG_IGN)` to `AppDelegate.applicationDidFinishLaunching` (`Sources/SwiftStar/SwiftStarApp.swift:36`)
  - `:116-117`: the stale "P32 Backlog entry" comment
  - `:31,278`: use the constants from Task 2's file:
    `EngineSessionConstants.stderrTailLimit` and `.sessionArtifactsMarker`,
    defined in `EngineGraces.swift`
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift`: expose
  `public private(set) var sawReady`
- Test: `Tests/SwiftStarIntegrationTests/EngineSessionTests.swift`

**Interfaces:**
- `EngineSession.init(…, drainLimit: Duration = .seconds(2))`.
- After the process exits, `finishIfComplete` waits at most `drainLimit` for
  both pipes, then closes the read handles and reports the exit.

- [ ] Write `exitReportedWhenGrandchildHoldsPipe`. The executable is a temp
  `/bin/sh` script that prints `ready`, runs `sleep 30 &` (inheriting stdout),
  and exits 0. Assert `onExit` fires within 5 s with code 0. The test cleans
  up the `sleep` by its pid file.
- [ ] See it fail (it times out). Implement the drain limit. See it pass.
- [ ] Make the dead-code and constant changes. Both tiers pass. Commit.

### Task 5: The catalog loader without blocking reads under GCD (B9)

**Files:**
- Modify: `Sources/SwiftStarEngine/EngineModelCatalogLoader.swift:8-104`:
  - rewrite on `Process.terminationHandler`
  - collect output through the same readability-handler streams
    `EngineSession` uses (`ChunkBytes`, `EngineSession.swift:131`)
  - race against `Task.sleep(for: timeout)` in a task group
  - drop the two `@unchecked Sendable` boxes and the hand-made `Duration`
    conversion
- Test: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`;
  all six existing tests unchanged

**Interfaces:** the signature is unchanged:
`EngineModelCatalogLoader.load(executable:timeout:environment:) async -> Result<EngineModelList, CatalogError>`.

- [ ] Run the six loader tests: they pass. Rewrite. All six pass, including
  `loaderTimesOutOnChildIgnoringSIGTERM` and
  `loaderReportsStderrTailBeyond4KiB`.
- [ ] Break the timeout race (remove the sleep arm). See
  `loaderTimesOutOnChildIgnoringSIGTERM` fail. Restore. Commit.

### Task 6: `EngineController` edges (B4, §3.3, §3.4, EN.1 minors 2, 6, 7)

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - `:52-56`: graces come from an injected `EngineGraces` (default `.standard`)
  - `:56-71`: the observer returns early unless the Settings executable
    string changed since it last looked, and is removed in `isolated deinit`
  - `:148-158` and the `start()` resolution: one `resolveExecutable()` that
    returns `EngineResolution`
  - `:102`: `canChoose` becomes internal, and `SessionToolbar.swift`'s copy of
    it goes
  - `:330-340`: when the quit bound fires, the session is ended explicitly
  - `relaunch(_:)`: when the bound fired, post a notice and don't start
  - `select(modelID:)`: a pick while a `/model` is already pending is refused
    with a notice
  - `start()`: `model.willStart()` before awaiting the model list, so the
    composer reads "Starting…"
- Modify: `Sources/SwiftStarKit/EngineSessionModel.swift`: add `willStart()`
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`, and
  `EngineSessionModelTests.swift`

**Interfaces:**
- `EngineController.init(graces: EngineGraces = .standard)`
- `EngineSessionModel.willStart()`: the phase becomes `.starting`; the
  transcript is not touched.
- The bound's message: `EngineExit(code: -1, message: "the engine did not exit after quit; it may still be running")`.
- Notice texts:
  - "Relaunch skipped: the engine did not exit."
  - "A model switch is already pending."

- [ ] Write the tests:
  - `quitBoundEndsTheSession`: graces stop 0.1 s, term 0.1 s, kill 30 s, safety bound 0.5 s, against a fake with `FAKE_ENGINE_IGNORE_QUIT` and `FAKE_ENGINE_IGNORE_SIGTERM` (the test wrapper gains an `extra` exports parameter); after `quit()`, `phase` is `.ended` within 2 s and `isActive == false`
  - `fixtureStartStaysIdle`: `EngineController.previewIdle`, after `await start()`, is still `.idle` (closes SU.3's leftover)
  - `ownDefaultsWritesDontReloadCatalog`: two `select(modelID:)` while idle leave the models-call log at 1
  - `secondModelPickWhilePendingIsRefused`: running, pick X then Y, and the fake's input log has exactly one `/model` line
  - `willStartShowsStarting`: `EngineSessionModel().willStart()`, then `composer.label == "Starting…"`
- [ ] See each fail, implement, see it pass. Both tiers pass. Render the
  `SessionToolbar` previews. Commit.

### Task 7: Close 5a1

- [ ] Run `just lint-docs` and both tiers. Add `## Result` to this plan. Update
  `ROADMAP.md`'s SU.5 row to "5a1 done", with links. Commit.
