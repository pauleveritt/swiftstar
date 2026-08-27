import Foundation
import Testing
@testable import SwiftStarKit

struct FakeSourceLiteralTests {
    @Test func escapesQuotesAndBackslashes() {
        #expect(FakeSourceLiteral.swiftStringLiteral(#"a "b" \ c"#) == #""a \"b\" \\ c""#)
    }

    @Test func escapesControlCharacters() {
        #expect(FakeSourceLiteral.swiftStringLiteral("a\nb\tc") == #""a\nb\tc""#)
    }

    @Test func roundTripsEmbeddedJSON() {
        let lit = FakeSourceLiteral.swiftStringLiteral("data: {\"a\":1}")
        #expect(lit.hasPrefix("\""))
        #expect(lit.hasSuffix("\""))
        #expect(lit.contains(#"\""#))  // the inner quotes are escaped
    }
}
