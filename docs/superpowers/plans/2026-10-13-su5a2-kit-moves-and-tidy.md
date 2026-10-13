# SU.5a2 Implementation Plan: Kit moves, Quick Look, dead code, UI tidy

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (name plus a one-line assertion). It doesn't paste code
> bodies.

**Goal:** the view logic left in views moves to Kit under test, Quick Look
resolves against the source, dead code and fossils are gone, and the UI is
tidied (EN.1 minors 4, 5, 8, 9). It runs after
[5a1](2026-10-13-su5a1-bugs-and-plumbing.md), whose `EngineGraces`,
`EngineSessionConstants`, `MetricsFormatting` additions and `String.trimmedOrNil`
it uses.

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

Most likely to bite first (5a1's four items are pinned there):
1. **Quick Look after the session has ended, from a picked subfolder**, opens
   the file under the git root. Task 2 `fileURLResolvesAgainstSource`.

---

### Task 1: View logic into Kit (§3.6), and the menus get their own file

**Files:**
- Create: `Sources/SwiftStarKit/ToolbarMenus.swift`: move `MenuChoice`,
  `ModelMenuAction`, `ModelMenu`, `ContextMenu` and `RecentWorkspaces` out of
  `EngineModelCatalog.swift:118-250`
- Modify, the sources of the moves:
  - `SessionToolbar.swift:105-111,129-138`
  - `StatusBarView.swift:52-56`
  - `ComposerView.swift:41-44,63,75-80`
  - `SessionView.swift:46`
  - `SettingsView.swift:40-52`
- Modify: `EngineSessionModel.swift:21-50`: merge `canType` into `canSend`
- Modify: `EngineMetrics.swift`: `.resumed` sets `contextUsed` from
  `resumed.contextUsed` (EN.1 minor)
- Test: `Tests/SwiftStarKitTests/` (new tests beside each type's existing ones)

**Interfaces:**
- `ModelMenu.label(loaded: String?, chosen: String) -> String`
- `ContextMenu.label(loaded: Int?, chosen: Int) -> String`
- `ContextMenu.parseCustom(_ text: String) -> Int?`
- `MetricsFormatting.statusLine(phase: EngineSessionPhase, label: String, metrics: EngineMetricsState) -> String`
- `EngineComposer.button(forInput: String) -> ComposerButton`, where
  `enum ComposerButton: Equatable { case send(enabled: Bool), stop }`
- `EngineSessionPhase.notFoundNotice: String?`
- `TranscriptFontScale.slot(for: Int) -> Int` and `.size(forSlot: Int) -> Int`

- [ ] Write the tests:
  - `modelLabelLoadedToChosen`: `label(loaded: "a", chosen: "b") == "a → b"` and `label(loaded: "a", chosen: "a") == "a"`
  - `contextParseCustom`: `parseCustom(" 4096 ") == 4096`, while `parseCustom("0")` and `parseCustom("x")` are nil
  - `composerButtonStates`: busy with empty input gives `.stop`; ready with text gives `.send(enabled: true)`; ready with blank input gives `.send(enabled: false)`
  - `notFoundNoticeListsSearched`: `.notFound(["/a"])`'s notice contains `/a`, and `.running`'s is nil
  - `fontSlotRoundTrip`: `size(forSlot: slot(for: s)) == s` for every size, and `slot(for: 999)` is the last slot
  - `resumedSetsContextUsed`: the reducer, after `.resumed(contextUsed: 1071)`, has `contextUsed == 1071`
- [ ] See them fail, move the logic, and the views call it. Render the
  previews of every touched view. Both tiers pass. Commit.

### Task 2: Quick Look resolves against the source (§3.5, as revised)

**Files:**
- Modify: `EngineController.swift`: `private(set) var source: URL?`, set in
  `start()` from the `--source` it resolves, and kept past the session's end
- Modify: `Sources/SwiftStarUI/Transcript/ToolCardView.swift:81-85`: call the
  Kit function
- Modify: `TranscriptView` and `TranscriptRowView`: pass `source` where they
  pass `workspace` today
- Modify: `Sources/SwiftStarKit/EngineTranscript.swift` (`EngineToolCard`)
- Test: `Tests/SwiftStarKitTests/EngineTranscriptTests.swift`

**Interfaces:** `EngineToolCard.fileURL(source: URL?) -> URL?`. It returns
nil without a path or a source, and uses `source.appending(path:)`. The
file-exists check stays in the view.

- [ ] Write the tests:
  - `fileURLResolvesAgainstSource`: a card with path `Sources/a.swift` and source `/r` (no trailing slash) gives `/r/Sources/a.swift`
  - `fileURLNilWithoutPath`: a `bash` card gives nil
- [ ] See them fail, implement, see them pass. Render the `ToolCardView`
  previews. Commit.

### Task 3: Dead code and fossils in Kit and Engine (§3.1, §3.2, audit §2)

**Files and deletions:**
- `EngineModelCatalog.swift`: `CatalogNoteGate` becomes a `Set<String>` in
  the controller
- `EngineTranscript.swift:215-221`: `apply(.closed)` calls `end()`
- `EngineTranscript.swift:100`: `canStop` is deleted, and its four tests read
  `isBusy`
- `EngineEvent.swift`: `EngineSessionInfo.id` is deleted
- `EngineWireParser.swift:111-112` and `EngineEvent`: the unread `.steering`
  text is dropped
- `EngineSessionModel.swift:59,75,110` and `EngineController.swift:18`:
  `sessionDirectory` is deleted. `didRelaunchKeepsRows` drops its
  `sessionDirectory` line; the row check covers it.
- `DefaultsKey.swift:4`: drop `CaseIterable`
- `PathAbbreviation.swift`: fold `leafName` into `extension URL { var leafName: String }`;
  the file and its tests go
- `EngineCommand.swift:11` and `EngineCommandTests.swift:113-115`: "P28"
  names become plain ones
- **§3.2 stale comments:**
  - `ProjectRoot.swift:3-9`
  - `MarkdownText.swift:22-25`
  - `MarkdownPreprocess.swift:3-7`
  - `ValueGaugeView.swift:16-17`
  - `EngineControllerTests.swift:6-10`

**Test:** the existing suites. No behaviour changes except `.closed`, which
is pinned by the existing `EngineTranscriptTests` close tests.

- [ ] Make each deletion. `grep -rn` finds no caller of the deleted symbols in
  `Sources` or `Tests`. Both tiers pass, with no warnings. Commit.

### Task 4: UI tidy, the self-test, the resources entry, warnings (§3.1, §3.4, EN.1 minors 4, 9)

**Files:**
- `PreviewTraits.swift:27-33,41`: delete `RunningNoGPUSessionPreview` and
  `.runningSessionNoGPU`
- `SessionToolbar.swift:51` and its environment read: delete the dead `.font`
- `SessionToolbar.swift:105-150`: one generic `choiceMenu`
- `Components/TranscriptFontSize.swift`: becomes `@Entry var transcriptFontSize`
- `ComposerView.swift:10`: read the font size from the environment only
- `MarkdownText.swift:110`: pass `view.theme`, so the theme isn't rebuilt
  every update
- **Self-test:**
  - `MarkdownText.swift:55-66` becomes `public enum MarkdownSelfTest { static func runIfRequested() }`
  - `MarkdownText` becomes internal
  - `SwiftStarApp.swift:41` calls the new name
  - `Tools/make-app.sh` runs
    `DS4_SELFTEST_MARKDOWN=1 "$APP/Contents/MacOS/SwiftStar" --markdown-selftest`
    and fails unless stderr has `DS4_SELFTEST_MARKDOWN: OK`
- `Package.swift:64`: drop `resources:`. Then either add
  `exclude: ["Resources"]`, or move the `.icns` to `Tools/` and update
  `make-app.sh:11`. Build the app and check the Dock icon file is in
  `Contents/Resources`.
- **Redundant `@MainActor`** under default main-actor isolation:
  - `SwiftStarApp.swift:31,59`
  - `MarkdownText.swift:55,137`
- **`SessionView.swift:41`:** the alert's copy says a running session
  switches with `/model` and keeps its files. An id the engine doesn't list
  is reported as unknown, not as "no longer offered".
- **The six main-actor warnings** in `MemoryStatusView`'s "GPU toggle"
  `#Preview` are fixed. Find out why warnings-as-errors missed them, and
  record why in the commit.

**Test:**
- `just app` succeeds with the self-test passing, and the icon is in the
  bundle.
- Both tiers pass, and the build has zero warnings
  (`swift build 2>&1 | grep -c warning: == 0`).

- [ ] Make the changes. Render every preview in each touched view file. Commit.

### Task 5: The recorder writes atomically, and SU.5a closes (EN.1 minor 5)

**Files:**
- `Tools/record-engine-fixture.py`: `run()` writes to `out + ".tmp"`. It
  replaces `out` only when the scenario succeeded, so a failed
  `tool-rejected` attempt leaves the committed fixture alone.
- `ROADMAP.md`: the SU.5 row reads "5a done" (5a1 and 5a2), and
  `## Now` points at 5b.
- This plan: add `## Result`.

- [ ] Check with
  `python3 Tools/record-engine-fixture.py /usr/bin/false . tool-rejected /tmp/x.ndjson`:
  no `/tmp/x.ndjson` is left behind.
- [ ] Run `just lint-docs` and both tiers. Write the Result. Commit.
