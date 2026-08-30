import Foundation
import SwiftStarAppKit

/// Test-support: a disposable git repo with one seed commit, for integration
/// tests that need a real `git` working tree to dispatch/repair against.
/// Extracted 2026-08-29 from four near-identical private copies
/// (`WorktreeDispatcherTests`, `WorktreeTransactionTests`, `PhaseRepairTests`,
/// `RepairLoopTests`) so the fixture is defined once.
enum GitFixtureRepo {
    /// Build a temp git repo named `<prefix>-<uuid>` with one seed commit
    /// containing `a.txt` ("seed\n"), so a dispatch/repair test has a real
    /// HEAD to branch from and a real file to baseline. `git` runs via
    /// `/usr/bin/git` (the same binary AgentController resolves); the repo
    /// config gets a test identity so `git commit` works without inheriting
    /// the user's global config.
    static func make(prefix: String) throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
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

    /// Run `git -C <dir> <args>`, returning stdout. Throws (with stdout+stderr
    /// in the message) on non-zero exit.
    @discardableResult
    static func git(_ dir: URL, _ args: [String]) throws -> String {
        let result = try GitProcess.run(args, in: dir)
        guard result.exit == 0, !result.timedOut else {
            throw NSError(domain: "GitFixtureRepo.git", code: Int(result.timedOut ? 124 : result.exit),
                          userInfo: [NSLocalizedDescriptionKey: result.stdout + result.stderr])
        }
        return result.stdout
    }
}
