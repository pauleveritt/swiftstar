import Foundation

/// Locates the git repository root containing a given anchor path, walking up
/// a bounded number of levels. The engine's `--source` is the root of the
/// folder the user picked; with none picked, the default workspace is the
/// root of the checkout the app runs from, anchored to the *executable's*
/// location, never the launch cwd. `.git` may be a directory (a repository)
/// or a file (a linked worktree); `fileExists` covers both.
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
