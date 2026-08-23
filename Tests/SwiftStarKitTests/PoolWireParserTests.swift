import Testing
@testable import SwiftStarKit

struct PoolWireParserTests {
    @Test func absentWorkerDefaultsToOrchestrator() {
        var p = PoolWireParser()
        guard case .hello = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":1}"#)?.event else {
            Issue.record("expected hello"); return
        }
        // second line: worker field absent
        let ev = p.feed(#"{"t":"text","s":"hi","ts":2}"#)
        #expect(ev?.worker == .orchestrator)
        if case .text(let s) = ev?.event { #expect(s == "hi") }
    }
    @Test func readsWorkerField() {
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        let ev = p.feed(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":0,"power":100,"error":"","worker":3,"ts":5}"#)
        #expect(ev?.worker == WorkerId(3))
    }
    @Test func malformedWorkerIsZeroNotRefused() {
        var p = PoolWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        let ev = p.feed(#"{"t":"text","s":"x","worker":"nope","ts":9}"#)
        #expect(ev?.worker == .orchestrator)
    }
}
