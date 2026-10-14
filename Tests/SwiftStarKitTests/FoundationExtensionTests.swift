import Foundation
import Testing
@testable import SwiftStarKit

struct FoundationExtensionTests {
    @Test func leafNameUsesOnlyTheLastDirectoryComponent() {
        #expect(URL(fileURLWithPath: "/Users/me/projects/swiftstar").leafName == "swiftstar")
    }

    @Test func leafNameFallsBackToRootPath() {
        #expect(URL(fileURLWithPath: "/").leafName == "/")
    }
}

struct WindowTitleTests {
    private static let folder = URL(fileURLWithPath: "/Users/me/projects/swiftstar")
    private static let chat = Conversation(
        id: "c1", title: "Fix the toolbar", updated: nil, modelID: nil, resumable: true,
        problems: [], sessionIDs: ["c1"])

    // SU.11, D2: titled by the conversation; "New conversation" while an
    // unlisted one runs; else the project (SU.6a), else the app.
    @Test func windowTitle() {
        #expect(WindowTitle.text(workspace: Self.folder, conversation: Self.chat, active: true) == "Fix the toolbar")
        #expect(WindowTitle.text(workspace: Self.folder, conversation: nil, active: true) == "New conversation")
        #expect(WindowTitle.text(workspace: Self.folder, conversation: nil, active: false) == "swiftstar")
        #expect(WindowTitle.text(workspace: nil, conversation: nil, active: false) == "SwiftStar")
    }

    // SU.11, D4: a running session's id that no listed conversation holds.
    @Test func unlistedSession() {
        #expect(Conversations.isUnlisted(sessionID: "new", in: [Self.chat]))
        #expect(!Conversations.isUnlisted(sessionID: "c1", in: [Self.chat]))
        #expect(!Conversations.isUnlisted(sessionID: nil, in: [Self.chat]))
    }
}
