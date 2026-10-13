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
    // SU.6a: the window is titled by its workspace folder.
    @Test(arguments: [
        (URL?.none, "SwiftStar"), (URL(fileURLWithPath: "/Users/me/projects/swiftstar"), "swiftstar"),
    ]) func windowTitle(_ workspace: URL?, _ title: String) {
        #expect(WindowTitle.text(workspace: workspace) == title)
    }
}
