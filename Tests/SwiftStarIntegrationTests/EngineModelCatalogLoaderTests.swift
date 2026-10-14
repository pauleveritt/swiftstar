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

    nonisolated struct TimeoutCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let env: [String: String]
        /// Seconds the load may take in all, the 0.5 s timeout included.
        let within: Double
    }

    nonisolated static let timeoutCases: [TimeoutCase] = [
        .init(testDescription: "loaderFallsBackOnTimeout", env: ["FAKE_ENGINE_MODELS_SLEEP_MS": "5000"], within: 3),
        .init(testDescription: "loaderTimesOutOnChildIgnoringSIGTERM",
              env: ["FAKE_ENGINE_MODELS_SLEEP_MS": "8000", "FAKE_ENGINE_IGNORE_SIGTERM": "1"], within: 2.5),
    ]

    /// The load returns at its timeout either way; the child must also be
    /// gone (SIGKILL for one that ignores SIGTERM), or it outlives the app.
    @Test(arguments: timeoutCases) func loaderTimesOut(_ c: TimeoutCase) async throws {
        let pidFile = tempPath("models-pid")
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        let started = Date()
        let result = await EngineModelCatalogLoader.load(
            executable: Self.fake, timeout: .milliseconds(500),
            environment: env(c.env.merging(["FAKE_ENGINE_PIDFILE": pidFile]) { a, _ in a }))
        #expect(result == .failure(.timedOut))
        #expect(Date().timeIntervalSince(started) < c.within)
        let pid = try #require(Int32(String(contentsOfFile: pidFile, encoding: .utf8)))
        let gone = await eventually(within: .seconds(2)) { kill(pid, 0) != 0 }
        #expect(gone)
        if !gone { kill(pid, SIGKILL) }
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
        #expect(result == .failure(.commandMissing("models")))
        if case .failure(let e) = result {
            #expect(e.reason == "this ds4-dogfood has no `models` command (needs ds4-engine TUI.35 or later)")
        }
    }
}

/// SU.7a: `sessions --json` through the same runner as the model list.
@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))
struct SessionListLoaderTests {
    private static let fake = Fixtures.path("fake-ds4-dogfood")

    private func env(_ extra: [String: String]) -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e.removeValue(forKey: "FAKE_ENGINE_SESSIONS")
        for (k, v) in extra { e[k] = v }
        return e
    }

    @Test func sessionListLoaderReadsTheFake() async throws {
        let entries = try await SessionListLoader.load(
            executable: Self.fake, source: URL(fileURLWithPath: "/r"),
            environment: env(["FAKE_ENGINE_SESSIONS": Fixtures.path("sessions.json")])).get()
        #expect(entries.count == 12)
    }

    @Test func sessionListLoaderPassesSourceAndLimit() async throws {
        let log = tempPath("argv")
        defer { try? FileManager.default.removeItem(atPath: log) }
        _ = await SessionListLoader.load(
            executable: Self.fake, source: URL(fileURLWithPath: "/r"),
            environment: env(["FAKE_ENGINE_SESSIONS": Fixtures.path("sessions.json"), "FAKE_ENGINE_ARGV_LOG": log]))
        let argv = try String(contentsOfFile: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(argv == ["sessions", "--json", "--source", "/r", "--limit", "50"])
    }

    @Test func allSessionsLoaderPassesAll() async throws {
        let log = tempPath("argv")
        defer { try? FileManager.default.removeItem(atPath: log) }
        _ = await SessionListLoader.loadAll(
            executable: Self.fake,
            environment: env(["FAKE_ENGINE_SESSIONS": Fixtures.path("sessions-all.json"), "FAKE_ENGINE_ARGV_LOG": log]))
        let argv = try String(contentsOfFile: log, encoding: .utf8).split(separator: "\n").map(String.init)
        #expect(argv == ["sessions", "--json", "--all", "--limit", "200"])
    }

    @Test func sessionListLoaderReportsMissingCommand() async {
        let result = await SessionListLoader.load(
            executable: Self.fake, source: URL(fileURLWithPath: "/r"), environment: env([:]))
        // SU.17: the note names the command that's missing, not `models`.
        #expect(result == .failure(.commandMissing("sessions")))
        if case .failure(let e) = result {
            #expect(e.reason == "this ds4-dogfood has no `sessions` command (update ds4-engine)")
        }
    }
}
