import Testing
import Foundation
import CryptoKit
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

    /// The lowercase hex SHA-256 of `data` (CryptoKit), the reference digest
    /// `FileBaseline.sha256` must equal — independent of `git hash-object`.
    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    // P11: the async pooled path — prepare a worktree, mutate it, finalize to a
    // candidate ref, discard; the caller's tree is never touched.
    @Test func prepareFinalizeDiscardIsolatesTheCallerTree() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)

        // The scripted worker mutates the worktree's a.txt.
        try "candidate\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                                atomically: true, encoding: .utf8)
        // The caller's tree is untouched.
        let caller = try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(caller == "seed\n", "the caller's a.txt must be unchanged")

        let result = try WorktreeDispatcher.finalize(
            worktree, packet: packet, turnOutcome: outcome(mutations: ["a.txt"]),
            validation: nil, in: repo)
        guard case .candidate(let ref, _, _) = result else {
            Issue.record("expected a candidate for an in-bounds mutation"); return
        }
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved.count == 40)

        WorktreeDispatcher.discard(worktree, in: repo)
        #expect(!FileManager.default.fileExists(atPath: worktree.url.path),
                "the worktree must be removed after discard")
    }

    // MARK: - the happy path: an allowed mutation commits a candidate ref

    @Test func candidateCommitsAllowedMutation() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }

        guard case .candidate(let ref, let carried, _) = outcome else {
            Issue.record("expected candidate for an in-bounds mutation"); return
        }
        #expect(!ref.isEmpty, "candidate ref must be a non-empty namespaced ref")
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"), "candidate ref must be durable (F7)")
        // Evidence floor: the ref is a real commit that resolves in the repo.
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved.count == 40, "candidate ref must resolve to a commit SHA")
        // The commit changed a.txt (the allowed file).
        let show = try git(repo, ["show", "--stat", "--name-only", ref])
        #expect(show.contains("a.txt"))
        // D4: the candidate carries the P9 TurnOutcome as evidence.
        #expect(carried.mutations == ["a.txt"])
    }

    /// A worker can "mutate" a file by rewriting it with byte-identical content.
    /// The host records the write, so `mutations` is non-empty, but git sees no
    /// diff and `git commit` exits 1 with "nothing to commit, working tree
    /// clean". Observed in a real batch (C16 run 2: 8 mutations, then
    /// gitFailed), where it killed the run mid-transaction.
    @Test func rewritingIdenticalContentDoesNotFailTheCommit() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let head = try git(repo, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let packet = HandoffPacket(
            taskText: "rewrite a.txt with what it already says",
            writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            // Byte-identical to the seed commit.
            try "seed\n".write(to: wt.appendingPathComponent("a.txt"),
                                atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }

        guard case .candidate(let ref, _, _) = outcome else {
            Issue.record("expected a candidate, not a throw or a receipt"); return
        }
        // The tree is unchanged, so the candidate is the parent commit itself —
        // honest, and it keeps the phase chain resolvable.
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved == head, "an empty diff should resolve to the unchanged tree")
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
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            try "second\n".write(to: wt.appendingPathComponent("a.txt"),
                                 atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(let ref, _, _) = outcome else {
            Issue.record("expected candidate"); return
        }
        // The worktree dir is gone.
        // (dispatch removes it; nothing to assert beyond the ref resolving.)
        let resolved = try git(repo, ["rev-parse", ref])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved.count == 40)
    }

    @Test func candidateCommitDoesNotIncludeUntrackedBuildDir() throws {
        // FINDING 4 regression: `commitDiff` must stage only the writable files
        // (`git add -- <writableFiles>`), not `git add -A`. An untracked `.build/`
        // dir left in the worktree by the attempt (or by a build the agent ran)
        // must NOT end up in the candidate commit — only the mutated writable
        // file should be there.
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            // Mutate the writable file...
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            // ...and leave an untracked .build/ dir (the pollution `git add -A`
            // would sweep into the candidate). The fixture repo has no
            // .gitignore, so this is genuinely untracked, not ignored.
            let build = wt.appendingPathComponent(".build")
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            try "junk\n".write(to: build.appendingPathComponent("junk.txt"),
                               atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(let ref, _, _) = outcome else {
            Issue.record("expected candidate"); return
        }
        let show = try git(repo, ["show", "--stat", "--name-only", ref])
        #expect(show.contains("a.txt"), "the mutated writable file must be in the candidate")
        #expect(!show.contains(".build"),
                "an untracked .build/ dir must NOT be swept into the candidate")
    }

    @Test func relativizeAcceptsSymlinkResolvedMutationFromHostWrite() throws {
        // FINDING 1 regression: the host executor's `confinedRealPath` resolves
        // symlinks (macOS /tmp -> /private/tmp, or any symlinked worktree root),
        // so the mutation it records is the symlink-resolved absolute path.
        // `relativize` must strip against the symlink-resolved worktree root,
        // else an in-contract write under a symlinked temp dir is mis-relativized
        // to an absolute path and the verdict refuses it (an allowed mutation
        // refused).
        //
        // This mirrors the real data flow: `consent` resolves the path with
        // `standardizedFileURL` (no symlink I/O), but `executeHostTool`'s
        // `confinedRealPath` re-confines with `resolvingSymlinksInPath()` and
        // records the resolved path as the mutation. The `execute` closure
        // below replicates that exactly.

        // A real temp dir + a symlink to it (the symlinked worktree root).
        // Seed `a.txt` in the real dir first: `resolvingSymlinksInPath()` only
        // follows the symlink when the leaf exists, so this mirrors an `edit`
        // of an existing writable file (the canonical FINDING 1 scenario — the
        // host executor records the symlink-resolved mutation only when the
        // file is present to resolve).
        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "seed\n".write(to: real.appendingPathComponent("a.txt"),
                          atomically: true, encoding: .utf8)
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path,
                                                   withDestinationPath: real.path)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: real)
        }

        // The host executor's write (mirrors AgentController.executeHostTool +
        // confinedRealPath): resolve symlinks on both the workspace and the
        // file, re-confine, write, and record the symlink-resolved path as the
        // mutation.
        let resp = ToolCallbackResponder.respond(
            idx: 0, name: "write",
            params: [ToolParam(name: "path", value: "a.txt"),
                     ToolParam(name: "content", value: "candidate")],
            workspace: link, shellAllowed: false,
            writableFiles: ["a.txt"],
            execute: { req in
                guard let path = req.resolvedPath else {
                    return ToolExecutionResult(ok: false, text: "no resolved path")
                }
                let wsReal = req.workspace.resolvingSymlinksInPath()
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                guard resolved.path == wsReal.path
                    || resolved.path.hasPrefix(wsReal.path + "/") else {
                    return ToolExecutionResult(ok: false, text: "escape")
                }
                try? "candidate".write(toFile: resolved.path, atomically: true, encoding: .utf8)
                return ToolExecutionResult(ok: true, text: "wrote", mutations: [resolved.path])
            })
        #expect(resp.ok == true, "the in-contract write must be executed")
        #expect(resp.mutations.count == 1)

        // The TurnOutcome carries the symlink-resolved mutation (as the host
        // records it — absolute, through /private/...).
        var oc = TurnOutcome(model: "m", build: "b", sampler: "s", task: "write a.txt",
                             generatedTokens: 5, ctxUsed: 10, stopReason: .eos,
                             toolCalls: [ToolCallOutcome(name: "write",
                                                         transitions: [.emitted, .executed])])
        oc.mutations = resp.mutations

        // relativize + verdict: the symlink-resolved mutation must relativize
        // back to "a.txt" (matching writableFiles) and yield a candidate — not
        // a refusedTool for the absolute resolved path.
        let rel = WorktreeDispatch.relativize(outcome: oc, worktree: link)
        #expect(rel.mutations == ["a.txt"],
                "the symlink-resolved mutation must relativize to the worktree-relative form")
        let packet = HandoffPacket(taskText: "write a.txt", writableFiles: ["a.txt"],
                                   validationCommand: nil, baselines: [:],
                                   turnBudget: 10_000, toolCallBudget: 16)
        let result = WorktreeDispatch.verdict(packet: packet, allowedMutations: rel.mutations,
                                               turnOutcome: rel, validation: nil)
        guard case .candidate = result else {
            Issue.record("expected candidate; the symlink-resolved mutation was mis-relativized and refused"); return
        }
    }

    // MARK: - revision check: a mutation outside writableFiles is a receipt

    @Test func mutationOutsideWritableFilesYieldsReceipt() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
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
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
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
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(let ref, _, _) = outcome else {
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
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, _ in
            self.outcome(mutations: [], toolCalls: 0)
        }
        guard case .receipt(.noChanges) = outcome else {
            Issue.record("expected noChanges when nothing was mutated"); return
        }
    }

    // MARK: - evidence floor: baselines are read from the worktree

    @Test func baselineReadFromWorktreeDiffersAfterChange() throws {
        // A baseline read from the worktree (sha256 via CryptoKit SHA-256 of
        // the file's bytes, mode via `git ls-files -s`, line ending by scanning
        // bytes) differs from the post-mutation hash — the parent can detect
        // drift a candidate introduces on a file it was allowed to touch.
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

    @Test func baselineSha256IsTheActualSha256OfTheBytes() throws {
        // FINDING 3 regression: `FileBaseline.sha256` must hold the SHA-256 of
        // the file's bytes (CryptoKit SHA256), not `git hash-object`'s SHA-1.
        // The fixture seeds `a.txt` with `"seed\n"`; the baseline's sha256 must
        // equal the CryptoKit SHA-256 of those exact bytes (a 64-char hex), and
        // must NOT equal the git hash-object SHA-1 of the same bytes.
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let baseline = try WorktreeDispatcher.readBaseline(for: "a.txt", in: repo)
        let expected = sha256Hex(Data("seed\n".utf8))
        #expect(baseline.sha256 == expected,
                "sha256 must be the CryptoKit SHA-256 of the bytes, not git hash-object's SHA-1")
        #expect(baseline.sha256.count == 64, "SHA-256 is 64 hex chars (not SHA-1's 40)")

        // Cross-check: it must differ from the git hash-object SHA-1 of the
        // same bytes (the value the old code stored).
        let gitSha1 = try git(repo, ["hash-object", "a.txt"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(baseline.sha256 != gitSha1,
                "sha256 must not be the git hash-object SHA-1")
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

    @Test func candidateCarriesBaselinesForWritableFiles() throws {
        // FINDING 2 regression: `dispatch` reads each writableFile's baseline
        // from the worktree and must carry it into the `DispatchOutcome.candidate`
        // (D1 — the typed contract is complete), so the parent can diff the
        // candidate against the pre-attempt state of each writable file. The
        // old code read the baselines then discarded them (`_ = try? ...`),
        // leaving the candidate's baselines empty.
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        // The expected baseline is the seed state of `a.txt` (what a fresh
        // worktree checkout of HEAD holds) — read from the repo, which shares
        // the seed commit's `a.txt` bytes/mode/line-ending with the worktree.
        let expected = try WorktreeDispatcher.readBaseline(for: "a.txt", in: repo)

        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { _, wt in
            try "candidate\n".write(to: wt.appendingPathComponent("a.txt"),
                                   atomically: true, encoding: .utf8)
            return self.outcome(mutations: ["a.txt"])
        }
        guard case .candidate(_, _, let baselines) = outcome else {
            Issue.record("expected candidate"); return
        }
        let baseline = try #require(baselines["a.txt"],
                                    "candidate must carry the baseline for the writable file a.txt")
        #expect(baseline == expected,
                "the carried baseline must match a fresh readBaseline of the seed file")
        #expect(baseline.sha256 == expected.sha256)
        #expect(baseline.mode == 0o644)
        #expect(baseline.lineEnding == .lf)
    }
}
