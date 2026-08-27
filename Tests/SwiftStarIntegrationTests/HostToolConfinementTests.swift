import Foundation
import Testing
@testable import SwiftStarAppKit
@testable import SwiftStarKit

/// The consent check is pure and resolves `..` but not symlinks, deferring that
/// to the engine's `realpath`. Under `--host-tools` the host executes the call,
/// so the deferral does not apply and the host must resolve them itself.
struct HostToolConfinementTests {
    private func makeWorkspace() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("confinement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func symlinkEscapingTheWorkspaceIsRefused() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let outside = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: outside) }

        let secret = outside.appendingPathComponent("secret.txt")
        try "secret".write(to: secret, atomically: true, encoding: .utf8)

        // The shape a repo (hence a worktree built from it) can carry.
        let escape = workspace.appendingPathComponent("escape.txt")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: secret)

        #expect(HostToolConfinement.realPath(escape.path, workspace: workspace) == nil)
    }

    @Test func symlinkStayingInsideTheWorkspaceIsAllowed() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let real = workspace.appendingPathComponent("real.txt")
        try "fine".write(to: real, atomically: true, encoding: .utf8)
        let link = workspace.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let resolved = HostToolConfinement.realPath(link.path, workspace: workspace)
        #expect(resolved != nil)
        #expect(resolved == real.resolvingSymlinksInPath().path)
    }

    @Test func plainPathInsideTheWorkspaceIsAllowedAndTheRootItself() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let file = workspace.appendingPathComponent("a.txt")
        try "a".write(to: file, atomically: true, encoding: .utf8)

        #expect(HostToolConfinement.realPath(file.path, workspace: workspace) != nil)
        #expect(HostToolConfinement.realPath(workspace.path, workspace: workspace) != nil)
    }

    @Test func siblingDirectorySharingAPrefixIsRefused() throws {
        // "/tmp/ws-evil" must not pass a prefix test against "/tmp/ws".
        let base = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: base) }
        let workspace = base.appendingPathComponent("ws")
        let sibling = base.appendingPathComponent("ws-evil")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        let file = sibling.appendingPathComponent("x.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        #expect(HostToolConfinement.realPath(file.path, workspace: workspace) == nil)
    }
}
