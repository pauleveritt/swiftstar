import Foundation
import Testing
@testable import SwiftStarKit

struct WireStatusDecoderTests {
    private static let hello =
        #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"]}"#

    /// One status line carrying every documented field must surface intact
    /// through BOTH parsers. This is the regression the power/error drop
    /// needed and never had: those fields were parsed by WireEventParser and
    /// silently dropped by AgentWireParser — the parser that feeds the running
    /// app — for multiple phases.
    @Test func everyStatusFieldReachesBothParsers() {
        let line = """
        {"t":"status","state":"generating","prefill_tps":231.5,"gen_tps":46.3,\
        "generated":352,"ctx_used":1233,"ctx_size":16384,"power":100,\
        "error":"boom","ts":802076707009}
        """
        var agent = AgentWireParser()
        _ = agent.feed(Self.hello)
        guard case .status(let a)? = agent.feed(line) else {
            Issue.record("AgentWireParser did not yield .status"); return
        }
        var wire = WireEventParser()
        _ = wire.feed(Self.hello)
        guard case .status(let w)? = wire.feed(line) else {
            Issue.record("WireEventParser did not yield .status"); return
        }
        #expect(a == w, "the two parsers disagree on the same status line")
        for s in [a, w] {
            #expect(s.state == "generating")
            #expect(s.prefillTPS == 231.5)
            #expect(s.genTPS == 46.3)
            #expect(s.generated == 352)
            #expect(s.ctxUsed == 1233)
            #expect(s.ctxSize == 16384)
            #expect(s.power == 100)
            #expect(s.error == "boom")
            #expect(s.ts == 802076707009)
        }
    }

    /// The turn-end `ready` payload, likewise. Every field is optional because
    /// `ready` is emitted twice with different shapes — once at startup with
    /// the memory plan, once per turn end with the outcome.
    @Test func everyReadyFieldReachesBothParsers() {
        let line = """
        {"t":"ready","planned_bytes":6344835080,"stop_reason":"eos",\
        "generated":352,"ctx_used":1236,"ts":802076748367}
        """
        var agent = AgentWireParser()
        _ = agent.feed(Self.hello)
        guard case .ready(let pb, let sr, let gen, let ctx)? = agent.feed(line) else {
            Issue.record("AgentWireParser did not yield .ready"); return
        }
        #expect(pb == 6_344_835_080)
        #expect(sr == "eos")
        #expect(gen == 352)
        #expect(ctx == 1236)

        let decoded = WireStatusDecoder.ready(from: [
            "planned_bytes": NSNumber(value: 6_344_835_080 as Int64),
            "stop_reason": "eos",
            "generated": NSNumber(value: 352),
            "ctx_used": NSNumber(value: 1236),
        ])
        #expect(decoded.plannedBytes == pb)
        #expect(decoded.stopReason == sr)
        #expect(decoded.generated == gen)
        #expect(decoded.ctxUsed == ctx)
    }
}
