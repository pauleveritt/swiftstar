# SwiftStar repo audit at fb46abb

> Research for SU.4 (Xcode-first UI loop) and SU.5 (cleanup and test
> modernisation), gathered 2026-10-04 by a research agent (read-only: code, docs, build, ROADMAP, agent tooling; line numbers are at `fb46abb`). Kept as
> written, apart from this header. Each finding carries its own confidence tag; treat
> **UNCONFIRMED** items as leads, not facts, and re-check before building on
> them. Related: [`2026-10-04-su4-handoff-brief.md`](2026-10-04-su4-handoff-brief.md).

Legend: **[H/M/L]** severity · **C** = certain (verified by grep/run) · **S** = suspect (reasoned, not proven).
Verification runs: `swift build --scratch-path <scratchpad>` (fresh, Swift 6.4 toolchain): 0 warnings, 14 s.
`swift test` (fast): 143 tests / 16 suites pass; integration suite reports 30 "passed" but all are skipped without `SWIFTSTAR_INTEGRATION=1`.
`just lint-docs`: exit 0. `git status` clean after all runs.

## 1. Dead code, fossils, smells, dead weight

### 1a. Unused in Sources (certain: grep over `Sources/` finds only the declaration; tests may still use them)
- [M][C] `EngineTranscript.isAwaitingInput` is written 5 times, never read in Sources (`Sources/SwiftStarKit/EngineTranscript.swift:75`). P32 step 6 named it as B5 dead code (`ROADMAP.md:79`), and P32 says "B5 dead code deleted" (`ROADMAP.md:59`), but commit `eeb49fe` left it. Only tests read it (`Tests/SwiftStarKitTests/EngineTranscriptTests.swift:27,179`).
- [M][C] `EngineTranscript.isQueued(rowAt:)` and `queuedUserRows` (`EngineTranscript.swift:84,90`): only tests use them. The UI shows "Queued" for every *pending* row (`Sources/SwiftStarUI/SessionView.swift:208` passes `isPending`), so the engine-confirmed queue state is computed but never shown.
- [L][C] `EngineTranscript.canStop` (`EngineTranscript.swift:86`): the UI uses `EngineComposer.canStop` instead (`SessionView.swift:285`, `EngineController.swift:255`).
- [L][C] `EngineController.sessionDirectory` (`Sources/SwiftStarUI/EngineController.swift:18`): nothing reads it.
- [L][C] `EngineSessionInfo.id` is parsed (`Sources/SwiftStarKit/EngineWireParser.swift:61`) and never read (`EngineEvent.swift:84`).
- [L][C] The `.steering(applied:text:)` text payload is decoded (`EngineWireParser.swift:106`) but ignored (`EngineTranscript.swift:169`).
- [L][C] Several decoded catalog fields are never read in Sources: `EngineModelList.Model.family/path/downloadable` (`EngineModelCatalog.swift:41,43,44`) and `EngineModelList.gpuBudgetBytes/savedModelID` (`:80-81`). These are deliberately forward-looking (`fixtures/engine/provenance.md:43-47`).
- [L][C] The `DefaultsKey: CaseIterable` conformance is unused (`Sources/SwiftStarKit/DefaultsKey.swift:4`).
- [L][C] `resources: [.process("Resources")]` (`Package.swift:49`): `Bundle.module` is never referenced, and `Tools/make-app.sh:11` copies the `.icns` directly. `:12-14` also copies `SwiftStar_SwiftStar.bundle`, so the icon ships twice.
- [L][C] `MarkdownText` is `public` (`Sources/SwiftStarUI/MarkdownText.swift:26`), but its `init` is internal (`:30`). It is public only for the self-test hook.
- [L][S] `ValueGaugeView` default `diameter = 60` (`ValueGaugeView.swift:21`) is used only by previews; real callers pass 15 or 30.

### 1b. Stale comments and names (certain)
- [M][C] `BRIEF.md:196-198` describes a `FastTierGuard` tripwire that "fails the build". P32 replaced it with a grep in `just test` (`Justfile:112`), and plain `swift test` or Xcode runs skip that grep.
- [M][C] `docs/sdd.md:55` says the same thing: "enforced by a tripwire that fails the build".
- [L][C] `Justfile:110`: the comment still names "the FastTierGuard build-tool plugin".
- [L][C] `Justfile:116` says "fake engine binaries generated from committed captures". In fact one Python script replays the fixtures.
- [L][C] `Justfile:1,7` ("the gate CI runs") and `BRIEF.md:192-193` ("CI: yes"): the repo has no CI config (`.github/` is absent and no workflow file is tracked).
- [M][C] `Sources/SwiftStarEngine/EngineSession.swift:116-117` points to "the P32 Backlog entry", but no P32 Backlog entry exists (the ROADMAP Backlog, lines 105-268, does not mention P32). The real source is the spec's §1.
- [L][C] `Sources/SwiftStarKit/PathAbbreviation.swift:3-5`: the doc describes `~` abbreviation, but `abbreviate` was deleted in P32 and only `leafName` remains.
- [L][C] `Sources/SwiftStarUI/MarkdownText.swift:23-25` says the "transcript coalesces deltas in place", but `EngineTranscript` appends one row per event and has no coalescing.
- [L][C] `Sources/SwiftStarKit/MarkdownPreprocess.swift:36` refers to "`think` wire events". The wire kind is `thinking` (`EngineWireParser.swift:68`).
- [L][C] `Sources/SwiftStarKit/ProjectRoot.swift:4-9` uses pre-P28 framing ("the agent is confined to the app's own checkout"). Confinement is now the engine's job.
- [L][C] `docs/glossary.md:31` maps tool card to `AgentToolCardView`; the type is now `ToolCardView`. `:26` maps apply to `EngineController`; it actually lives in `EngineCommand.applyCommand` / `EngineSessionModel.didExit`.
- [L][C] `README.md:46` says `just app` will "build and launch the .app", but `Tools/make-app.sh` does not launch it.
- [L][C] `pyproject.toml:1` says "Python exists … for documentation and nothing else". Python also runs the fake engine (`fixtures/engine/fake-ds4-dogfood`), the recorder (`Tools/record-engine-fixture.py`) and inline fakes in `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift:23,94`. `BRIEF.md:252-254` has it right.
- [L][C] `docs/sdd.md:119` says "The two easiest to forget" and then lists three bullets.
- [L][C] `docs/index.md:7` says the site "gains content in phase P14", but Phase P is closed (`docs/sdd.md:100`) and P14 still reads "planned" (`ROADMAP.md:43`).
- [L][C] Old UI copy and naming remain: `navigationTitle("Agent")`, "Ask the agent…" and "agent session" (`SessionView.swift:26,268,331`), "Agent toolbar menus" (`SettingsView.swift:17`), the `DS4_SELFTEST_MARKDOWN` env var (`MarkdownText.swift:56,62`) and the `agentWorkspace` key (`DefaultsKey.swift:5`; deliberately frozen). The glossary allows "agent" as UI copy (`docs/glossary.md:18`).

### 1c. Provenance comments (low value now)
- [L][C] Pre-cut-over provenance: `Package.swift:14-21` ("DS4 patches", "ds4-control's Package.swift"), `MarkdownText.swift:1-14,46-54` ("agent-mode MarkdownText.swift", "shipped DS4 .app"), `MarkdownPreprocess.swift:3-7`, `ValueGaugeView.swift:16`.
- [L][C] `EngineControllerTests.swift:6-10` ("first coverage it has ever had … before P30") is history, not a spec. `EngineSession.swift:109-117` is the one worth keeping, because it explains a non-obvious design choice.

### 1d. Duplicate logic
- [M][C] `EngineController` resolves the executable twice with the same code: `resolveExecutablePath()` (`EngineController.swift:136-146`) and inline in `start()` (`:207-212`).
- [L][C] The grace periods are defined twice: `EngineController.swift:49-51` (10/5/10 s) repeats the defaults in `EngineSession.swift:66-67`.
- [L][C] The 4 KiB stderr limit appears twice: `EngineSession.swift:31` and `EngineModelCatalogLoader.swift:93`.
- [L][C] The `"Session artifacts:"` literal appears twice: `EngineCommand.swift:84` and `EngineSession.swift:276`.
- [L][C] There are three trim helpers: `EngineCommand.swift:22-25`, `EngineModelCatalog.swift:135-137` and `EngineController.swift:115`.
- [L][C] GiB and number formatting is scattered outside `MetricsFormatting`: `EngineWireParser.swift:166-168`, `InspectorView.swift:39`, `EngineModelCatalog.swift:139-141,202` (forced `en_US` locale), and `SessionView.swift:168,171` (`.grouping(.never)`). Locale handling is inconsistent.
- [L][C] Both `.help(tooltip)` and `.nativeTooltip(tooltip)` are applied to the same widgets (`SessionView.swift:368-372,397-401`). The comment at `:415-417` explains why, but the result is two tooltip mechanisms.

### 1e. Smells and suspected bugs
- [M][S] **The font-size environment is read in the wrong scope.** `SessionView` sets `.environment(\.transcriptFontSize, …)` on its own body (`SessionView.swift:27`). It then reads `@Environment(\.transcriptFontSize)` (`:14`) at `:85,245,250,261,350`. Those reads resolve against the parent's environment, and nothing sets it there (`MainView.swift`), so they are always the 16 pt default. As a result the toolbar menus, system and error rows, the not-found notice and the status bar do not follow the slider; child views do. Found by reading the code; not run.
- [M][S] `ToolCardView.resolvedFileURL` resolves the tool path against `controller.workspace` (the folder the user picked; `ToolCardView.swift:71-75`). The engine gets the git root (`EngineController.swift:222-223`) and runs in its own candidate worktree. Quick Look can therefore miss the file when the picked folder is a subfolder, or show the un-edited checkout copy.
- [M][C] The memory widget is a lone-`if` `@ViewBuilder` (`SessionView.swift:380-403`). The Backlog records that it crashed the preview agent, and that a Debug run may still crash (`ROADMAP.md:140-150`). This matters for the Xcode-first loop.
- [L][C] There is one force unwrap, at `SettingsView.swift:44` (safe because `clamp` returns a member). The slot count is hard-coded as `0...3` and `min(3,…)` (`:22,50`) instead of `sizes.count-1`.
- [L][C] `@unchecked Sendable` lock boxes are used at `EngineModelCatalogLoader.swift:20,27`, together with GCD semaphores and a blocking `waitUntilExit` (`:66-87`). There is no `nonisolated(unsafe)`, no TODO/FIXME, no `try!`/`as!`, and no debug `print` (the self-test writes to stderr and calls `exit(0)`, gated by env var plus CLI flag, at `MarkdownText.swift:55-64`).
- [L][C] `EngineController.defaultsObserver` is registered (`EngineController.swift:63-71`) and never removed (there is no `deinit`). It fires on every `UserDefaults` write, including the controller's own `select()` writes, and each time it stats the engine binary.
- [L][C] `EngineSession.start()` sets a process-wide `signal(SIGPIPE, SIG_IGN)` (`EngineSession.swift:83`).
- [L][C] `PreviewFixtures.swift` (all of it) and the markdown self-test are compiled into the release app; there is no `#if DEBUG`.
- [L][C] Magic layout numbers are scattered through the views: `SessionView.swift:276,279,294,299,365,389`, `ValueGaugeView.swift:24,31,32,38`, `SettingsView.swift:37`, `MainView.swift:14`, `SwiftStarApp.swift:22`, `InspectorView.swift:18,45,62`.
- [L][C] `MarkdownNSText.updateNSView` builds the theme twice per update (`MarkdownText.swift:107,110`).
- [L][S] `ProjectRoot.locate` walks up at most 5 levels (`ProjectRoot.swift:11`). A picked folder deeper than that below the repo root would pass the folder itself as `--source`, and the engine refuses it.

### 1f. Oversized file: `Sources/SwiftStarUI/SessionView.swift` (453 lines)
- [M][C] It holds eight jobs:
  - toolbar plus two alerts (18-78)
  - menu helpers and three menus: folder, model, context (80-187)
  - `NSOpenPanel` (189-199)
  - transcript and `rowView` switch (201-254)
  - composer with send/stop logic (256-343)
  - status bar plus memory widget plus `bottomStatusText` (345-412)
  - the `NativeTooltip` AppKit bridge (415-448)
  - preview (450-453)

  The menu-label logic (139-145, 163-172), `bottomStatusText` (407-412) and the send/stop button state (285, 304) are untested view-embedded logic.
- [L][C] Files whose name doesn't match their contents: `ThinkingDisclosure` lives in `PromptBubble.swift:33-65`; `Severity.color` lives in `ValueGaugeView.swift:4-13`; `EngineModelCatalog.swift` (250 lines) mixes catalog decoding with the `ModelMenu`, `ContextMenu`, `RecentWorkspaces`, `CatalogNoteGate` and `CatalogCacheKey` menu models.

### 1g. Tools, Justfile, fixtures, docs, Python
- [L][C] All 8 Justfile recipes are live: `watch-docs`, `docs`, `lint-docs`, `install-hooks`, `test`, `integration`, `capture`, `app`. Both `Tools/` scripts are used, by `capture` and `app`.
- [L][C] The app icon can no longer be regenerated: `Tools/make-icon.swift` was deleted in P32 (`eeb49fe`), and `AppIcon.icns` is now a source-less binary.
- [L][C] Untracked leftovers (all gitignored): `Tools/__pycache__/` holds 5 `.pyc` files from scripts P28 deleted; `.worktrees/ds4-fork-backup/` is empty; `.superpowers/sdd/2026-08-24-p12-4-repair-role/` is old run state; there is also `.pytest_cache/` and `.idea/`.
- [L][C] Two fixtures are hand-authored (`fixtures/engine/bad-handshake.ndjson`, 1 line; `garbage-after-ready.ndjson`, 3 lines) and missing from the provenance table (`fixtures/engine/provenance.md:17-21`). That is an undocumented exception to "never hand-authored" (`BRIEF.md:200`). `models.json` is hand-written too, but that one is documented (`provenance.md:43`).
- [L][S] Python is still needed for:
  - docs: Sphinx via `uv` (`pyproject.toml:11-19`; `uv.lock` is 85 KB, docs group only)
  - the integration-tier fake engine and the inline test fakes (system `python3`, stdlib only, not pinned by `uv`)
  - the live-tier recorder

  The docs site itself (`docs/laptop-ai.md`, `pathologies.md`, `remediations.md`, `harvest/`) is pre-P28 history, last touched at `e27d0b2` (P28 task 8). For the UI cycle, uv/Sphinx is dead weight unless P14 is revived.
- [L][C] Dependencies: `MarkdownView` and `MarkdownParser` are both imported (`MarkdownText.swift:17-18`). The 7 `Package.resolved` pins (Highlightr 2.3.0, Litext 1.3.0, LRUCache 1.3.0, swift-cmark 0.8.0, swift-collections 1.6.0, SwiftMath 1.7.3, MarkdownView@`d83032f`) are all transitive from the fork. SwiftMath is inert by owner decision (`BRIEF.md:165-171`). No direct dependency is unused.
- [L][C] Plans for removed machinery still sit in the current plans directory, not `archive/`: `docs/superpowers/plans/2026-08-24-p12-reliable-agency.md`, `2026-08-30-eval-cli-1a/1b/1c`, and `2026-08-30-p24-*` (4 files).

## 2. Layout

Roles: V = view, C = app-state controller, M = model / pure logic, S = service (process I/O), F = formatting, X = fixture, A = app shell.

| File | Lines | Role |
|---|---|---|
| Sources/SwiftStar/SwiftStarApp.swift | 66 | A (`@main`, `AppDelegate` terminate/quit handshake) |
| Sources/SwiftStar/Resources/AppIcon.icns | bin | resource (also copied raw by make-app) |
| Sources/SwiftStarEngine/EngineSession.swift | 321 | S (child process, pipes, quit escalation) |
| Sources/SwiftStarEngine/EngineModelCatalogLoader.swift | 104 | S (`models --json`, timeout/kill) |
| Sources/SwiftStarKit/DefaultsKey.swift | 12 | M (keys) |
| Sources/SwiftStarKit/EngineCommand.swift | 120 | M (argv, resolution, `EngineExit` mapping) |
| Sources/SwiftStarKit/EngineEvent.swift | 124 | M (event types) |
| Sources/SwiftStarKit/EngineMetrics.swift | 53 | M (metrics reducer) |
| Sources/SwiftStarKit/EngineModelCatalog.swift | 250 | M (catalog decode) + M (menu models) |
| Sources/SwiftStarKit/EngineSessionModel.swift | 116 | M (phase, composer state) |
| Sources/SwiftStarKit/EngineTranscript.swift | 205 | M (transcript fold, tool card text) |
| Sources/SwiftStarKit/EngineWireParser.swift | 193 | M (wire parser) |
| Sources/SwiftStarKit/MarkdownPreprocess.swift | 82 | F |
| Sources/SwiftStarKit/MetricsFormatting.swift | 20 | F |
| Sources/SwiftStarKit/PathAbbreviation.swift | 13 | F |
| Sources/SwiftStarKit/ProjectRoot.swift | 25 | M (touches the filesystem) |
| Sources/SwiftStarKit/Severity.swift | 18 | M |
| Sources/SwiftStarKit/TranscriptFontScale.swift | 19 | M |
| Sources/SwiftStarUI/EngineController.swift | 298 | C (`@Observable`; UserDefaults, catalog, session lifecycle) |
| Sources/SwiftStarUI/PreviewFixtures.swift | 62 | X |
| Sources/SwiftStarUI/MainView.swift | 21 | V |
| Sources/SwiftStarUI/SessionView.swift | 453 | V (plus AppKit tooltip bridge) |
| Sources/SwiftStarUI/InspectorView.swift | 69 | V |
| Sources/SwiftStarUI/MarkdownText.swift | 158 | V (`NSViewRepresentable` plus self-test) |
| Sources/SwiftStarUI/PromptBubble.swift | 83 | V (also `ThinkingDisclosure`) |
| Sources/SwiftStarUI/SettingsView.swift | 57 | V |
| Sources/SwiftStarUI/ToolCardView.swift | 95 | V |
| Sources/SwiftStarUI/TranscriptFontSize.swift | 16 | V-support (`EnvironmentKey`) |
| Sources/SwiftStarUI/ValueGaugeView.swift | 57 | V (plus `Severity.color`) |

Tests: fast tier, 143 tests in `SwiftStarKitTests`, one file per Kit source:
- DefaultsKey 14 lines / 1 test
- EngineCommand 152 / 23
- EngineMetrics 65 / 6
- EngineModelCatalog 177 / 16
- EngineSessionModel 124 / 10
- EngineTranscript 323 / 35
- EngineWireParser 238 / 25
- MarkdownPreprocess 45 / 7
- MetricsFormatting 26 / 5
- PathAbbreviation 14 / 2
- ProjectRoot 58 / 4
- Severity 21 / 2
- TranscriptFontScale 49 / 7

`EngineEvent` is covered through the parser tests.

Integration tier, 30 tests in `SwiftStarIntegrationTests`, env-gated:
- EngineSessionTests: 423 lines / 22 tests
- EngineModelCatalogLoaderTests: 72 / 6
- EngineControllerTests: 176 / 2

Placement and coverage findings:
- [M][C] No test runs SwiftStarUI logic under plain `just test`. `EngineControllerTests` is env-gated (`EngineControllerTests.swift:12`), and there is no `SwiftStarUITests` target.
- [M][C] SwiftStarUI logic with no test:
  - `SessionView` menu labels (139-145, 163-172), `bottomStatusText` (407-412), `noticeText` (315-320), send/stop state (285, 304), custom-context parsing (70)
  - `SettingsView` slot mapping (42-52)
  - `ToolCardView.resolvedFileURL` (71-75)
  - `EngineController`: `stop`/`send` error paths (245-261), the quit safety bound (266-284), the restart-skipped path (195-198), `defaultWorkspace` (87-94), the fixture `start()` refusal (206; also listed at `ROADMAP.md:145`), `showCatalogNote` gating (184-188)
  - `AppDelegate.applicationShouldTerminate` (`SwiftStarApp.swift:54-65`), which can't be tested from an executable target
  - `MarkdownNSText`'s sizing cache
- [L][C] SwiftStarEngine is well covered (`EngineSession` 22 tests, the loader 6). There is no test for `EngineSession.deinit` beyond `droppedSessionTerminatesTheEngine`, or for the `ChunkBytes` framing across chunk boundaries (the fake writes whole lines).
- [L][S] Possible placement moves: `ProjectRoot` (filesystem I/O) is in "pure" Kit; `PreviewFixtures` ships in the product library; the `EngineModelCatalog.swift` menu models belong with the toolbar view logic. Nothing is in the wrong target per BRIEF's rules (Kit has no SwiftUI or `Process`).

## 3. Build settings (facts)

- [L][C] `swift-tools-version: 6.2` (`Package.swift:1`); the local compiler is Swift 6.4 (swiftlang-6.4.0.34.1). Platforms: `.macOS(.v26)` (`:6`).
- [L][C] Products (`:7-12`): library `SwiftStarKit`, library `SwiftStarUI` (exists only so Xcode makes a scheme for previews, `:9`), executable `SwiftStar`. **There is no `SwiftStarEngine` product**, so Xcode has no scheme for it.
- [L][C] All six targets set `.swiftLanguageMode(.v6)` explicitly (`:27,31,44,50,55,60`).
- [L][C] `.defaultIsolation(MainActor.self)` is set on `SwiftStarUI` (`:44`), `SwiftStar` (`:50`) and `SwiftStarIntegrationTests` (`:60`), but not on Kit, Engine or KitTests.
- [L][C] Explicit `@MainActor` annotations that are redundant under that default: `SwiftStarApp.swift:31`, `MarkdownText.swift:55,137`, `EngineControllerTests.swift:11`, `EngineSessionTests.swift:9,16`. `EngineSession` is explicitly `@MainActor` (`EngineSession.swift:21`) in a nonisolated-default module.
- [L][C] No target sets any `enableUpcomingFeature`, `enableExperimentalFeature`, `unsafeFlags`, strict-memory-safety or warnings-as-errors setting.
- [L][C] Dependency: one direct package, the `notatestuser/MarkdownView` fork, pinned by `revision:` (`Package.swift:22-24`). Six transitive pins are version-resolved in `Package.resolved` (format version 3).
- [L][C] Fresh build (separate scratch path): 0 warnings, 0 deprecations. Resource bundles produced: Highlightr, Litext, MarkdownView, SwiftMath, SwiftStar.
- [L][C] `Tools/make-app.sh`:
  - does a release build only (`:6`); the Debug-run crash risk is therefore unverified (`ROADMAP.md:144`)
  - writes `Info.plist` inline (`:15-31`) with `CFBundleIdentifier` `com.pauleveritt.SwiftStar`, `LSMinimumSystemVersion` 26.0, hard-coded `CFBundleShortVersionString` 0.2.0 and `CFBundleVersion` 1, and `NSHighResolutionCapable`
  - has no `codesign` step and no entitlements
  - sets no `LSApplicationCategoryType` and no `NSHumanReadableCopyright`
  - copies the icon raw plus all `*.bundle` (`:11-14`)
- [L][C] There is no `.xcodeproj`, by design (`.gitignore:7`; `BRIEF.md:249`). Local `.swiftpm/xcode/` holds user workspace state only (gitignored). There is no shared scheme, so previews depend on picking the `SwiftStarUI` scheme by hand.

## 4. ROADMAP.md organization

- [M][C] Size: 280 lines, 45,521 bytes; the longest line is 1,742 chars (P22 row, `:51`).
- [M][C] Sections in order:
  - blurb (1-9)
  - `## Now` (11-22)
  - Phases table P0–P32 (27-59)
  - a prose paragraph (61)
  - SU rows (63-67)
  - `## P29 steps` (69-93, including plan pointers at 85-93)
  - "Dependencies worth knowing" (95-102)
  - Backlog (105-268): Front-end, Engine requests, Process and tooling, Closed or re-homed by P28 (218-262), Declined
  - `## Prior work` (270-272)
  - `## Workflow` (274-280)
- [M][C] **The SU rows have no table header or delimiter row** (`:63-67` follow paragraph `:61`), so they do not render as a table in GFM.
- [M][C] **`just lint-docs` never checks SU rows.** Its matcher is `/^\| P[0-9]/` (`Justfile:25`). SU.1's Status cell is 998 chars against the 1,000 cap (`:63`), so it is not checked and is 2 chars from failing once the regex covers it.
- [L][C] Largest cells (lint is green; caps are 900 for Direction, 1,000 for Status, `docs/sdd.md:71-73`):
  - Status: P22 998, SU.1 998, P20 971, P18 963, P23 935, P19 934, P13 908
  - Direction: P23 719, P22 692
  - The P29-steps items aren't cells, so no cap applies; step 6 is 1,149 chars (`:79`), step 5 is 942 (`:78`).
- [M][C] The P25 and P26 rows are missing (the table jumps from P24 at `:53` to P27 at `:54`; they were last present before the 2026-08-30 revert/reapply, `9b9d8d1`), yet `:18` refers to "P25 cycles 5–6".
- [M][C] The Backlog entry "P29.10's deferred minors" (`:132-138`) is still open, but P30 resolved it (`:57`). Only the pid-reuse window was left out of scope.
- [L][C] P14 is still "planned" (`:43`) although Phase P is "closed to new entries" (`:61`; `docs/sdd.md:100`).
- [L][C] P18's status opens with "deferred to last" (`:47`) but `:18` says P18 closed with P28. The row only says "Removed in P28" at its tail.
- [L][C] P29 step 7 says it "Continues as SU.1 (2026-10-04)" (`:80`), but SU.1 was done on 2026-10-03 (`:63`).
- [L][C] SU.3's Direction still says "none exist today" (`:65`), and SU.2's says "all 14 test files" (`:64`; there are 16 now).
- [L][C] Fossils:
  - `:85-93`: P12, P13 and P15 plan pointers, plus "Each plan is written as its phase begins"
  - `:95-102`: a P28 retrospective
  - `:166-178`: closed engine requests still listed
  - `:218-262`: 45 lines of closed Backlog groups
  - `:270-280`: Prior work and Workflow, which repeat README and sdd
- [L][C] `:126-131`: "A session browser" is "the same item as the session picker above" (a self-declared duplicate).
- [L][S] Pre-P28 or off-repo Backlog items are probably no longer SwiftStar work: "P6 has no verification record" (`:193-197`), "standing guard against under-specified authored prompts" (`:198-202`), and the Pi-harness tooling item (`:203-216`).
- [M][C] Finding "what's next" takes too long. The only pointer is the 340-char line `:17` (SU.4 next). SU.4 (`:66`) has a Direction but no spec or plan, and SU.5 is "not yet brainstormed". The SU.3 deferred items that bear on SU.4/SU.5 sit in the Backlog (`:140-150`), not near the SU rows. `:21-22` ("Then, if wanted: Front-end entries") predates Phase SU. Closed history (the P table, P29 steps, the closed Backlog) makes up about 75% of the file's bytes.
- `just lint-docs`: green (exit 0). It checks only P rows and current plans; SU rows are not checked.

## 5. Agent tooling present

- [L][C] `.claude/` contains only two empty directories, `commands/` and `worktrees/`. There is no `settings.json`, `settings.local.json`, skills or agents. `.claude/commands/goal.md` was deleted in P32 (`eeb49fe`). `.claude/worktrees/` is gitignored (`.gitignore:15`).
- [L][C] There is no `.mcp.json` and no `AGENTS.md`.
- [M][C] `~/.claude.json` has no `mcpServers` at global or project level (only names and keys inspected; no values printed). The Xcode `RenderPreview` MCP used in SU.3 "via `xcrun mcpbridge`" (`ROADMAP.md:65`) is not configured in any repo or user Claude Code file. SU.4's house rule (`ROADMAP.md:66`) depends on that MCP, so its setup is currently undocumented and not reproducible from the repo.
- [L][C] User plugins enabled (`~/.claude/settings.json`): superpowers, plugin-dev, code-simplifier.
- [L][C] `CLAUDE.md` (25 lines) points at `docs/sdd.md` and `BRIEF.md`, plus the finishing-a-branch rule (update ROADMAP, then `just lint-docs`). User-global rules (RTK, ctx7) live outside the repo.
- [L][C] `.githooks/pre-commit` (48 lines) runs `just lint-docs` and blocks only on staged-file violations. It exits 0 with a stderr note if `just` is missing (`:16-19`). `core.hooksPath=.githooks` is set in this clone.
- [L][C] Skills the docs reference:
  - `superpowers:finishing-a-development-branch` (`CLAUDE.md:10`)
  - `superpowers:writing-plans`, which the repo partly overrides (`docs/sdd.md:15-21`)
  - `superpowers:subagent-driven-development` (headers of the recent plans, e.g. `docs/superpowers/plans/2026-10-03-su3-preview-adoption.md`, `2026-10-04-p30-deferred-minors.md`)
- [L][C] `.superpowers/` is gitignored run state (`.gitignore:17-20`); only a 2026-08-24 P12.4 folder remains. `.idea/` (JetBrains) is present and ignored.
- [L][S] The user auto-memory for this project holds 7 entries, all about pre-P28 machinery (Mellum, RepairLoop, P26 campaigns, allocator). None describes the current UI codebase, so it can mislead a UI-cycle agent.
