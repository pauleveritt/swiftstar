import Foundation
import Testing
import SwiftStarKit

@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct PoolEngineTests {

    @Test func workerTaggedCaptureRoutesByWorker() throws {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("pool.ndjson"))
        let settings = AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 8192,
            workspace: URL(fileURLWithPath: "/tmp/w"),
            shellAllowed: false)
        // A pool spawn adds --subagent-pool 2 (one orchestrator + one worker);
        // --host-tools is already in AgentCommand.argv.
        let argv = AgentCommand.argv(settings: settings) + ["--subagent-pool", "2"]
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: false)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pool-\(UUID().uuidString)")
        let binary = try FakeAgentHarness.compileFake(source: source, into: dir)
        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: ["FAKE_SPEED": "0"])
        defer {
            fake.process.terminate()
            fake.process.waitUntilExit()
        }

        var parser = PoolWireParser()
        // The inbound contract (D1): the prompt is PoolPrompt-encoded. The fake
        // replays the whole capture per prompt line, so one prompt yields every
        // worker-tagged event in the fixture.
        FakeAgentHarness.writePrompt(fake, PoolPrompt(worker: .orchestrator, text: "go").encode())
        let events = try FakeAgentHarness.readPoolEvents(fake, parser: &parser) { es in
            es.contains { $0.worker.rawValue == 1 }
        }
        // The dispatch request is on worker 0; the worker's turn is worker 1.
        let hasDispatch = events.contains { ev in
            if ev.worker == .orchestrator, case .toolRequest(_, let name, _) = ev.event { return name == "dispatch" }
            return false
        }
        #expect(hasDispatch)
        let workerEvents = events.filter { $0.worker == WorkerId(1) }
        #expect(!workerEvents.isEmpty)
    }

    @Test func kvReaderSkipsThe48ByteHeader() throws {
        // A synthetic .kv: 48 header bytes, then rendered UTF-8 text.
        var bytes = Data(repeating: 0x41, count: 48)   // header (garbage, ignored)
        let body = Data("hello conversation".utf8)
        bytes.append(body)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.kv")
        try bytes.write(to: url)
        let text = try PoolEngine.readKVText(url)
        #expect(text == "hello conversation")
    }
}
