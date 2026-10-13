# SU.7a: the project's conversations, and resume

SU.7 splits into three parts:
- **7a, this spec:** a sidebar of the current project's conversations, and
  resuming one.
- **7b:** switching between projects.
- **7c:** more than one window, which waits on the engine.

The starting point is
[the 2026-10-04 options](../research/2026-10-04-project-focus-options.md):
one window, one project at a time, and a sidebar that shows only this
project.

## Decisions

The owner made these on 2026-10-13.

**D1. Sessions and resume come first,** ahead of switching projects. The
engine supports them today.

**D2. A sidebar row is one conversation, not one session directory.** Each
`/rewind`, `/model` or resume starts a new session directory, linked to the
one before by `resumed_from`. A row follows that chain and stands for its
newest session.

**D3. Clicking a row resumes it.**
- **The current session:** it ends, and stays in the list.
- **The clicked conversation:** it resumes, with its transcript rebuilt from
  the engine.
- **Mid-turn:** a confirmation comes first. Otherwise nothing asks, because
  the current conversation is already saved and listed.

**D4. A real sidebar.** `MainView` becomes a `NavigationSplitView`:
- conversations in the sidebar
- the session (transcript, composer, status bar) in the detail
- the inspector staying on the right

A toolbar popover was rejected, because it hides the project's past work.

## 1. What the engine provides

This was checked on 2026-10-13 against `ds4-dogfood` at `5451cd7d`.

**The list command.** `ds4-dogfood sessions --json --source <repo>
--limit N` returns sessions newest first (`E/src/ds4_engine/sessions.py:344-366`).
- **Fields seen:** `id` (the directory name, such as
  `20261013-123136-swiftstar`), `path`, `source`, `model_id`,
  `context_size`, `updated`, `prompts`, `first_prompt`, `last_prompt`,
  `context_used`, `resumed_from` (a path or null), `commit`,
  `files_changed`, `snapshots`, `resumable` and `problems`.
- **`first_prompt` belongs to that directory, not the conversation.**
  Session `123136` was resumed from `122439`. It says "Hello", while
  `122439`'s says "I want to see how you work as an agent…".

**Resuming.** `tui --ndjson --resume <id>` resumes a session
(`E/src/ds4_engine/tui_cli.py:535-560`). Two catches:
- **`--commit`:** must not be passed (`:758-759`).
- **`--model-id`:** must not be passed without `--new-conversation`
  (`:510-518`). Leaving it out keeps the conversation's own model.

Laguna-era conversations name a model id the engine now refuses. Such a
start fails with the engine's reason.

**The `resumed` event** names the session it resumed from: `session` is the
directory id, and `path` is its directory (`fixtures/engine/resumed.ndjson`).
`resumed.turns` rebuilds the transcript. That already works for `/rewind`
and `/model` (EN.1).

**The current session's own directory.** The `session` event doesn't name
it. The first `checkpoint`'s `snapshot.capture_path` does: it's
`…/sessions/<id>/run-*.partial.json` (`fixtures/engine/tool-read.ndjson`).

## 2. Kit: entries, conversations and arguments

- **`EngineSessionEntry`** (`Decodable`, `Sendable`, `Equatable`) holds
  `id`, `path`, `source`, `modelID`, `updated` (a `Date`, parsed from the
  local ISO timestamp), `prompts`, `firstPrompt`, `lastPrompt`,
  `resumedFrom`, `resumable` and `problems`.
  - Every field except `id` and `path` is optional.
  - Unknown keys are ignored.
  - `EngineSessionEntry.decodeList(_ data: Data) -> Result<[EngineSessionEntry], CatalogError>`
    reuses the model list's error type.
- **`Conversation`** holds `id` (its newest session's `id`, which is also
  the resume target), `title`, `updated`, `modelID`, `resumable`,
  `problems` and `sessionIDs` (every listed id in its chain).
- **`Conversations.group(_ entries: [EngineSessionEntry]) -> [Conversation]`**
  is pure.
  - **Heads:** a head is an entry whose `path` isn't any other entry's
    `resumedFrom`. Two entries resumed from the same parent make two heads,
    since a rewind branches.
  - **The walk:** from each head, follow `resumedFrom` through the listed
    entries to the oldest one. It stops at an unlisted path or a cycle.
  - **`title`:** the oldest listed entry's `firstPrompt`. If that's
    missing, the head's `firstPrompt`; failing that, "Untitled".
  - **The other fields** come from the head.
  - **Order:** newest `updated` first.
- **`Conversations.subtitle(_ c: Conversation, now: Date, locale: Locale) -> String`**
  gives, for example, "12 min ago · qwen3.8-27b". It uses
  `RelativeDateTimeFormatter`, and leaves the model out when there's none.
- **`EngineCommand.resumeArguments(id: String, source: URL) -> [String]`**
  gives `["tui", "--ndjson", "--resume", id, "--source", source.path]`, with
  no `--commit` and no model or context flags.
- **`PauseMetrics` gains `capturePath: String?`,** decoded from
  `snapshot.capture_path`. A helper,
  `EngineSessionEntry.directoryID(fromCapturePath:) -> String?`, returns
  the parent directory's name.

## 3. Engine: the list loader

`SessionListLoader.load(executable:source:limit:timeout:environment:) async -> Result<[EngineSessionEntry], CatalogError>`
lives in `SwiftStarEngine`. It runs `sessions --json --source <root>
--limit 50`, with the same timeout, stderr tail and `commandMissing`
handling as `EngineModelCatalogLoader`. Where they share code, the shared
part moves out rather than being copied.

## 4. The controller

**State and loading:**
- **`conversations: [Conversation]`:** empty until loaded, and empty when
  there's no workspace.
- **`reloadConversations() async`** loads the list for the current
  workspace's git root, then groups it.
  - **When it runs:** after `init`'s workspace is resolved, after every
    session exit, and after `select(workspace:)`.
  - **On failure:** the list stays as it was, and a one-time note goes in
    the transcript, as for the model list.
- **`currentConversationID: String?`** is the id of the conversation whose
  `sessionIDs` contain the current session.
  - **The current session** is known from `resumed.session` (the session it
    resumed from) or from the first checkpoint's capture path.
  - **Before either arrives** it's nil, and no row is highlighted.

**Actions:**
- **`resume(_ c: Conversation) async`:**
  - **Guards:** it's ignored when `!canChoose`, when the conversation isn't
    resumable, or when `c.id` is already the current conversation.
  - **Otherwise:** it quits any running session and waits, then calls
    `start(relaunch: EngineRelaunch(kind: .resume, argv: resumeArguments(…), reason: ""))`.
  - **What you see:** the existing "Resumed session `<id>`" divider and the
    rebuilt rows.
- **`resumeNeedsConfirmation: Bool`** is `transcript.isBusy`. The view asks
  before calling `resume` while it's true.
- **`newConversation() async`** quits any running session, then calls
  `start()`, which uses your Settings.
- **A refused resume** reuses EN.1's handling: the engine's reason, and an
  ended phase. When the reason mentions the model, a notice adds: "Its
  files can still be recovered by starting a new conversation from it in
  Terminal: `ds4-dogfood tui --resume <id> --new-conversation`". The
  automatic retry is out of scope (§7).

## 5. Views

- **`MainView`:** `NavigationSplitView { ConversationList() } detail: { SessionView() }`,
  with the `.inspector` as before. The sidebar's visibility uses the
  standard toggle, and is saved under
  `DefaultsKey.sidebarVisible = "sidebarVisible"`.
- **`ConversationList`** (`Sources/SwiftStarUI/Sidebar/`):
  - **The list:** `List(selection:)` over `controller.conversations`.
  - **Each row:** the title, one line, truncated, and the subtitle in
    secondary text.
  - **A row that can't be resumed:** dimmed, with `.help` showing its
    problems, or "This conversation can't be resumed".
  - **The selection:** follows `currentConversationID`. Choosing another
    row runs `resume`, with a confirmation alert first when
    `resumeNeedsConfirmation`.
  - **"New Conversation":** a button in the sidebar's toolbar, ⌘N.
  - **An empty list:** "No conversations yet in `<project>`", or nothing
    at all with no workspace.
- **The previews:** a populated list, an empty list, a dimmed row, and
  `MainView` with the sidebar. They use fixture conversations, and spawn
  nothing.

## 6. Tests and fixtures

**A new fixture,** `fixtures/engine/sessions.json`:
- **Source:** a real `sessions --json` capture from 2026-10-13, with the
  user paths redacted to `/Users/example`.
- **Contents:** at least one chain of two or more sessions and one session
  that stands alone.
- **Provenance:** recorded in `provenance.md`.

**The fake engine** gets a `sessions` mode, which prints
`FAKE_ENGINE_SESSIONS` or exits 2 as an older engine would. Its existing
`--resume` handling replays `resumed.ndjson`.

**Fast tier:**
- **Decoding:** the fixture's entries; unknown keys; `resumed_from` null;
  bad JSON → `.malformed`.
- **Grouping, a table:** one alone; a chain of three (one row, the root's
  title); a chain whose root isn't listed (titled from the oldest listed);
  a branch (two rows); a missing `first_prompt` ("Untitled"); newest first.
- **`subtitle`:** a fixed `now`, en_US, with and without a model.
- **`resumeArguments`:** exact, with no `--commit` and no model flags.
- **`directoryID(fromCapturePath:)`:** a capture path and its id; nil for
  garbage.

**Integration tier:**
- `sessionListLoaderReadsTheFake`: reads the fake's list, and an older
  engine gives `commandMissing`.
- `resumeSpawnsResumeArgv`: running, then `resume(c)` → the second spawn's
  argv is `["tui", "--ndjson", "--resume", c.id, "--source", <root>]`, and
  the transcript opens with "Resumed session …".
- `resumeAsksMidTurn`: mid-turn, `resumeNeedsConfirmation` is true.
- `refusedResumeEndsCleanly`: a fake refusing `--resume` → an ended phase
  with the engine's reason. (Its sibling for the relaunch path already
  exists.)
- `conversationsReloadAfterExit`: after a session exits, the list is
  reloaded.

Each test is shown to fail first.

## 7. Out of scope

- 7b: the project switcher, the quick switcher, Open Recent and the busy
  dot.
- Recovering a refused conversation automatically with
  `--new-conversation`.
- Narration in rebuilt turns, which waits on the engine (ROADMAP, Engine
  requests).
- More than one window (7c).
- Deleting or renaming conversations. The engine has no command for either.
