import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

/// P11 addendum D3: WorktreeTransaction chains phases across worktrees branched
/// from the prior commit, keeps the final worktree for grading, and discards
/// intermediates on commitBack. Env-guarded (integration tier).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct WorktreeTransactionTests {

    private func makeFixtureRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("agenttest-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try git(repo, ["init"])
        _ = try git(repo, ["config", "user.email", "swiftstar@test.local"])
        _ = try git(repo, ["config", "user.name", "SwiftStar Test"])
        try "seed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try git(repo, ["add", "a.txt"])
        _ = try git(repo, ["commit", "-m", "seed"])
        return repo
    }

    private func git(_ dir: URL, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw NSError(domain: "git", code: Int(p.terminationStatus)) }
        return output
    }

    private func packet(_ files: [String], task: String) -> HandoffPacket {
        HandoffPacket(taskText: task, writableFiles: files, validationCommand: nil,
                      baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    }

    private func outcome(mutations: [String]) -> TurnOutcome {
        var oc = TurnOutcome(model: "m", build: "b", sampler: "s", task: "t",
                             generatedTokens: 5, ctxUsed: 10, stopReason: .eos,
                             toolCalls: [ToolCallOutcome(name: "write", transitions: [.emitted, .executed])])
        oc.mutations = mutations
        return oc
    }

    @Test func phasesChainAndKeepFinalWorktreeForGrading() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let txn = WorktreeTransaction(repo: repo)

        let p1 = packet(["a.txt"], task: "phase 1")
        let wt1 = try txn.preparePhase(packet: p1)
        try "one\n".write(to: wt1.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        guard case .candidate = try txn.finalizePhase(wt1, packet: p1, turnOutcome: outcome(mutations: ["a.txt"]), validation: nil) else {
            Issue.record("phase 1 must be a candidate"); return
        }

        let p2 = packet(["b.txt"], task: "phase 2")
        let wt2 = try txn.preparePhase(packet: p2)
        // Phase 2's checkout already contains phase 1's committed change.
        #expect(try String(contentsOf: wt2.url.appendingPathComponent("a.txt"), encoding: .utf8) == "one\n")
        try "two\n".write(to: wt2.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        _ = try txn.finalizePhase(wt2, packet: p2, turnOutcome: outcome(mutations: ["b.txt"]), validation: nil)

        guard let ref = txn.commitBack() else { Issue.record("commitBack must return the final ref"); return }
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
        // The final worktree survives for grading; the intermediate wt1 is gone.
        let gradeWT = try #require(txn.finalWorktree)
        #expect(FileManager.default.fileExists(atPath: gradeWT.url.appendingPathComponent("b.txt").path))
        #expect(!FileManager.default.fileExists(atPath: wt1.url.path))
        let show = try git(repo, ["show", "--stat", "--name-only", ref])
        #expect(show.contains("b.txt"))
        // The final tree carries BOTH phases: a.txt (phase 1) and b.txt (phase 2).
        #expect(try git(repo, ["show", "\(ref):a.txt"]) == "one\n")
        #expect(try git(repo, ["show", "\(ref):b.txt"]) == "two\n")
        #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "seed\n")

        txn.discardFinal()
        #expect(!FileManager.default.fileExists(atPath: gradeWT.url.path))
    }

    @Test func writeFileCreatesParentDirs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try WorktreeDispatcher.writeFile("x = 1", to: "templates/base.html", in: dir)
        let url = dir.appendingPathComponent("templates/base.html")
        #expect(try String(contentsOf: url, encoding: .utf8) == "x = 1")
    }

    @Test func receiptStopsTheTransaction() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let txn = WorktreeTransaction(repo: repo)

        let p1 = packet(["a.txt"], task: "phase 1")
        let wt1 = try txn.preparePhase(packet: p1)
        try "one\n".write(to: wt1.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        // No mutations recorded -> the pure verdict returns .noChanges receipt.
        let r1 = try txn.finalizePhase(wt1, packet: p1, turnOutcome: outcome(mutations: []), validation: nil)
        guard case .receipt = r1 else { Issue.record("expected a receipt"); return }
        #expect(txn.candidateRef == nil)
        #expect(txn.finalWorktree == nil)
        _ = txn.commitBack()  // discards the failed phase's worktree
        #expect(!FileManager.default.fileExists(atPath: wt1.url.path))
    }
}
