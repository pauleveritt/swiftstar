import Foundation
import Testing
@testable import SwiftStarUI
import SwiftStarKit

/// Drives `EngineController` directly. Mutates `UserDefaults.standard` (the
/// real, persistent domain; there is no isolated suite here), so the suite is
/// serialized and every touched key is saved, reset to a known value before
/// use, and restored afterward.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
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
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("p30-fake-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: tempPath) }
        let callLogPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("p30-calls-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: callLogPath) }
        try writeFakeEngine(to: tempPath, callLogPath: callLogPath)

        let defaults = UserDefaults.standard
        let savedExecutable = defaults.string(forKey: DefaultsKey.executable.rawValue)
        defaults.set(tempPath, forKey: DefaultsKey.executable.rawValue)
        defer {
            if let savedExecutable {
                defaults.set(savedExecutable, forKey: DefaultsKey.executable.rawValue)
            } else {
                defaults.removeObject(forKey: DefaultsKey.executable.rawValue)
            }
        }

        let controller = EngineController()

        await controller.loadCatalogIfNeeded()
        #expect(controller.catalog != nil)
        #expect(callCount(callLogPath) == 1)

        // Same path, unchanged content: a second call is a cache hit, no retry.
        await controller.loadCatalogIfNeeded()
        #expect(callCount(callLogPath) == 1)

        // "Upgrade" the engine in place: rewrite the script, bumping its mtime.
        try writeFakeEngine(to: tempPath, callLogPath: callLogPath)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: tempPath)

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

    private func argvLines(_ logPath: String) -> [[String]] {
        ((try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "")
            .split(separator: "\n")
            .compactMap { line -> [String]? in
                (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String]
            }
    }

    private func poll(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private static let realModels = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/engine/models-real.json")

    /// Runs `body` with the executable and model id defaults set, restoring both.
    private func withDefaults(executable: String, modelID: String?, _ body: () async -> Void) async {
        let defaults = UserDefaults.standard
        let saved = (defaults.string(forKey: DefaultsKey.executable.rawValue),
                     defaults.string(forKey: DefaultsKey.modelID.rawValue))
        defaults.set(executable, forKey: DefaultsKey.executable.rawValue)
        if let modelID { defaults.set(modelID, forKey: DefaultsKey.modelID.rawValue) }
        else { defaults.removeObject(forKey: DefaultsKey.modelID.rawValue) }
        defer {
            for (key, value) in [(DefaultsKey.executable, saved.0), (DefaultsKey.modelID, saved.1)] {
                if let value { defaults.set(value, forKey: key.rawValue) }
                else { defaults.removeObject(forKey: key.rawValue) }
            }
        }
        await body()
    }

    private func tempPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("en1-\(name)-\(UUID().uuidString)").path
    }

    @Test func staleModelClearedBeforeSpawn() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log,
                             models: try String(contentsOf: Self.realModels, encoding: .utf8))
        await withDefaults(executable: script, modelID: "laguna-xs-2.1") {
            let controller = EngineController()
            controller.workspace = FileManager.default.temporaryDirectory
            await controller.start()
            await poll { controller.phase == .running }
            #expect(argvLines(log).first?.contains("--model-id") == false)
            #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "")
            #expect(controller.transcript.rows.contains(
                .system("laguna-xs-2.1 is no longer offered; using the engine default")))
            await controller.quit()
        }
    }

    /// Found live (EN.1 Task 7): at launch a defaults change makes the
    /// observer start a model-list load first; start() must wait for that
    /// load, not see its cache key and start with no list.
    @Test func staleModelClearedWhenCatalogLoadInFlight() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log,
                             models: try String(contentsOf: Self.realModels, encoding: .utf8), modelsDelay: 0.5)
        await withDefaults(executable: script, modelID: "laguna-xs-2.1") {
            let controller = EngineController()
            controller.workspace = FileManager.default.temporaryDirectory
            let inFlight = Task { await controller.loadCatalog() }
            try? await Task.sleep(for: .milliseconds(50))
            await controller.start()
            await poll { controller.phase == .running }
            #expect(argvLines(log).first?.contains("--model-id") == false)
            await inFlight.value
            await controller.quit()
        }
    }

    @Test func startProceedsWhenCatalogFails() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log)
        await withDefaults(executable: script, modelID: "laguna-xs-2.1") {
            let controller = EngineController()
            controller.workspace = FileManager.default.temporaryDirectory
            await controller.start()
            await poll { controller.phase == .running }
            let argv = argvLines(log).first ?? []
            #expect(argv.firstIndex(of: "--model-id").map { argv[$0 + 1] } == "laguna-xs-2.1")
            await controller.quit()
        }
    }

    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/engine")

    /// `fake-ds4-dogfood` behind a wrapper that bakes in its environment (the
    /// controller spawns with the test process's environment, see the top of
    /// this file): replays tool-read, resumes from resumed.ndjson, logs each
    /// spawn's argv and each stdin line. `refuseResume` makes the relaunched
    /// start exit 2 before `ready`.
    private func writeFakeWrapper(
        to path: String, spawnLog: String, inputLog: String, refuseResume: Bool = false,
        extra: [String: String] = [:]
    ) throws {
        let f = Self.fixtures
        var refuse = refuseResume ? #"case "$*" in *--resume*) export FAKE_ENGINE_REFUSE=1;; esac"# : ""
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { refuse += "\nexport \(k)=\(v)" }
        let script = """
        #!/bin/sh
        export FAKE_ENGINE_FIXTURE=\(f.appendingPathComponent("tool-read.ndjson").path)
        export FAKE_ENGINE_RESUME_FIXTURE=\(f.appendingPathComponent("resumed.ndjson").path)
        export FAKE_ENGINE_MODELS=\(f.appendingPathComponent("models-real.json").path)
        export FAKE_ENGINE_SPAWN_LOG=\(spawnLog)
        export FAKE_ENGINE_LOG=\(inputLog)
        export FAKE_ENGINE_PACE_MS=50
        \(refuse)
        exec /usr/bin/env python3 \(f.appendingPathComponent("fake-ds4-dogfood").path) "$@"
        """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    }

    private struct Fake {
        let script: String, spawns: String, inputs: String
        var paths: [String] { [script, spawns, inputs] }
    }

    private func fake(refuseResume: Bool = false, extra: [String: String] = [:]) throws -> Fake {
        let f = Fake(script: tempPath("wrapper"), spawns: tempPath("spawns"), inputs: tempPath("inputs"))
        try writeFakeWrapper(
            to: f.script, spawnLog: f.spawns, inputLog: f.inputs, refuseResume: refuseResume, extra: extra)
        return f
    }

    /// A started controller whose session is idle at its first `input`.
    private func running(_ f: Fake, graces: EngineGraces = .standard) async -> EngineController {
        let controller = EngineController(graces: graces)
        controller.workspace = FileManager.default.temporaryDirectory
        await controller.start()
        await poll { controller.phase == .running && controller.composer.canSend && !controller.transcript.isBusy
            && controller.transcript.isAwaitingInput }
        return controller
    }

    @Test func rewindRelaunches() async throws {
        let f = try fake()
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = await running(f)
            controller.send("/rewind 1")
            await poll(timeout: .seconds(15)) {
                argvLines(f.spawns).count == 2 && controller.transcript.isAwaitingInput }
            let spawns = argvLines(f.spawns)
            #expect(spawns.count == 2)
            let source = spawns.first.flatMap { a in a.firstIndex(of: "--source").map { a[$0 + 1] } } ?? "?"
            #expect(spawns.last == ["tui", "--resume", "/tmp/fake-ds4-session", "--source", source,
                                    "--rewind-to", "1", "--ndjson"])
            #expect(controller.transcript.rows.first == .divider("Rewound to prompt 1"))
            await controller.quit()
        }
    }

    @Test func modelMenuSendsModelCommand() async throws {
        let f = try fake()
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = await running(f)
            controller.select(modelID: "qwen3.8-flash-next")
            await poll(timeout: .seconds(15)) {
                argvLines(f.spawns).count == 2 && controller.transcript.isAwaitingInput }
            let prompts = ((try? String(contentsOfFile: f.inputs, encoding: .utf8)) ?? "")
                .split(separator: "\n")
                .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
                .compactMap { $0["text"] as? String }
            #expect(prompts.contains("/model qwen3.8-flash-next"))
            #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "qwen3.8-flash-next")
            #expect(controller.transcript.rows.first
                == .divider("Switched to qwen3.8-flash-next: new conversation, files kept"))
            await controller.quit()
        }
    }

    @Test func modelMenuIdleRestartsFresh() async throws {
        let f = try fake()
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = EngineController()
            controller.workspace = FileManager.default.temporaryDirectory
            controller.select(modelID: "qwen3.8-flash-next")
            #expect(UserDefaults.standard.string(forKey: DefaultsKey.modelID.rawValue) == "qwen3.8-flash-next")
            await controller.start()
            await poll { controller.phase == .running }
            let argv = argvLines(f.spawns).first ?? []
            #expect(argv.firstIndex(of: "--model-id").map { argv[$0 + 1] } == "qwen3.8-flash-next")
            #expect(argv.firstIndex(of: "--commit").map { argv[$0 + 1] } == "HEAD")
            await controller.quit()
        }
    }

    @Test func relaunchRefusedEndsCleanly() async throws {
        let f = try fake(refuseResume: true)
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = await running(f)
            controller.send("Use the read tool on Package.swift")
            await poll(timeout: .seconds(10)) {
                controller.transcript.isAwaitingInput
                    && controller.transcript.rows.contains { if case .answer = $0 { true } else { false } }
            }
            controller.send("/rewind 1")
            await poll(timeout: .seconds(15)) {
                if argvLines(f.spawns).count == 2, case .ended = controller.phase { return true }
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
    }

    @Test func relaunchIgnoredWhileTerminating() async throws {
        let f = try fake()
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = await running(f)
            controller.beginTerminating()
            controller.send("/rewind 1")
            await poll(timeout: .seconds(10)) {
                if case .ended = controller.phase { return true }
                return false
            }
            try? await Task.sleep(for: .milliseconds(300))
            #expect(argvLines(f.spawns).count == 1)
        }
    }

    // MARK: SU.5a1 Task 6

    /// Audit B4: when even the safety bound passes, the session is ended, so
    /// the app is not left at "Ending…" with Start disabled.
    @Test func quitBoundEndsTheSession() async throws {
        let f = try fake(extra: ["FAKE_ENGINE_IGNORE_QUIT": "1", "FAKE_ENGINE_IGNORE_SIGTERM": "1"])
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let graces = EngineGraces(
                stop: .milliseconds(100), term: .milliseconds(100), kill: .seconds(3), safetyBound: .milliseconds(500))
            let controller = await running(f, graces: graces)
            await controller.quit()
            await poll(timeout: .seconds(2)) { if case .ended = controller.phase { true } else { false } }
            guard case .ended(let exit) = controller.phase else { Issue.record("phase \(controller.phase)"); return }
            #expect(exit.message == "the engine did not exit after quit; it may still be running")
            #expect(!controller.isActive)
            try? await Task.sleep(for: .seconds(4))  // the old session's SIGKILL lands; nothing changes
            #expect(controller.transcript.rows.last == .system(exit.message))
        }
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
        await withDefaults(executable: a, modelID: nil) {
            let controller = EngineController()
            await controller.loadCatalogIfNeeded()
            controller.select(modelID: "x")
            controller.select(contextSize: 4096)
            try? await Task.sleep(for: .milliseconds(300))
            #expect(callCount(aLog) == 1)
            UserDefaults.standard.set(b, forKey: DefaultsKey.executable.rawValue)
            await poll { callCount(bLog) == 1 }
            #expect(callCount(bLog) == 1)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.contextSize.rawValue)
        }
    }

    @Test func secondModelPickWhilePendingIsRefused() async throws {
        let f = try fake()
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let controller = await running(f)
            controller.select(modelID: "qwen3.8-flash-next")
            controller.select(modelID: "qwen3.8-27b")
            #expect(controller.transcript.rows.contains(.system("A model switch is already pending.")))
            await poll(timeout: .seconds(15)) { argvLines(f.spawns).count == 2 && controller.transcript.isAwaitingInput }
            let prompts = ((try? String(contentsOfFile: f.inputs, encoding: .utf8)) ?? "")
                .split(separator: "\n")
                .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] }
                .compactMap { $0["text"] as? String }
            #expect(prompts.filter { $0.hasPrefix("/model") } == ["/model qwen3.8-flash-next"])
            await controller.quit()
        }
    }

    // MARK: 5a1 final review

    /// The first start loads the catalog; when that fails, the note must
    /// survive into the session's transcript.
    @Test func catalogNoteShownOnFirstStart() async throws {
        let script = tempPath("session"), log = tempPath("argv")
        defer { for p in [script, log] { try? FileManager.default.removeItem(atPath: p) } }
        try writeSessionFake(to: script, argvLogPath: log)
        await withDefaults(executable: script, modelID: nil) {
            let controller = EngineController()
            controller.workspace = FileManager.default.temporaryDirectory
            await controller.start()
            await poll { controller.phase == .running }
            #expect(controller.transcript.rows.contains {
                if case .system(let s) = $0 { s.hasPrefix("Model list unavailable") } else { false } })
            await controller.quit()
        }
    }

    /// After the safety bound, a restart (menu pick) must not start a second
    /// engine beside one that may still hold the GPU; a deliberate Start does.
    @Test func restartAfterQuitBoundIsSkippedButStartWorks() async throws {
        let f = try fake(extra: ["FAKE_ENGINE_IGNORE_QUIT": "1", "FAKE_ENGINE_IGNORE_SIGTERM": "1"])
        defer { for p in f.paths { try? FileManager.default.removeItem(atPath: p) } }
        await withDefaults(executable: f.script, modelID: nil) {
            let graces = EngineGraces(
                stop: .milliseconds(100), term: .milliseconds(100), kill: .seconds(2), safetyBound: .milliseconds(500))
            let controller = await running(f, graces: graces)
            await controller.quit()
            await controller.restart()
            #expect(argvLines(f.spawns).count == 1)
            #expect(controller.transcript.rows.contains {
                if case .system(let s) = $0 { s.hasPrefix("Restart skipped") } else { false } })
            try? await Task.sleep(for: .seconds(3))  // the old engine's SIGKILL lands
            await controller.start()
            await poll { controller.phase == .running && controller.transcript.isAwaitingInput }
            #expect(argvLines(f.spawns).count == 2)
            controller.select(modelID: "qwen3.8-flash-next")
            #expect(!controller.transcript.rows.contains(.system("A model switch is already pending.")))
        }
    }
}
