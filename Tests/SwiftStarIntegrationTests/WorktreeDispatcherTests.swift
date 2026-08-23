import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

/// P10 WorktreeDispatcher integration tests (design D2/D3/D4).
///
/// `dispatch` creates a disposable git worktree on a throwaway branch, reads
/// each writableFile's `FileBaseline` from the worktree, runs the packet's
/// validation command when set, and commits the diff to the throwaway branch
/// when the pure verdict returns a candidate — else a typed receipt. The
/// caller's tree is never touched; the worktree is removed on completion or
/// failure.
///
/// Env-guarded: run via `just integration`
/// (`SWIFTSTAR_INTEGRATION=1 swift test`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct WorktreeDispatcherTests {

    // MARK: - a small fixture git repo (git init + a seed commit)

    /// Build a temp git repo with one seed commit containing `a.txt`, so the
    /// worktree dispatch has a real HEAD to branch from and a real file to
    /// baseline. `git` runs via `/usr/bin/git` (the same binary AgentController
    /// resolves); the repo config gets a test identity so `git commit` works
    /// without inheriting the user's global config.
    private func makeFixtureRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-dispatch-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try git(repo, ["init"])
        _ = try git(repo, ["config", "user.email", "swiftstar@test.local"])
        _ = try git(repo, ["config", "user.name", "SwiftStar Test"])
        try "seed\n".write(to: repo.appendingPathComponent("a.txt"),
                           atomically: true, encoding: .utf8)
        _ = try git(repo, ["add", "a.txt"])
        _ = try git(repo, ["commit", "-m", "seed"])
        return repo
    }

    /// A clean `TurnOutcome` whose `mutations` list the attempt wrote.
    private func outcome(mutations: [String], task: String = "edit a.txt",
                         toolCalls: Int = 1) -> TurnOutcome {
        let calls = (0..<toolCalls).map { _ in
            ToolCallOutcome(name: "write", transitions: [.emitted, .executed])
        }
        var oc = TurnOutcome(model: "m", build: "b", sampler: "s", task: task,
                             generatedTokens: 5, ctxUsed: 10,
                             stopReason: .eos, toolCalls: calls)
        oc.mutations = mutations
        return oc
    }

    /// Run `git -C <dir> <args>`, returning stdout. Throws on non-zero exit.
    private func git(_ dir: URL, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        p.waitUntilExit()
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let errorOutput = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                 encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "WorktreeDispatcherTests.git", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: output + errorOutput])
        }
        return output
    }

    // MARK: - the happy path: an allowed mutation commits a candidate ref

    @Test func candidateCommitsAllowedMutation() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }

        guard case .candidate(let ref, let carried) = outcome else {
            Issue.record("expected candidate for an in-bounds mutation"); return
        }
        #expect(!ref.isEmpty, "candidate ref must be a non-empty SHA")
        // Evidence floor: the ref is a real commit that resolves in the repo.
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved == ref, "candidate ref must resolve via git rev-parse")
        // The commit changed a.txt (the allowed file).
        let show = try git(repo, ["show", "--stat", "--name-only", ref])
        #expect(show.contains("a.txt"))
        // D4: the candidate carries the P9 TurnOutcome as evidence.
        #expect(carried.mutations == ["a.txt"])
    }

    @Test func candidateCommitResolvesFromOutsideTheWorktree() throws {
        // The worktree is removed by dispatch; the candidate ref must still
        // resolve in the parent repo (the commit object survives the
        // worktree's removal — the parent reviews the ref, not the worktree).
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { wt in
            try "second\n".write(to: wt.appendingPathComponent("a.txt"),
                                 atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(let ref, _) = outcome else {
            Issue.record("expected candidate"); return
        }
        // The worktree dir is gone.
        // (dispatch removes it; nothing to assert beyond the ref resolving.)
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved == ref)
    }

    // MARK: - revision check: a mutation outside writableFiles is a receipt

    @Test func mutationOutsideWritableFilesYieldsReceipt() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { wt in
            try "outside\n".write(to: wt.appendingPathComponent("outside.txt"),
                                 atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["outside.txt"])
        }
        guard case .receipt(.refusedTool(let path)) = outcome else {
            Issue.record("expected refusedTool for an out-of-bounds mutation"); return
        }
        #expect(path == "outside.txt")
    }

    // MARK: - validation: a failing validation yields a receipt with exit+digest

    @Test func validationFailedYieldsReceiptWithExitAndDigest() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: "false",
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .receipt(.validationFailed(let exit, let digest)) = outcome else {
            Issue.record("expected validationFailed"); return
        }
        #expect(exit != 0)
        #expect(!digest.isEmpty)
    }

    @Test func validationPassedYieldsCandidate() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: "true",
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(let ref, _) = outcome else {
            Issue.record("expected candidate when validation passed"); return
        }
        #expect(!ref.isEmpty)
    }

    // MARK: - no changes: nothing mutated -> nothing to commit -> receipt

    @Test func noMutationsYieldNoChangesReceipt() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _ in
            self.outcome(mutations: [], toolCalls: 0)
        }
        guard case .receipt(.noChanges) = outcome else {
            Issue.record("expected noChanges when nothing was mutated"); return
        }
    }

    // MARK: - evidence floor: baselines are read from the worktree

    @Test func baselineReadFromWorktreeDiffersAfterChange() throws {
        // A baseline read from the worktree (sha256 via `git hash-object`, mode
        // via `git ls-files -s`, line ending by scanning bytes) differs from the
        // post-mutation hash — the parent can detect drift a candidate
        // introduces on a file it was allowed to touch.
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let baseline = try WorktreeDispatcher.readBaseline(for: "a.txt", in: repo)
        #expect(!baseline.sha256.isEmpty)
        #expect(baseline.mode == 0o644, "mode is the permission bits (0o644)")
        #expect(baseline.lineEnding == .lf)

        // Change the file; the new sha differs from the baseline.
        try "changed\n".write(to: repo.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)
        let after = try WorktreeDispatcher.readBaseline(for: "a.txt", in: repo)
        #expect(after.sha256 != baseline.sha256)
        #expect(after.mode == baseline.mode, "mode is unchanged by a content edit")
    }

    @Test func baselineClassifiesCrlfLineEnding() throws {
        // The line-ending classification scans the file's bytes: a CRLF file
        // reads as `.crlf`; a mixed file (CRLF + lone LF) reads as `.mixed`.
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let crlf = repo.appendingPathComponent("crlf.txt")
        try "line1\r\nline2\r\n".write(to: crlf, atomically: true, encoding: .utf8)
        _ = try git(repo, ["add", "crlf.txt"])
        _ = try git(repo, ["commit", "-m", "crlf seed"])
        let baseline = try WorktreeDispatcher.readBaseline(for: "crlf.txt", in: repo)
        #expect(baseline.lineEnding == .crlf)
    }
}
