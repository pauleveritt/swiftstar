import Foundation
import CryptoKit
import SwiftStarKit

/// The P10 app-layer dispatcher (design D2/D3/D4).
///
/// `dispatch` creates a disposable git worktree on a throwaway branch, reads
/// each writableFile's `FileBaseline` from the worktree (the pre-attempt
/// state), runs the packet's `validationCommand` parent-side when set
/// (capturing exit status + output digest), and commits the worktree's diff
/// to the throwaway branch when the pure `WorktreeDispatch.verdict` returns a
/// candidate — filling the ref — else it returns the typed `Receipt` the
/// verdict produced. The caller's tree is never touched; the worktree is
/// removed on completion or failure.
///
/// The `attempt` closure is the injection point for the dispatched turn: in
/// production it spawns the agent (host mode, shell off, the P9 responder
/// revision-checking against `writableFiles`) pointed at the worktree and
/// returns the P9 `TurnOutcome` carrying the observed mutations; in a test it
/// is a scripted write. The pure verdict consumes that `TurnOutcome` (D4) —
/// a handoff packet's success is never inferred from prose.
public enum WorktreeDispatcher {

    /// Dispatch `packet` into a disposable worktree of `repo`, running `attempt`
    /// in the worktree and committing the diff to a throwaway branch when the
    /// pure verdict returns a candidate. Returns the candidate ref (a real
    /// commit that resolves in `repo`) or a typed `Receipt` naming why not.
    /// Throws on infrastructure failure (worktree creation, git, a thrown
    /// `attempt`); a validation command exiting non-zero is a `Receipt`, not a
    /// throw.
    public static func dispatch(
        packet: HandoffPacket,
        in repo: URL,
        attempt: (HandoffPacket, URL) throws -> TurnOutcome
    ) throws -> DispatchOutcome {
        let branch = "swiftstar-dispatch-\(UUID().uuidString)"
        let candidateRefName = "refs/swiftstar/candidates/\(UUID().uuidString)"
        let worktree = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-wt-\(UUID().uuidString)")

        // Create the worktree on a throwaway branch (D2): `git worktree add -b`
        // branches from HEAD and checks the worktree out on it.
        _ = try git(repo, ["worktree", "add", "-b", branch, worktree.path])
        defer {
            // Remove the worktree and the throwaway branch on completion or
            // failure. The candidate commit stays reachable via the namespaced
            // ref (refs/swiftstar/candidates/<uuid>) — a raw SHA is GC-eligible
            // once the branch is deleted, which is not a durable ref (F7).
            try? git(repo, ["worktree", "remove", "--force", worktree.path])
            try? git(repo, ["branch", "-D", branch])
            try? FileManager.default.removeItem(at: worktree)
        }

        // Read each writableFile's baseline from the worktree (D1): the
        // SHA-256 of its bytes (CryptoKit, not `git hash-object`'s SHA-1), the
        // mode via `git ls-files -s`, and the line ending by scanning the
        // file's bytes — each read from the worktree, never guessed. A
        // not-yet-existing writableFile (the agent will create it) has no
        // pre-baseline; reading is best-effort per file. The dict is carried
        // into the candidate (D1) so the parent can detect drift on a file
        // the candidate was allowed to touch.
        var baselines: [String: FileBaseline] = [:]
        for path in packet.writableFiles {
            if let baseline = try? readBaseline(for: path, in: worktree) {
                baselines[path] = baseline
            }
        }
        // The attempt receives the ENRICHED packet — the declared handoff
        // packet actually carrying its computed baselines — plus the worktree
        // (F6: previously the attempt got only the worktree, so production
        // captured baselines: [:]).
        var enriched = packet
        enriched.baselines = baselines

        // Run the dispatched turn: the closure mutates files in the worktree
        // and returns the P9 `TurnOutcome` carrying the observed mutations.
        let turnOutcome = try attempt(enriched, worktree)

        // Run the packet's validation command parent-side (D3), capturing the
        // exit status and a SHA-256 digest of stdout. `nil` when the packet sets
        // no validation command.
        let validation = try runValidation(packet.validationCommand, in: worktree)

        // Decide candidate vs receipt via the pure verdict (D3/D4): the verdict
        // leaves the candidate `ref` empty; this layer fills it after committing.
        let verdict = WorktreeDispatch.verdict(
            packet: packet,
            allowedMutations: turnOutcome.mutations,
            turnOutcome: turnOutcome,
            validation: validation)
        switch verdict {
        case .candidate(_, var carried, _):
            // Attach the validation evidence to the candidate's TurnOutcome
            // (F5): validationRan, exit status, and output digest were computed
            // above but the original TurnOutcome did not carry them.
            if let validation {
                carried.validationRan = true
                carried.exitStatus = Int(validation.exit)
                carried.outputDigest = validation.digest
            }
            // Commit the worktree's diff to the throwaway branch (D3) and
            // return a durable namespaced ref. The baselines read above (D1)
            // ride on the candidate so the parent can diff the candidate
            // against the pre-attempt state of each writable file.
            let sha = try commitDiff(in: worktree, writableFiles: packet.writableFiles)
            // Keep the commit reachable via a namespaced ref, not a dangling
            // SHA (F7): `git update-ref refs/swiftstar/candidates/<uuid> <sha>`.
            _ = try git(repo, ["update-ref", candidateRefName, sha])
            return .candidate(ref: candidateRefName, turnOutcome: carried, baselines: baselines)
        case .receipt(let receipt):
            return .receipt(receipt)
        }
    }

    /// Read one file's baseline from `worktree` (D1): `sha256` as the
    /// lowercase-hex SHA-256 of the file's bytes (CryptoKit `SHA256`, not
    /// `git hash-object`'s SHA-1 — the field name is honest), `mode` via
    /// `git ls-files -s` (the index's permission bits), and `lineEnding` by
    /// scanning the file's bytes for CRLF vs lone LF. Throws when the file is
    /// not in the worktree (a not-yet-existing writableFile has no baseline;
    /// the caller's `try?` skips it).
    public static func readBaseline(for path: String, in worktree: URL) throws -> FileBaseline {
        let url = file(path, in: worktree)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw WorktreeDispatcherError.gitFailed(
                status: -1, output: "", error: "readBaseline: file not found: \(url.path)")
        }
        // The SHA-256 of the file's bytes (CryptoKit), not `git hash-object`'s
        // SHA-1 — `FileBaseline.sha256` must be honest about which hash it holds.
        let sha = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }.joined()
        // `git ls-files -s <path>` -> "<mode> <sha> 0\t<path>"; the first field
        // is the octal git mode (e.g. "100644"). Mask to the permission +
        // setuid/setgid/sticky bits (the file-type prefix is not a mode bit).
        let entry = try git(worktree, ["ls-files", "-s", path])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mode = parseMode(entry)
        let lineEnding = scanLineEnding(url)
        return FileBaseline(sha256: sha, lineEnding: lineEnding, mode: mode)
    }

    // MARK: - internals

    /// Run the packet's validation command in `worktree` (D3), capturing the
    /// exit status and a SHA-256 digest of stdout. Returns `nil` when the packet
    /// sets no validation command. A non-zero exit is a validation result (not a
    /// throw); the pure verdict maps it to `.validationFailed`.
    private static func runValidation(_ command: String?, in worktree: URL) throws -> ValidationResult? {
        guard let command else { return nil }
        // SubprocessRunner drains stdout/stderr concurrently and enforces a
        // timeout, so a verbose validation command can neither deadlock on a
        // full pipe nor hang the dispatch forever.
        let r = try SubprocessRunner.run(command, in: worktree)
        let digest = "sha256:" + SHA256.hash(data: Data(r.stdout.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let exit = r.timedOut ? Int32(124) : r.exit  // 124 = timeout, per `timeout(1)` convention
        return ValidationResult(exit: exit, digest: digest)
    }

    /// Commit the worktree's diff to the throwaway branch, staging only the
    /// packet's `writableFiles` (`git add -- <writableFiles>`, not `git add -A`)
    /// so an untracked build dir (`.build/` etc.) the attempt left in the
    /// worktree is NOT swept into the candidate. Returns the commit SHA
    /// (`git rev-parse HEAD`). Throws on a git failure (infrastructure); the
    /// pure verdict gates reaching here, so a candidate always has a diff to
    /// commit.
    private static func commitDiff(in worktree: URL, writableFiles: [String]) throws -> String {
        // Stage only the writable files that exist (a not-yet-created contract
        // file has nothing to stage; the verdict guarantees at least one
        // mutation, so at least one writable file exists). `--` separates
        // options from pathspecs so paths with odd characters are safe.
        let paths = writableFiles.filter {
            FileManager.default.fileExists(atPath: file($0, in: worktree).path)
        }
        if !paths.isEmpty {
            _ = try git(worktree, ["add", "--"] + paths)
        }
        _ = try git(worktree, ["commit", "-m", "SwiftStar dispatch candidate"])
        return try git(worktree, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run `git -C <dir> <args>`, returning stdout. Throws on a non-zero exit
    /// with the captured stdout+stderr for the message.
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

    /// Parse the octal mode out of a `git ls-files -s` line
    /// (`<mode> <sha> 0\t<path>`), masked to the permission + special bits.
    private static func parseMode(_ entry: String) -> UInt32 {
        guard let first = entry.split(separator: " ").first else { return 0 }
        return (UInt32(first, radix: 8) ?? 0) & 0o7777
    }

    /// Resolve a relative `path` against `worktree` into an absolute file URL,
    /// tolerating subdirectory separators in `path` (appendingPathComponent
    /// percent-encodes a literal slash).
    private static func file(_ path: String, in worktree: URL) -> URL {
        var url = worktree
        for component in path.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }

    /// Classify a file's line endings by scanning its bytes (D1): `lf` when only
    /// lone LFs appear, `crlf` when only CRLF, `mixed` when both are present.
    /// A file with no newlines reads as `.lf` (the default).
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
