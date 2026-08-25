import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct RepairLoopTests {

    private func makeRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("repairloop-\(UUID().uuidString)")
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
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw NSError(domain: "git", code: Int(p.terminationStatus)) }
        return output
    }

    private func authoredPacket() -> HandoffPacket {
        HandoffPacket(taskText: "fix it", writableFiles: ["a.txt"], validationCommand: nil,
                      baselines: [:], turnBudget: 1000, toolCallBudget: 8,
                      role: .repair, sampling: SamplingPolicy(think: .off))
    }

    private func outcome(mutations: [String], stop: TurnStopReason = .eos) -> TurnOutcome {
        var o = TurnOutcome(model: "m", build: "b", sampler: "s", task: "t",
                            generatedTokens: 5, ctxUsed: 10, stopReason: stop,
                            toolCalls: [ToolCallOutcome(name: "write", transitions: [.emitted, .executed])])
        o.mutations = mutations
        return o
    }

    /// A grade that passes only when the worktree's a.txt holds `fixed\n`.
    private func gradingScheme() -> (URL) throws -> GradeResult {
        { wt in
            let content = (try? String(contentsOf: wt.appendingPathComponent("a.txt"), encoding: .utf8)) ?? ""
            return GradeResult(exit: content == "fixed\n" ? 0 : 1, output: content)
        }
    }

    @Test func passesOnFirstCandidate() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in self.authoredPacket() },
            runPhase: { _, wt, _ in
                try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme())
        guard case .passed(let ref, let grade, _) = result else {
            Issue.record("expected passed, got \(result)"); return
        }
        #expect(!ref.isEmpty)
        #expect(grade.exit == 0)
    }

    @Test func retriesAfterCandidateStillFails() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let calls = LockedCounter()
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in self.authoredPacket() },
            runPhase: { _, wt, _ in
                calls.increment()
                let content = calls.value == 1 ? "broken\n" : "fixed\n"
                try content.write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme())
        guard case .passed = result else { Issue.record("expected passed"); return }
        #expect(calls.value == 2)
    }

    @Test func exhaustsAfterTwoCandidateRounds() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in self.authoredPacket() },
            runPhase: { _, wt, _ in
                try "broken\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme())
        guard case .exhausted(let lastGrade, let receipt) = result else {
            Issue.record("expected exhausted"); return
        }
        #expect(receipt == .repairExhausted)
        #expect(lastGrade?.passed == false)
    }

    @Test func receiptEndsTheLoopImmediately() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let calls = LockedCounter()
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in self.authoredPacket() },
            runPhase: { _, _, _ in
                calls.increment()
                return self.outcome(mutations: [])   // noChanges
            },
            grade: gradingScheme())
        guard case .exhausted(_, let receipt) = result else { Issue.record("expected exhausted"); return }
        #expect(receipt == .noChanges)
        #expect(calls.value == 1)
    }

    @Test func sessionExhaustionThrows() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        #expect(throws: RepairLoopError.self) {
            _ = try RepairLoop.run(
                repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
                packetBuilder: { _ in self.authoredPacket() },
                runPhase: { _, _, _ in self.outcome(mutations: [], stop: .limit) },
                grade: self.gradingScheme())
        }
    }

    @Test func writesPerRoundCapture() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let cap = FileManager.default.temporaryDirectory.appendingPathComponent("repairloop-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cap) }
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in self.authoredPacket() },
            runPhase: { _, wt, _ in
                try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme(), captureDir: cap)
        guard case .passed = result else { Issue.record("expected passed"); return }
        let packetFile = cap.appendingPathComponent("repair-packet-1.json")
        #expect(FileManager.default.fileExists(atPath: packetFile.path))
        let data = try Data(contentsOf: packetFile)
        let packet = try JSONDecoder().decode(HandoffPacket.self, from: data)
        #expect(packet.taskText.contains("Failure evidence (machine output)"))
    }
}

/// A tiny thread-safe counter for the scripted fakes above.
final class LockedCounter: @unchecked Sendable {
    private var n = 0
    private let lock = NSLock()
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
