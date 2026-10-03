import Foundation
import Testing
@testable import SwiftStar
import SwiftStarKit

/// Drives `EngineController` directly (first coverage it has ever had — it
/// lives in the app target, which neither test target depended on before
/// P30). Mutates `UserDefaults.standard` (the real, persistent domain — there
/// is no isolated suite here), so kept serialized and every touched key is
/// saved, reset to a known value before use, and restored afterward.
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
        let savedExecutable = defaults.string(forKey: EngineController.executableDefaultsKey)
        defaults.set(tempPath, forKey: EngineController.executableDefaultsKey)
        defer {
            if let savedExecutable {
                defaults.set(savedExecutable, forKey: EngineController.executableDefaultsKey)
            } else {
                defaults.removeObject(forKey: EngineController.executableDefaultsKey)
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
    private func writeSessionFake(to scriptPath: String, argvLogPath: String) throws {
        let script = """
        #!/usr/bin/env python3
        import json, sys
        if sys.argv[1:2] != ["models"]:
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

    @Test func selectingModelWhileRunningEndsTurnAndRestarts() async throws {
        let scriptPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("p30-session-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        let argvLogPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("p30-session-argv-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: argvLogPath) }
        try writeSessionFake(to: scriptPath, argvLogPath: argvLogPath)

        let defaults = UserDefaults.standard
        let savedExecutable = defaults.string(forKey: EngineController.executableDefaultsKey)
        let savedModelID = defaults.string(forKey: EngineController.modelIDDefaultsKey)
        defaults.set(scriptPath, forKey: EngineController.executableDefaultsKey)
        // A clean, known baseline: a prior run (or the real app, sharing this
        // same persistent domain) could otherwise leave "a-different-model"
        // already selected, silently no-op-ing this test's select() call.
        defaults.removeObject(forKey: EngineController.modelIDDefaultsKey)
        defer {
            if let savedExecutable {
                defaults.set(savedExecutable, forKey: EngineController.executableDefaultsKey)
            } else {
                defaults.removeObject(forKey: EngineController.executableDefaultsKey)
            }
            if let savedModelID {
                defaults.set(savedModelID, forKey: EngineController.modelIDDefaultsKey)
            } else {
                defaults.removeObject(forKey: EngineController.modelIDDefaultsKey)
            }
        }

        let controller = EngineController()
        controller.workspace = FileManager.default.temporaryDirectory
        controller.start()
        await poll { controller.phase == .running }
        #expect(controller.phase == .running)
        #expect(argvLines(argvLogPath).count == 1)
        #expect(argvLines(argvLogPath).first?.contains("--model-id") == false)

        controller.select(modelID: "a-different-model")

        await poll(timeout: .seconds(10)) { argvLines(argvLogPath).count == 2 }
        let spawns = argvLines(argvLogPath)
        #expect(spawns.count == 2)
        #expect(spawns.last?.contains("--model-id") == true)
        #expect(spawns.last?.last == "a-different-model")
    }
}
