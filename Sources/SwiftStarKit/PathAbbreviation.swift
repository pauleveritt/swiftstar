import Foundation

/// Display abbreviation for a file-system path: a path at or under the given
/// home directory renders with `~` for home, so the workspace button and any
/// other path label stay short on screen.
public enum PathAbbreviation {
    /// The directory name shown in compact UI controls. Root has no path
    /// component, so retain its path as the useful fallback.
    public static func leafName(_ path: URL) -> String {
        let leaf = path.lastPathComponent
        return leaf.isEmpty ? path.path : leaf
    }

    public static func abbreviate(_ path: URL, home: URL) -> String {
        let pathString = path.path
        let homeString = home.path
        if pathString == homeString {
            return "~"
        }
        // Component boundary: "/Users/me-other" must not abbreviate under
        // home "/Users/me".
        if pathString.hasPrefix(homeString + "/") {
            return "~" + pathString.dropFirst(homeString.count)
        }
        return pathString
    }
}
