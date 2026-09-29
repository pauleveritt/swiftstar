import Foundation
import Testing
@testable import SwiftStarAppKit
import SwiftStarKit

/// Drives `EngineModelCatalogLoader` against the fake engine's `models --json` mode.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct EngineModelCatalogLoaderTests {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let fake = repoRoot.appendingPathComponent("fixtures/engine/fake-ds4-dogfood").path
    private static let models = repoRoot.appendingPathComponent("fixtures/engine/models.json").path

    private func env(_ extra: [String: String] = [:]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["FAKE_ENGINE_MODELS"] = Self.models
        for (k, v) in extra { e[k] = v }
        return e
    }

    @Test func loaderReadsFakeList() async throws {
        let list = try await EngineModelCatalogLoader.load(
            executable: Self.fake, environment: env()).get()
        #expect(list.models.count == 5)
        #expect(list.defaultModelID == "qwen3.8-flash-next")
    }

    @Test func loaderFallsBackOnFailure() async {
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, environment: env(["FAKE_ENGINE_MODELS_FAIL": "1"]))
        #expect(result == .failure(.failed("exit code 2")))
        let missing = await EngineModelCatalogLoader.load(executable: "/nonexistent/ds4-dogfood")
        if case .failure(.failed) = missing {} else { Issue.record("launch failure expected") }
    }

    @Test func loaderFallsBackOnTimeout() async {
        let started = Date()
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, timeout: .milliseconds(500),
            environment: env(["FAKE_ENGINE_MODELS_SLEEP_MS": "5000"]))
        #expect(result == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func loaderTimesOutOnChildIgnoringSIGTERM() async {
        let started = Date()
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, timeout: .milliseconds(500),
            environment: env(["FAKE_ENGINE_MODELS_SLEEP_MS": "8000", "FAKE_ENGINE_IGNORE_SIGTERM": "1"]))
        #expect(result == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < 2.5)
    }
}
