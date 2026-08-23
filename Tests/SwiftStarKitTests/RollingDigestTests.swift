import Testing
@testable import SwiftStarKit

struct RollingDigestTests {
    @Test func wireToolCallKeepsNameOnly() {
        var d = RollingDigest()
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        if let ev = p.feed(#"{"t":"tool_request","idx":0,"name":"edit","params":[{"name":"path","value":"a.swift"}],"worker":1,"ts":3}"#) {
            d = RollingDigestReducer.apply(d, event: ev)
        }
        #expect(d.toolCalls == ["edit"])
        #expect(!d.filesTouched.contains("a.swift"))   // mutations come via recordHostVerdict, not the wire
    }
    @Test func recordReceiptAddsRef() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(1), ref: "ref1", reason: nil, summary: "changed 2 files"))
        #expect(d.refs[WorkerId(1)] == "ref1")
        #expect(d.summary().contains("ref1"))
    }
    @Test func recordHostVerdictAccumulatesMutationsAndExit() {
        var d = RollingDigest()
        d = RollingDigestReducer.recordHostVerdict(d, mutations: ["a.swift"], exitStatus: 0, validationRan: true)
        #expect(d.filesTouched == ["a.swift"])
        #expect(d.exitStatuses == [0])
        #expect(d.validationRan)
    }
    @Test func summaryIsDeterministic() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(2), ref: "r", reason: nil, summary: "s"))
        let s1 = d.summary()
        let s2 = d.summary()
        #expect(s1 == s2)
        #expect(s1.contains("Worker 2"))
    }
}
