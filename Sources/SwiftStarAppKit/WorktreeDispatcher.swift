import Foundation
import CryptoKit
import SwiftStarKit

/// The P10/P11 app-layer dispatcher (design D2/D3/D4).
///
/// `dispatch` creates a disposable git worktree on a throwaway branch, reads
/// each writableFile's `FileBaseline` from the worktree (the pre-attempt
/// state), runs the packet's `validationCommand` parent-side when set, and
/// commits the worktree's diff when the pure `WorktreeDispatch.verdict` returns
/// a candidate — filling the ref — else it returns the typed `Receipt` the
/// verdict produced. The caller's tree is never touched; the worktree is
/// removed on completion or failure.
///
/// For P11's pooled workers — whose turn is *asynchronous* (the pooled engine's
/// wire is drained by the app, not by a synchronous `attempt` closure) — the
/// same machinery is exposed as `prepare`/`finalize`/`discard`, so a pooled
/// worker runs inside its own disposable worktree exactly like a P10 attempt.
/// The caller runs the turn in `Worktree.url`, calls `finalize` with the host
/// facts, then `discard`.
public enum WorktreeDispatcher {

    /// A prepared disposable worktree for one attempt (P11): its URL, its
    /// throwaway branch, the namespaced candidate ref, and the per-file
    /// baselines read from the worktree at prepare time.
    public struct Worktree: Sendable {
        public let url: URL
        public let branch: String
        public let candidateRefName: String
        public var baselines: [String: FileBaseline]
    }

    /// Create a disposable worktree on a throwaway branch and read each
    /// writableFile's baseline from it (D1/D2). When `baseRef` is set, the
    /// worktree is branched from that commit instead of `HEAD` (P11 addendum D3:
    /// a transaction chains phases). The caller runs the attempt in
    /// `worktree.url`, then calls `finalize` and `discard`.
    public static func prepare(packet: HandoffPacket, in repo: URL,
                               baseRef: String? = nil) throws -> Worktree {
        let branch = "swiftstar-dispatch-\(UUID().uuidString)"
        let candidateRefName = "refs/swiftstar/candidates/\(UUID().uuidString)"
        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-wt-\(UUID().uuidString)")

        // `git worktree add -b <branch> <path> [<commit-ish>]` branches from
        // <commit-ish> (default HEAD) and checks the worktree out on it.
        if let baseRef {
            _ = try git(repo, ["worktree", "add", "-b", branch, worktree.path, baseRef])
        } else {
            _ = try git(repo, ["worktree", "add", "-b", branch, worktree.path])
        }

        var baselines: [String: FileBaseline] = [:]
        for path in packet.writableFiles {
            if let baseline = try? readBaseline(for: path, in: worktree) {
                baselines[path] = baseline
            }
        }
        return Worktree(url: worktree, branch: branch,
                        candidateRefName: candidateRefName, baselines: baselines)
    }

    /// Resolve a namespaced ref to its commit SHA (`git rev-parse <ref>`).
    public static func resolve(ref: String, in repo: URL) throws -> String {
        try git(repo, ["rev-parse", ref]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commit the worktree's diff and return the candidate ref, or a receipt.
    /// The caller has already run the validation command and passes its result;
    /// the pure `WorktreeDispatch.verdict` maps the host facts to the outcome.
    public static func finalize(_ worktree: Worktree, packet: HandoffPacket,
                                turnOutcome: TurnOutcome,
                                validation: ValidationResult?,
                                in repo: URL) throws -> DispatchOutcome {
        var carried = turnOutcome
        if let validation {
            carried.validationRan = true
            carried.exitStatus = Int(validation.exit)
            carried.outputDigest = validation.digest
        }
        let verdict = WorktreeDispatch.verdict(
            packet: packet,
            allowedMutations: carried.mutations,
            turnOutcome: carried,
            validation: validation)
        switch verdict {
        case .candidate:
            let sha = try commitDiff(in: worktree.url, writableFiles: packet.writableFiles)
            // Keep the commit reachable via a namespaced ref, not a dangling SHA.
            _ = try git(repo, ["update-ref", worktree.candidateRefName, sha])
            return .candidate(ref: worktree.candidateRefName,
                              turnOutcome: carried, baselines: worktree.baselines)
        case .receipt(let receipt):
            return .receipt(receipt)
        }
    }

    /// Remove the worktree and its throwaway branch (the candidate commit stays
    /// reachable via the namespaced ref).
    public static func discard(_ worktree: Worktree, in repo: URL) {
        try? git(repo, ["worktree", "remove", "--force", worktree.url.path])
        try? git(repo, ["branch", "-D", worktree.branch])
        try? FileManager.default.removeItem(at: worktree.url)
    }

    /// Dispatch `packet` into a disposable worktree of `repo`, running `attempt`
    /// in the worktree and committing the diff when the pure verdict returns a
    /// candidate. Returns the candidate ref (a real commit that resolves) or a
    /// typed `Receipt`. Throws on infrastructure failure (worktree creation,
    /// git, a thrown `attempt`); a validation command exiting non-zero is a
    /// `Receipt`, not a throw.
    public static func dispatch(
        packet: HandoffPacket,
        in repo: URL,
        attempt: (HandoffPacket, URL) throws -> TurnOutcome
    ) throws -> DispatchOutcome {
        let wt = try prepare(packet: packet, in: repo)
        defer { discard(wt, in: repo) }

        var enriched = packet
        enriched.baselines = wt.baselines
        let turnOutcome = try attempt(enriched, wt.url)
        let validation = try runValidation(packet.validationCommand, in: wt.url)
        return try finalize(wt, packet: packet, turnOutcome: turnOutcome,
                            validation: validation, in: repo)
    }

    /// Read one file's baseline from `worktree` (D1): `sha256` as the
    /// lowercase-hex SHA-256 of the file's bytes (CryptoKit `SHA256`, not
    /// `git hash-object`'s SHA-1 — the field name is honest), `mode` via
    /// `git ls-files -s` (the index's permission bits), and `lineEnding` by
    /// scanning the file's bytes. Throws when the file is not in the worktree.
    public static func readBaseline(for path: String, in worktree: URL) throws -> FileBaseline {
        let url = file(path, in: worktree)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw WorktreeDispatcherError.gitFailed(
                status: -1, output: "", error: "readBaseline: file not found: \(url.path)")
        }
        let sha = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()
        let entry = try git(worktree, ["ls-files", "-s", path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = parseMode(entry)
        let lineEnding = scanLineEnding(url)
        return FileBaseline(sha256: sha, lineEnding: lineEnding, mode: mode)
    }

    /// Run the packet's validation command in `worktree` (D3), capturing the
    /// exit status and a SHA-256 digest of stdout. Returns `nil` when the packet
    /// sets no validation command. A non-zero exit is a validation result (not a
    /// throw); the pure verdict maps it to `.validationFailed`.
    public static func runValidation(_ command: String?, in worktree: URL) throws -> ValidationResult? {
        guard let command else { return nil }
        let r = try SubprocessRunner.run(command, in: worktree)
        // Combined, and digested over the same text `output` carries. Hashing
        // stdout alone meant a Python traceback (stderr) produced the digest of
        // the empty string — a field that looked like evidence and described
        // nothing.
        let combined = r.stdout + (r.stdout.isEmpty || r.stderr.isEmpty ? "" : "\n") + r.stderr
        let digest = "sha256:" + SHA256.hash(data: Data(combined.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let exit = r.timedOut ? Int32(124) : r.exit  // 124 = timeout, per `timeout(1)` convention
        return ValidationResult(exit: exit, digest: digest, output: combined)
    }

    /// Write one harvested file's content into the worktree, creating parent
    /// directories as needed (text-contract harvest). The path is a worktree-
    /// relative writable path (may contain `/` separators).
    public static func writeFile(_ content: String, to path: String, in worktree: URL) throws {
        let url = file(path, in: worktree)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - internals

    /// Commit the worktree's diff to the throwaway branch, staging only the
    /// packet's `writableFiles` (`git add -- <writableFiles>`, not `git add -A`).
    /// Returns the commit SHA (`git rev-parse HEAD`).
    private static func commitDiff(in worktree: URL, writableFiles: [String]) throws -> String {
        let paths = writableFiles.filter {
            FileManager.default.fileExists(atPath: file($0, in: worktree).path)
        }
        if !paths.isEmpty {
            _ = try git(worktree, ["add", "--"] + paths)
        }
        // A worker can "mutate" a file by rewriting it with byte-identical
        // content: the host records the write, so `mutations` is non-empty and
        // the verdict is a candidate, but git has nothing staged and `commit`
        // exits 1 ("nothing to commit"). Treating that as a failure killed a
        // real run mid-transaction. The tree genuinely is the parent's tree, so
        // the parent commit *is* the candidate — report it rather than
        // manufacturing an empty commit that claims a change.
        // Only commit when there are STAGED changes (porcelain column 1 is not
        // space and not `?`). Untracked files (e.g. __pycache__/ from the import
        // check) must not trigger a commit that then fails with "nothing added
        // to commit". A byte-identical rewrite still has nothing staged, so the
        // parent commit is returned as the candidate — unchanged behavior.
        let porcelain = try git(worktree, ["status", "--porcelain"])
        let hasStagedChanges = porcelain.split(separator: "\n").contains { line in
            guard let first = line.first else { return false }
            return first != " " && first != "?"
        }
        if hasStagedChanges {
            _ = try git(worktree, ["commit", "-m", "SwiftStar dispatch candidate"])
        }
        return try git(worktree, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run `git -C <dir> <args>`, returning stdout. Throws on a non-zero exit.
    private static func git(_ dir: URL, _ args: [String]) throws -> String {
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
            throw WorktreeDispatcherError.gitFailed(
                status: p.terminationStatus, output: output, error: errorOutput)
        }
        return output
    }

    /// Parse the octal mode out of a `git ls-files -s` line, masked to the
    /// permission + special bits.
    private static func parseMode(_ entry: String) -> UInt32 {
        guard let first = entry.split(separator: " ").first else { return 0 }
        return (UInt32(first, radix: 8) ?? 0) & 0o7777
    }

    /// Resolve a relative `path` against `worktree` into an absolute file URL,
    /// tolerating subdirectory separators in `path`.
    private static func file(_ path: String, in worktree: URL) -> URL {
        var url = worktree
        for component in path.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }

    /// Classify a file's line endings by scanning its bytes (D1): `lf` when only
    /// lone LFs appear, `crlf` when only CRLF, `mixed` when both. A file with no
    /// newlines reads as `.lf` (the default).
    private static func scanLineEnding(_ url: URL) -> LineEnding {
        guard let data = FileManager.default.contents(atPath: url.path) else { return .lf }
        var crlf = 0
        var loneLF = 0
        var prevCR = false
        for byte in data {
            if byte == 0x0D { prevCR = true; continue }
            if byte == 0x0A {
                if prevCR { crlf += 1 } else { loneLF += 1 }
            }
            prevCR = false
        }
        if crlf > 0 && loneLF > 0 { return .mixed }
        if crlf > 0 { return .crlf }
        return .lf
    }
}

/// Errors thrown by `WorktreeDispatcher` on infrastructure failure (a git
/// command exiting non-zero); a validation command exiting non-zero is a
/// `Receipt`, not this error.
public enum WorktreeDispatcherError: Error, Sendable {
    /// `git -C <dir> <args>` exited non-zero; `status` is the exit code and
    /// `output`/`error` are the captured stdout/stderr for the message.
    case gitFailed(status: Int32, output: String, error: String)
}
