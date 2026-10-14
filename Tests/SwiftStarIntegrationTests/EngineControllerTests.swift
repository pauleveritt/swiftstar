import Foundation
import Testing
@testable import SwiftStarUI
import SwiftStarEngine
import SwiftStarKit

/// Drives `EngineController` directly. Mutates `UserDefaults.standard` (the
/// real, persistent domain; there is no isolated suite here), so the suite is
/// serialized and every touched key is saved, reset to a known value before
/// use, and restored afterward.
@MainActor
@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))
struct EngineControllerTests {
    /// A standalone `models --json` fake that needs no environment variables:
    /// `EngineController.loadCatalog()` calls the loader with `environment:
    /// nil`, and `Process.environment = nil` was found (empirically, while
    /// writing this test) to snapshot the environment before the test's own
    /// `setenv()` calls run, not at spawn time — so env-var-driven fakes (as
    /// used in `EngineModelCatalogLoaderTests`, which pass an explicit
    /// environment) don't work here. The call-log path is baked into the
    /// script text instead of read from the environment.
    private func writeFakeEngine(to scriptPath: String, callLogPath: String) throws {
        let script = """
        #!/usr/bin/env python3
        import sys
        if sys.argv[1:2] == ["models"]:
            with open(\(String(reflecting: callLogPath)), "a") as f:
                f.write("x\\n")
            sys.stdout.write('{"models":[{"id":"m","context":100}]}')
            sys.exit(0)
        sys.exit(1)
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    }

    private func callCount(_ logPath: String) -> Int {
        ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "")
            .split(separator: "\n").count
    }

    @Test func catalogRefetchesWhenEngineUpgradedInPlace() async throws {
        let script = tempPath("engine"), callLogPath = tempPath("calls")
        defer { for p in [script, callLogPath] { try? FileManager.default.removeItem(atPath: p) } }
        try writeFakeEngine(to: script, callLogPath: callLogPath)
        let defaults = DefaultsScope([.executable: script])
        defer { defaults.restore() }
        let controller = EngineController()

        await controller.loadCatalogIfNeeded()
        #expect(controller.catalog != nil)
        #expect(callCount(callLogPath) == 1)

        // Same path, unchanged content: a second call is a cache hit, no retry.
        await controller.loadCatalogIfNeeded()
        #expect(callCount(callLogPath) == 1)

        // "Upgrade" the engine in place: rewrite the script, bumping its mtime.
        try writeFakeEngine(to: script, callLogPath: callLogPath)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: script)

        await controller.loadCatalogIfNeeded()
        #expect(callCount(callLogPath) == 2)
    }

    /// A standalone `tui --ndjson` fake, again with no environment
    /// dependency: emits `ready` at once (which alone is enough to reach
    /// `EngineSessionPhase.running` — `restartIfRunning()` does not
    /// distinguish idle from mid-generation, so reaching `.running` already
    /// exercises the shared guard a menu pick restarts through), logs its
    /// `tui` argv, and exits cleanly the moment it sees `quit` on stdin so
    /// the restart does not wait out any grace period. `select(modelID:)`
    /// writing to UserDefaults also triggers `EngineController`'s own
    /// defaults-change observer, which probes `models --json` on this same
    /// executable path — that invocation is deliberately not logged, so the
    /// log only ever reflects real session spawns.
    /// `models` is what `models --json` prints; nil exits 2 as an engine
    /// without the command does, so a start never waits out the loader's
    /// timeout.
    private func writeSessionFake(
        to scriptPath: String, argvLogPath: String, models: String? = nil, modelsDelay: Double = 0
    ) throws {
        let modelsBranch = models.map {
            "time.sleep(\(modelsDelay)); sys.stdout.write(\(String(reflecting: $0))); sys.exit(0)" }
            ?? "sys.exit(2)"
        let script = """
        #!/usr/bin/env python3
        import json, sys, time
        if sys.argv[1:2] == ["models"]:
            \(modelsBranch)
        with open(\(String(reflecting: argvLogPath)), "a") as f:
            f.write(json.dumps(sys.argv[1:]) + "\\n")
        print(json.dumps({"kind": "ready", "protocol": 1}), flush=True)
        for line in sys.stdin:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("kind") == "quit":
                print(json.dumps({"kind": "quitting"}), flush=True)
                print(json.dumps({"kind": "close"}), flush=True)
                sys.exit(0)
        sys.exit(0)
        """
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)
    }

    @Test func staleModelClearedBeforeSpawn() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log,
                             models: try String(contentsOfFile: Fixtures.path("models-real.json"), encoding: .utf8))
        let defaults = DefaultsScope([.executable: script, .modelID: "laguna-xs-2.1"])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.start()
        await eventually { controller.phase == .running }
        #expect(argvLog(log).first?.contains("--model-id") == false)
        #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "")
        #expect(controller.transcript.rows.contains(
            .system("laguna-xs-2.1 isn't offered by the engine; using the engine default")))
        await controller.quit()
    }

    /// Found live (EN.1 Task 7): at launch a defaults change makes the
    /// observer start a model-list load first; start() must wait for that
    /// load, not see its cache key and start with no list.
    @Test func staleModelClearedWhenCatalogLoadInFlight() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log,
                             models: try String(contentsOfFile: Fixtures.path("models-real.json"), encoding: .utf8), modelsDelay: 0.5)
        let defaults = DefaultsScope([.executable: script, .modelID: "laguna-xs-2.1"])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        let inFlight = Task { await controller.loadCatalog() }
        try? await Task.sleep(for: .milliseconds(50))
        await controller.start()
        await eventually { controller.phase == .running }
        #expect(argvLog(log).first?.contains("--model-id") == false)
        await inFlight.value
        await controller.quit()
    }

    @Test func startProceedsWhenCatalogFails() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log)
        let defaults = DefaultsScope([.executable: script, .modelID: "laguna-xs-2.1"])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.start()
        await eventually { controller.phase == .running }
        let argv = argvLog(log).first ?? []
        #expect(argv.firstIndex(of: "--model-id").map { argv[$0 + 1] } == "laguna-xs-2.1")
        await controller.quit()
    }

    /// Deferred from 5a2: "Starting…" shows while the model list loads, before
    /// any spawn.
    @Test func startShowsStartingWhileTheListLoads() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log,
                             models: try String(contentsOfFile: Fixtures.path("models-real.json"), encoding: .utf8),
                             modelsDelay: 0.5)
        let defaults = DefaultsScope([.executable: script, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        let starting = Task { await controller.start() }
        #expect(await eventually(within: .milliseconds(300)) { controller.composer.label == "Starting…" })
        #expect(argvLog(log).isEmpty)
        await starting.value
        #expect(await eventually { controller.phase == .running })
        await controller.quit()
    }

    // MARK: SU.6c, D1: no usable workspace

    /// A temporary folder with a `.git` directory: a usable workspace.
    private func tempRepo() throws -> String {
        let path = tempPath("repo")
        try FileManager.default.createDirectory(atPath: path + "/.git", withIntermediateDirectories: true)
        return path
    }

    @Test func missingWorkspaceFallsBackToRecent() throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let gone = tempPath("gone")
        let defaults = DefaultsScope([.workspace: gone, .recentWorkspaces: [gone, repo]])
        defer { defaults.restore() }
        let controller = EngineController()
        #expect(controller.workspace?.path == repo)
        #expect(UserDefaults.standard.string(forKey: DefaultsKey.workspace.rawValue) == repo)
    }

    @Test func noWorkspaceDoesNotSpawn() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: tempPath("gone"),
                                      .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        #expect(controller.workspace == nil)
        await controller.start()
        #expect(f.spawnArgv.isEmpty)
        #expect(controller.wantsFolder)
        #expect(controller.phase == .idle)
        let asked = controller.transcript.rows.contains { row in
            if case .system(let s) = row { s.hasSuffix("Choose a folder in a git repository to start.") } else { false }
        }
        #expect(asked)
    }

    // MARK: SU.6c, D2: the last session's apply command

    @Test func lastSessionDirectoryOutlivesTheController() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .lastSessionDirectory: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        await controller.quit()
        // The fake's exit names /tmp/fake-session ("Session artifacts:").
        let next = EngineController()
        #expect(next.lastSessionDirectory?.path == "/tmp/fake-session")
        #expect(next.applyCommand == nil)  // that folder doesn't exist here
    }

    /// Final review: applying during a session changes the checkout under
    /// it (TUI.21 non-goal), so the menu item waits for the session to end.
    @Test func copyApplyCommandWaitsForTheSessionToEnd() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let dir = tempPath("sessions") + "/20261013-000000-y"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .lastSessionDirectory: dir])
        defer { defaults.restore() }
        let controller = await running(f)
        #expect(!controller.canCopyApplyCommand)
        await controller.quit()
        #expect(controller.canCopyApplyCommand == (controller.applyCommand != nil))
    }

    @Test func applyCommandNeedsAnExistingDirectory() throws {
        let dir = tempPath("sessions") + "/20261013-000000-x"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let defaults = DefaultsScope([.lastSessionDirectory: dir])
        defer { defaults.restore() }
        let controller = EngineController()
        #expect(controller.applyCommand == "ds4-dogfood apply 20261013-000000-x")
        try FileManager.default.removeItem(atPath: dir)
        #expect(controller.applyCommand == nil)
    }

    // MARK: SU.7a: conversations and resume

    private static let fixtureConversations: [Conversation] = {
        let data = (try? Data(contentsOf: Fixtures.root.appendingPathComponent("sessions.json"))) ?? Data()
        return Conversations.group((try? EngineSessionEntry.decodeList(data).get()) ?? [])
    }()

    /// The newest resumable conversation in the fixture.
    private var resumable: Conversation { Self.fixtureConversations.first { $0.resumable }! }

    @Test func conversationsLoadForTheWorkspace() async throws {
        let f = try FakeEngine(sessions: "sessions.json")
        defer { f.remove() }
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: repo])
        defer { defaults.restore() }
        let controller = EngineController()
        await controller.reloadConversations()
        #expect(controller.conversations.map(\.id) == Self.fixtureConversations.map(\.id))
    }

    @Test func resumeSpawnsResumeArgv() async throws {
        let f = try FakeEngine(sessions: "sessions.json")
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let c = resumable
        await controller.resume(c)
        let spawned = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(spawned)
        let root = FileManager.default.temporaryDirectory
        #expect(f.spawnArgv.last == EngineCommand.resumeArguments(id: c.id, source: root))
        #expect(controller.transcript.rows.first == .divider("Resumed session \(c.id)"))
        await controller.quit()
    }

    @Test func resumeAsksMidTurn() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        #expect(!controller.resumeNeedsConfirmation)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        #expect(controller.resumeNeedsConfirmation)
        await controller.quit()
    }

    @Test func resumingTheCurrentConversationDoesNothing() async throws {
        let f = try FakeEngine(sessions: "sessions.json")
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        await controller.reloadConversations()
        let c = resumable
        await controller.resume(c)
        let resumed = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(resumed)
        #expect(controller.currentConversationID == c.id)
        await controller.resume(c)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(f.spawnArgv.count == 2)
        await controller.quit()
    }

    /// Final review: after Quit nothing is current, so the conversation just
    /// ended can be resumed again.
    @Test func endedConversationCanBeResumedAgain() async throws {
        let f = try FakeEngine(sessions: "sessions.json")
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        await controller.reloadConversations()
        let c = resumable
        await controller.resume(c)
        let resumed = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(resumed)
        await controller.quit()
        #expect(controller.currentConversationID == nil)
        await controller.resume(c)
        let again = await eventually(within: .seconds(10)) { f.spawnArgv.count == 3 }
        #expect(again)
        await controller.quit()
    }

    @Test func resumeIgnoredWhileStarting() async throws {
        let f = try FakeEngine(extra: ["FAKE_ENGINE_MODELS_SLEEP_MS": "500"])
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        let starting = Task { await controller.start() }
        let isStarting = await eventually { controller.phase == .starting }
        #expect(isStarting)
        await controller.resume(resumable)
        await starting.value
        let up = await eventually { controller.phase == .running }
        #expect(up)
        #expect(f.spawnArgv.count == 1)
        #expect(f.spawnArgv.first?.contains("--resume") == false)
        await controller.quit()
    }

    @Test func staleListIsDropped() async throws {
        let f = try FakeEngine(sessions: "sessions.json", extra: ["FAKE_ENGINE_SESSIONS_SLEEP_MS": "500"])
        defer { f.remove() }
        let a = try tempRepo(), b = try tempRepo()
        defer { for p in [a, b] { try? FileManager.default.removeItem(atPath: p) } }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: a])
        defer { defaults.restore() }
        let controller = EngineController()
        let loading = Task { await controller.reloadConversations() }
        try? await Task.sleep(for: .milliseconds(150))
        controller.workspace = URL(fileURLWithPath: b)
        await loading.value
        #expect(controller.conversations.isEmpty)
    }

    @Test func sessionListUnavailableIsANote() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.reloadConversations()
        #expect(controller.conversations.isEmpty)
        await controller.start()
        let up = await eventually { controller.phase == .running }
        #expect(up)
        let notes = controller.transcript.rows.filter { row in
            if case .system(let s) = row { s.hasPrefix("Session list unavailable") } else { false }
        }
        #expect(notes.count == 1)
        await controller.quit()
    }

    @Test func conversationsReloadAfterExit() async throws {
        let f = try FakeEngine(sessions: "sessions.json")
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        #expect(controller.conversations.isEmpty)
        await controller.quit()
        let reloaded = await eventually { !controller.conversations.isEmpty }
        #expect(reloaded)
    }

    @Test func refusedResumeShowsTheHint() async throws {
        let f = try FakeEngine(sessions: "sessions.json", refuseResume: true)
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let c = resumable
        await controller.resume(c)
        let ended = await eventually(within: .seconds(10)) {
            if case .ended = controller.phase { true } else { false } }
        #expect(ended)
        let hint = "Its files can still be recovered by starting a new conversation from it in Terminal: "
            + "`ds4-dogfood tui --resume \(c.id) --new-conversation`"
        #expect(controller.transcript.rows.last == .system(hint))
    }

    // MARK: SU.7b: recent projects

    /// `sessions-all.json` with beta's source moved to `repo`, written to a
    /// temporary file for `FAKE_ENGINE_SESSIONS`.
    private func allSessionsFile(betaAt repo: String) throws -> String {
        let text = try String(contentsOf: Fixtures.root.appendingPathComponent("sessions-all.json"), encoding: .utf8)
        let path = tempPath("sessions-all") + ".json"
        try text.replacingOccurrences(of: "/Users/example/projects/beta", with: repo)
            .write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    @Test func recentProjectsFillFromAllSessions() async throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let sessions = try allSessionsFile(betaAt: repo)
        defer { try? FileManager.default.removeItem(atPath: sessions) }
        let f = try FakeEngine(extra: ["FAKE_ENGINE_SESSIONS": sessions])
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: [repo]])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.reloadRecentProjects()
        let row = controller.recentProjects.first { $0.path == repo }
        #expect(row?.latest?.id == "20261013-110000-beta")
    }

    @Test func recentProjectsFailQuietly() async throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: [repo]])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.reloadRecentProjects()
        #expect(controller.recentProjects.map(\.path) == [repo])
        #expect(controller.recentProjects.allSatisfy { $0.latestLabel == nil })
        #expect(controller.transcript.rows.isEmpty)
    }

    @Test func clearRecentsEmptiesTheList() throws {
        let repo = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let defaults = DefaultsScope([.workspace: repo, .recentWorkspaces: [repo, "/elsewhere"]])
        defer { defaults.restore() }
        let controller = EngineController()
        #expect(controller.hasRecents)
        controller.clearRecents()
        #expect(!controller.hasRecents)
        #expect(controller.recentWorkspaces.isEmpty)
        #expect(UserDefaults.standard.object(forKey: DefaultsKey.recentWorkspaces.rawValue) == nil)
        #expect(controller.workspace?.path == repo)
    }

    // MARK: SU.7b: one switch path

    private func sourceArg(_ argv: [String]?) -> String? {
        guard let argv, let i = argv.firstIndex(of: "--source"), i + 1 < argv.count else { return nil }
        return argv[i + 1]
    }

    /// A hand-built conversation in the project being switched to.
    private static let betaConversation = Conversation(
        id: "20261013-110000-beta", title: "Add a menu", updated: nil, modelID: nil, resumable: true,
        problems: [], sessionIDs: ["20261013-110000-beta", "20261013-100000-beta"])

    @Test func switchWhenIdleDoesNotAsk() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let bURL = URL(fileURLWithPath: b)
        controller.requestSwitch(to: bURL)
        #expect(controller.pendingSwitch == nil)
        let restarted = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(restarted)
        #expect(sourceArg(f.spawnArgv.last) == ProjectRoot.locate(anchor: bURL)?.path)
        await controller.quit()
    }

    @Test func switchMidTurnAsksFirst() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let before = controller.workspace
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        #expect(controller.pendingSwitch?.folder.path == b)
        #expect(controller.workspace == before)
        #expect(f.spawnArgv.count == 1)
        await controller.quit()
    }

    @Test func confirmedSwitchRestartsInTheNewRoot() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        let bURL = URL(fileURLWithPath: b)
        controller.requestSwitch(to: bURL)
        controller.confirmSwitch()
        #expect(controller.workspace?.path == b)
        #expect(controller.pendingSwitch == nil)
        let restarted = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(restarted)
        #expect(sourceArg(f.spawnArgv.last) == ProjectRoot.locate(anchor: bURL)?.path)
        await controller.quit()
    }

    @Test func cancelledSwitchChangesNothing() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let before = controller.workspace
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        controller.cancelSwitch()
        #expect(controller.pendingSwitch == nil)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(controller.workspace == before)
        #expect(f.spawnArgv.count == 1)
        await controller.quit()
    }

    @Test func confirmAfterTheTurnEndsStillSwitches() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        let idle = await eventually(within: .seconds(10)) { !controller.transcript.isBusy }
        #expect(idle)
        controller.confirmSwitch()
        #expect(controller.workspace?.path == b)
        await controller.quit()
    }

    @Test func switchAndResumeSpawnsOnce() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let bURL = URL(fileURLWithPath: b)
        let c = Self.betaConversation
        controller.requestSwitch(to: bURL, resuming: c)
        let resumed = await eventually(within: .seconds(10)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        #expect(resumed)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(f.spawnArgv.count == 2)
        let root = try #require(ProjectRoot.locate(anchor: bURL))
        #expect(f.spawnArgv.last == EngineCommand.resumeArguments(id: c.id, source: root))
        #expect(controller.workspace?.path == b)
        await controller.quit()
    }

    @Test func switchIgnoredWhileStarting() async throws {
        let f = try FakeEngine(extra: ["FAKE_ENGINE_MODELS_SLEEP_MS": "500"])
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        let before = controller.workspace
        let starting = Task { await controller.start() }
        let isStarting = await eventually { controller.phase == .starting }
        #expect(isStarting)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        #expect(controller.workspace == before)
        #expect(controller.pendingSwitch == nil)
        await starting.value
        await controller.quit()
    }

    @Test func switchToTheCurrentFolderDoesNothing() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        let here = try #require(controller.workspace)
        controller.requestSwitch(to: here)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(f.spawnArgv.count == 1)
        await controller.quit()
    }

    // SU.7b final review fixes

    @Test func confirmSwitchTakesThePresentedRequest() async throws {
        // The alert's binding may reset (cancelSwitch) before "Switch" runs.
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo()
        defer { try? FileManager.default.removeItem(atPath: b) }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        let request = try #require(controller.pendingSwitch)
        controller.cancelSwitch()
        controller.confirmSwitch(request)
        #expect(controller.workspace?.path == b)
        await controller.quit()
    }

    @Test func switchToTheCurrentFolderMidTurnDoesNotAsk() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        let here = try #require(controller.workspace)
        controller.requestSwitch(to: here)
        #expect(controller.pendingSwitch == nil)
        await controller.quit()
    }

    @Test func performingASwitchClearsAPendingOne() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let b = try tempRepo(), c = try tempRepo()
        defer { for p in [b, c] { try? FileManager.default.removeItem(atPath: p) } }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil, .workspace: nil, .recentWorkspaces: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        let busy = await eventually { controller.transcript.isBusy }
        #expect(busy)
        controller.requestSwitch(to: URL(fileURLWithPath: b))
        let idle = await eventually(within: .seconds(10)) { !controller.transcript.isBusy }
        #expect(idle)
        controller.requestSwitch(to: URL(fileURLWithPath: c))
        #expect(controller.workspace?.path == c)
        #expect(controller.pendingSwitch == nil)
        await controller.quit()
    }

    /// A started controller whose session is idle at its first `input`.
    private func running(_ f: FakeEngine, graces: EngineGraces = .standard) async -> EngineController {
        let controller = EngineController(graces: graces)
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.start()
        await eventually { controller.phase == .running && controller.composer.canSend && !controller.transcript.isBusy
            && controller.transcript.isAwaitingInput }
        return controller
    }

    @Test func rewindRelaunches() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("/rewind 1")
        await eventually(within: .seconds(15)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        let spawns = f.spawnArgv
        #expect(spawns.count == 2)
        let source = spawns.first.flatMap { a in a.firstIndex(of: "--source").map { a[$0 + 1] } } ?? "?"
        #expect(spawns.last == ["tui", "--resume", "/tmp/fake-ds4-session", "--source", source,
                                "--rewind-to", "1", "--ndjson"])
        #expect(controller.transcript.rows.first == .divider("Rewound to prompt 1"))
        await controller.quit()
    }

    @Test func modelMenuSendsModelCommand() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.select(modelID: "qwen3.8-flash-next")
        await eventually(within: .seconds(15)) {
            f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        let prompts = f.prompts
        #expect(prompts.contains("/model qwen3.8-flash-next"))
        #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "qwen3.8-flash-next")
        #expect(controller.transcript.rows.first
            == .divider("Switched to qwen3.8-flash-next: new conversation, files kept"))
        await controller.quit()
    }

    @Test func modelMenuIdleRestartsFresh() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        controller.select(modelID: "qwen3.8-flash-next")
        #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "qwen3.8-flash-next")
        await controller.start()
        await eventually { controller.phase == .running }
        let argv = f.spawnArgv.first ?? []
        #expect(argv.firstIndex(of: "--model-id").map { argv[$0 + 1] } == "qwen3.8-flash-next")
        #expect(argv.firstIndex(of: "--commit").map { argv[$0 + 1] } == "HEAD")
        await controller.quit()
    }

    @Test func relaunchRefusedEndsCleanly() async throws {
        let f = try FakeEngine(refuseResume: true)
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.send("Use the read tool on Package.swift")
        await eventually(within: .seconds(10)) {
            controller.transcript.isAwaitingInput
                && controller.transcript.rows.contains { if case .answer = $0 { true } else { false } }
        }
        controller.send("/rewind 1")
        await eventually(within: .seconds(15)) {
            if f.spawnArgv.count == 2, case .ended = controller.phase { return true }
            return false
        }
        guard case .ended(let exit) = controller.phase else {
            Issue.record("not ended: \(controller.phase)"); return
        }
        #expect(exit.message == "refused to start: ds4-dogfood tui: error: no model on this Mac")
        // The conversation and the old session's pointer stay on screen.
        #expect(controller.transcript.rows.contains { if case .answer = $0 { true } else { false } })
        #expect(controller.transcript.rows.contains {
            if case .system(let s) = $0 { s.hasPrefix("Session: ") } else { false } })
        #expect(controller.transcript.rows.last == .system(exit.message))
    }

    @Test func relaunchIgnoredWhileTerminating() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.beginTerminating()
        controller.send("/rewind 1")
        #expect(await eventually { f.prompts.contains("/rewind 1") })
        // Ignored outright: no quit, and no second spawn.
        let respawned = await eventually(within: .seconds(1)) { f.spawnArgv.count > 1 }
        #expect(!respawned)
        #expect(controller.phase == .running)
        await controller.quit()
    }

    /// Deferred from 5a1: a relaunch whose quit hit the safety bound must not
    /// start a second engine beside one that may still hold the GPU.
    @Test func relaunchSkippedWhenQuitHitTheBound() async throws {
        let f = try FakeEngine(extra: ["FAKE_ENGINE_IGNORE_QUIT": "1", "FAKE_ENGINE_IGNORE_SIGTERM": "1"])
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let graces = EngineGraces(
            stop: .milliseconds(100), term: .milliseconds(100), kill: .seconds(1), safetyBound: .milliseconds(400))
        let controller = await running(f, graces: graces)
        controller.send("/rewind 1")
        #expect(await eventually(within: .seconds(3)) {
            controller.transcript.rows.contains(.system("Relaunch skipped: the engine did not exit.")) })
        #expect(f.spawnArgv.count == 1)
    }

    // MARK: SU.5a1 Task 6

    /// Audit B4: when even the safety bound passes, the session is ended, so
    /// the app is not left at "Ending…" with Start disabled.
    @Test func quitBoundEndsTheSession() async throws {
        let f = try FakeEngine(extra: ["FAKE_ENGINE_IGNORE_QUIT": "1", "FAKE_ENGINE_IGNORE_SIGTERM": "1"])
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let graces = EngineGraces(
            stop: .milliseconds(100), term: .milliseconds(100), kill: .seconds(1), safetyBound: .milliseconds(500))
        let controller = await running(f, graces: graces)
        await controller.quit()
        await eventually(within: .seconds(2)) { if case .ended = controller.phase { true } else { false } }
        guard case .ended(let exit) = controller.phase else { Issue.record("phase \(controller.phase)"); return }
        #expect(exit.message == "the engine did not exit after quit; it may still be running")
        #expect(!controller.isActive)
        try? await Task.sleep(for: .seconds(1.5))  // past the old session's SIGKILL; nothing changes
        #expect(controller.transcript.rows.last == .system(exit.message))
    }

    @Test func fixtureStartStaysIdle() async {
        let controller = EngineController.previewIdle
        await controller.start()
        #expect(controller.phase == .idle)
    }

    /// The observer reloads the model list when Settings names another
    /// engine, and not on the controller's (or anyone's) other writes.
    @Test func catalogReloadsOnlyForANewExecutable() async throws {
        let a = tempPath("engine-a"), aLog = tempPath("calls-a"), b = tempPath("engine-b"), bLog = tempPath("calls-b")
        defer { for p in [a, aLog, b, bLog] { try? FileManager.default.removeItem(atPath: p) } }
        try writeFakeEngine(to: a, callLogPath: aLog)
        try writeFakeEngine(to: b, callLogPath: bLog)
        let defaults = DefaultsScope([.executable: a, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        await controller.loadCatalogIfNeeded()
        controller.select(modelID: "x")
        controller.select(contextSize: 4096)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(callCount(aLog) == 1)
        UserDefaults.standard.set(b, forKey: DefaultsKey.executable.rawValue)
        await eventually { callCount(bLog) == 1 }
        #expect(callCount(bLog) == 1)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.contextSize.rawValue)
    }

    @Test func secondModelPickWhilePendingIsRefused() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await running(f)
        controller.select(modelID: "qwen3.8-flash-next")
        controller.select(modelID: "qwen3.8-27b")
        #expect(controller.transcript.rows.contains(.system("A model switch is already pending.")))
        await eventually(within: .seconds(15)) { f.spawnArgv.count == 2 && controller.transcript.isAwaitingInput }
        let prompts = f.prompts
        #expect(prompts.filter { $0.hasPrefix("/model") } == ["/model qwen3.8-flash-next"])
        await controller.quit()
    }

    // MARK: 5a1 final review

    /// The first start loads the catalog; when that fails, the note must
    /// survive into the session's transcript.
    @Test func catalogNoteShownOnFirstStart() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log)
        let defaults = DefaultsScope([.executable: script, .modelID: nil])
        defer { defaults.restore() }
        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.start()
        await eventually { controller.phase == .running }
        #expect(controller.transcript.rows.contains {
            if case .system(let s) = $0 { s.hasPrefix("Model list unavailable") } else { false } })
        await controller.quit()
    }

    /// After the safety bound, a restart (menu pick) must not start a second
    /// engine beside one that may still hold the GPU; a deliberate Start does.
    @Test func restartAfterQuitBoundIsSkippedButStartWorks() async throws {
        let f = try FakeEngine(extra: ["FAKE_ENGINE_IGNORE_QUIT": "1", "FAKE_ENGINE_IGNORE_SIGTERM": "1"])
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let graces = EngineGraces(
            stop: .milliseconds(100), term: .milliseconds(100), kill: .seconds(1), safetyBound: .milliseconds(500))
        let controller = await running(f, graces: graces)
        await controller.quit()
        await controller.restart()
        #expect(f.spawnArgv.count == 1)
        #expect(controller.transcript.rows.contains {
            if case .system(let s) = $0 { s.hasPrefix("Restart skipped") } else { false } })
        try? await Task.sleep(for: .seconds(1.5))  // past the old engine's SIGKILL
        await controller.start()
        await eventually { controller.phase == .running && controller.transcript.isAwaitingInput }
        #expect(f.spawnArgv.count == 2)
        controller.select(modelID: "qwen3.8-flash-next")
        #expect(!controller.transcript.rows.contains(.system("A model switch is already pending.")))
        await controller.quit()  // this fake ignores quit and SIGTERM; f.remove() ends it
    }

    // MARK: AN.2, analyze and done

    /// Running, one prompt answered, so a checkpoint has named the directory.
    private func answered(_ f: FakeEngine) async -> EngineController {
        let controller = await running(f)
        controller.send("Read a file")
        await eventually(within: .seconds(10)) {
            controller.transcript.isAwaitingInput && !controller.transcript.isBusy && controller.model.canAnalyze }
        return controller
    }

    @Test func analyzeForksThenSendsPrompt() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await answered(f)
        #expect(controller.model.canAnalyze)
        controller.reportLoader = { _ in .success("R-REPORT") }
        await controller.analyze()
        await eventually(within: .seconds(15)) { f.prompts.contains { $0.contains("R-REPORT") } }
        #expect(f.spawnArgv.count == 2)
        #expect(f.spawnArgv.last?.contains("--resume") == true)
        #expect(controller.transcript.rows.contains(.report("R-REPORT")))
        #expect(f.prompts.contains { $0.contains("R-REPORT") })
        await controller.quit()
    }

    @Test func analyzeFailureDoesNotFork() async throws {
        let f = try FakeEngine()
        defer { f.remove() }
        let defaults = DefaultsScope([.executable: f.script, .modelID: nil])
        defer { defaults.restore() }
        let controller = await answered(f)
        controller.reportLoader = { _ in .failure(SessionReportFailure(message: "boom")) }
        await controller.analyze()
        #expect(f.spawnArgv.count == 1)
        #expect(controller.transcript.rows.contains {
            if case .error(let s) = $0 { s.contains("boom") } else { false } })
        #expect(controller.model.analysis == nil)
        #expect(controller.composer.canSend)
        await controller.quit()
    }
}
