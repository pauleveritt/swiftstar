import Testing
import Foundation
@testable import SwiftStarAppKit
import SwiftStarKit

/// Eval-cli task 4: `AgentSession.run(_ command: Command)` routes a parsed
/// `CommandRouter` command to the wire, folding in the per-command envelope
/// decision that used to live duplicated inside `AgentController`
/// (`quick`'s advertised-cap gate, `orchestrate`'s directive build). These
/// tests replace `ThinkOverrideCapGateTests`/`PoolEngineArgvTests`, which
/// grepped `AgentController.swift`'s source text for those same facts
/// (BRIEF.md binding rule 3 forbids that) — moving the logic supplied the
/// module boundary those greps existed to compensate for, so what they
/// pinned is now pinned behaviorally, against the wire.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct AgentSessionCommandTests {

    // MARK: - fixtures

    /// hello (with `think_override`) → one generating segment → turn-end
    /// ready. Same minimal shape as `AgentSessionTests.plainTurn`, duplicated
    /// here rather than shared (that type's fixtures are `private`, and this
    /// file's own promptGuard variants make each fixture's caps the point
    /// under test, not an incidental detail worth abstracting away).
    private static func plainTurn(caps: [String]) -> String {
        let capsJSON = caps.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"t":"hello","v":1,"caps":[\(capsJSON)],"ts":1}
        {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":4,"gen_tps":10.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":4}
        {"t":"text","s":"hi there","ts":5}
        {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":8,"gen_tps":10.0,"ctx_used":20,"ctx_size":32768,"power":100,"error":"","ts":6}
        {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":8,"ctx_used":20,"ts":7}
        """
    }

    private static let capsWithOverride = ["status", "ready", "text", "think", "tool", "queued", "ts", "think_override"]
    private static let capsWithoutOverride = ["status", "ready", "text", "think", "tool", "queued", "ts"]

    // MARK: - harness (mirrors AgentSessionTests)

    private func makeSettings(engineDir: URL, workspace: URL) -> AgentSettings {
        AgentSettings(
            engineDir: engineDir,
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 8192,
            workspace: workspace,
            shellAllowed: true)
    }

    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsessioncmd-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Compile `capture` (optionally with a `promptGuard` snippet spliced
    /// into the fake's prompt loop — the mechanism `FakeAgentSource` built
    /// for exactly this: proving what actually reached the engine from
    /// outside the app target) into a fake `ds4-agent` at the path
    /// `AgentCommand.binaryPath(settings:)` resolves.
    private func buildFakeEngine(
        capture: String, settings: AgentSettings, promptGuard: String = ""
    ) throws {
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(
            capture: Data(capture.utf8), engineArgv: argv, hostTools: false, promptGuard: promptGuard)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsessioncmd-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        try FileManager.default.moveItem(
            at: binary, to: settings.engineDir.appendingPathComponent("ds4-agent"))
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                Issue.record("waitUntil timed out")
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// `FakeAgentSource`'s observation-only replay bundles `hello` into the
    /// SAME reply it plays after reading a prompt line (`AgentSessionTests`'
    /// fixture doc: "this fake only emits anything at all once it reads a
    /// stdin line") — unlike the real engine, whose `hello` arrives
    /// unsolicited at spawn, before the app ever calls `send`. So a test that
    /// needs `advertisedCaps` populated before the call under test has to
    /// prime it with one throwaway turn first, mirroring the real ordering
    /// (a prior handshake, already known) that `AgentController` relies on.
    /// Returns once the primer's `TurnOutcome` has landed.
    @MainActor
    private func primeAdvertisedCaps(_ session: AgentSession) async throws {
        var outcomes = 0
        session.onOutcome = { _ in outcomes += 1 }
        #expect(session.send("warm up the handshake") == true)
        try await waitUntil { outcomes >= 1 }
        session.onOutcome = nil
    }

    // MARK: - quickTurnSendsNoThinkAndChatDoesNot

    /// Replaces the `/quick`-guard grep: pins the envelope `run(_:)` actually
    /// writes to the wire for `.quick` (must carry `"think":"none"`) versus
    /// `.chat` (must carry no `"think"` field at all — a plain turn). Each
    /// half spawns its own fake with a `promptGuard` that fails the process
    /// (`exit(1)`) if the written prompt line doesn't match; a guard failure
    /// means the fake never replays its `ready`, so the assertion is "the
    /// turn actually completes" — a hung/failed fake fails the test via
    /// `waitUntil`'s timeout, same as any other broken round trip here.
    @Test @MainActor func quickTurnSendsNoThinkAndChatDoesNot() async throws {
        // .quick: the prompt line must carry the no-think override. The
        // guard only fires on the marked task text — the primer turn's own
        // prompt line (used only to populate `advertisedCaps`, see
        // `primeAdvertisedCaps`) must not trip it.
        do {
            let engineDir = try tempDir("engine-quick")
            let workspace = try tempDir("ws-quick")
            let captureDir = try tempDir("capture-quick")
            let settings = makeSettings(engineDir: engineDir, workspace: workspace)
            try buildFakeEngine(
                capture: Self.plainTurn(caps: Self.capsWithOverride), settings: settings,
                promptGuard: #"""
                if promptLine.contains("go fast") {
                    guard promptLine.contains("\"think\":\"none\"") else {
                        FileHandle.standardError.write(Data("PROMPT_GUARD_FAIL: expected think=none, got \(promptLine)\n".utf8))
                        exit(1)
                    }
                }
                """#)

            let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
            _ = try session.start()
            defer { session.stop() }
            try await primeAdvertisedCaps(session)

            var outcomes: [TurnOutcome] = []
            session.onOutcome = { outcomes.append($0) }
            #expect(session.run(.quick(task: "go fast")) == true)
            try await waitUntil { outcomes.count >= 1 }
            #expect(outcomes.count == 1, "the fake's promptGuard must have accepted a think=none envelope")
        }

        // .chat: the prompt line must carry NO think field — a plain turn.
        do {
            let engineDir = try tempDir("engine-chat")
            let workspace = try tempDir("ws-chat")
            let captureDir = try tempDir("capture-chat")
            let settings = makeSettings(engineDir: engineDir, workspace: workspace)
            try buildFakeEngine(
                capture: Self.plainTurn(caps: Self.capsWithOverride), settings: settings,
                promptGuard: #"""
                if promptLine.contains("just answer this") {
                    guard !promptLine.contains("\"think\"") else {
                        FileHandle.standardError.write(Data("PROMPT_GUARD_FAIL: expected no think field, got \(promptLine)\n".utf8))
                        exit(1)
                    }
                }
                """#)

            let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
            _ = try session.start()
            defer { session.stop() }
            try await primeAdvertisedCaps(session)

            var outcomes: [TurnOutcome] = []
            session.onOutcome = { outcomes.append($0) }
            #expect(session.run(.chat(task: "just answer this")) == true)
            try await waitUntil { outcomes.count >= 1 }
            #expect(outcomes.count == 1, "the fake's promptGuard must have accepted an envelope with no think field")
        }
    }

    // MARK: - advertisedCapsComeFromTheParserNotADefault

    /// Replaces the caps grep: `.quick` must refuse (binding rule 7 — a
    /// mismatch refuses loudly, never silently degrades) against an engine
    /// whose handshake never advertised `think_override`; the sibling proves
    /// the same command is admitted once the handshake does advertise it —
    /// the fact must come from the parsed `hello`, not a hardcoded default.
    @Test @MainActor func advertisedCapsComeFromTheParserNotADefault() async throws {
        // Refusal: no think_override cap on the handshake.
        do {
            let engineDir = try tempDir("engine-norefuse")
            let workspace = try tempDir("ws-norefuse")
            let captureDir = try tempDir("capture-norefuse")
            let settings = makeSettings(engineDir: engineDir, workspace: workspace)
            try buildFakeEngine(capture: Self.plainTurn(caps: Self.capsWithoutOverride), settings: settings)

            let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
            _ = try session.start()
            defer { session.stop() }
            try await primeAdvertisedCaps(session)

            #expect(session.advertisedCaps.contains(TurnThinkPolicy.overrideCap) == false)
            #expect(session.run(.quick(task: "go fast")) == false,
                    "a /quick must refuse when the engine never advertised think_override")
        }

        // Admission: the sibling case, same command, cap present.
        do {
            let engineDir = try tempDir("engine-admit")
            let workspace = try tempDir("ws-admit")
            let captureDir = try tempDir("capture-admit")
            let settings = makeSettings(engineDir: engineDir, workspace: workspace)
            try buildFakeEngine(capture: Self.plainTurn(caps: Self.capsWithOverride), settings: settings)

            let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
            _ = try session.start()
            defer { session.stop() }
            try await primeAdvertisedCaps(session)

            #expect(session.advertisedCaps.contains(TurnThinkPolicy.overrideCap) == true)
            var outcomes: [TurnOutcome] = []
            session.onOutcome = { outcomes.append($0) }
            #expect(session.run(.quick(task: "go fast")) == true,
                    "a /quick must be admitted once the handshake advertises think_override")
            try await waitUntil { outcomes.count >= 1 }
            #expect(outcomes.count == 1)
        }
    }

    // MARK: - pooledSpawnArgvCarriesSubagentPool

    /// Replaces the `PoolEngine.argv(` call-site grep (`PoolEngineArgvTests
    /// .poolEngineArgvIsTheOnlyPooledArgvBuilder`): asserts the argv a pooled
    /// `AgentSession` actually spawns with, not which source line built it.
    ///
    /// Fable-fixes review, F7: this used to build `expectedArgv` from the
    /// SAME `PoolEngine.argv(...)` call `AgentSession.resolveSpawnRecord`
    /// uses, and never observed the fake engine — comparing `record.argv`
    /// to `expectedArgv` was really comparing the record to itself. A
    /// regression where `start()` spawned the plain, non-pooled argv while
    /// the record still claimed the pooled one would have passed. The fix:
    /// a `promptGuard` snippet (the mechanism `FakeAgentSource` built for
    /// exactly this — proving what actually reached the engine from outside
    /// the app target) dumps `CommandLine.arguments` to a file from inside
    /// the fake's own prompt loop, and the assertion below compares
    /// `record.argv` to THAT — what the fake actually received — not to the
    /// expression that built it.
    @Test @MainActor func pooledSpawnArgvCarriesSubagentPool() async throws {
        let engineDir = try tempDir("engine-pool")
        let workspace = try tempDir("ws-pool")
        let captureDir = try tempDir("capture-pool")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        let expectedArgv = PoolEngine.argv(settings: settings, workers: 2)

        let argvDumpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsessioncmd-observed-argv-\(UUID().uuidString).txt")
        let escapedDumpPath = argvDumpURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let promptGuard = """
            let __observedArgv = CommandLine.arguments.dropFirst().joined(separator: "\\u{1}")
            try? __observedArgv.write(toFile: "\(escapedDumpPath)", atomically: true, encoding: .utf8)
            """

        let source = try FakeAgentSource.generate(
            capture: Data(Self.plainTurn(caps: Self.capsWithOverride).utf8),
            engineArgv: expectedArgv, hostTools: false, promptGuard: promptGuard)
        let binary = try FakeAgentHarness.compileFake(source: source, into: engineDir)
        try FileManager.default.moveItem(at: binary, to: engineDir.appendingPathComponent("ds4-agent"))

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir, poolSize: 2)
        let record = try session.start()
        defer { session.stop() }

        #expect(record.argv.contains("--subagent-pool"))
        let idx = try #require(record.argv.firstIndex(of: "--subagent-pool"))
        #expect(record.argv[record.argv.index(after: idx)] == "2")

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }
        #expect(session.send("go") == true)
        try await waitUntil { outcomes.count >= 1 }

        let observedArgv = try String(contentsOf: argvDumpURL, encoding: .utf8)
            .components(separatedBy: "\u{1}")
        #expect(observedArgv == record.argv,
                "the record must match what the fake engine actually received, not itself")
    }
}
