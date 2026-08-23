import Testing
@testable import SwiftStarKit

struct GraderVerdictTests {
    @Test func parsesGoodVerdict() {
        let v = GraderVerdict.parse(#"{"verdict":"good","reasons":["matches the spec"]}"#)
        #expect(v.verdict == .good)
        #expect(v.reasons == ["matches the spec"])
    }
    @Test func parsesBadVerdict() {
        let v = GraderVerdict.parse(#"{"verdict":"bad","reasons":["wrong framework"]}"#)
        #expect(v.verdict == .bad)
        #expect(v.reasons == ["wrong framework"])
    }
    @Test func malformedResponseIsErrorNotGood() {
        #expect(GraderVerdict.parse("not json").verdict == .error)
        #expect(GraderVerdict.parse(#"{"reasons":[]}"#).verdict == .error)   // no verdict key
        #expect(GraderVerdict.parse(#"{"verdict":"maybe"}"#).verdict == .error)  // unknown value
    }
}
