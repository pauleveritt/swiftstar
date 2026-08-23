import Testing
@testable import SwiftStarKit

struct AgentTestAnalyzerTests {
    @Test func computesMetricsFromTheWire() {
        let wire = [
            #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":0,"worker":0}"#,
            #"{"t":"ready","kv_bytes":1,"ts":1,"worker":0}"#,
            #"{"t":"tool_request","idx":0,"name":"read","params":[{"name":"path","value":"a.txt"}],"ts":2,"worker":1}"#,
            #"{"t":"text","s":"ok","ts":3,"worker":1}"#,
            #"{"t":"tool_request","idx":0,"name":"read","params":[{"name":"path","value":"a.txt"}],"ts":4,"worker":1}"#,
            #"{"t":"tool_request","idx":1,"name":"write","params":[{"name":"path","value":"b.txt"}],"ts":5,"worker":1}"#,
            #"{"t":"tool_request","idx":2,"name":"write","params":[{"name":"path","value":"b.txt"}],"ts":6,"worker":1}"#,
            #"{"t":"ready","stop_reason":"eos","generated":10,"ctx_used":500,"ts":7,"worker":1}"#,
        ]
        var parser = PoolWireParser()
        var events: [PoolWireEvent] = []
        for line in wire {
            if let ev = parser.feed(line) { events.append(ev) }
        }
        let report = AgentTestAnalyzer.analyze(events: events)
        #expect(report.phases.count == 1)
        let p = report.phases[0]
        #expect(p.worker == WorkerId(1))
        #expect(p.toolCalls == 4)                 // read, read, write, write
        #expect(p.rounds == 2)                    // (read) then (read,write,write)
        #expect(p.reReads == 1)                   // a.txt read twice
        #expect(p.repeatedIdenticalCalls == 1)    // the two consecutive `write b.txt`
        #expect(p.generatedTokens == 10)
        #expect(p.ctxAtEnd == 500)
        #expect(report.totalToolCalls == 4)
        #expect(report.summary().contains("4 tool calls"))
    }

    @Test func workerZeroEventsAreIgnored() {
        let wire = [
            #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":0,"worker":0}"#,
            #"{"t":"text","s":"orchestrator prose","ts":1,"worker":0}"#,
            #"{"t":"ready","stop_reason":"eos","generated":3,"ctx_used":100,"ts":2,"worker":0}"#,
        ]
        var parser = PoolWireParser()
        var events: [PoolWireEvent] = []
        for line in wire { if let ev = parser.feed(line) { events.append(ev) } }
        #expect(AgentTestAnalyzer.analyze(events: events).phases.isEmpty)
    }
}
