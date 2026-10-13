# SU.7b: Switching Projects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switching projects asks first mid-turn, and each recent project
shows its newest conversation, which can be resumed in one step. This
works from the toolbar's folder menu, File › Open Recent and the Dock menu.

**Architecture:**
- **Kit** turns the Recent list plus one `sessions --json --all` list into
  `RecentProject` rows. That part is pure and tested.
- **`SessionListLoader`** gains an `all` mode.
- **The controller** owns the rows, `clearRecents()`, and one switch path:
  `requestSwitch`, with `pendingSwitch`, `confirmSwitch` and `cancelSwitch`.
- **One `RecentProjectRows` view** fills the toolbar's menu and Open
  Recent. The Dock menu is an `NSMenu` built from the same rows.

Plans here list files, interfaces and tests, not bodies (`docs/sdd.md`).

**Tech Stack:** Swift 6.4, SwiftUI and AppKit on macOS 26, Swift Testing,
and the Python fake engine.

**Spec:** [`docs/superpowers/specs/2026-10-13-su7b-switching-projects-design.md`](../specs/2026-10-13-su7b-switching-projects-design.md)

## Global Constraints

- **Builds:**
  - Warnings are errors on our own targets.
  - There are no new package dependencies.
- **Tiers:**
  - The fast tier spawns nothing.
  - Integration test bodies stay at function level, using `DefaultsScope`
    plus `defer`, never closures (the Swift 6.4 closure miscompile, in
    `Support.swift`).
  - Every integration test that switches lists `.workspace: nil` and
    `.recentWorkspaces: nil` in its `DefaultsScope`, so a switch's saves
    are restored.
- **Tests:**
  - Every new test is shown to fail first.
  - Break one implementation line per table, then restore it from a backup
    copy (`/private/tmp/claude-501/brk2.sh`, `brki2.sh`), never with
    `git checkout` on uncommitted work.
- **UI:** every `#Preview` in a touched file under `Sources/SwiftStarUI/`
  is rendered with `RenderPreview` (scheme `SwiftStarUI`) and looked at.
- **Previews never spawn:** fixture controllers come from
  `EngineController(model:)`.
- **The engine's arguments, verbatim from the spec:**
  `["sessions", "--json", "--all", "--limit", "200"]`, with no `--source`.
- **Copy:**
  - the project row: the title, then " · " and the label when there is one
  - the label: the title, cut at 40 characters with "…", then " · ", then
    the relative time ("Hello · 12m ago")
  - the resume item: `Resume "<title>" · <time>`, with the `bubble.left`
    symbol
  - the alert: "End the running turn and switch to `<project>`?", with the
    conversation's title as its message, and "Switch" and "Cancel"
  - File › Open Recent, ending with "Clear Menu"
- **Parallel runs:** the `session-last` worktree's integration runs share
  our `UserDefaults`. Check `ps` for `swiftpm-testing-helper` before
  trusting a failure.

## Review Focus

1. **A Recent folder that's a subfolder of its repository.** Its label
   comes from the repository's sessions. Pinned in Task 1
   (`subfolderUsesItsRoot`).
2. **An engine without `--all`, or a failing list.** The menus still list
   the folders, with no labels and no notice. Pinned in Task 2
   (`recentProjectsFailQuietly`).
3. **A switch asked for while a session starts or quits.** It's ignored.
   Pinned in Task 3 (`switchIgnoredWhileStarting`).
4. **The turn ends while the alert is up.** "Switch" still switches.
   Pinned in Task 3 (`confirmAfterTheTurnEndsStillSwitches`).
5. **Choosing the project that's already current.** Nothing restarts.
   Pinned in Task 3 (`switchToTheCurrentFolderDoesNothing`).

---

### Task 1: Kit — recent projects and the fixture

**Files:**
- Modify: `Sources/SwiftStarKit/ToolbarMenus.swift:136-152`, which adds
  `RecentProject` and `RecentProjects` after `RecentWorkspaces`.
  `RecentWorkspaces.items` stays until Task 4.
- Create: `fixtures/engine/sessions-all.json`, hand-written
- Modify: `fixtures/engine/provenance.md`, adding its row ("hand-written,
  SU.7b")
- Test: `Tests/SwiftStarKitTests/RecentProjectsTests.swift` (new)

**Interfaces (produced):**
- `public struct RecentProject: Equatable, Sendable, Identifiable`.
  - **Fields:** `path: String` (also its `id`), `title: String` (the
    folder's `leafName`), `isCurrent: Bool`, `disabledReason: String?`
    ("folder not found"), `latest: Conversation?` and
    `latestLabel: String?`.
- `public enum RecentProjects`:
  - `static func items(recents: [String], entries: [EngineSessionEntry], current: String?, exists: (String) -> Bool, rootOf: (URL) -> URL?, now: Date, locale: Locale = .current) -> [RecentProject]`.
    For each Recent path, in order:
    - **Root:** `rootOf(URL(fileURLWithPath: path)) ?? that URL`.
    - **Its entries:** those whose `source` equals the root, comparing
      `resolvingSymlinksInPath().standardizedFileURL.path` on both sides.
    - **`latest`:** the first `resumable` row of `Conversations.group`
      over those entries.
    - **None for** a current path (`path == current`) or a missing one.
  - `static func label(_ c: Conversation, now: Date, locale: Locale) -> String`:
    the title cut at 40 characters with "…", then " · ", then the
    relative time from `Conversations.subtitle`'s formatter. It's just the
    title when `updated` is nil.
- **The fixture** has 4 entries, `updated` in local ISO form:
  - `20261012-090000-alpha`: source `/Users/example/projects/alpha`,
    "Fix the parser", resumable, alone.
  - `20261013-100000-beta`: source `/Users/example/projects/beta`,
    "Add a menu", resumable.
  - `20261013-110000-beta`: resumed from the one above, resumable, with
    first prompt "Carry on".
  - `20261013-120000-beta`: alone, `resumable: false`, 2 prompts, with
    problems `["unknown model id laguna-xs-2.1"]`.

- [ ] **Step 1: Write the fixture and the failing tests.** `RecentProjectsTests`
  is a table over the fixture, with `exists` and `rootOf` faked, `now` set
  to `parseUpdated("2026-10-13T11:12:00")`, and en_US:
  - `resumableNewestGetsItsLabel`: beta's `latest?.id` is
    `20261013-110000-beta`, and its `latestLabel` is "Add a menu · 12m ago".
  - `nonResumableNewestIsSkipped`: the same row. Its `latest` isn't
    `20261013-120000-beta`.
  - `noEntriesNoLabel`: `/Users/example/projects/gamma` has nil `latest`
    and nil `latestLabel`.
  - `currentIsCheckedWithoutLatest`: with `current` set to beta, beta's row
    has `isCurrent` true and nil `latest`.
  - `missingFolderIsDisabled`: an `exists` that says no gives
    "folder not found" and nil `latest`.
  - `subfolderUsesItsRoot`: the Recent path `…/beta/Sources`, with
    `rootOf` mapping it to `…/beta`, gets beta's `latest`.
  - `privateMatchesVar`: in a real temp folder, a Recent path that's the
    resolved temp folder matches an entry whose `source` is the
    `FileManager.temporaryDirectory` form. `latest` isn't nil.
  - `longTitleIsCut`: a hand-built entry with a 60-character first prompt
    gets a label that starts with its first 40 characters, then "… · ".
- [ ] **Step 2: Run them and see them fail.** Run
  `swift test --filter RecentProjectsTests`. Expected: a compile failure,
  because `RecentProjects` is missing.
- [ ] **Step 3: Implement it, and see them pass.** Break checks:
  - drop the `resumable` filter → `nonResumableNewestIsSkipped` fails
  - compare raw paths instead of resolved ones → `privateMatchesVar` fails
  - Restore each from a copy.
- [ ] **Step 4: Run `just test` and commit** with the message
  `SU.7b Task 1: recent projects with their newest conversation`.

### Task 2: the loader's `all` mode, and the controller's recent projects

**Files:**
- Modify: `Sources/SwiftStarEngine/SessionListLoader.swift:7-13`
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`:
  - next to `recentWorkspaces` (`:135`): the new state
  - `select(workspace:)` (`:236-247`) and `handleExit` (`:572`): each
    also starts `reloadRecentProjects()`
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift:39-42`, where the
  start-up `.task` also awaits `controller.reloadRecentProjects()`
- Test: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- Consumes: `RecentProjects.items`, `RecentProject`, and the fixture
  (Task 1).
- **Produces, on `SessionListLoader`:**
  - `public static func loadAll(executable: String, limit: Int = 200, timeout: Duration = .seconds(10), environment: [String: String]? = nil) async -> Result<[EngineSessionEntry], CatalogError>`.
    Its argv is the Global Constraints' list.
  - This refines spec §3's `all: Bool` flag: a separate entry point keeps
    `load`'s `source` non-optional. Ledger it as a ruling.
- **Produces, on `EngineController`:**
  - `private(set) var allSessions: [EngineSessionEntry] = []`
  - `public var recentProjects: [RecentProject]`, computed:
    `RecentProjects.items(recents: recentWorkspaces, entries: allSessions, current: workspace?.path, exists: { FileManager.default.fileExists(atPath: $0) }, rootOf: { ProjectRoot.locate(anchor: $0) }, now: .now)`
  - `func reloadRecentProjects() async`:
    - `guard !isFixture`
    - a `@ObservationIgnored private var recentProjectsGeneration = 0`,
      raised at each call; a result whose generation is no longer current
      is dropped
    - on success it sets `allSessions`; on failure it does nothing, with
      no notice
  - `public func clearRecents()`: empties `recentWorkspaces` and removes
    the `recentWorkspaces` default. `workspace` stays.

- [ ] **Step 1: Write the failing tests.**
  - `allSessionsLoaderPassesAll` (loader suite): `loadAll`, with
    `FAKE_ENGINE_ARGV_LOG`, the argv is exactly
    `["sessions", "--json", "--all", "--limit", "200"]`.
  - `recentProjectsFillFromAllSessions`:
    - read `sessions-all.json` and replace `/Users/example/projects/beta`
      with a `tempRepo()`'s path; write it to a `tempPath`, and pass it
      as `FakeEngine(extra: ["FAKE_ENGINE_SESSIONS": path])`
    - `DefaultsScope` sets `.recentWorkspaces: [repo]`; after `init`, set
      `controller.workspace = FileManager.default.temporaryDirectory`,
      so the repository isn't current
    - after `reloadRecentProjects()`, the row for `repo` has
      `latest?.id == "20261013-110000-beta"`
  - `recentProjectsFailQuietly`: with a `FakeEngine()` that has no
    `sessions` mode, after `reloadRecentProjects()` every row's
    `latestLabel` is nil and `transcript.rows` is empty.
  - `clearRecentsEmptiesTheList`: `recentWorkspaces` is empty, the default
    is nil, and `workspace` is unchanged.
- [ ] **Step 2: Run them and see them fail.** Run
  `SWIFTSTAR_INTEGRATION=1 swift test --filter "EngineModelCatalogLoaderTests|EngineControllerTests"`.
  Expected: a compile failure on the missing members.
- [ ] **Step 3: Implement it, and see them pass.** The generation counter
  has no test of its own: the fake reads its file after a fixed sleep, so
  an older call can't be made to finish last. It's for review. Break
  check: drop `"--all"` from the argv → `allSessionsLoaderPassesAll`
  fails. Restore it.
- [ ] **Step 4: Run `just test` and `just integration`, and commit** with
  the message `SU.7b Task 2: the controller lists every project's sessions`.

### Task 3: the controller — one switch path

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`, next to
  `select(workspace:)` (`:236-247`)
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- Consumes: `resume(_:)` (`:112`), `select(workspace:)`, `canChoose`,
  `transcript.isBusy`, and `reloadRecentProjects()` (Task 2).
- **Produces, on `EngineController`:**
  - `public struct ProjectSwitch: Equatable, Sendable`, with
    `folder: URL` and `resuming: Conversation?`
  - `public private(set) var pendingSwitch: ProjectSwitch?`
  - `public func requestSwitch(to folder: URL, resuming: Conversation? = nil)`:
    - ignored when `!canChoose`
    - when `transcript.isBusy`: sets `pendingSwitch` and returns
    - otherwise: `perform(…)`
  - `public func confirmSwitch()`: takes `pendingSwitch`, clears it, then
    performs it. `public func cancelSwitch()` only clears it.
  - `private func perform(_ s: ProjectSwitch)`:
    - `guard canChoose`
    - **No conversation:** `select(workspace: s.folder)`.
    - **A conversation:**
      - save Recent as `select` does, and set `workspace`
      - clear `conversations`
      - then `Task { await resume(c); await reloadConversations(); await reloadRecentProjects() }`
      - no `restartIfRunning()`
    - The Recent save is shared with `select(workspace:)` through a
      private `remember(_ url: URL)`, not copied.

- [ ] **Step 1: Write the failing tests.** Each uses `running(f)` (the
  workspace is the temp folder) and a `tempRepo()` as `b`. Its root is
  `ProjectRoot.locate(anchor: b)!`.
  - `switchWhenIdleDoesNotAsk`: `requestSwitch(to: b)` leaves
    `pendingSwitch` nil. Eventually there are 2 spawns, the last with
    `--source` set to `b`'s root.
  - `switchMidTurnAsksFirst`: after `send` and `eventually isBusy`,
    `requestSwitch(to: b)` sets `pendingSwitch?.folder == b`. The
    `workspace` and `spawnArgv.count` (1) are unchanged.
  - `confirmedSwitchRestartsInTheNewRoot`: the same, then
    `confirmSwitch()` → `workspace == b`, `pendingSwitch == nil`, and
    eventually the 2nd spawn's `--source` is `b`'s root.
  - `cancelledSwitchChangesNothing`: the same, then `cancelSwitch()` →
    `pendingSwitch` is nil, the workspace is unchanged, and there's 1 spawn
    after 300 ms.
  - `confirmAfterTheTurnEndsStillSwitches`: ask mid-turn, wait until
    `!isBusy`, then `confirmSwitch()` → `workspace == b`.
  - `switchAndResumeSpawnsOnce`:
    - running in the temp folder, call `requestSwitch(to: b, resuming: c)`
    - `c` is a hand-built resumable `Conversation`, id
      `20261013-110000-beta`
    - eventually 2 spawns, and after 300 ms still 2
    - the last spawn is `EngineCommand.resumeArguments(id: c.id, source: root)`
  - `switchIgnoredWhileStarting`: during `.starting`, `requestSwitch(to: b)`
    leaves `workspace` and `pendingSwitch` unchanged.
  - `switchToTheCurrentFolderDoesNothing`: `requestSwitch(to: workspace!)`
    leaves 1 spawn after 300 ms.
- [ ] **Step 2: Run them and see them fail.** Expected: a compile failure
  on the missing members.
- [ ] **Step 3: Implement it, and see them pass.** Break checks:
  - drop the `isBusy` branch → `switchMidTurnAsksFirst` fails
  - let a resuming switch call `select(workspace:)`, which restarts →
    `switchAndResumeSpawnsOnce` fails with 3 spawns
  - Restore each from a copy.
- [ ] **Step 4: Run `just test` and `just integration`, and commit** with
  the message `SU.7b Task 3: one switch path that asks first mid-turn`.

### Task 4: the menus, the alert, previews and close

**Files:**
- Create: `Sources/SwiftStarUI/Session/RecentProjectRows.swift`
- Modify: `Sources/SwiftStarUI/Session/SessionToolbar.swift`:
  - `:81-101`: `folderMenu` uses `RecentProjectRows`
  - `:146-150`: `pickWorkspace` calls `requestSwitch`
  - the `.help` text: "Choosing another ends a running session; mid-turn,
    it asks first."
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift`, adding the
  switch alert after the context-size alert
- Modify: `Sources/SwiftStar/SwiftStarApp.swift`:
  - `.commands` gains Open Recent
  - `AppDelegate` gains the Dock menu
  - `import SwiftStarKit`
- Modify: `Package.swift:65`, where the `SwiftStar` target depends on
  `SwiftStarKit` too. That's only if the build asks for it; ledger it if not.
- Modify: `Sources/SwiftStarKit/ToolbarMenus.swift`, removing
  `RecentWorkspaces.items`
- Modify: `Tests/SwiftStarKitTests/EngineModelCatalogTests.swift:202-208`,
  removing `recentWorkspaceItemsDisableMissingFolders`. Its checks live on
  in `currentIsCheckedWithoutLatest` and `missingFolderIsDisabled`.
- Modify: `ROADMAP.md`:
  - the `## Now` "Next" line
  - SU.7's Status, at most 400 characters: "7a and 7b done 2026-10-13",
    with links to both specs and plans
- Modify: this plan, adding `## Result`

**Interfaces:**
- Consumes: `recentProjects`, `requestSwitch`, `pendingSwitch`,
  `confirmSwitch`, `cancelSwitch`, `clearRecents` and `ProjectSwitch`
  (Tasks 2–3).
- **Produces:**
  - `public struct RecentProjectRows: View`, with `public init(controller: EngineController)`.
    Its controller is a parameter, because `.commands` has no window
    environment. For each `recentProjects` row:
    - **The project row:** a `Button` with the checkmark `Label` for
      `isCurrent`, its text being `title` plus " · `latestLabel`" when
      there's one, and " — `disabledReason`" when there's one. It's
      `.disabled` when there's a reason. The action is
      `requestSwitch(to: URL(fileURLWithPath: path))`.
    - **The resume item, when `latest` is set:**
      `Label("Resume \"\(c.title)\" · …", systemImage: "bubble.left")`.
      Its action is `requestSwitch(to:resuming: c)`. Its time is
      `latestLabel`'s part after its last " · ".
  - **The toolbar:** `Menu { RecentProjectRows(controller:); if !recentWorkspaces.isEmpty { Divider() }; Button("Choose Folder…") }`.
  - **Open Recent:** `CommandGroup(after: .newItem) { Menu("Open Recent") { RecentProjectRows(controller: engine); Divider(); Button("Clear Menu") { engine.clearRecents() } } }`.
    "Clear Menu" is disabled when `recentProjects` is empty.
  - **The Dock menu:** `func applicationDockMenu(_ sender: NSApplication) -> NSMenu?`.
    - It builds one `NSMenuItem` per row, and one per resume item with
      `indentationLevel = 1`, using the row titles above.
    - `representedObject` is a `ProjectSwitch`; current and disabled rows
      have no action.
    - The action, `@objc openRecent(_:)`, calls `NSApp.activate()` and
      then `engine?.requestSwitch(to:resuming:)`.
    - It returns nil when there's no engine or no rows.
  - **The alert:** `.alert("End the running turn and switch to \(leafName)?", isPresented: Binding(get: { controller.pendingSwitch != nil }, set: { if !$0 { controller.cancelSwitch() } }))`.
    - "Switch" calls `confirmSwitch()`, and "Cancel" (`.cancel`) calls
      `cancelSwitch()`.
    - The message is `pendingSwitch?.resuming?.title`, or nothing.

- [ ] **Step 1: Build the views.** There's no new unit test: the rows hold
  no logic beyond Task 1's, and menus and alerts don't show in a snapshot.
  `swift build` must be clean, with warnings as errors.
- [ ] **Step 2: Remove `RecentWorkspaces.items` and its test.** Run
  `just test`; expected: green, with one fewer test.
- [ ] **Step 3: Render the previews** and look at each one:
  - `SessionView`: "Running", "Idle", "Analyzing" and "Large font"
  - `SessionToolbar`'s "Running"
  - `MainView`'s "Running"

  Each should look as it did before, apart from the folder menu's label.
- [ ] **Step 4: Run `just test`, `just integration` and `just lint-docs`**,
  all green, with no orphaned fakes.
- [ ] **Step 5: Write `## Result` and the ROADMAP update, then commit**
  with the message `SU.7b Task 4: the menus, Open Recent, the Dock menu and the switch alert; close 7b`.
  - The Result names the owner's live checks: the folder menu, Open
    Recent, the Dock menu, the confirmation, and both resume paths.
  - It also names what's still unverified live from earlier cycles: the
    6c no-folder picker, the Session menu, and the 7a sidebar.

## Result

**Commits:** `ec160f8`..this one, on `main`. Suites: 139 fast and 78
integration.

**Break checks:** each broken line failed its test, then passed restored.
- **Kit:** taking the newest row even if it can't be resumed; comparing raw
  paths, not resolved ones; dropping "folder not found" from a row title.
- **Loader:** dropping `--all`.
- **Controller:** dropping the mid-turn branch; letting a resuming switch
  restart first (it fails on the last spawn's arguments).

**Previews**, rendered and unchanged: `SessionView`'s four (its "Running"
again after the fixes), plus `SessionToolbar`'s and `MainView`'s "Running".

**Final review fixes**, each failing first: "Switch" confirms the alert's
own request (`confirmSwitchTakesThePresentedRequest`); the current folder
mid-turn doesn't ask (`switchToTheCurrentFolderMidTurnDoesNotAsk`); a
performed switch clears a waiting one (`performingASwitchClearsAPendingOne`);
"Clear Menu" reads a cheap `hasRecents` (`clearRecentsEmptiesTheList`).

**Diverged:**
- **`SessionListLoader.loadAll`,** not spec §3's `all:` flag.
- **Row titles are built in Kit** (`RecentProject.menuTitle`,
  `resumeTitle`; `menuTitlesReadAsSpecified`), shared by all three menus.
  The resume item uses the label's shortened title.
- **The reload is its own `.task`; `RecentProjectsTests` aren't a table.**
- **`SwiftStar` depends on `SwiftStarKit`; the counter has no test.**
- **Two full integration runs failed** in `exitReportedWhenGrandchildHoldsPipe`,
  which this cycle didn't touch: the exit wasn't seen within 5 s.
  - Those runs took 62–74 s, not about 30 s, while Xcode rendered previews
    and a `ds4-candidate` engine worktree was open.
  - It passed 3 times alone and in later full runs; it's in the Backlog.

**For the owner to check live:** the folder menu, Open Recent with "Clear
Menu", the Dock menu, the mid-turn confirmation, and both resume paths.
Still unchecked from earlier cycles: the 6c no-folder picker, the Session
menu, and the 7a sidebar.
