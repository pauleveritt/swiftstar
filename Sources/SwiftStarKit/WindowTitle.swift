import Foundation

/// The session window's title: the workspace folder's name (SU.6a, D2).
public enum WindowTitle {
    public static func text(workspace: URL?) -> String {
        workspace?.leafName ?? "SwiftStar"
    }
}
