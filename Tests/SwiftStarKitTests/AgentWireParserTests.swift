import Testing
import Foundation
@testable import SwiftStarKit

struct AgentWireParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private static let helloLine = #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":100}"#

    private func feedAll(_ parser: inout AgentWireParser, _ text: String) -> [AgentEvent] {
        var out: [AgentEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { out.append(e) }
        }
        return out
    }

    @Test func handshakeParses() {
        var p = AgentWireParser()
        let events = feedAll(&p, Self.helloLine)
        #expect(events == [.hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"])])
    }

    @Test func firstNonBlankLineMustBeHandshake() {
        var p = AgentWireParser()
        let refused = p.feed(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#)
        #expect(refused == .refused(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#))
    }

    @Test func missingRequiredCapRefuses() {
        var p = AgentWireParser()
        // caps lacks "tool" — the transcript cannot be built; refuse loudly.
        let line = #"{"t":"hello","v":1,"caps":["status","ready","text","ts"],"ts":1}"#
        #expect(p.feed(line) == .refused(line))
    }

    @Test func unknownVersionRefuses() {
        var p = AgentWireParser()
        let line = #"{"t":"hello","v":2,"caps":["status","ready","text","think","tool","queued","ts"],"ts":1}"#
        #expect(p.feed(line) == .refused(line))
    }

    @Test func parsesToolBlockPhases() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let start = p.feed(#"{"t":"tool","phase":"start","idx":0,"ts":10}"#)
        #expect(start == .tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let tool = p.feed(#"{"t":"tool","phase":"tool","idx":0,"name":"read","ts":11}"#)
        #expect(tool == .tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let pb = p.feed(#"{"t":"tool","phase":"param_begin","idx":0,"kind":"path","name":"path","ts":12}"#)
        #expect(pb == .tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        let pv = p.feed(#"{"t":"tool","phase":"param_value","idx":0,"s":"seed.txt","ts":13}"#)
        #expect(pv == .tool(AgentToolEvent(phase: .paramValue, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "seed.txt", status: nil, calls: nil)))
        let pe = p.feed(#"{"t":"tool","phase":"param_end","idx":0,"ts":14}"#)
        #expect(pe == .tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let finish = p.feed(#"{"t":"tool","phase":"finish","idx":0,"calls":1,"ts":15}"#)
        #expect(finish == .tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        let output = p.feed(#"{"t":"tool","phase":"output","idx":0,"s":"1 hello from golden-tools\n","ts":16}"#)
        #expect(output == .tool(AgentToolEvent(phase: .output, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "1 hello from golden-tools\n", status: nil, calls: nil)))
    }

    @Test func finishCarriesInterruptedStatus() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"tool","phase":"finish","idx":0,"calls":1,"status":"[tool call interrupted]\n","ts":20}"#
        #expect(p.feed(line) == .tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: "[tool call interrupted]\n", calls: 1)))
    }

    @Test func textAndThinkParse() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        #expect(p.feed(#"{"t":"text","s":"hello","ts":1}"#) == .text("hello"))
        #expect(p.feed(#"{"t":"think","s":"hmm","ts":2}"#) == .think("hmm"))
    }

    @Test func statusCarriesState() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // The shared StatusSnapshot carries the wire's state string: D6's turn
        // end is inferred from state → idle, and the controller needs it.
        let line = #"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#
        #expect(p.feed(line) == .status(StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0.0, genTPS: 0.0, ts: 5, generated: 0, state: "idle")))
    }

    @Test func statusCarriesGeneratedCounter() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // The monotonic generated-token counter feeds TurnSummary's decode
        // average (Δgenerated / Δts over a turn).
        let line = #"{"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":512,"gen_tps":41.2,"ctx_used":958,"ctx_size":32768,"power":80,"error":"","ts":6500000000000}"#
        #expect(p.feed(line) == .status(StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0.0, genTPS: 41.2, ts: 6_500_000_000_000, generated: 512, state: "generating")))
    }

    @Test func queuedAndReadyParse() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        #expect(p.feed(#"{"t":"queued","ts":1}"#) == .queued)
        #expect(p.feed(#"{"t":"ready","kv_bytes":1,"scratch_bytes":2,"model_bytes":3,"planned_bytes":4,"ts":2}"#) == .ready(plannedBytes: 4, stopReason: nil, generated: nil, ctxUsed: nil))
        #expect(p.feed(#"{"t":"ready","ts":3}"#) == .ready(plannedBytes: nil, stopReason: nil, generated: nil, ctxUsed: nil))  // ctx_size <= 0 sessions omit the plan
    }

    @Test func readyCarriesTurnOutcomeFields() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // D12: the turn-end ready carries the stop reason and final figures.
        #expect(p.feed(#"{"t":"ready","stop_reason":"context_full","generated":7,"ctx_used":32768,"ts":4}"#) == .ready(plannedBytes: nil, stopReason: "context_full", generated: 7, ctxUsed: 32768))
        // And the fields coexist with the memory plan.
        #expect(p.feed(#"{"t":"ready","kv_bytes":1,"planned_bytes":4,"stop_reason":"eos","generated":9,"ctx_used":100,"ts":5}"#) == .ready(plannedBytes: 4, stopReason: "eos", generated: 9, ctxUsed: 100))
    }

    @Test func unknownLinesIgnored() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"future_event","x":1,"ts":1}"#
        #expect(p.feed(line) == .ignored(line))
    }

    // P9: the bidirectional wire. `tool_request` is the host-tools event the
    // agent emits instead of executing; the parser must accept it after the
    // handshake and surface it as `.toolRequest` (reusing the transcript's
    // `ToolParam`). The hello caps may advertise "tool_request" but the parser
    // must not require it (backward compatible; requiredCaps unchanged).
    @Test func toolRequestParses() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"tool_request","idx":2,"name":"read","params":[{"name":"path","value":"seed.txt"}],"ts":99}"#
        #expect(p.feed(line) == .toolRequest(idx: 2, name: "read", params: [ToolParam(name: "path", value: "seed.txt")]))
    }

    @Test func toolRequestMultipleParamsPreserveOrder() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"tool_request","idx":1,"name":"bash","params":[{"name":"cmd","value":"ls"},{"name":"cwd","value":"/tmp"}],"ts":5}"#
        #expect(p.feed(line) == .toolRequest(idx: 1, name: "bash", params: [
            ToolParam(name: "cmd", value: "ls"),
            ToolParam(name: "cwd", value: "/tmp"),
        ]))
    }

    @Test func toolRequestEmptyParamsParses() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        #expect(p.feed(#"{"t":"tool_request","idx":0,"name":"list","params":[],"ts":1}"#) == .toolRequest(idx: 0, name: "list", params: []))
    }

    @Test func toolRequestOmittedParamsParses() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // `params` is optional on the wire — a tool with no params may omit it.
        #expect(p.feed(#"{"t":"tool_request","idx":0,"name":"ping","ts":1}"#) == .toolRequest(idx: 0, name: "ping", params: []))
    }

    @Test func toolRequestMissingNameRefused() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // `name` is required; without it the tool_request is a LOUD refusal,
        // not `.ignored`: the engine emits one request then blocks on its
        // result, so an `.ignored` malformed request would let the controller
        // skip the `tool_result` and the engine would hang forever. The idx is
        // carried best-effort (0 when unparseable) so the controller can write
        // an `ok:false` `tool_result` that unblocks the engine.
        let line = #"{"t":"tool_request","idx":0,"params":[],"ts":1}"#
        let event = p.feed(line)
        guard case .toolRequestRefused(let idx, let reason) = event else {
            Issue.record("expected .toolRequestRefused for a missing-name tool_request, got \(event)"); return
        }
        #expect(idx == 0)
        #expect(reason.contains("malformed tool_request"))
    }

    @Test func toolRequestMissingNameRefusedCarriesBestEffortIdx() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // The idx is still parseable when only `name` is missing; the refusal
        // carries it so the controller's `tool_result` matches the engine's
        // expected idx (avoiding a spurious idx-mismatch on a different call).
        let line = #"{"t":"tool_request","idx":3,"params":[],"ts":1}"#
        let event = p.feed(line)
        guard case .toolRequestRefused(let idx, _) = event else {
            Issue.record("expected .toolRequestRefused, got \(event)"); return
        }
        #expect(idx == 3)
    }

    @Test func handshakeMayAdvertiseToolRequestCap() {
        var p = AgentWireParser()
        // The host may advertise "tool_request" in caps; the parser must not
        // require it (backward compatible; requiredCaps unchanged).
        let line = #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","tool_request"],"ts":1}"#
        #expect(p.feed(line) == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts", "tool_request"]))
    }

    @Test func goldenNdjsonParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = AgentWireParser()
        let events = feedAll(&p, text)
        #expect(events.first == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"]))
        #expect(events.allSatisfy { if case .refused = $0 { return false } else { return true } })
        // 45-line text-only capture: 1 hello, 3 ready, 20 status, no tool events.
        #expect(events.filter { if case .tool = $0 { return true } else { return false } }.isEmpty)
    }

    @Test func goldenToolsNdjsonParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = AgentWireParser()
        let events = feedAll(&p, text)
        #expect(events.first == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"]))
        #expect(events.allSatisfy { if case .refused = $0 { return false } else { return true } })
        // The tool capture must actually carry tool events (evidence floor).
        let toolEvents = events.compactMap { if case .tool(let te) = $0 { return te } else { return nil } }
        #expect(toolEvents.contains { $0.phase == .start })
        #expect(toolEvents.contains { $0.phase == .output })
        #expect(toolEvents.contains { $0.phase == .finish })
        // D12 (evidence floor): the capture's turn-end readys carry the stop reason.
        let readyReasons = events.compactMap { if case .ready(_, let stop, _, _) = $0 { return stop } else { return nil } }
        #expect(readyReasons.contains { $0 != nil })
    }
}
