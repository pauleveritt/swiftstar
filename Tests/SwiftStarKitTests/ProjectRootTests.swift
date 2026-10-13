import Foundation
import Testing
@testable import SwiftStarKit

struct ProjectRootTests {
    /// A fresh temporary tree with `dirs` created under it, removed afterward.
    private func withTree(_ dirs: [String], _ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("projectroot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for dir in dirs {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try body(root)
    }

    @Test func findsGitDirAncestor() throws {
        try withTree(["a/b/c/repo/.git"]) { root in
            let anchor = root.appendingPathComponent("a/b/c/repo/src")
            #expect(ProjectRoot.locate(anchor: anchor) == root.appendingPathComponent("a/b/c/repo"))
        }
    }

    @Test func findsGitFileWorktreeMarker() throws {
        try withTree(["repo"]) { root in
            // A linked worktree's .git is a FILE, not a directory.
            try "gitdir: elsewhere".write(
                to: root.appendingPathComponent("repo/.git"), atomically: true, encoding: .utf8)
            #expect(ProjectRoot.locate(anchor: root.appendingPathComponent("repo"))
                == root.appendingPathComponent("repo"))
        }
    }

    @Test func returnsNilWithoutGit() throws {
        try withTree(["plain"]) { root in
            #expect(ProjectRoot.locate(anchor: root.appendingPathComponent("plain")) == nil)
        }
    }

    @Test func boundedWalkDoesNotEscapeToUnrelatedRepo() throws {
        // Deep anchor: more levels below the repo than the walk is allowed to climb.
        try withTree(["repo/.git", "repo/deep/1/2/3/4/5/6/7"]) { root in
            let anchor = root.appendingPathComponent("repo/deep/1/2/3/4/5/6/7/src")
            #expect(ProjectRoot.locate(anchor: anchor) == nil)
        }
    }
}
