# SU.7a: Conversations and Resume Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A sidebar that lists the current project's conversations, newest
first. Clicking one resumes it.

**Architecture:**
- **Kit** decodes `ds4-dogfood sessions --json` and groups its entries into
  conversations along `resumed_from` chains. That part is pure and tested.
- **The Engine target** gains `SessionListLoader`, which shares one
  process-running core with the model-list loader.
- **The controller** owns the list, the current conversation, `resume` and
  `newConversation`. Resume reuses the relaunch path from EN.1.
- **`MainView`** becomes a `NavigationSplitView`.

Plans here list files, interfaces and tests, not bodies (`docs/sdd.md`).

**Tech Stack:** Swift 6.4, SwiftUI on macOS 26, Swift Testing, and the
Python fake engine.

**Spec:** [`docs/superpowers/specs/2026-10-13-su7a-sessions-and-resume-design.md`](../specs/2026-10-13-su7a-sessions-and-resume-design.md)

## Global Constraints

- **Builds:**
  - Warnings are errors on our own targets.
  - There are no new package dependencies.
- **Tiers:**
  - The fast tier spawns nothing.
  - Integration test bodies stay at function level, using `DefaultsScope`
    plus `defer` (the Swift 6.4 closure-identity rule in `Support.swift`).
- **Tests:**
  - Every new test is shown to fail first.
  - Break one implementation line per table, then restore it from a backup
    copy, never with `git checkout` on uncommitted work.
- **UI:** every `#Preview` in a touched file under `Sources/SwiftStarUI/`
  is rendered with `RenderPreview` and looked at.
- **Previews never spawn:** fixture controllers come from
  `EngineController(model:)`.
- **Resume arguments, verbatim from the spec:**
  `["tui", "--ndjson", "--resume", id, "--source", root]`. No `--commit`,
  and no model or context flags.
- **Copy:**
  - "New Conversation" (⌘N)
  - "No conversations yet in `<project>`"
  - "This conversation can't be resumed"
  - the refused-resume hint: "Its files can still be recovered by starting
    a new conversation from it in Terminal: `ds4-dogfood tui --resume <id> --new-conversation`"
- **Parallel runs:** integration runs must not overlap with another
  worktree's (ROADMAP, Process). Check `ps` for `swiftpm-testing-helper`
  before trusting a failure.

## Review Focus

1. **A list that arrives late, after the workspace has changed.** The
   previous project's list must not appear. Pinned in Task 3
   (`staleListIsDropped`).
2. **Clicking the conversation that's already running.** Nothing should
   restart. Pinned in Task 3
   (`resumingTheCurrentConversationDoesNothing`).
3. **An engine without `sessions --json`, or a failing one.** The app
   still starts, the list stays empty, and one note says why. Pinned in
   Tasks 2 and 3.
4. **A bad or missing `updated` timestamp.** The entry still decodes and
   sorts last. Pinned in Task 1.
5. **A click while a session is starting or quitting.** It's ignored, like
   the menus' `canChoose`. Pinned in Task 3
   (`resumeIgnoredWhileStarting`).

---

### Task 1: Kit — entries, conversations, arguments and the fixture

**Files:**
- Create: `Sources/SwiftStarKit/EngineSessionList.swift`, holding
  `EngineSessionEntry`, `Conversation` and `Conversations`
- Modify: `Sources/SwiftStarKit/EngineCommand.swift`, adding
  `resumeArguments`
- Modify: `Sources/SwiftStarKit/EngineEvent.swift:151-163`, where
  `PauseMetrics` gains `capturePath: String? = nil`
- Modify: `Sources/SwiftStarKit/EngineWireParser.swift`, where the
  checkpoint case reads `snapshot.capture_path`
- Create: `fixtures/engine/sessions.json`
- Modify: `fixtures/engine/provenance.md`, adding its row
- Test: `Tests/SwiftStarKitTests/EngineSessionListTests.swift` (new)
- Test: `EngineCommandTests`
- Test: `EngineWireParserTests`

**Interfaces (produced):**
- `public struct EngineSessionEntry: Decodable, Equatable, Sendable`.
  - **Fields:** `id: String`, `path: String`, `source: String?`,
    `modelID: String?`, `updated: Date?`, `prompts: Int?`,
    `firstPrompt: String?`, `lastPrompt: String?`, `resumedFrom: String?`,
    `resumable: Bool?`, `problems: [String]?`.
  - **Keys:** snake_case on the wire.
  - **`updated`:** parsed as a local `yyyy-MM-dd'T'HH:mm:ss`. Anything that
    doesn't parse becomes nil.
- `public static func decodeList(_ data: Data) -> Result<[EngineSessionEntry], CatalogError>`.
  Garbage gives `.malformed(…)`.
- `public static func directoryID(fromCapturePath: String) -> String?`: the
  parent directory's name, or nil for a path without one.
- `public struct Conversation: Identifiable, Equatable, Sendable`, with
  `id`, `title`, `updated: Date?`, `modelID`, `resumable: Bool`,
  `problems: [String]` and `sessionIDs: [String]`.
- **`public enum Conversations`:**
  - `static func group(_ entries: [EngineSessionEntry]) -> [Conversation]`
    follows the rules in spec §2. Entries with no `updated` sort last.
  - `static func subtitle(_ c: Conversation, now: Date, locale: Locale) -> String`.
- `EngineCommand.resumeArguments(id: String, source: URL) -> [String]`.

- [ ] **Step 1: Capture the fixture.**
  - Run `ds4-dogfood sessions --json --source . --limit 12`, then replace
    `/Users/pauleveritt` with `/Users/example` throughout.
  - Check that it holds a chain of two or more sessions, and one session
    that stands alone.
  - Add a provenance row: date, command, engine `5451cd7d`, and "paths
    redacted".
- [ ] **Step 2: Write the failing tests.**
  - `decodesTheCapture`:
    - the fixture decodes
    - the count matches the file
    - the first entry's `id` matches `^\d{8}-\d{6}-`
  - `decodeEdges`, a table:
    - unknown keys are ignored
    - `resumed_from: null` gives nil
    - `"updated":"garbage"` gives `updated == nil`
    - `"nope"` gives `.malformed`
  - `group`, a table of hand-built entries:
    - `alone`: one entry gives one row titled by its `first_prompt`
    - `chainOfThree`: c resumed from b, b resumed from a, gives one row
      with `id == c` and the title from a
    - `rootNotListed`: titled from the oldest listed entry
    - `branch`: b and c both resumed from a give two rows
    - `untitled`: no `first_prompt` anywhere gives "Untitled"
    - `newestFirst`: the order follows `updated`, with nil last
    - `cycle`: the walk stops
  - `groupsTheCapture`: the fixture gives fewer rows than entries, and
    each row's `sessionIDs` holds its chain.
  - `subtitle`, a table using a fixed `now` and en_US:
    - "12 min ago · qwen3.8-27b"
    - without a model, "12 min ago"
    - with `updated` nil, "qwen3.8-27b"
  - `resumeArguments` (in `EngineCommandTests`): an exact array, with no
    `--commit`.
  - `directoryID`: a `…/sessions/20261013-112927-swiftstar/run-7-1.partial.json`
    path gives `20261013-112927-swiftstar`, and `"x"` gives nil.
  - `toolReadFixtureDecodes` (extended): the first pause's `capturePath`
    contains `/sessions/`.
- [ ] **Step 3: Run them and see them fail.** Run
  `swift test --filter "EngineSessionListTests|EngineCommandTests|EngineWireParserTests"`.
  Expected: a compile failure, because the types are missing.
- [ ] **Step 4: Implement, and see them pass.**
  - Break check 1: make `group` return every entry. `chainOfThree` should
    fail.
  - Break check 2: take the title from the head instead.
    `chainOfThree` should fail.
  - Restore each from a copy.
- [ ] **Step 5: Run `just test` and commit** with the message
  `SU.7a Task 1: decode sessions --json and group conversations`.

### Task 2: Engine — a shared command runner and the session list loader

**Files:**
- Create: `Sources/SwiftStarEngine/EngineJSONCommand.swift`. The process,
  pipe, timeout and stderr-tail core moves here from
  `EngineModelCatalogLoader.swift:12-106`.
- Modify: `Sources/SwiftStarEngine/EngineModelCatalogLoader.swift`, so
  `load` calls the shared core and then `EngineModelList.decode`.
- Create: `Sources/SwiftStarEngine/SessionListLoader.swift`
- Modify: `fixtures/engine/fake-ds4-dogfood`, adding a `sessions` mode.
  - It prints `FAKE_ENGINE_SESSIONS`, after a delay of
    `FAKE_ENGINE_SESSIONS_SLEEP_MS` (default 0).
  - When `FAKE_ENGINE_SESSIONS` is unset, it exits 2 with the argparse
    "invalid choice" text.
  - Its docstring changes to match.
- Modify: `Tests/SwiftStarIntegrationTests/Support.swift`, where
  `FakeEngine.init` gains `sessions: String? = nil`. That's the fixture
  name, exported as `FAKE_ENGINE_SESSIONS` when it's set.
- Test: `Tests/SwiftStarIntegrationTests/EngineModelCatalogLoaderTests.swift`,
  which grows a `SessionListLoader` section

**Interfaces (produced):**
- `enum EngineJSONCommand { static func run(executable: String, arguments: [String], timeout: Duration, environment: [String: String]?) async -> Result<Data, CatalogError> }`.
  The behaviour moves over unchanged: launch failure, timeout with
  SIGTERM then SIGKILL, `commandMissing` on exit 2 with "invalid choice",
  and the exit code with the last stderr line.
- `public enum SessionListLoader { public static func load(executable: String, source: URL, limit: Int = 50, timeout: Duration = .seconds(10), environment: [String: String]? = nil) async -> Result<[EngineSessionEntry], CatalogError> }`.

- [ ] **Step 1: Write the failing tests.**
  - `sessionListLoaderReadsTheFake`: with `FAKE_ENGINE_SESSIONS` pointing at
    `sessions.json`, the result's count matches the fixture.
  - `sessionListLoaderPassesSourceAndLimit`: using the fake's
    `FAKE_ENGINE_ARGV_LOG`, the argv is exactly
    `sessions --json --source <root> --limit 50`.
  - `sessionListLoaderReportsMissingCommand`: an unset
    `FAKE_ENGINE_SESSIONS` gives `.failure(.commandMissing)`.
- [ ] **Step 2: Run them and see them fail.** Run
  `SWIFTSTAR_INTEGRATION=1 swift test --filter EngineModelCatalogLoaderTests`.
  Expected: a compile failure, because `SessionListLoader` is missing.
- [ ] **Step 3: Extract `EngineJSONCommand`, and add `SessionListLoader`
  and the fake's mode.** The existing loader tests, which cover timeouts
  (including the child's death), stderr beyond 4 KiB and the missing
  command, must stay green without change. They are the extraction's
  proof.
- [ ] **Step 4: See them pass.** Break check: drop `--limit` from the
  argv, and `sessionListLoaderPassesSourceAndLimit` should fail. Restore.
- [ ] **Step 5: Run `just integration` and commit** with the message
  `SU.7a Task 2: a shared JSON-command runner and the session list loader`.

### Task 3: the controller — the list, the current conversation, resume

**Files:**
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`
- Modify: `Sources/SwiftStarKit/EngineSessionModel.swift`, so the model
  records the current session's directory id
- Test: `Tests/SwiftStarIntegrationTests/EngineControllerTests.swift`
- Test: `Tests/SwiftStarKitTests/EngineSessionModelTests.swift`

**Interfaces:**
- Consumes:
  - `SessionListLoader.load`
  - `Conversations.group`
  - `EngineCommand.resumeArguments`
  - `EngineSessionEntry.directoryID(fromCapturePath:)`
- **Produces, on `EngineSessionModel`:**
  - `public private(set) var currentSessionID: String?`, which is:
    - set from `resumed.session` (the session resumed from)
    - set from the first `.pause` whose `capturePath` gives an id
    - cleared by `didStart()`
- **Produces, on `EngineController`:**
  - `private(set) var conversations: [Conversation]`
  - `func reloadConversations() async`:
    - it uses the workspace's git root, through `ProjectRoot.locate`, else
      the folder itself
    - it drops a result whose root no longer matches the workspace
    - on failure it keeps the list and adds one note per path: "Session
      list unavailable: `<reason>`"
  - `var currentConversationID: String?`: the conversation whose
    `sessionIDs` contain `model.currentSessionID`
  - `var resumeNeedsConfirmation: Bool { transcript.isBusy }`
  - `func resume(_ c: Conversation) async`:
    - ignored when `!canChoose`, when `!c.resumable`, or when `c.id ==
      currentConversationID`
    - otherwise it quits and waits, then calls
      `start(relaunch: EngineRelaunch(kind: .resume, argv: …, reason: ""))`
  - `func newConversation() async`: quits, then `start()`
  - **When reloads run:** after `init` (from the view's `.task`), after
    every `handleExit`, and after `select(workspace:)`
  - **A refused resume:** when the refusal follows a `.resume` relaunch
    and the reason mentions "model", the model gets the refused-resume
    hint (Global Constraints) as a notice

- [ ] **Step 1: Write the failing tests.**
  - **Fast tier** (`EngineSessionModelTests`):
    - `currentSessionIDFromResumed`: a `.resumed` event with `session: "a"`
      gives `currentSessionID == "a"`.
    - `currentSessionIDFromFirstPause`: a pause whose capture path is under
      `sessions/b/` gives `"b"`, and `didStart()` clears it.
  - **Integration tier** (`EngineControllerTests`), each with
    `FakeEngine(sessions: "sessions.json")` and a temporary git repo:
    - `conversationsLoadForTheWorkspace`: after `reloadConversations()`,
      the count equals `Conversations.group` of the fixture.
    - `resumeSpawnsResumeArgv`: running, then `resume(c)` → the second
      spawn's argv equals `resumeArguments(id: c.id, source: root)`, and
      the first transcript row is a "Resumed session" divider.
    - `resumeAsksMidTurn`: after sending a prompt and before the answer,
      `resumeNeedsConfirmation` is true.
    - `resumingTheCurrentConversationDoesNothing`: once the conversation
      is current, `resume` leaves the spawn count unchanged.
    - `resumeIgnoredWhileStarting`: `resume` during `.starting` adds no
      spawn.
    - `staleListIsDropped`: start a reload with
      `FAKE_ENGINE_SESSIONS_SLEEP_MS` 500, switch the workspace before it
      finishes → the conversations aren't the first project's.
    - `refusedResumeShowsTheHint`: `FakeEngine(refuseResume: true)` →
      `resume(c)` ends the session with the engine's reason ("no model on
      this Mac"), followed by the refused-resume hint notice.
    - `sessionListUnavailableIsANote`: with no `sessions` mode, start
      still spawns, the conversations are empty, and one "Session list
      unavailable" note appears.
    - `conversationsReloadAfterExit`: after a quit, the fake's argv log
      shows a second `sessions` call.
- [ ] **Step 2: Run them and see them fail.** Expected: a compile failure
  on the missing members.
- [ ] **Step 3: Implement it.**
- [ ] **Step 4: See them pass.** Break checks:
  - drop the stale-root guard → `staleListIsDropped` fails
  - drop the current-conversation guard →
    `resumingTheCurrentConversationDoesNothing` fails
  - Restore each from a copy.
- [ ] **Step 5: Run `just test` and `just integration`, and commit** with
  the message `SU.7a Task 3: the controller lists conversations and resumes one`.

### Task 4: the sidebar, `MainView`, previews and close

**Files:**
- Create: `Sources/SwiftStarUI/Sidebar/ConversationList.swift`
- Modify: `Sources/SwiftStarUI/Shell/MainView.swift`, which becomes a
  `NavigationSplitView`
- Modify: `Sources/SwiftStarKit/DefaultsKey.swift`, adding
  `sidebarVisible = "sidebarVisible"`
- Modify: `Tests/SwiftStarKitTests/DefaultsKeyTests.swift`, pinning the new
  raw value
- Modify: `Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift`, adding
  `[Conversation].preview` (three rows, one of them not resumable)
- Modify: `Sources/SwiftStarUI/State/EngineController.swift`'s
  `init(model:)`, adding `conversations: [Conversation] = []`
- Modify: `ROADMAP.md`:
  - the SU.7 row reads "7a done", with links
  - Backlog: the Front-end "session picker" item closes, if one remains
- Modify: this plan, adding `## Result`

**Interfaces:**
- `struct ConversationList: View` reads `EngineController` from the
  environment.
  - **The list:** `List(selection:)` bound to a local selection, which
    starts at `currentConversationID`.
  - **Choosing a row:** when `resumeNeedsConfirmation`, an
    `.alert("End the running turn and resume?")` comes first. Then
    `Task { await controller.resume(c) }`.
  - **A row:** a `VStack` holding the title (`.lineLimit(1)`) and the
    `Conversations.subtitle` (`.secondary`, `.caption`). A row that isn't
    resumable is dimmed with `.foregroundStyle(.tertiary)`, and its `.help`
    gives its problems or the copy line.
  - **The toolbar:** a "New Conversation" button, ⌘N, that calls
    `newConversation()`.
  - **The empty state:** `ContentUnavailableView`, with "No conversations
    yet in `<leafName>`".
- **`MainView`:** `NavigationSplitView(columnVisibility:)` holds
  `ConversationList` and `SessionView`, plus the existing `.inspector`.
  The visibility is stored under `sidebarVisible`.

- [ ] **Step 1: Write the failing test.** Extend `rawValuesMatchToday`
  with `sidebarVisible`. It fails because the case is missing. The views
  themselves are checked by rendering, as in the earlier SU cycles.
- [ ] **Step 2: Build the views and the fixtures.** Previews:
  - `ConversationList`: "Conversations" (the three fixture rows, the
    second one current), "Empty" and "No workspace"
  - `MainView`: "Running", with the sidebar
- [ ] **Step 3: Render every preview in `ConversationList.swift` and
  `MainView.swift`, and look at each.** Check that:
  - the titles are truncated to one line
  - the subtitles read "… ago · model"
  - the row that can't be resumed is dimmed
  - the current row is selected
  - the sidebar sits left of the transcript, and the inspector stays
    available
- [ ] **Step 4: Close.**
  - Write `## Result`: commits, what diverged, the break checks, and the
    previews.
  - Update the ROADMAP SU.7 row and `## Now` (next is 7b), and add any
    Backlog changes.
  - Run `just lint-docs`.
  - Run `just test` and `just integration`; both must pass, and a full
    run must leave no orphaned fake (`ps -axo ppid,args | grep fake-ds4-dogfood | awk '$1==1'`
    prints nothing).
- [ ] **Step 5: Commit** with the message
  `SU.7a Task 4: the conversation sidebar; close 7a`.

## Result

*Written at close.*
