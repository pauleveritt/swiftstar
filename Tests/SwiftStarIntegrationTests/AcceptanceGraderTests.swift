import Testing
import Foundation
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct AcceptanceGraderTests {
    /// V2 fix (2026-08-26): a module-level import failure makes pytest abort
    /// collection and report exactly ONE error, however much is missing. Over
    /// the overnight matrix that meant no repair round in 80 cells was ever
    /// shown a failing assertion -- the budget was spent clearing gates one at
    /// a time. The grade must instead name every unmet precondition at once.
    ///
    /// This reproduces the real gate chain from the acceptance suite:
    /// `import app` (present), `import models` (missing), and
    /// `models.complaints` (unreachable). pytest alone reports only the first.
    @Test func collectionAbortIsReplacedByAnEnumeratedPreconditionManifest() throws {
        let pyProject = ProcessInfo.processInfo.environment["AGENTTEST_PY_PROJECT"]
            ?? NSHomeDirectory() + "/projects/pauleveritt/local-ai-pi"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // `app.py` exists; `models.py` does not -- exactly the state a build
        // phase that wrote nothing leaves behind.
        try "value = 1\n".write(to: dir.appendingPathComponent("app.py"),
                                atomically: true, encoding: .utf8)
        let suite = """
        import app
        import models
        from models import Complaint

        SEED = tuple(models.complaints)

        def test_one():
            assert True
        """
        let grade = try AcceptanceGrader.grade(
            worktree: dir, acceptanceSource: suite, pyProject: pyProject)

        #expect(!grade.passed)
        // The bare collection abort must be gone ...
        #expect(!grade.output.contains("error during collection"),
                "grade still shows a bare collection abort:\n\(grade.output)")
        // ... replaced by a manifest naming every requirement, met and unmet.
        #expect(grade.output.contains("[MET]   import app"))
        #expect(grade.output.contains("[UNMET] import models"))
        #expect(grade.output.contains("[UNMET] from models import Complaint"))
        #expect(grade.output.contains("models.complaints"),
                "the attribute gate was never surfaced:\n\(grade.output)")
        #expect(grade.output.contains("preconditions unmet"))
        // The probe must not leave itself behind in the graded tree.
        #expect(!FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(".swiftstar-preconditions.py").path))
    }

    @Test func gradeRunsPytestInTheWorktree() throws {
        let pyProject = ProcessInfo.processInfo.environment["AGENTTEST_PY_PROJECT"]
            ?? NSHomeDirectory() + "/projects/pauleveritt/local-ai-pi"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grader-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let grade = try AcceptanceGrader.grade(
            worktree: dir,
            acceptanceSource: "def test_trivial():\n    assert 1 == 1\n",
            pyProject: pyProject)
        #expect(grade.passed)
        #expect(grade.exit == 0)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("test_acceptance.py").path))
    }
}
