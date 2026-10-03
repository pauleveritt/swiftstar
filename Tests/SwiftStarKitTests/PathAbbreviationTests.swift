import Foundation
import Testing
@testable import SwiftStarKit

struct PathAbbreviationTests {
    @Test func leafNameUsesOnlyTheLastDirectoryComponent() {
        let path = URL(fileURLWithPath: "/Users/me/projects/swiftstar")
        #expect(PathAbbreviation.leafName(path) == "swiftstar")
    }

    @Test func leafNameFallsBackToRootPath() {
        #expect(PathAbbreviation.leafName(URL(fileURLWithPath: "/")) == "/")
    }
}
