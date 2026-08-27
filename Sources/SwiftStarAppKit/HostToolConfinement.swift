import Foundation
import SwiftStarKit

/// Symlink-resolving re-confinement for host-executed tool calls.
///
/// `ToolCallbackResponder`'s consent check is deliberately pure: it resolves
/// `..` without touching the filesystem, and its own doc defers symlink
/// resolution to "the engine's `realpath`-based confinement". That deferral
/// only holds when the *engine* executes the tool. Under `--host-tools` the
/// host executes it, so nothing resolves symlinks unless the host does — and a
/// symlink inside the workspace pointing anywhere outside it passes the pure
/// check. A worktree is built from repo content, so a committed symlink is
/// enough; no agent cleverness is required.
///
/// One implementation, used by every host executor. `AgentController` had this
/// hardening and `PoolOrchestrator` did not, which is exactly the kind of
/// divergence a shared helper exists to prevent.
public enum HostToolConfinement {
    /// The symlink-resolved absolute path, or nil when it escapes the grant.
    public static func realPath(_ request: ToolExecutionRequest) -> String? {
        guard let path = request.resolvedPath else { return nil }
        return realPath(path, workspace: request.workspace)
    }

    /// Resolve `path` and refuse it unless it is the workspace root or lies
    /// beneath it, comparing both sides symlink-resolved.
    public static func realPath(_ path: String, workspace: URL) -> String? {
        let root = workspace.resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolved == root || resolved.hasPrefix(root + "/") else { return nil }
        return resolved
    }
}
