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
