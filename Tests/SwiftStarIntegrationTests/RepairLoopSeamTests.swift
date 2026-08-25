import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct RepairLoopSeamTests {

    /// Fake-tier seam test (spec Verification #5): the text-contract repair
    /// path must work end-to-end with NO model. A fake `runPhase` returns a
    /// text-only `TurnOutcome` whose `text` is a labeled block; `RepairLoop.run`
    /// harvests it, writes it, and the host-side `grade` returns `.passed`.
    @Test func textContractSeamWritesHarvestedBlockAndGradesPassed() throws {
        // temp repo with a failing app.py
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("seam-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        func git(_ a: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + a
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["config", "user.email", "t@t"]); git(["config", "user.name", "t"])
        try "broken\n".write(to: repo.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
        git(["add", "app.py"]); git(["commit", "-q", "-m", "seed"])

        let failedRef = "HEAD"

        // fake runPhase: returns a text-only turn with a labeled block whose
        // body is "fixed\n" (a blank line before the closing fence preserves the
        // trailing newline through LabeledBlockParser's line-join).
        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { _, _, _ in
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.text = "#app.py\n```\nfixed\n\n```\n"
            return o
        }

        let packetBuilder: (RepairContext) throws -> HandoffPacket = { ctx in
            HandoffPacket(taskText: "fix app.py", writableFiles: ["app.py"],
                          validationCommand: "true",
                          baselines: [:],
                          turnBudget: 100, toolCallBudget: 5,
                          textContract: true,
                          role: .repair,
                          sampling: SamplingPolicy())
        }

        let grade: (URL) throws -> GradeResult = { wt in
            let content = (try? String(contentsOf: wt.appendingPathComponent("app.py"), encoding: .utf8)) ?? ""
            return GradeResult(exit: content == "fixed\n" ? 0 : 1, output: content)
        }

        let outcome = try RepairLoop.run(repo: repo, failedRef: failedRef,
                                         initialGrade: GradeResult(exit: 1, output: ""),
                                         packetBuilder: packetBuilder,
                                         runPhase: runPhase, grade: grade)
        guard case .passed = outcome else {
            Issue.record("expected .passed, got \(outcome)")
            return
        }
    }

    /// Two-turn emission protocol. Measured 2026-08-25 across three live repair
    /// runs: Mellum reasons *or* emits, never both in one turn. Prose allowed ->
    /// correct diagnosis, then eos at the moment it should write the file
    /// (captures 20260825-160310, -164557). Prose forbidden -> perfect emission
    /// of a byte-identical *broken* file, because nothing was generated to
    /// deviate from the copy sitting in context (capture 20260825-163139).
    ///
    /// So the host asks twice on the same pooled worker session: turn 1 reasons
    /// and stops; turn 2 is a short follow-up that only has to emit. This test
    /// pins the seam with no model: turn 1 returns prose with no labeled block,
    /// turn 2 returns the block, and the round must still reach `.passed`
    /// instead of bailing out with `.contractNotFollowed` on turn 1.
    @Test func emissionFollowUpTurnHarvestsAfterAProseOnlyFirstTurn() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("seam-followup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repo) }
        func git(_ a: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + a
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["config", "user.email", "t@t"]); git(["config", "user.name", "t"])
        try "broken\n".write(to: repo.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
        git(["add", "app.py"]); git(["commit", "-q", "-m", "seed"])

        // Turn 1 narrates and stops at the act boundary (the live failure mode);
        // turn 2 — driven by the follow-up text — emits the block.
        let followUp = "EMIT NOW"
        var seenTasks: [String] = []
        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { pkt, _, _ in
            seenTasks.append(pkt.taskText)
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: pkt.taskText,
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.text = pkt.taskText == followUp
                ? "#app.py\n```\nfixed\n\n```\n"
                : "The failure is a 307/303 mismatch. Now I will write the file:"
            return o
        }

        let packetBuilder: (RepairContext) throws -> HandoffPacket = { _ in
            HandoffPacket(taskText: "fix app.py", writableFiles: ["app.py"],
                          validationCommand: "true",
                          baselines: [:],
                          turnBudget: 100, toolCallBudget: 5,
                          textContract: true,
                          role: .repair,
                          sampling: SamplingPolicy())
        }

        let grade: (URL) throws -> GradeResult = { wt in
            let content = (try? String(contentsOf: wt.appendingPathComponent("app.py"), encoding: .utf8)) ?? ""
            return GradeResult(exit: content == "fixed\n" ? 0 : 1, output: content)
        }

        let outcome = try RepairLoop.run(repo: repo, failedRef: "HEAD",
                                         initialGrade: GradeResult(exit: 1, output: ""),
                                         packetBuilder: packetBuilder,
                                         runPhase: runPhase, grade: grade,
                                         emissionFollowUp: followUp)
        guard case .passed = outcome else {
            Issue.record("expected .passed, got \(outcome)")
            return
        }
        #expect(seenTasks.count == 2)
        #expect(seenTasks.last == followUp)
    }
}
