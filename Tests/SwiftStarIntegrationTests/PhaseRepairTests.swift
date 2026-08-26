import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

/// P12.8 (D4): PhaseRepair turns a validation-failed phase into a repaired
/// result — commitForRepair + RepairLoop.run (grade = always-pass) — with a
/// fake runPhase so no model is involved. Env-guarded (integration tier).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct PhaseRepairTests {

    private func makeFixtureRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ a: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + a
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["config", "user.email", "t@t"]); git(["config", "user.name", "t"])
        try "seed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "a.txt"]); git(["commit", "-q", "-m", "seed"])
        return repo
    }

    @Test func repairsAValidationFailedPhaseWhenTheFakeTurnFixesIt() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packet = HandoffPacket(
            taskText: "fix a.txt", writableFiles: ["a.txt"], validationCommand: "true",
            baselines: [:], turnBudget: 100, toolCallBudget: 5,
            textContract: true, role: .repair, sampling: SamplingPolicy())
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }
        try "broken\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)

        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { _, _, _ in
            // Text-contract turn: a labeled block the host harvests and writes.
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.text = "#a.txt\n```\nfixed\n\n```\n"
            return o
        }
        let packetBuilder: (RepairContext) throws -> HandoffPacket = { _ in packet }

        let result = try PhaseRepair.run(
            repo: repo, failedWorktree: worktree, packet: packet,
            validation: ValidationResult(exit: 1, digest: "sha256:x", output: "ImportError"),
            packetBuilder: packetBuilder, runPhase: runPhase)

        guard case .repaired(let ref, let repairedWT) = result else {
            Issue.record("expected .repaired, got \(result)"); return
        }
        defer { WorktreeDispatcher.discard(repairedWT, in: repo) }
        #expect(try String(contentsOf: repairedWT.url.appendingPathComponent("a.txt"),
                           encoding: .utf8) == "fixed\n")
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
    }

    @Test func exhaustsWhenTheRepairTurnStillFailsValidation() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packet = HandoffPacket(
            taskText: "fix a.txt", writableFiles: ["a.txt"], validationCommand: "false",
            baselines: [:], turnBudget: 100, toolCallBudget: 5)
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }
        try "broken\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)

        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { _, _, _ in
            // Mutated, but the content still fails validation.
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.mutations = ["a.txt"]
            return o
        }
        let packetBuilder: (RepairContext) throws -> HandoffPacket = { _ in packet }

        let result = try PhaseRepair.run(
            repo: repo, failedWorktree: worktree, packet: packet,
            validation: ValidationResult(exit: 1, digest: "sha256:x", output: "ImportError"),
            packetBuilder: packetBuilder, runPhase: runPhase)

        // Track 3A (P12): `.validationFailed` carries new evidence (a fresh
        // traceback), so RepairLoop no longer exits on the first occurrence —
        // it spends the round budget retrying instead. `validationCommand:
        // "false"` fails deterministically every round, so both rounds hit
        // `.validationFailed`, and the loop falls through its round budget to
        // `.repairExhausted` rather than surfacing the per-round receipt.
        guard case .exhausted(let receipt) = result else {
            Issue.record("expected .exhausted, got \(result)"); return
        }
        #expect(receipt == .repairExhausted)
    }
}
