import Foundation
import Testing
@testable import SwiftStarAppKit
import SwiftStarKit

/// Drives `EngineSession` against `fixtures/engine/fake-ds4-dogfood`, a Python
/// stand-in for `ds4-dogfood tui --ndjson` that replays the recorded fixtures.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
@MainActor
struct EngineSessionTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let fake = repoRoot.appendingPathComponent("fixtures/engine/fake-ds4-dogfood").path

    @MainActor
    final class Recorder {
        var events: [EngineEvent] = []
        var exits: [(EngineExit, URL?)] = []
        var exit: EngineExit? { exits.first?.0 }

        func count(_ match: (EngineEvent) -> Bool) -> Int { events.filter(match).count }
        func has(_ match: (EngineEvent) -> Bool) -> Bool { events.contains(where: match) }
    }

    private func make(
        fixture: String, pace: Int = 5000, extra: [String: String] = [:], log: URL? = nil,
        workingDirectory: URL? = nil
    ) -> (EngineSession, Recorder) {
        var env = ProcessInfo.processInfo.environment
        env["FAKE_ENGINE_FIXTURE"] = Self.repoRoot.appendingPathComponent("fixtures/engine/\(fixture).ndjson").path
        env["FAKE_ENGINE_PACE_MS"] = String(pace)
        if let log { env["FAKE_ENGINE_LOG"] = log.path }
        for (k, v) in extra { env[k] = v }
        let session = EngineSession(
            executable: Self.fake, arguments: [], environment: env, workingDirectory: workingDirectory)
        let recorder = Recorder()
        session.onEvent = { recorder.events.append($0) }
        session.onExit = { recorder.exits.append(($0, $1)) }
        return (session, recorder)
    }

    private func wait(_ seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func isAwaiting(_ e: EngineEvent) -> Bool { if case .awaitingInput = e { true } else { false } }
    private func isAnswer(_ e: EngineEvent) -> Bool { if case .answer = e { true } else { false } }
    private func isToolStart(_ e: EngineEvent) -> Bool { if case .toolStart = e { true } else { false } }
    private func isToolEnd(_ e: EngineEvent) -> Bool { if case .toolEnd = e { true } else { false } }
    private func isInterrupted(_ e: EngineEvent) -> Bool { if case .interrupted = e { true } else { false } }
    private func isProtocolError(_ e: EngineEvent) -> Bool { if case .protocolError = e { true } else { false } }

    @Test func fakeReceivesModelFlags() async throws {
        let argvLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-argv-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: argvLog) }
        var env = ProcessInfo.processInfo.environment
        env["FAKE_ENGINE_FIXTURE"] = Self.repoRoot.appendingPathComponent("fixtures/engine/tool-read.ndjson").path
        env["FAKE_ENGINE_PACE_MS"] = "20"
        env["FAKE_ENGINE_ARGV_LOG"] = argvLog.path
        let args = EngineCommand.arguments(
            source: URL(fileURLWithPath: "/tmp/r"), modelID: "qwen3.8-flash-next", contextSize: 20000)
        let session = EngineSession(executable: Self.fake, arguments: args, environment: env)
        let rec = Recorder()
        session.onEvent = { rec.events.append($0) }
        session.onExit = { rec.exits.append(($0, $1)) }
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
        let logged = try String(contentsOf: argvLog, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(logged == args)
        let i = try #require(logged.firstIndex(of: "--model-id"))
        #expect(logged[i + 1] == "qwen3.8-flash-next")
        let j = try #require(logged.firstIndex(of: "--context-size"))
        #expect(logged[j + 1] == "20000")
    }

    @Test func promptRoundTrip() async throws {
        let (session, rec) = make(fixture: "tool-read", pace: 20)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "read Package.swift")
        #expect(await wait { rec.has(isAnswer) && rec.count(isAwaiting) == 2 })
        session.quit()
        #expect(await wait { rec.exit != nil })
        #expect(rec.exit?.code == 0)
        #expect(session.isRunning == false)
        #expect(rec.exits.count == 1)
    }

    @Test func stopMidTurn() async throws {
        // Pace far above the wait: only a real stop can end the turn in time.
        let (session, rec) = make(fixture: "stop", pace: 30000)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "read everything")
        #expect(await wait { rec.has(isToolStart) })
        try session.stop()
        #expect(await wait { rec.count(isAwaiting) == 2 })
        #expect(!rec.has(isToolEnd), "the stop path drops the fixture's tool_end")
        let interrupted = rec.events.firstIndex(where: isInterrupted)
        let secondAwaiting = rec.events.indices.filter { isAwaiting(rec.events[$0]) }.last
        #expect(interrupted != nil && interrupted! < secondAwaiting!)
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func interruptByteMidTurn() async throws {
        let (session, rec) = make(fixture: "stop", pace: 30000)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "read everything")
        #expect(await wait { rec.has(isToolStart) })
        try session.interrupt()
        #expect(await wait { rec.has(isInterrupted) && rec.count(isAwaiting) == 2 })
        #expect(!rec.has(isToolEnd), "the stop path drops the fixture's tool_end")
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func badHandshakeTerminates() async throws {
        let (session, rec) = make(fixture: "bad-handshake")
        try session.start()
        #expect(await wait { rec.has(isProtocolError) })
        #expect(await wait { rec.exit != nil })
        #expect(rec.exit?.code == 130)
        #expect(rec.exits.count == 1)
    }

    @Test func refusalBeforeReady() async throws {
        let (session, rec) = make(fixture: "tool-read", extra: ["FAKE_ENGINE_REFUSE": "1"])
        try session.start()
        #expect(await wait { rec.exit != nil })
        #expect(!rec.has(isProtocolError))
        #expect(rec.exit?.message == "refused to start: ds4-dogfood tui: error: no model on this Mac")
    }

    @Test func sessionDirectoryKnownAtExit() async throws {
        let (session, rec) = make(fixture: "tool-read")
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
        #expect(rec.exits.first?.1?.path == "/tmp/fake-session")
        #expect(session.sessionDirectory?.path == "/tmp/fake-session")
    }

    @Test func quitAfterTimeoutSendsSIGTERM() async throws {
        let (session, rec) = make(fixture: "tool-read", extra: ["FAKE_ENGINE_IGNORE_QUIT": "1"])
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit(timeout: .seconds(1))
        #expect(await wait(3) { rec.exit != nil })
        #expect(rec.exit?.code == 130)
    }

    @Test func closedCapturePathResolvesSessionDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-wd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (session, rec) = make(
            fixture: "tool-read",
            extra: ["FAKE_ENGINE_CAPTURE_PATH": "session-x/run-1-123.json"],
            workingDirectory: dir)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
        // The closed event wins over the (later) stderr "Session artifacts:" line.
        let expected = dir.appendingPathComponent("session-x").standardizedFileURL.path
        #expect(rec.exits.first?.1?.path == expected, "got \(String(describing: rec.exits.first?.1?.path)) want \(expected)")
        #expect(session.sessionDirectory?.path == expected)
    }

    @Test func droppedSessionTerminatesTheEngine() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        var session: EngineSession?
        let rec: Recorder
        do {  // scope the tuple so only `session` keeps the engine alive
            let made = make(fixture: "tool-read", extra: ["FAKE_ENGINE_PIDFILE": pidFile.path, "FAKE_ENGINE_IGNORE_QUIT": "1"])
            session = made.0
            rec = made.1
        }
        try session?.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        let pid = Int32((try? String(contentsOf: pidFile, encoding: .utf8)) ?? "") ?? 0
        #expect(pid > 0)
        #expect(kill(pid, 0) == 0)
        session = nil  // never quit: deinit must tear the engine down
        #expect(await wait { kill(pid, 0) != 0 })
        if pid > 0, kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    @Test func startIsOneShot() async throws {
        let (session, rec) = make(fixture: "tool-read")
        try session.start()
        #expect(throws: EngineSessionError.alreadyStarted) { try session.start() }
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func sendWhileBusyIsForwarded() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-session-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let (session, rec) = make(fixture: "tool-read", log: log)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "first prompt")
        #expect(await wait { rec.has(isToolStart) })
        try session.send(prompt: "second prompt")
        #expect(await wait {
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            return text.contains("first prompt") && text.contains("second prompt")
        })
        session.quit()
        #expect(await wait { rec.exit != nil })
    }
}
