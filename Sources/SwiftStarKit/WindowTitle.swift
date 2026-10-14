import Foundation

/// The session window's title (SU.11, D2): the conversation's title; "New
/// conversation" while a session runs that isn't listed yet; else the
/// workspace folder's name (SU.6a), else the app's.
public enum WindowTitle {
    public static func text(workspace: URL?, conversation: Conversation?, active: Bool) -> String {
        if let conversation { return conversation.title }
        if active { return "New conversation" }
        return workspace?.leafName ?? "SwiftStar"
    }
}
