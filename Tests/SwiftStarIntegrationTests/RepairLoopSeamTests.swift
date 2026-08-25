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
}
