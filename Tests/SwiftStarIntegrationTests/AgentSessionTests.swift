import Testing
import Foundation
@testable import SwiftStarAppKit
import SwiftStarKit

/// Eval-cli task 2: `AgentSession` is the app's single-turn agent loop, lifted
/// out of `AgentController` so a headless CLI can drive a real turn without
/// linking SwiftUI. These tests drive it against the same compiled-fake
/// `ds4-agent` harness every other test in this target uses
/// (`FakeAgentHarness`/`FakeAgentSource`) — no real engine, no real model.
// .serialized: `interruptEndsTheTurn` races a real wall-clock delay against
// this test process's own scheduling — running alongside the other three
// tests (swift-testing's default parallelism) left enough CPU contention to
// occasionally let the fake's replay outrun the test's `interrupt()` call
// before it landed (observed during the Step 5 falsification run).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct AgentSessionTests {

    // MARK: - fixtures (inline, minimal, single-turn — the committed
    // `fixtures/agent/*.ndjson` captures each replay several turns' worth of
    // events behind a single `send`-triggered fake, which would make "one
    // send yields exactly one TurnOutcome" untestable here)

    /// hello → one generating segment → turn-end ready (`stop_reason":"eos"`).
    /// No tool calls. Deliberately carries no SEPARATE startup `ready` before
    /// the turn content: this fake only emits anything at all once it reads a
    /// stdin line (`FakeAgentSource`'s `readStdinLine`/`readPromptLine`
    /// loops), and that line is `AgentSession.send`'s own write — which
    /// already opened `outcomeBuilder` before writing. A startup `ready`
    /// arriving while that builder is open would close the turn prematurely
    /// (`consume`'s `.ready` case has no way to tell "the engine's own
    /// pre-turn handshake ready" from "the turn actually ended" other than
    /// builder-open state — see the type doc). In real production use this
    /// never happens: the real engine's startup ready always arrives BEFORE
    /// `AgentController` ever calls `send` (gated by its own `state`).
    private static let plainTurn = """
    {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","think_override"],"ts":1}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":4,"gen_tps":10.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":4}
    {"t":"text","s":"hi there","ts":5}
    {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":8,"gen_tps":10.0,"ctx_used":20,"ctx_size":32768,"power":100,"error":"","ts":6}
    {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":8,"ctx_used":20,"ts":7}
    """

    /// Same shape as `plainTurn`, but with one `write` tool block before the
    /// turn-end `ready` —
    /// `FakeAgentSource.generate(hostTools: true)` rewrites the block into a
    /// `tool_request`/`tool_result` round trip, exercising the exact path
    /// `AgentSession.consume`'s `.toolRequest` case answers.
    private static let toolTurn = """
    {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":1}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":4}
    {"t":"text","s":"\\n","ts":5}
    {"t":"tool","phase":"start","idx":0,"ts":6}
    {"t":"tool","phase":"tool","idx":0,"name":"write","ts":7}
    {"t":"tool","phase":"param_begin","idx":0,"kind":"path","name":"path","ts":8}
    {"t":"tool","phase":"param_value","idx":0,"s":"seed.txt","ts":9}
    {"t":"tool","phase":"param_end","idx":0,"ts":10}
    {"t":"tool","phase":"param_begin","idx":0,"kind":"content","name":"content","ts":11}
    {"t":"tool","phase":"param_value","idx":0,"s":"hello from AgentSessionTests","ts":12}
    {"t":"tool","phase":"param_end","idx":0,"ts":13}
    {"t":"tool","phase":"finish","idx":0,"calls":1,"ts":14}
    {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":8,"gen_tps":10.0,"ctx_used":30,"ctx_size":32768,"power":100,"error":"","ts":15}
    {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":8,"ctx_used":30,"ts":16}
    """

    /// Slow enough (with `FAKE_MIN_LINE_DELAY`) that the test can interrupt
    /// mid-stream, before the natural turn-end `ready` ever plays. No tool
    /// call — the ETX/interrupt path only exists in the fake's
    /// observation-only (`hostTools: false`) template (see
    /// `FakeAgentSource.buildHostTools`'s `replayOnce`, which has no ETX
    /// check at all).
    private static let interruptibleTurn = """
    {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":1}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":2,"gen_tps":10.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":200003}
    {"t":"text","s":"one ","ts":400006}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":4,"gen_tps":10.0,"ctx_used":12,"ctx_size":32768,"power":100,"error":"","ts":600009}
    {"t":"text","s":"two ","ts":800012}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":6,"gen_tps":10.0,"ctx_used":14,"ctx_size":32768,"power":100,"error":"","ts":1000015}
    {"t":"text","s":"three","ts":1200018}
    {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":6,"gen_tps":10.0,"ctx_used":16,"ctx_size":32768,"power":100,"error":"","ts":1400021}
    {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":6,"ctx_used":16,"ts":1600024}
    """

    // MARK: - harness

    private func makeSettings(engineDir: URL, workspace: URL) -> AgentSettings {
        AgentSettings(
            engineDir: engineDir,
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 8192,
            workspace: workspace,
            shellAllowed: true)
    }

    /// Compile `capture` into a fake `ds4-agent`, place it where
    /// `AgentCommand.binaryPath(settings:)` resolves, and return the argv the
    /// fake will validate against (== what `AgentSession.start()` will spawn
    /// it with).
    private func buildFakeEngine(
        capture: String, settings: AgentSettings, hostTools: Bool
    ) throws -> [String] {
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(
            capture: Data(capture.utf8), engineArgv: argv, hostTools: hostTools)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsession-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        try FileManager.default.moveItem(
            at: binary, to: settings.engineDir.appendingPathComponent("ds4-agent"))
        return argv
    }

    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsession-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Polls `condition` until it's true or `timeout` elapses. `AgentSession`'s
    /// callbacks land on the MainActor via a detached drain `Task`, so a test
    /// awaiting one cannot just `await` a single call — it has to give the
    /// drain loop turns to run.
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

    // MARK: - Step 1 tests

    @Test @MainActor func sessionSpawnsAndCompletesOneTurn() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = try tempDir("capture")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        let expectedArgv = try buildFakeEngine(capture: Self.plainTurn, settings: settings, hostTools: true)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
        let record = try session.start()
        defer { session.stop() }

        #expect(record.argv == AgentCommand.argv(settings: settings))
        #expect(record.argv == expectedArgv)

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }

        #expect(session.send("hello there") == true)
        try await waitUntil { outcomes.count >= 1 }

        #expect(outcomes.count == 1, "one send() must yield exactly one TurnOutcome")
        #expect(outcomes.first?.stopReason == .eos)
    }

    @Test @MainActor func toolCallbackRoundTripIsAnswered() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = try tempDir("capture")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        _ = try buildFakeEngine(capture: Self.toolTurn, settings: settings, hostTools: true)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
        _ = try session.start()
        defer { session.stop() }

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }
        var sawToolRequest = false
        session.onEvent = { event in
            if case .toolRequest = event { sawToolRequest = true }
        }

        #expect(session.send("write the seed file") == true)
        // A round trip that deadlocked would never produce an outcome; the
        // timeout in `waitUntil` is this test's failure mode for that case.
        try await waitUntil { outcomes.count >= 1 }

        #expect(sawToolRequest, "the fake's tool block must have become a tool_request")
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.stopReason == .eos)
        #expect(outcomes.first?.toolCalls.contains { $0.name == "write" && $0.transitions.contains(.executed) } == true)
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("seed.txt").path),
                "the host executor must have actually written the file")
    }

    @Test @MainActor func interruptEndsTheTurn() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = try tempDir("capture")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        _ = try buildFakeEngine(capture: Self.interruptibleTurn, settings: settings, hostTools: false)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
        _ = try session.start()
        defer { session.stop() }

        var textEvents = 0
        session.onEvent = { event in
            if case .text = event { textEvents += 1 }
        }
        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }

        // FAKE_SPEED/FAKE_MIN_LINE_DELAY aren't settable per-process through
        // `AgentSession` (it owns argv, not env); the fake's env comes from
        // `AgentCommand.engineEnvironment`, which passes the test process's
        // own environment through. Set it here before spawning.
        setenv("FAKE_SPEED", "1", 1)
        setenv("FAKE_MIN_LINE_DELAY", "0.4", 1)
        defer { unsetenv("FAKE_SPEED"); unsetenv("FAKE_MIN_LINE_DELAY") }

        #expect(session.send("say three things slowly") == true)
        try await waitUntil { textEvents >= 1 }
        session.interrupt()

        try await waitUntil(timeout: 15) { outcomes.count >= 1 }
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.stopReason == .interrupt)
        #expect(textEvents < 3, "the interrupt must have cut the replay short of its natural end")
    }

    @Test @MainActor func captureIsOnDiskBeforeTheReadback() async throws {
        // Binding rule 5: the wire capture is written to disk before anything
        // reads it back. Proven by reading `wire.ndjson` from INSIDE the
        // `onOutcome` callback — which fires from `consume`, after that same
        // line's bytes were already appended to the file (`start()`'s drain
        // loop tees before it parses/calls back; see its doc comment).
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = try tempDir("capture")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        _ = try buildFakeEngine(capture: Self.plainTurn, settings: settings, hostTools: true)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir)
        _ = try session.start()
        defer { session.stop() }

        var onDiskAtOutcomeTime: String?
        session.onOutcome = { _ in
            let wireURL = captureDir.appendingPathComponent("wire.ndjson")
            onDiskAtOutcomeTime = try? String(contentsOf: wireURL, encoding: .utf8)
        }

        #expect(session.send("hello there") == true)
        try await waitUntil { onDiskAtOutcomeTime != nil }

        let onDisk = try #require(onDiskAtOutcomeTime)
        #expect(onDisk.contains(#""t":"hello""#))
        #expect(onDisk.contains(#""stop_reason":"eos""#),
                "the turn-end ready line must already be flushed by the time onOutcome fires")
    }

    // MARK: - Step 1 test (task 3): pooled dispatch

    /// Eval-cli task 3, Step 1: a pooled dispatch against the fake engine
    /// surfaces worker events tagged with the right `WorkerId`, and the
    /// parent (orchestrator) turn completes. `fixtures/agent/pool.ndjson`
    /// (already used by `PoolOrchestratorTests`) replays worker 0's whole
    /// turn followed by worker 1's — the fake's `replayOnce()` fires the
    /// entire remaining capture off ONE stdin prompt line (see
    /// `FakeAgentSource`'s doc), so a single `send()` (worker 0's own prompt)
    /// is enough to observe both streams: worker 0's through `onOutcome`,
    /// worker 1's through `onWorkerEvent`.
    @Test @MainActor func dispatchedWorkerEventsReachTheHost() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = try tempDir("capture")
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        let argv = PoolEngine.argv(settings: settings, workers: 2)
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("pool.ndjson"))
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: false)
        let binary = try FakeAgentHarness.compileFake(source: source, into: engineDir)
        try FileManager.default.moveItem(at: binary, to: engineDir.appendingPathComponent("ds4-agent"))

        // `pool.ndjson` carries real captured `ts` deltas (tens of seconds
        // between worker 0's startup `ready` and its first real status line)
        // — `FAKE_SPEED=0` disables the fake's replay delay entirely (the
        // same knob `PoolEngineTests`/`WorktreeDispatchFakeAgentTests` use for
        // this exact fixture) so the test doesn't have to wait out the
        // original capture's wall-clock time.
        setenv("FAKE_SPEED", "0", 1)
        defer { unsetenv("FAKE_SPEED") }

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir,
                                   poolSize: 2)
        _ = try session.start()
        defer { session.stop() }

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }
        var workerEvents: [(WorkerId, AgentEvent)] = []
        session.onWorkerEvent = { worker, event in workerEvents.append((worker, event)) }

        #expect(session.send("do the thing") == true)
        try await waitUntil {
            outcomes.count >= 1 && workerEvents.contains {
                if case .ready = $0.1 { return $0.0 == WorkerId(1) }
                return false
            }
        }

        #expect(outcomes.count == 1, "the orchestrator's (worker 0) turn must complete via onOutcome")
        #expect(outcomes.first?.stopReason == .eos)
        #expect(workerEvents.allSatisfy { $0.0 == WorkerId(1) },
                "every event forwarded to onWorkerEvent in this fixture belongs to worker 1")
        #expect(workerEvents.contains { if case .text = $0.1 { return true }; return false },
                "worker 1's own text events must reach the host, tagged with its WorkerId")
    }

    // MARK: - Regression fix: sessionCaptureEnabled (task 2 made capture
    // unconditional; these pin the refusal/success pair per binding rule 4).

    /// `captureEnabled: false` must write NOTHING under `captureDirectory` —
    /// not even the directory itself. Task 2's report flagged this as a
    /// deliberate regression ("capture is no longer optional"); this test
    /// pins the fix.
    @Test @MainActor func captureDisabledWritesNoCaptureTree() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        // Deliberately NOT `tempDir(_:)` — that helper pre-creates the
        // directory, which would make this test pass trivially (the
        // directory would already exist for a reason unrelated to capture).
        let captureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsession-capture-off-\(UUID().uuidString)", isDirectory: true)
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        _ = try buildFakeEngine(capture: Self.plainTurn, settings: settings, hostTools: true)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir,
                                   captureEnabled: false)
        _ = try session.start()
        defer { session.stop() }

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }
        #expect(session.send("hello there") == true)
        try await waitUntil { outcomes.count >= 1 }

        #expect(outcomes.count == 1, "the turn must still complete with capture off")
        #expect(!FileManager.default.fileExists(atPath: captureDir.path),
                "captureEnabled: false must not create the capture directory at all")
    }

    /// The success half of the pair: `captureEnabled: true` (the default)
    /// writes the same capture tree it always did.
    @Test @MainActor func captureEnabledWritesACaptureTree() async throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let captureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentsession-capture-on-\(UUID().uuidString)", isDirectory: true)
        let settings = makeSettings(engineDir: engineDir, workspace: workspace)
        _ = try buildFakeEngine(capture: Self.plainTurn, settings: settings, hostTools: true)

        let session = AgentSession(settings: settings, tools: [], captureDirectory: captureDir,
                                   captureEnabled: true)
        _ = try session.start()
        defer { session.stop() }

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }
        #expect(session.send("hello there") == true)
        try await waitUntil { outcomes.count >= 1 }

        #expect(outcomes.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: captureDir.appendingPathComponent("wire.ndjson").path))
        #expect(FileManager.default.fileExists(
            atPath: captureDir.appendingPathComponent("provenance.md").path))
    }
}
