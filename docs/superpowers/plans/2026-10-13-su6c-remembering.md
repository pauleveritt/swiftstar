# SU.6c: remembering the workspace and the last session

A small cycle (`docs/sdd.md`): one doc, no spec. It covers SU.6's
"Remembering" punch-list item.

## Decisions

The owner made these on 2026-10-13.

**D1. When there's no usable workspace, fall back, else ask.**
- **A usable folder** is one that exists and sits in a git repository.
- **When the saved folder can't be used:** use the newest Recent folder
  that can, and say so in a notice.
- **When nothing can be used:** don't start. A notice says why, and the
  folder picker opens. Picking a folder starts the session.

This replaces two failures seen on 2026-10-13:
- a saved folder that pointed at a deleted worktree refused every start
- a packaged app's first launch started in `~`, which the engine refuses

**D2. The apply command for the last session is one click away.**
- **What's remembered:** the most recent ended session's directory, kept
  across relaunches and app restarts.
- **The action:** a **Session** menu holds "Copy Apply Command" (⇧⌘C).
- **Older sessions:** applying one waits for SU.7's session list.

## Facts this rests on

- **The saved workspace is never checked.**
  `EngineController.defaultWorkspace()` (`EngineController.swift:106-113`)
  restores it unchecked.
- **`start()` falls back to the home folder:** `workspace ?? home`
  (`:286`).
- **A deleted folder can still find a git root.** `ProjectRoot.locate`
  walks up from the anchor, so a deleted worktree inside a repository
  (`<repo>/.claude/worktrees/x`) still finds `<repo>`. "Usable" therefore
  needs the folder to exist as well as a root to be found.
- **The apply command is shown once.** It's in the system row written at
  exit (`EngineSessionModel.swift:136-140`). After that it's only in the
  scrollback.
- **The folder picker** is a private `NSOpenPanel` in `SessionToolbar`
  (`:146-156`). `SessionToolbar` is `ToolbarContent`, so it can't hold an
  `.onChange`.

## Tasks

### Task 1: the workspace rule in Kit and the controller

**Files:**
- Create: `Sources/SwiftStarKit/WorkspaceChoice.swift`
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`
  - `:64-75`: `init` uses the rule
  - `:106-113`: `defaultWorkspace()` gives way to the rule
  - `:260-290`: `start()` with no workspace
- Modify: `Sources/SwiftStarUI/Session/SessionToolbar.swift:146-156`: the
  picker moves to a shared `WorkspacePicker`
- Modify: `Sources/SwiftStarUI/Session/SessionView.swift`: opens the picker
  when the controller asks
- Tests:
  - `Tests/SwiftStarKitTests/WorkspaceChoiceTests.swift` (new)
  - `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`

**Interfaces:**
- `public enum WorkspaceChoice`, with
  `static func resolve(saved: String?, recents: [String], checkout: URL?, isUsable: (URL) -> Bool) -> (workspace: URL?, notice: String?)`.
  It works through these in order:
  1. **A usable saved folder:** return it, with no notice.
  2. **A saved folder that isn't usable:** return the first usable Recent
     folder other than the saved one, with the notice "The saved folder
     `<saved>` can't be used (it's missing or not in a git repository);
     using `<leafName>`."
  3. **Nothing saved:** return `checkout` if it's usable, with no notice.
  4. **Otherwise:** return nil, with the notice "Choose a folder in a git
     repository to start." For a saved folder that couldn't be used, the
     notice starts with the "can't be used" sentence first.
- `WorkspaceChoice.isUsable(_ url: URL) -> Bool`: the folder exists, is a
  directory, and `ProjectRoot.locate(anchor: url)` isn't nil.
- **`EngineController`:**
  - **At `init`:** it calls `resolve` with `isUsable`. The workspace it
    returns is saved through `workspace`'s `didSet`. The notice is held
    and shown once, the way the catalog note is.
  - **`wantsFolder: Bool`:** set by `start()` when `workspace` is nil.
    That `start()` shows the notice and spawns nothing. The flag is reset
    by `select(workspace:)`, or by `folderPickerDismissed()`.
  - **`start()`** no longer falls back to the home folder.
- **`WorkspacePicker.run(from: URL?) -> URL?`**
  (`Sources/SwiftStarUI/Components/WorkspacePicker.swift`) is the panel,
  moved from the toolbar.
  - **The toolbar's "Choose Folder…"** calls it, as today.
  - **`SessionView`:** `.onChange(of: controller.wantsFolder)`, when true,
    calls it. A picked folder means `select(workspace:)` then `start()`.
    Cancelling means `folderPickerDismissed()`.

**Tests** (each shown to fail first):
- `resolve`, a table with `isUsable` faked on a set of paths:
  - `savedUsableIsKept`: returns the saved folder, with no notice.
  - `missingSavedFallsBackToRecent`: returns the first usable Recent folder,
    with the "can't be used … using `<name>`" notice.
  - `fallbackSkipsTheSavedEntryInRecents`: when the saved path is also first
    in the Recent list, the second usable entry is used.
  - `nothingUsableAsksForAFolder`: the saved folder is gone and no Recent
    folder is usable → nil, and the notice contains both sentences.
  - `firstLaunchInACheckout`: nothing is saved and the checkout is usable →
    the checkout, with no notice.
  - `firstLaunchOutsideACheckout`: nothing is saved and the checkout isn't
    usable → nil, with "Choose a folder in a git repository to start."
- `isUsableNeedsTheFolderItself`: a temporary repository with `.git`. Its
  missing child folder isn't usable, though `locate` finds the repository
  from it. The repository root is usable.
- **Integration:**
  - `missingWorkspaceFallsBackToRecent`:
    - setup: `DefaultsScope` with a deleted saved folder, and the Recent list
      holding a temporary git folder
    - checks: the controller's `workspace` is the Recent folder, and the
      saved default now holds it
  - `noWorkspaceDoesNotSpawn`:
    - setup: nothing usable
    - checks: `start()` leaves `FakeEngine.spawnArgv` empty, `wantsFolder` is
      true, and the transcript has the notice

Break check: let `isUsable` skip the existence check, and
`isUsableNeedsTheFolderItself` fails.

### Task 2: the last session's apply command, the menu and the close

**Files:**
- `Sources/SwiftStarKit/DefaultsKey.swift`: adds
  `lastSessionDirectory = "lastSessionDirectory"`
- `Sources/SwiftStarUI/State/EngineController.swift:405-411`: `handleExit`
  saves the directory
- `Sources/SwiftStar/SwiftStarApp.swift`: the `CommandMenu("Session")`
- `ROADMAP.md`:
  - SU.6's Status
  - the Remembering punch-list item, which comes out
- This doc's `## Result`

**Interfaces:**
- `EngineController.lastSessionDirectory: URL?`:
  - loaded at `init`
  - saved by `handleExit` when its directory isn't nil
- `EngineController.applyCommand: String?`:
  - `EngineCommand.applyCommand(sessionDirectory:)` for
    `lastSessionDirectory`
  - nil when there's none, or when the folder no longer exists
- `EngineController.copyApplyCommand()` writes the command to
  `NSPasteboard.general` and adds the notice "Copied: `<command>`".
- **The menu item:** `CommandMenu("Session") { Button("Copy Apply Command")
  { engine.copyApplyCommand() }.keyboardShortcut("c", modifiers:
  [.command, .shift]).disabled(engine.applyCommand == nil) }`.

**Tests** (each shown to fail first):
- `lastSessionDirectoryOutlivesTheController` (integration):
  - a `FakeEngine` session is started and quit
  - its exit reports `/tmp/fake-session`
  - a new `EngineController()` has `lastSessionDirectory` set to
    `/tmp/fake-session`
  - `applyCommand` is nil there, because that folder doesn't exist in the
    test
- `applyCommandNeedsAnExistingDirectory` (integration):
  - `DefaultsScope` sets `lastSessionDirectory` to a temporary folder named
    `20261013-000000-x`
  - `applyCommand` is "ds4-dogfood apply 20261013-000000-x"
  - after the folder is deleted, it's nil

Break check: drop the save in `handleExit`, and
`lastSessionDirectoryOutlivesTheController` fails.

**Close:**
- Render `SessionView`'s and `ComposerView`'s previews. The previews' fixture
  controllers skip `init()`, so nothing in them changes. Rendering confirms
  they still build.
- Run `just test` and `just integration`; both must pass, and a full run
  must leave no orphaned fakes.
- Run `just lint-docs`.
- Write the Result.

## Result

**Commits:** `2945936`..this one, on `main`. Suites: 100 fast and 43
integration, all passing, with no orphaned fakes.

**Break checks:** each new test failed against one broken line, then
passed once it was restored.
- Without the existence check, `isUsableNeedsTheFolderItself` fails.
- Starting in the home folder again fails `noWorkspaceDoesNotSpawn`.
- Without the `didSet` save, `missingWorkspaceFallsBackToRecent` fails.
- Without the save in `handleExit`,
  `lastSessionDirectoryOutlivesTheController` fails.
- Without the existence check on `applyCommand`,
  `applyCommandNeedsAnExistingDirectory` fails.

**Previews:** `SessionView`'s three previews and `ComposerView`'s "Ready"
were rendered and are unchanged. Their fixture controllers skip `init()`.

**Diverged:**
- **The "skip the saved entry" filter was dropped.** Breaking it changed
  nothing: the saved folder had already failed `isUsable`.
- **There's no explicit save of a fallback in `init`.** `@Observable`
  makes `workspace` a computed property, so its `didSet` runs in `init`.
  The doc's premise that it doesn't was wrong.
- **`DefaultsScope` now takes `Any?` values,** because the Recent list is
  an array.
- **`DefaultsKeyTests` pins the new key's raw value.**
- **The menu's enabling flag is `canCopyApplyCommand`.**
- **Not exercised live:** the Session menu and the picker that opens when
  there's no folder. Both need a real app launch with windows.
- **Interference between test runs:** the first full run failed while
  another session ran integration tests in the `session-last` worktree.
  Both share the test runner's `UserDefaults` domain. A re-run on its own
  passed.
