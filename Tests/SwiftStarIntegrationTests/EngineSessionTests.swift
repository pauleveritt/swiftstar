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

    private let shortGrace = Duration.milliseconds(300)

    private func make(
        fixture: String, pace: Int = 5000, extra: [String: String] = [:], log: URL? = nil,
        workingDirectory: URL? = nil, grace: Duration? = nil
    ) -> (EngineSession, Recorder) {
        var env = ProcessInfo.processInfo.environment
        env["FAKE_ENGINE_FIXTURE"] = Self.repoRoot.appendingPathComponent("fixtures/engine/\(fixture).ndjson").path
        env["FAKE_ENGINE_PACE_MS"] = String(pace)
        if let log { env["FAKE_ENGINE_LOG"] = log.path }
        for (k, v) in extra { env[k] = v }
        let session = EngineSession(
            executable: Self.fake, arguments: [], environment: env, workingDirectory: workingDirectory,
            stopGrace: grace ?? .seconds(10), termGrace: grace ?? .seconds(5), killGrace: grace ?? .seconds(10))
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
    private func isQueued(_ e: EngineEvent) -> Bool { if case .queued = e { true } else { false } }

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

    /// Not covered here, by design: a non-JSON or non-object stdin line
    /// (relay texts "the line is not JSON" / "the line is not a JSON
    /// object") has no `EngineSession` entry point that can send malformed
    /// content — `send(prompt:)` always writes a well-formed `{"kind":
    /// "prompt", ...}` object. Verified instead by reading the fake script
    /// against the real relay source directly. Likewise, `{"kind":"quitting"}`
    /// firing immediately on `quit` isn't independently assertable — the
    /// wire parser still decodes it as `.ignored` — but its real consequence
    /// (a mid-turn quit ending fast and in the right order) is exactly what
    /// `quitMidTurnStopsFirst` and `quitWithQueuedPromptEndsPromptly` prove.

    @Test func emptyPromptIsRefused() async throws {
        let (session, rec) = make(fixture: "tool-read")
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "   ")
        #expect(await wait { rec.events.contains(.error("a prompt needs a non-empty text")) })
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func stopWhileIdleIsRefused() async throws {
        let (session, rec) = make(fixture: "tool-read")
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.stop()
        #expect(await wait { rec.events.contains(.error("no turn is running")) })
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func secondStopIsIdempotent() async throws {
        let (session, rec) = make(fixture: "stop", pace: 30000)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "read everything")
        #expect(await wait { rec.has(isToolStart) })
        try session.stop()
        try session.stop()
        #expect(await wait { rec.has(isInterrupted) })
        // No second "stopping"-triggered error or duplicate interrupt.
        #expect(rec.count(isInterrupted) == 1)
        #expect(!rec.events.contains(.error("no turn is running")))
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func loadGapQueuesAndKeepsStopDisabled() async throws {
        // A2: a prompt sent during the model-load gap is queued, not
        // forwarded, and Stop stays disabled (no turn exists yet) until the
        // gap elapses and the fixture's own `input` finally arrives.
        let (session, rec) = make(fixture: "tool-read", extra: ["FAKE_ENGINE_LOAD_MS": "300"])
        try session.start()
        try session.send(prompt: "typed while loading")
        #expect(await wait { rec.has(isQueued) })
        #expect(!rec.has(isAwaiting), "input must not arrive before the gap elapses")
        try? await Task.sleep(for: .milliseconds(100))
        try session.stop()
        #expect(await wait { rec.events.contains(.error("no turn is running")) })
        #expect(await wait(1) { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
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
        // The contract is the order (interrupted before the next awaitingInput),
        // not the absence of tool_end, which was only ever incidental to how
        // this fixture happens to be laid out.
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
        // The contract is the order, not the absence of tool_end (incidental
        // to this fixture's layout, not a claim about interrupt's behavior).
        let interrupted = rec.events.firstIndex(where: isInterrupted)
        let secondAwaiting = rec.events.indices.filter { isAwaiting(rec.events[$0]) }.last
        #expect(interrupted != nil && interrupted! < secondAwaiting!)
        session.quit()
        #expect(await wait { rec.exit != nil })
    }

    @Test func badHandshakeTerminates() async throws {
        let (session, rec) = make(fixture: "bad-handshake")
        try session.start()
        #expect(await wait { rec.has(isProtocolError) })
        #expect(await wait { rec.exit != nil })
        // "interrupted", not just code 130 -- disambiguates this from a
        // quit-timeout exit, which also lands on 130 but reads differently.
        #expect(rec.exit?.message == "interrupted")
        #expect(rec.exits.count == 1)
    }

    @Test func garbageAfterReadyIsNoticeNotFatal() async throws {
        let (session, rec) = make(fixture: "garbage-after-ready")
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        #expect(rec.events.contains(.notice("Engine output: this is not json")))
        #expect(!rec.has(isProtocolError))
        session.quit()
        #expect(await wait { rec.exit != nil })
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

    @Test func exitOneReportsStderrTailAtProcessLevel() async throws {
        // EngineCommandTests.exitOneIsNotClean already proves this at the
        // pure EngineExit.describe level; this proves the process-level
        // wiring actually gets real stderr content there.
        let (session, rec) = make(
            fixture: "tool-read",
            extra: ["FAKE_ENGINE_EXIT": "1", "FAKE_ENGINE_EXIT_STDERR": "boom from the engine"])
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait { rec.exit != nil })
        #expect(rec.exit?.message.contains("Ended without a clean answer") == true)
        #expect(rec.exit?.message.contains("boom from the engine") == true)
    }

    @Test func quitAfterTimeoutSendsSIGTERM() async throws {
        let (session, rec) = make(
            fixture: "tool-read", extra: ["FAKE_ENGINE_IGNORE_QUIT": "1"], grace: shortGrace)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        #expect(await wait(3) { rec.exit != nil })
        // The meaning, not just the raw code -- also 130, but "interrupted"
        // (badHandshakeTerminates) means something different to a reader.
        #expect(rec.exit?.message == "ended after the quit timed out")
    }

    @Test func quitMidTurnEndsTheEngine() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-pid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let (session, rec) = make(
            fixture: "tool-read", pace: 30000,
            extra: ["FAKE_ENGINE_PIDFILE": pidFile.path, "FAKE_ENGINE_IGNORE_QUIT": "1",
                    "FAKE_ENGINE_IGNORE_SIGTERM": "1"],
            grace: shortGrace)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        let pid = Int32((try? String(contentsOf: pidFile, encoding: .utf8)) ?? "") ?? 0
        #expect(pid > 0)
        try session.send(prompt: "read Package.swift")
        #expect(await wait { rec.has(isToolStart) })
        session.quit()
        #expect(await wait(2) { kill(pid, 0) != 0 })
        #expect(await wait { rec.exit != nil })
        #expect(rec.exit?.message == "ended by force after the quit timed out")
        #expect(rec.exits.count == 1)
        if pid > 0, kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    @Test func quitMidTurnStopsFirst() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-session-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        let (session, rec) = make(fixture: "tool-read", pace: 30000, log: log)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "read Package.swift")
        #expect(await wait { rec.has(isToolStart) })
        session.quit()
        #expect(await wait { rec.exit != nil })
        let kinds = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["kind"] as? String
        }
        let stop = try #require(kinds.firstIndex(of: "stop"))
        let quit = try #require(kinds.firstIndex(of: "quit"))
        #expect(stop < quit, "\(kinds)")
        #expect(rec.exit?.code == 0)
    }

    private func loggedKinds(_ log: URL) throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["kind"] as? String
        }
    }

    @Test func quitIsIdempotent() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-session-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        // The engine ignores quit, so a non-idempotent quit() would write it again.
        let (session, rec) = make(
            fixture: "tool-read", extra: ["FAKE_ENGINE_IGNORE_QUIT": "1"], log: log, grace: shortGrace)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        session.quit()
        session.quit()
        try? await Task.sleep(for: .milliseconds(50))
        session.quit()
        #expect(await wait { rec.exit != nil })
        session.quit()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rec.exits.count == 1)
        #expect(try loggedKinds(log).filter { $0 == "quit" }.count == 1)
    }

    @Test func quitWithQueuedPromptEndsPromptly() async throws {
        let log = FileManager.default.temporaryDirectory
            .appendingPathComponent("engine-session-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: log) }
        // Default graces: only a prompt quit (not a stopGrace wait) is fast enough.
        // Queueing is the fake's unconditional default now (P31).
        let (session, rec) = make(fixture: "tool-read", pace: 30000, log: log)
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "first")
        #expect(await wait { rec.has(isToolStart) })
        try session.send(prompt: "second, queued")
        let began = ContinuousClock.now
        session.quit()
        #expect(await wait(1.5) { rec.exit != nil })
        #expect(ContinuousClock.now - began < .seconds(1.5))
        let kinds = try loggedKinds(log)
        let stop = try #require(kinds.firstIndex(of: "stop"))
        let quit = try #require(kinds.firstIndex(of: "quit"))
        #expect(stop < quit, "\(kinds)")
        #expect(rec.exit?.message == "ended", "\(String(describing: rec.exit))")
        #expect(!rec.events.contains { if case .prompt(let t) = $0 { t == "second, queued" } else { false } })
    }

    @Test func notRunningErrorIsReadable() {
        #expect(EngineSessionError.notRunning.localizedDescription == "The engine is not running.")
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

    @Test func sendWhileBusyIsQueued() async throws {
        // A prompt sent mid-turn is acked with `queued`, not forwarded to the
        // engine — the opposite of this test's old name and assertion.
        // Delivery once the turn ends is the sibling of
        // `quitWithQueuedPromptEndsPromptly`'s drop-on-quit case; not
        // re-proven here (the fixture's own recorded `input` line still
        // shows before a queued turn starts, a known simplification — the
        // real relay suppresses it, P31 plan `## Result`).
        let (session, rec) = make(fixture: "tool-read")
        try session.start()
        #expect(await wait { rec.count(isAwaiting) == 1 })
        try session.send(prompt: "first prompt")
        #expect(await wait { rec.has(isToolStart) })
        try session.send(prompt: "second prompt")
        #expect(await wait { rec.has(isQueued) })
        // "Forwarded" would show as a wire-level `.prompt` event for the
        // second text; queued means no such event until a turn actually
        // starts for it, which this test does not let happen (it quits).
        func isSecondPrompt(_ e: EngineEvent) -> Bool {
            if case .prompt(let t) = e { t == "second prompt" } else { false }
        }
        #expect(!rec.has(isSecondPrompt))
        session.quit()
        #expect(await wait { rec.exit != nil })
    }
}
