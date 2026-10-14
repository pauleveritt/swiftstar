import Foundation

/// Locates the git repository root containing a given anchor path. The
/// engine's `--source` is the root of the folder the user picked, found from
/// any depth, as the engine finds it and as `WorkspaceChoice.isUsable`
/// accepts it (SU.17, finding 3). With none picked, the default workspace is
/// the root of the checkout the app runs from, anchored to the *executable's*
/// location, never the launch cwd; that walk alone is bounded, so an app run
/// from elsewhere doesn't adopt an unrelated repository above it. `.git` may
/// be a directory (a repository) or a file (a linked worktree);
/// `fileExists` covers both.
public enum ProjectRoot {
    public static let executableWalkDepth = 5

    public static func locate(anchor: URL, maxDepth: Int = .max) -> URL? {
        // As an absolute file path: a scheme-less relative URL's parents run
        // `..`, `../..` forever, and the walk would never reach `/`.
        var dir = URL(fileURLWithPath: anchor.path).standardizedFileURL
        for _ in 0..<maxDepth {
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
