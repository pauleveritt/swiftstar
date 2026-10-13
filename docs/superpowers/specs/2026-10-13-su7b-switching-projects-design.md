# SU.7b: switching projects

SU.7 has three parts:
- **7a, done:** a sidebar of the current project's conversations, and
  resuming one.
- **7b, this spec:** switching between projects.
- **7c:** more than one window. It waits on the engine.

The starting point is
[the 2026-10-04 options, §Recommendation](../research/2026-10-04-project-focus-options.md):
one window and one project at a time. It also lists a richer project
switcher, a quick switcher, File › Open Recent and the Dock menu.

## Decisions

The owner made these on 2026-10-13.

**D1. Scope.**
- **In:**
  - a confirmation before switching mid-turn
  - each recent project's newest conversation
  - File › Open Recent
  - the Dock menu
- **Out:**
  - **The quick switcher (⌘K / ⇧⌘O):** five recent folders don't need one.
  - **The busy dot (D4).**

**D2. A recent project shows its newest conversation twice.**
- **A label** on the project's row: "Hello · 12m ago".
- **A resume item** under it, "Resume "Hello" · 12m ago". It switches to the
  project and resumes that conversation in one step.

Choosing the project row itself switches as it does today, and starts
fresh.

**D3. One switch path.** The toolbar's folder menu, the folder picker, File ›
Open Recent and the Dock menu all call `requestSwitch`. Mid-turn, it asks
first; otherwise it switches straight away. Today `select(workspace:)` ends
a running turn without asking.

**D4. No busy dot.** There is one engine, so only the current project can
be busy, and the status bar already shows that.

## 1. What the engine provides

This was checked on 2026-10-13 against `ds4-dogfood` at `5451cd7d`.

**`sessions --json --all --limit N`** lists every repository's sessions
(`E/src/ds4_engine/sessions.py:344-362`) in the same shape as 7a's
`--source` list.
- **This Mac:** 64 sessions from 8 sources, in 0.13 s.
- **`source`:** each worktree is its own source (`…/.claude/worktrees/session-last`).
  It's the path the session started from, unresolved: one is
  `/var/folders/…`, not `/private/var/…`.

**One call covers every recent project.** Five Recent folders, at most,
from one list. Asking `--source` per folder would spawn five processes.
With `--limit 200`, a project whose newest session is older than the 200
newest across all repositories gets no label. That's acceptable for a
"recent" menu.

## 2. Kit: recent projects

- **`RecentProject`** (`Equatable`, `Sendable`):
  - `path`, `title` (the folder's leaf name)
  - `isCurrent`, `disabledReason` (as `RecentWorkspaces.items` gives)
  - `latest: Conversation?`, `latestLabel: String?` ("Hello · 12m ago")
- **`RecentProjects.items(recents:entries:current:exists:rootOf:now:locale:) -> [RecentProject]`**
  is pure. For each Recent path, in order:
  - **Root:** `rootOf(path)`, the git root (`ProjectRoot.locate` in the
    app), else the path itself.
  - **Its entries:** those whose `source` is that root. Both sides are
    compared after `resolvingSymlinksInPath().standardizedFileURL`.
  - **`latest`:** the first resumable conversation of
    `Conversations.group(those entries)`, which is newest first.
  - **None for** the current project, whose conversations are in the
    sidebar, or a folder that doesn't exist.
  - **`latestLabel`:** the title, cut at 40 characters with "…", then " · ",
    then the relative time from `Conversations.subtitle`'s formatter.
- **`RecentWorkspaces.items`** goes. `RecentProjects.items` replaces it,
  and `RecentWorkspaces.updated` stays.

## 3. Engine: listing every repository

`SessionListLoader.load` gains `all: Bool = false`. When it's true, the
arguments are `["sessions", "--json", "--all", "--limit", "200"]`, with no
`--source`. Everything else is shared with 7a.

## 4. The controller

**The recent projects:**
- **`allSessions: [EngineSessionEntry]`:** empty until loaded.
- **`recentProjects: [RecentProject]`:** computed from `recentWorkspaces`,
  `allSessions` and `workspace`.
- **`reloadRecentProjects() async`:** runs on the same triggers as
  `reloadConversations()`: after `init`, after each exit, and after a switch.
  - **On failure:** `allSessions` stays as it was, and there's no notice.
    The rows show no label.
  - **A stale result:** a reload that finishes after a newer one has started
    is dropped. A generation counter tells them apart.
- **`clearRecents()`:** empties `recentWorkspaces` and its default. The
  current workspace stays.

**The switch:**
- **`ProjectSwitch`:** `folder: URL` and `resuming: Conversation?`.
- **`pendingSwitch: ProjectSwitch?`:** set when a switch waits for
  confirmation.
- **`requestSwitch(to folder: URL, resuming: Conversation? = nil)`:**
  - **Ignored when** `!canChoose`.
  - **Mid-turn** (`transcript.isBusy`): sets `pendingSwitch` and returns.
    Nothing spawns, and nothing changes.
  - **Otherwise:** calls `perform(_:)` straight away.
- **`confirmSwitch()`** performs `pendingSwitch` and clears it.
  **`cancelSwitch()`** only clears it.
- **`perform(_:)`** (private):
  - **A plain switch** is today's `select(workspace:)`: save to Recent,
    clear the conversations, reload, and restart a running session.
  - **A switch that resumes** saves to Recent and sets the workspace. It
    doesn't restart. Then it calls `resume(conversation)`, which quits any
    running session and spawns once with `--resume <id> --source <new root>`.
    Then it reloads both lists.
  - **The resume item isn't shown for** the current project (§2), so a
    resuming switch always changes folder.
- **`select(workspace:)`** stays for the folder picker that opens when
  there's no folder (6c), which never runs mid-turn. The toolbar's "Choose
  Folder…" moves to `requestSwitch`.

## 5. Where it shows

- **The toolbar's folder menu**, for each `RecentProject`:
  - **The project row:**
    - the title, with "· `latestLabel`" when it has one
    - a checkmark when it's current
    - disabled with its reason
  - **The resume item,** when `latest` is set: `Label("Resume "Hello" · 12m ago", systemImage: "bubble.left")`.
  - **Then** a divider and "Choose Folder…", as today.
- **File › Open Recent:** a `CommandGroup(after: .newItem)` holds a
  `Menu("Open Recent")` with the same rows. A divider and "Clear Menu"
  follow. Both menus build their rows from one `RecentProjectRows` view, so
  they stay alike.
- **The Dock menu:** `AppDelegate.applicationDockMenu(_:)` builds an
  `NSMenu` from `engine.recentProjects`.
  - The resume items sit at `indentationLevel = 1`.
  - Each item's action activates the app, then calls `requestSwitch`, so a
    mid-turn confirmation shows on a front window.
- **The confirmation:** `SessionView` shows an alert while `pendingSwitch`
  is set:
  - **Title:** "End the running turn and switch to `<project>`?"
  - **Message:** the conversation's title, when it resumes one.
  - **Buttons:** "Switch", which calls `confirmSwitch()`, and "Cancel".

## 6. Tests and fixtures

**A fixture,** `fixtures/engine/sessions-all.json`, is hand-written and
listed as such in `provenance.md`. It holds:
- two sources, one of which has a chain
- a newest session that can't be resumed, above an older one that can

**Fast tier, `RecentProjectsTests`** (a table, with `rootOf`, `exists`,
`now` and en_US fixed):
- **A recent with a resumable newest conversation** gets its label.
- **A newest conversation that can't be resumed** is skipped for the older
  one.
- **A recent with no entries** gets no label.
- **The current project** is checked, and has no `latest`.
- **A missing folder** is disabled, with no `latest`.
- **A subfolder** gets its repository's entries, through `rootOf`.
- **A `/private` path** matches its `/var` source. This row uses a real
  temporary folder, because resolving a symlink needs the path to exist.
- **A long title** is cut at 40 characters, with "…".

**Integration tier** (each with `FakeEngine` and `DefaultsScope`):
- `allSessionsLoaderPassesAll`: the fake's argv log is
  `["sessions", "--json", "--all", "--limit", "200"]`.
- `switchMidTurnAsksFirst`: mid-turn, `requestSwitch(to: b)` sets
  `pendingSwitch`. The workspace and `spawnArgv` are unchanged.
- `confirmedSwitchRestartsInTheNewRoot`: `confirmSwitch()` sets the
  workspace to `b`, and the next spawn's `--source` is `b`'s root.
- `cancelledSwitchChangesNothing`: after `cancelSwitch()`, `pendingSwitch`
  is nil, and the workspace and `spawnArgv` are unchanged.
- `switchAndResumeSpawnsOnce`: running in `a`, `requestSwitch(to: b,
  resuming: c)` gives exactly one new spawn,
  `resumeArguments(id: c.id, source: b)`.
- `recentProjectsFillFromAllSessions`: after `reloadRecentProjects()`, the
  Recent entry for `b` has `latest?.id == c.id`.
- `clearRecentsEmptiesTheList`: `recentWorkspaces` is empty, and so is the
  saved default.

Each test is shown to fail first.

**Previews:** `SessionView` "Running", and `MainView`. Menus and alerts
don't show in a snapshot, so the owner checks these live:
- the folder menu
- Open Recent
- the Dock menu
- the confirmation

## 7. Out of scope

- The quick switcher and the busy dot (D1, D4).
- More than one window (7c).
- Pinning or reordering recent projects. The Recent cap stays at 5.
- The 7a minors: the selection snapping back, two reloads out of order,
  branch rows sharing a title. `reloadRecentProjects` gets its own counter;
  `reloadConversations` is left as is.
