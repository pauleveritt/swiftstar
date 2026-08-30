import Foundation
import Testing
@testable import SwiftStarKit

struct CaptureUsabilityTests {
    private static let hello =
        #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","ts","tool_request","pool"],"ts":1,"worker":0}"#
    private static func status(_ state: String, worker: Int = 0) -> String {
        #"{"t":"status","state":"\#(state)","ctx_used":1337,"ctx_size":51200,"ts":2,"worker":\#(worker)}"#
    }
    private static let startupReady =
        #"{"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":98812439616,"ts":3,"worker":0}"#

    @Test func idleSpawnRecordsNoWork() {
        // `captures/live/20260830-163255`: handshake, statuses, the engine's
        // field-less startup ready. Non-empty wire (4 KB), zero work.
        let lines = [Self.hello, Self.status("prefill"), Self.startupReady, Self.status("idle")]
        #expect(CaptureUsability.recordsWork(wireLines: lines) == false)
    }

    @Test func emptyWireRecordsNoWork() {
        #expect(CaptureUsability.recordsWork(wireLines: []) == false)
    }

    @Test func aCompletedTurnRecordsWork() {
        let lines = [
            Self.hello, Self.status("prefill"), Self.startupReady,
            #"{"t":"ready","planned_bytes":7770898440,"stop_reason":"eos","generated":191,"ctx_used":5020,"ts":4,"worker":0}"#,
        ]
        #expect(CaptureUsability.recordsWork(wireLines: lines) == true)
    }

    @Test func sessionKilledMidTurnRecordsWork() {
        // `captures/agenttest/20260829-125901`: 258 tool events, 34 tool
        // requests, 235 text — and only the field-less startup ready, because
        // the session never closed. Usable evidence; a completed-turn
        // predicate would discard it.
        let lines = [
            Self.hello, Self.status("prefill"), Self.startupReady,
            #"{"t":"text","text":"Looking at the roadmap","ts":5,"worker":0}"#,
            #"{"t":"tool_request","idx":0,"name":"read","params":[],"ts":6,"worker":0}"#,
        ]
        #expect(CaptureUsability.recordsWork(wireLines: lines) == true)
    }

    @Test func pooledCaptureWithWorkOnlyOnASubagentRecordsWork() {
        // `captures/agenttest/20260829-122222`: the orchestrator emits only
        // statuses and the startup ready; all 1141 generated tokens are on
        // worker 1. Reading the orchestrator's stream alone discards it.
        let lines = [
            Self.hello, Self.status("prefill"), Self.startupReady,
            #"{"t":"queued","ts":5,"worker":1}"#,
            Self.status("generating", worker: 1),
            #"{"t":"text","text":"the subagent's answer","ts":6,"worker":1}"#,
        ]
        #expect(CaptureUsability.recordsWork(wireLines: lines) == true)
    }
}
