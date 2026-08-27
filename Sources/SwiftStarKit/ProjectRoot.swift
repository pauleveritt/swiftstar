import Foundation

/// Locates the git repo root containing a given anchor path, walking up a
/// bounded number of levels. The agent workspace defaults to it during
/// development, so the agent is confined to the app's own checkout — anchored
/// to the *executable's* location by the caller, never to the launch cwd (a
/// cwd-derived default would confine the agent to whatever repo the app was
/// launched from). `.git` may be a directory (a real repo) or a file (a
/// linked worktree); `fileExists` covers both.
public enum ProjectRoot {
    public static let maxWalkDepth = 5

    public static func locate(anchor: URL) -> URL? {
        var dir = anchor
        for _ in 0..<maxWalkDepth {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            guard parent.path != dir.path else { break }
            dir = parent
        }
        return nil
    }
}
