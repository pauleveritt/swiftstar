import Foundation
import SwiftStarKit

/// Runs the harness-owned acceptance suite in a worktree (the pytest run that
/// used to be inline in `main.swift`). Writes `test_acceptance.py` into the
/// worktree and runs `uv run --project <pyProject> pytest -q test_acceptance.py`
/// with cwd = the worktree, returning a `GradeResult`. Shared by `main.swift`
/// (first grade) and `RepairLoop` (re-grade after each candidate).
public enum AcceptanceGrader {
    public static func grade(worktree: URL, acceptanceSource: String,
                             pyProject: String) throws -> GradeResult {
        try acceptanceSource.write(
            to: worktree.appendingPathComponent("test_acceptance.py"),
            atomically: true, encoding: .utf8)
        let r = try SubprocessRunner.run(
            "uv run --project \(pyProject) pytest -q test_acceptance.py",
            in: worktree)
        let combined = r.stdout + (r.stderr.isEmpty ? "" : "\n" + r.stderr)
        let exit = r.timedOut ? Int32(124) : r.exit
        return GradeResult(exit: exit, output: combined)
    }
}
