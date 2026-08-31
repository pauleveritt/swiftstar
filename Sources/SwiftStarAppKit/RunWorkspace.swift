import Foundation

/// A fresh `git worktree` checkout of the harness repo, for exactly one
/// `swiftstar-eval experiment` run. Motivated by the same 2026-08-30
/// A/B-comparison incident `SpawnRecord`/`ArmDiff` exist for, one layer up:
/// even with a truthful `SpawnRecord`, six interleaved runs of a
/// change-and-verify prompt sharing one workspace directory means run 2
/// finds run 1's edit already applied, and by the third pair both arms are
/// measuring "confirm there is nothing to do" instead of the thing the
/// experiment declared. `RunWorkspace` gives every run — not every pair,
/// every RUN — a private checkout at the repo's starting ref, so an edit
/// made inside one worktree can never leak into another's.
///
/// Lives in `SwiftStarAppKit`, not `SwiftStarKit`: it spawns `git` processes
/// (`GitProcess`), which the fast-tier Kit target's build tripwire forbids.
public struct RunWorkspace: Sendable {
    /// The fresh checkout's path — pass this as the run's
    /// `AgentSettings.workspace`.
    public let path: URL
    /// The `HEAD` SHA `repoRoot` named at the moment this worktree was
    /// created — recorded into the run's `SpawnRecord` via
    /// `SpawnRecord.withWorkspaceRef`, so a later reader can tell which
    /// starting point every run actually began from.
    public let ref: String
    private let repoRoot: URL

    init(path: URL, ref: String, repoRoot: URL) {
        self.path = path
        self.ref = ref
        self.repoRoot = repoRoot
    }

    /// Create a fresh, detached `git worktree` of `repoRoot` at its current
    /// `HEAD`, in a private directory under the system temp root. Each call
    /// resolves `HEAD` and adds the worktree fresh — two calls in a row (as
    /// `swiftstar-eval experiment`'s interleaved run order makes) each get
    /// their own directory and their own private working tree, so neither
    /// can see a file the other wrote.
    public static func create(repoRoot: URL) throws -> RunWorkspace {
        let headResult = try GitProcess.run(["rev-parse", "HEAD"], in: repoRoot)
        guard headResult.exit == 0, !headResult.timedOut else {
            throw RunWorkspaceError.gitFailed("git rev-parse HEAD: \(headResult.stderr)")
        }
        let ref = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-eval-workspace-\(UUID().uuidString)", isDirectory: true)
        let addResult = try GitProcess.run(
            ["worktree", "add", "--detach", path.path, ref], in: repoRoot)
        guard addResult.exit == 0, !addResult.timedOut else {
            throw RunWorkspaceError.gitFailed("git worktree add: \(addResult.stderr)")
        }
        return RunWorkspace(path: path, ref: ref, repoRoot: repoRoot)
    }

    /// Remove this worktree — best-effort: `git worktree remove` first (so
    /// `repoRoot`'s own worktree bookkeeping stays clean), then a plain
    /// directory removal in case the git step left anything behind (a killed
    /// run, a worktree git already considers "prunable"). A caller that
    /// cannot remove a workspace has no better recovery than to move on; this
    /// never throws.
    public func remove() {
        _ = try? GitProcess.run(["worktree", "remove", "--force", path.path], in: repoRoot)
        try? FileManager.default.removeItem(at: path)
    }
}

public enum RunWorkspaceError: Error, Equatable {
    case gitFailed(String)
}
