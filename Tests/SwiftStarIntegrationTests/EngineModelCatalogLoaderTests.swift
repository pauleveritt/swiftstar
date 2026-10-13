import Foundation
import Testing
@testable import SwiftStarEngine
import SwiftStarKit

/// Drives `EngineModelCatalogLoader` against the fake engine's `models --json` mode.
@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))
struct EngineModelCatalogLoaderTests {
    private static let fake = Fixtures.path("fake-ds4-dogfood")
    private static let models = Fixtures.path("models.json")

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
        #expect(list.defaultModelID == "laguna-xs-2.1")
    }

    @Test func loaderFallsBackOnFailure() async {
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, environment: env(["FAKE_ENGINE_MODELS_FAIL": "1"]))
        #expect(result == .failure(.failed("exit code 2: ds4-dogfood: error: boom")))
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

    @Test func loaderReportsStderrTailBeyond4KiB() async {
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, environment: env(["FAKE_ENGINE_MODELS_HUGE_STDERR": "1"]))
        guard case .failure(.failed(let message)) = result else {
            Issue.record("expected .failed, got \(result)")
            return
        }
        #expect(message.hasSuffix("the real last line"))
    }

    @Test func loaderReportsMissingCommand() async {
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, environment: env(["FAKE_ENGINE_MODELS_UNKNOWN": "1"]))
        #expect(result == .failure(.commandMissing))
        if case .failure(let e) = result {
            #expect(e.reason == "this ds4-dogfood has no `models` command (needs ds4-engine TUI.35 or later)")
        }
    }
}
