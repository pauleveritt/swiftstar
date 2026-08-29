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
        let argv = PoolEngine.argv(settings: settings, workers: 3)

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

    /// P23 review follow-up: `runPhase` never sends a `think` field on the
    /// wire — `PoolPrompt` there carries no override (Task 10 did add
    /// `--per-turn-think` to the shared argv, so the engine advertises the
    /// cap, but the harness's send is still unwired) — so the recorded
    /// outcome must not claim one happened. Before this fix, a packet's declared `.on`
    /// (mapping to `.high`) was recorded verbatim in `outcome.sampler` while
    /// the wire silently ran the harness's fixed default: a capture-integrity
    /// lie identical in kind to the one this phase exists to retire.
    @Test func runPhaseRecordsDefaultThinkRegardlessOfPacketSampling() throws {
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
        let argv = PoolEngine.argv(settings: settings, workers: 3)

        let capture = try Data(contentsOf: FakeAgentHarness.fixture("pool.ndjson"))
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: false)
        let binary = try FakeAgentHarness.compileFake(source: source, into: fakeDir)
        try FileManager.default.moveItem(at: binary, to: fakeDir.appendingPathComponent("ds4-agent"))

        let orch = try PoolOrchestrator(settings: settings)
        defer { orch.stop() }

        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: worktree) }

        let packet = HandoffPacket(
            taskText: "do the thing", writableFiles: [], validationCommand: nil,
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            sampling: SamplingPolicy(think: .on))
        let outcome = try orch.runPhase(worker: WorkerId(1), packet: packet, worktree: worktree)
        #expect(outcome.sampler == "think=default")
    }
}
