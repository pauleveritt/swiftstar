import Testing
import Foundation
@testable import SwiftStarAppKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct AcceptanceGraderTests {
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
