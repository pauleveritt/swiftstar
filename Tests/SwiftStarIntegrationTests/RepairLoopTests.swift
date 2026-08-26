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
        HandoffPacket(taskText: "fix it", writableFiles: ["a.txt"], validationCommand: "true",
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

    /// A throw from `runPhase` (an infrastructure-style failure, per its own
    /// doc comment) must still discard the already-prepared disposable
    /// worktree before propagating — otherwise the worktree directory and its
    /// throwaway branch leak on disk. Regression test for that gap.
    private struct BoomError: Error {}

    @Test func runPhaseThrowDiscardsWorktree() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        var capturedWorktreeURL: URL?
        #expect(throws: BoomError.self) {
            _ = try RepairLoop.run(
                repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
                packetBuilder: { _ in self.authoredPacket() },
                runPhase: { _, wt, _ in
                    capturedWorktreeURL = wt
                    throw BoomError()
                },
                grade: self.gradingScheme())
        }
        let url = try #require(capturedWorktreeURL)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    /// A `writableFiles` entry that no phase ever created must still show up in
    /// the assembled evidence, explicitly marked as absent — not silently
    /// omitted, which would be indistinguishable from "unchanged/fine" to the
    /// model reading the rendered packet.
    @Test func missingWritableFileGetsExplicitMarkerInEvidence() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packetWithMissingFile = HandoffPacket(
            taskText: "fix it", writableFiles: ["a.txt", "never_created.py"], validationCommand: "true",
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            role: .repair, sampling: SamplingPolicy(think: .off))
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in packetWithMissingFile },
            runPhase: { _, wt, _ in
                // Only ever touches a.txt; never_created.py is never written.
                try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme())
        guard case .passed = result else { Issue.record("expected passed, got \(result)"); return }
    }

    @Test func missingWritableFileMarkerAppearsInCapturedPacket() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let cap = FileManager.default.temporaryDirectory.appendingPathComponent("repairloop-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cap) }
        let packetWithMissingFile = HandoffPacket(
            taskText: "fix it", writableFiles: ["a.txt", "never_created.py"], validationCommand: "true",
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            role: .repair, sampling: SamplingPolicy(think: .off))
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in packetWithMissingFile },
            runPhase: { _, wt, _ in
                try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme(), captureDir: cap)
        guard case .passed = result else { Issue.record("expected passed, got \(result)"); return }
        let packetFile = cap.appendingPathComponent("repair-packet-1.json")
        let data = try Data(contentsOf: packetFile)
        let packet = try JSONDecoder().decode(HandoffPacket.self, from: data)
        #expect(packet.taskText.contains("=== never_created.py ==="))
        #expect(packet.taskText.contains("(file does not exist in this worktree)"))
    }

    /// A `writableFiles` entry that contains binary data (not valid UTF-8) must
    /// show up in the assembled evidence with a marker indicating it exists but
    /// cannot be decoded — not the "does not exist" marker which would be wrong.
    @Test func undecodableFileGetsExplicitMarkerInEvidence() throws {
        // Create a repo with an existing binary file in the base commit.
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // Add invalid UTF-8 binary file to the repo.
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
        try invalidUTF8.write(to: repo.appendingPathComponent("binary.bin"))
        _ = try git(repo, ["add", "binary.bin"])
        _ = try git(repo, ["commit", "-m", "add binary file"])

        let cap = FileManager.default.temporaryDirectory.appendingPathComponent("repairloop-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cap) }
        let packetWithUndecodableFile = HandoffPacket(
            taskText: "fix it", writableFiles: ["a.txt", "binary.bin"], validationCommand: "true",
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            role: .repair, sampling: SamplingPolicy(think: .off))
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in packetWithUndecodableFile },
            runPhase: { _, wt, _ in
                // Fix a.txt so the grade passes.
                try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme(), captureDir: cap)
        guard case .passed = result else { Issue.record("expected passed, got \(result)"); return }
        let packetFile = cap.appendingPathComponent("repair-packet-1.json")
        let data = try Data(contentsOf: packetFile)
        let packet = try JSONDecoder().decode(HandoffPacket.self, from: data)
        #expect(packet.taskText.contains("=== binary.bin ==="))
        #expect(packet.taskText.contains("(file exists but is not valid UTF-8 — cannot be shown as text)"))
    }

    /// A text-contract packet whose writable file already exceeds `fileCap`
    /// in the worktree must short-circuit to `.exhausted(... .contractNotFollowed)`
    /// WITHOUT invoking `runPhase` — the cap guard refuses to ship a truncated
    /// view that a text-only repair would re-emit truncated and overwrite a
    /// good copy. `runPhase` throwing if called proves the guard short-circuits.
    private struct PhaseMustNotRunError: Error {}

    @Test func textContractCapGuardShortCircuitsBeforeRunPhase() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // a.txt is seeded with "seed\n" (5 bytes); a `fileCap` below that
        // trips the cap guard before any phase runs.
        let textContractPacket = HandoffPacket(
            taskText: "fix it", writableFiles: ["a.txt"], validationCommand: "true",
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            textContract: true, role: .repair, sampling: SamplingPolicy(think: .off))
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in textContractPacket },
            runPhase: { _, _, _ in
                // The cap guard must short-circuit before dispatch; reaching
                // here means it did not.
                throw PhaseMustNotRunError()
            },
            grade: gradingScheme(),
            fileCap: 4)
        guard case .exhausted(_, let receipt) = result else {
            Issue.record("expected exhausted, got \(result)"); return
        }
        #expect(receipt == .contractNotFollowed)
    }

    /// A `.validationFailed` receipt carries real new evidence (the round's own
    /// candidate broke the import check) even though it produced no committed
    /// candidate ref. Unlike other receipts, it must NOT end the loop
    /// immediately — it should refresh `lastGrade` from the real validation
    /// output and let the existing round budget continue.
    @Test func validationFailedReceiptRetriesWithFreshEvidence() throws {
        let repo = try makeRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let cap = FileManager.default.temporaryDirectory.appendingPathComponent("repairloop-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: cap, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cap) }
        let calls = LockedCounter()
        let packetWithMarkerCheck = HandoffPacket(
            taskText: "fix it", writableFiles: ["a.txt"], validationCommand: "test -f marker.txt",
            baselines: [:], turnBudget: 1000, toolCallBudget: 8,
            role: .repair, sampling: SamplingPolicy(think: .off))
        let result = try RepairLoop.run(
            repo: repo, failedRef: "HEAD", initialGrade: GradeResult(exit: 1, output: "fail"),
            packetBuilder: { _ in packetWithMarkerCheck },
            runPhase: { _, wt, _ in
                calls.increment()
                if calls.value == 1 {
                    // Round 1: mutate a.txt but don't create marker.txt ->
                    // validation fails -> .receipt(.validationFailed).
                    try "still broken\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                } else {
                    // Round 2: mutate a.txt AND create marker.txt -> validation
                    // passes -> .candidate.
                    try "fixed\n".write(to: wt.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
                    try "".write(to: wt.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
                }
                return self.outcome(mutations: ["a.txt"])
            },
            grade: gradingScheme(), captureDir: cap)
        guard case .passed = result else { Issue.record("expected passed, got \(result)"); return }
        #expect(calls.value == 2)

        // The receipt-then-candidate sequence proves round 1 hit
        // .validationFailed and round 2 actually produced a committed
        // candidate — the strongest available proof the retry ran on fresh
        // evidence rather than coincidentally looping.
        let round1 = try JSONDecoder().decode(
            RepairLoop.RoundRecord.self,
            from: Data(contentsOf: cap.appendingPathComponent("repair-round-1.json")))
        guard case .validationFailed = round1.receipt else {
            Issue.record("expected round 1 receipt to be .validationFailed, got \(String(describing: round1.receipt))")
            return
        }
        #expect(round1.candidateRef == nil)

        let round2 = try JSONDecoder().decode(
            RepairLoop.RoundRecord.self,
            from: Data(contentsOf: cap.appendingPathComponent("repair-round-2.json")))
        #expect(round2.candidateRef != nil)
    }

    /// A non-`validationFailed` receipt (e.g. `.noChanges`, from an empty
    /// `mutations` array) must still exit immediately with exactly one
    /// `runPhase` call — this fix must not change behavior for other receipt
    /// types. Companion to `receiptEndsTheLoopImmediately`, which already
    /// exercises this path; kept here to spell out the intent explicitly.
    @Test func nonValidationFailedReceiptStillEndsLoopImmediately() throws {
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
