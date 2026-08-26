import Foundation
import Testing
@testable import SwiftStarKit

struct PathAbbreviationTests {
    let home = URL(fileURLWithPath: "/Users/me")

    @Test func homeItselfIsTilde() {
        #expect(PathAbbreviation.abbreviate(home, home: home) == "~")
    }

    @Test func underHomeAbbreviates() {
        let path = URL(fileURLWithPath: "/Users/me/projects/swiftstar")
        #expect(PathAbbreviation.abbreviate(path, home: home) == "~/projects/swiftstar")
    }

    @Test func outsideHomeStaysFull() {
        let path = URL(fileURLWithPath: "/opt/engine/weights.gguf")
        #expect(PathAbbreviation.abbreviate(path, home: home) == "/opt/engine/weights.gguf")
    }

    @Test func homePrefixLookalikeIsNotAbbreviated() {
        // /Users/me-other shares the string prefix but is not under home.
        let path = URL(fileURLWithPath: "/Users/me-other/projects")
        #expect(PathAbbreviation.abbreviate(path, home: home) == "/Users/me-other/projects")
    }
}
