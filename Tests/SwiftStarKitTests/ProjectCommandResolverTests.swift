import Testing
import Foundation
@testable import SwiftStarKit

struct ProjectCommandResolverTests {
    @Test func swiftMarkerResolvesSwift() {
        #expect(ProjectCommandResolver.kind(having: ["Package.swift"]) == .swift)
    }

    @Test func pythonMarkerResolvesPython() {
        #expect(ProjectCommandResolver.kind(having: ["pyproject.toml"]) == .python)
    }

    @Test func mixedRepoSwiftWins() {
        #expect(ProjectCommandResolver.kind(having: ["Package.swift", "pyproject.toml"]) == .swift)
    }

    @Test func noMarkerResolvesNil() {
        #expect(ProjectCommandResolver.kind(having: []) == nil)
    }

    @Test func selectorValidationRejectsShellMetacharacters() {
        #expect(ProjectCommandResolver.isValidSelector("tests/FooTests.swift"))
        #expect(ProjectCommandResolver.isValidSelector("FooTests::testBar"))
        #expect(!ProjectCommandResolver.isValidSelector("a; rm -rf /"))
        #expect(!ProjectCommandResolver.isValidSelector("$(touch /tmp/x)"))
        #expect(!ProjectCommandResolver.isValidSelector("`ls`"))
        #expect(!ProjectCommandResolver.isValidSelector("a b"))
        #expect(!ProjectCommandResolver.isValidSelector(""))
    }
}
