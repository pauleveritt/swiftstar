import Foundation
import Testing
@testable import SwiftStarEngine

// SU.14, D5: the picker's files are `git ls-files` with ds4-engine's filters.
@Suite(.serialized, .integration, .tags(.integration), .timeLimit(.minutes(1)))
struct WorkspaceFileListerTests {
    @Test func listsTrackedTextFilesWithTheEnginesFilters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("su14-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files: [String: String] = [
            "README.md": "hi", "Sources/App.swift": "let x = 1",
            "node_modules/dep/index.js": "x", ".github/ci.yml": "x",
            "icon.png": "x", "has space.txt": "x",
        ]
        for (rel, body) in files {
            let url = root.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url, atomically: true, encoding: .utf8)
        }
        try git(["init", "-q"], in: root)
        try git(["add", "-A"], in: root)
        // Untracked: git ls-files leaves it out.
        try "x".write(to: root.appendingPathComponent("untracked.swift"), atomically: true, encoding: .utf8)

        let listed = await WorkspaceFileLister.list(root: root)
        #expect(listed == ["README.md", "Sources/App.swift"])
    }

    @Test func aFolderOutsideGitListsNothing() async {
        let listed = await WorkspaceFileLister.list(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("su14-none-\(UUID().uuidString)"))
        #expect(listed.isEmpty)
    }

    private func git(_ args: [String], in root: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path] + args
        try p.run()
        p.waitUntilExit()
    }
}
