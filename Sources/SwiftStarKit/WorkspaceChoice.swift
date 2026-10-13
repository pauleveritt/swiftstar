import Foundation

/// Which folder a session starts in (SU.6c, D1): the saved one if usable,
/// else the newest usable Recent folder, said so in a notice; with nothing
/// saved, the checkout the app runs from; otherwise none, and the notice
/// asks for a folder.
public enum WorkspaceChoice {
    public static func resolve(
        saved: String?, recents: [String], checkout: URL?, isUsable: (URL) -> Bool
    ) -> (workspace: URL?, notice: String?) {
        let choose = "Choose a folder in a git repository to start."
        guard let saved, !saved.isEmpty else {
            if let checkout, isUsable(checkout) { return (checkout, nil) }
            return (nil, choose)
        }
        let savedURL = URL(fileURLWithPath: saved)
        if isUsable(savedURL) { return (savedURL, nil) }
        let gone = "The saved folder \(saved) can't be used (it's missing or not in a git repository)"
        // The saved entry, if it's in Recent, is skipped by `isUsable` itself.
        let fallback = recents.lazy.map { URL(fileURLWithPath: $0) }.first(where: isUsable)
        if let fallback { return (fallback, "\(gone); using \(fallback.leafName).") }
        return (nil, "\(gone). \(choose)")
    }

    /// The folder exists, is a directory, and sits in a git repository. The
    /// existence check matters: `ProjectRoot.locate` walks up, so a deleted
    /// worktree inside a repository would still find that repository.
    public static func isUsable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return false }
        return ProjectRoot.locate(anchor: url) != nil
    }
}
