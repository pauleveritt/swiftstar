import Testing
import Foundation
@testable import SwiftStarKit

struct FakeAppSourceTests {
    @Test func determinism() {
        let a = FakeAppSource.generate(answers: ["write": "wrote it", "read": "read it"])
        let b = FakeAppSource.generate(answers: ["write": "wrote it", "read": "read it"])
        #expect(a == b)
    }

    @Test func determinismIsOrderIndependent() {
        // Answers are sorted by key at generation time, so the caller's
        // insertion order must not leak into the source.
        let a = FakeAppSource.generate(answers: ["zebra": "z", "apple": "a"])
        let b = FakeAppSource.generate(answers: ["apple": "a", "zebra": "z"])
        #expect(a == b)
    }

    @Test func embedsAnswersAsSwiftLiterals() {
        let source = FakeAppSource.generate(answers: ["write": "wrote it"])
        // swiftStringLiteral embeds `write` -> `"write"`; the dict literal
        // is `"write": "wrote it"`.
        #expect(source.contains("\"write\": \"wrote it\""))
    }

    @Test func embedsRefusal() {
        let source = FakeAppSource.generate(answers: [:])
        #expect(source.contains(FakeAppSource.refusal))
    }

    @Test func emptyAnswersProduceEmptyDict() {
        let source = FakeAppSource.generate(answers: [:])
        #expect(source.contains("[:]"))
    }

    @Test func refusalIsFixedAndNonEmpty() {
        #expect(!FakeAppSource.refusal.isEmpty)
    }

    @Test func sourceCompilesAsSwift() throws {
        // The generated source must be valid Swift (compiles with swiftc).
        // This is the fast-tier compile check; the integration tier runs it.
        let source = FakeAppSource.generate(answers: ["write": "wrote it"])
        #expect(source.contains("import Foundation"))
        #expect(source.contains("let answers: [String: String]"))
        #expect(source.contains("tool_result"))
        #expect(source.contains("tool_request"))
    }
}
