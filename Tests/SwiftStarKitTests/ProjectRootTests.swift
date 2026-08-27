import Foundation
import Testing
@testable import SwiftStarKit

struct ProjectRootTests {
    @Test func findsGitDirAncestor() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projectroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("a/b/c/repo/.git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let anchor = root.appendingPathComponent("a/b/c/repo/src")
        #expect(ProjectRoot.locate(anchor: anchor) == root.appendingPathComponent("a/b/c/repo"))
    }

    @Test func findsGitFileWorktreeMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projectroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("repo/.git/worktrees/x"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A linked worktree's .git is a FILE, not a directory.
        let marker = root.appendingPathComponent("repo/.git")
        try FileManager.default.removeItem(at: marker)
        try "gitdir: elsewhere".write(to: marker, atomically: true, encoding: .utf8)

        let anchor = root.appendingPathComponent("repo")
        #expect(ProjectRoot.locate(anchor: anchor) == root.appendingPathComponent("repo"))
    }

    @Test func returnsNilWithoutGit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projectroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("plain"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ProjectRoot.locate(anchor: root.appendingPathComponent("plain")) == nil)
    }

    @Test func boundedWalkDoesNotEscapeToUnrelatedRepo() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("projectroot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("repo/.git"), withIntermediateDirectories: true)
        // Deep anchor: more levels below the repo than the walk is allowed to climb.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("repo/deep/1/2/3/4/5/6/7"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let anchor = root.appendingPathComponent("repo/deep/1/2/3/4/5/6/7/src")
        #expect(ProjectRoot.locate(anchor: anchor) == nil)
    }
}
