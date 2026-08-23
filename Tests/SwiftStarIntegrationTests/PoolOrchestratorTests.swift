import Testing
import Foundation
import SwiftStarKit
@testable import SwiftStarAppKit

/// P11 addendum D7: PoolOrchestrator runs one phase against the pooled wire,
/// routing worker-tagged events and returning the worker's turn outcome.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct PoolOrchestratorTests {

    @Test func runPhaseReturnsWorkerTurnOutcome() throws {
        let fakeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-fake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeDir) }

        let settings = AgentSettings(
            engineDir: fakeDir,
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 16384,
            workspace: URL(fileURLWithPath: "/tmp/w"),
            shellAllowed: false)
        let argv = AgentCommand.argv(settings: settings) + ["--subagent-pool", "2"]

        let capture = try Data(contentsOf: FakeAgentHarness.fixture("pool.ndjson"))
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: false)
        let binary = try FakeAgentHarness.compileFake(source: source, into: fakeDir)
        // The orchestrator resolves the binary at engineDir/ds4-agent.
        try FileManager.default.moveItem(at: binary, to: fakeDir.appendingPathComponent("ds4-agent"))

        let orch = try PoolOrchestrator(settings: settings)
        defer { orch.stop() }

        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }

        let packet = HandoffPacket(
            taskText: "do the thing", writableFiles: [], validationCommand: nil,
            baselines: [:], turnBudget: 1000, toolCallBudget: 8)
        let outcome = try orch.runPhase(worker: WorkerId(1), packet: packet, worktree: worktree)
        #expect(outcome.stopReason == .eos)
    }
}
