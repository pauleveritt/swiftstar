import Foundation
import Testing
@testable import SwiftStarKit

// SU.6c, D1: when there's no usable workspace, fall back, else ask.
struct WorkspaceChoiceTests {
    struct ResolveCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let saved: String?
        let recents: [String]
        let checkout: String?
        /// The paths `isUsable` accepts.
        let usable: Set<String>
        let workspace: String?
        let notice: String?
    }

    static let gone = "The saved folder /gone can't be used (it's missing or not in a git repository)"
    static let choose = "Choose a folder in a git repository to start."

    static let resolveCases: [ResolveCase] = [
        .init(testDescription: "savedUsableIsKept", saved: "/a", recents: ["/b"], checkout: "/c",
              usable: ["/a", "/b", "/c"], workspace: "/a", notice: nil),
        .init(testDescription: "missingSavedFallsBackToRecent", saved: "/gone", recents: ["/x", "/b"], checkout: "/c",
              usable: ["/b", "/c"], workspace: "/b", notice: gone + "; using b."),
        .init(testDescription: "fallbackSkipsTheSavedEntryInRecents", saved: "/gone", recents: ["/gone", "/b"],
              checkout: nil, usable: ["/b", "/gone-not"], workspace: "/b", notice: gone + "; using b."),
        .init(testDescription: "nothingUsableAsksForAFolder", saved: "/gone", recents: ["/x"], checkout: "/c",
              usable: ["/c"], workspace: nil, notice: gone + ". " + choose),
        .init(testDescription: "firstLaunchInACheckout", saved: nil, recents: [], checkout: "/c",
              usable: ["/c"], workspace: "/c", notice: nil),
        .init(testDescription: "firstLaunchOutsideACheckout", saved: nil, recents: [], checkout: "/home",
              usable: [], workspace: nil, notice: choose),
    ]

    @Test(arguments: resolveCases) func resolve(_ c: ResolveCase) {
        let r = WorkspaceChoice.resolve(
            saved: c.saved, recents: c.recents, checkout: c.checkout.map { URL(fileURLWithPath: $0) },
            isUsable: { c.usable.contains($0.path) })
        #expect(r.workspace?.path == c.workspace)
        #expect(r.notice == c.notice)
    }

    @Test func isUsableNeedsTheFolderItself() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let missing = root.appendingPathComponent(".claude/worktrees/x")
        #expect(ProjectRoot.locate(anchor: missing) != nil)  // the walk still finds the repository
        #expect(!WorkspaceChoice.isUsable(missing))
        #expect(WorkspaceChoice.isUsable(root))
    }

    /// Final review: the engine finds the repository from any depth, so a
    /// deep folder is usable, and `ProjectRoot` finds the same root (SU.17).
    @Test func deepFolderIsUsable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let deep = root.appendingPathComponent("a/b/c/d/e/f/g")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        #expect(ProjectRoot.locate(anchor: deep)?.standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(WorkspaceChoice.isUsable(deep))
    }
}
