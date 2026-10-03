import Foundation
import Testing
@testable import SwiftStar
import SwiftStarKit

/// Drives `EngineController` directly (first coverage it has ever had — it
/// lives in the app target, which neither test target depended on before
/// P30). Mutates `UserDefaults.standard`, so kept serialized and restored.
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
}
