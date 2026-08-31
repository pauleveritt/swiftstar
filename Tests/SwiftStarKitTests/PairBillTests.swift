import Testing
import Foundation
@testable import SwiftStarKit

/// `PairBill` (task 4, eval-cli): reduces two arms' capture trees to one
/// paired delta — the capture-to-bill step the eval-cli self-review found
/// ownerless. Moved out of `swiftstar-analyze`'s `cmdDiff`.
struct PairBillTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private static let hello =
        #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","ts","tool_request","pool"],"ts":1,"worker":0}"#
    private static func status(_ state: String) -> String {
        #"{"t":"status","state":"\#(state)","ctx_used":1337,"ctx_size":51200,"ts":2,"worker":0}"#
    }
    private static let startupReady =
        #"{"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":98812439616,"ts":3,"worker":0}"#

    /// A wire that records work: handshake, startup ready, one completed turn.
    private static let workingWire = [
        hello, status("prefill"), startupReady,
        #"{"t":"ready","planned_bytes":7770898440,"stop_reason":"eos","generated":191,"ctx_used":5020,"ts":4,"worker":0}"#,
    ].joined(separator: "\n")

    /// A wire that records no work: handshake, statuses, the startup ready —
    /// same shape as an agent spawned and left idle.
    private static let idleWire = [hello, status("prefill"), startupReady, status("idle")].joined(separator: "\n")

    private static func trace(suffixes: [Int]) -> String {
        suffixes.enumerated().map { i, suffix in
            "2026-08-22 14:41:\(10 + i).704 prefill sync done prompt=1000 cached=900 suffix=\(suffix) rc=0 100.0 ms"
        }.joined(separator: "\n")
    }

    @Test func suffixTotalMatchesTheAnalyzerOnACommittedTrace() throws {
        // fixtures/agent/golden.trace — the committed fixture also used by
        // TraceParserTests. Two prefill syncs, suffix 66 and 16 (grepped).
        let url = Self.fixturesRoot.appendingPathComponent("golden.trace")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(PairBill.suffixTotal(trace: text) == 82)
    }

    @Test func reduceProducesTheDelta() {
        let control = CaptureTree(armID: "control", traceText: Self.trace(suffixes: [10, 20]), wireText: Self.workingWire)
        let treatment = CaptureTree(armID: "treatment", traceText: Self.trace(suffixes: [15, 25]), wireText: Self.workingWire)
        let result = PairBill.reduce(pair: 1, control: control, treatment: treatment)
        switch result {
        case .success(let pairResult):
            #expect(pairResult.pair == 1)
            #expect(pairResult.controlSuffix == 30)
            #expect(pairResult.treatmentSuffix == 40)
            #expect(pairResult.delta == 10)
        case .failure:
            Issue.record("expected a PairResult")
        }
    }

    @Test func oneUnusableArmDropsTheWholePair() {
        let control = CaptureTree(armID: "control", traceText: Self.trace(suffixes: [10]), wireText: Self.idleWire)
        let treatment = CaptureTree(armID: "treatment", traceText: Self.trace(suffixes: [15]), wireText: Self.workingWire)
        let result = PairBill.reduce(pair: 1, control: control, treatment: treatment)
        switch result {
        case .success:
            Issue.record("expected the pair dropped: control records no work")
        case .failure(let drop):
            #expect(drop == .unusable(arm: "control", reason: "wire records no work"))
        }
    }

    @Test func bothUsableIsKept() {
        let control = CaptureTree(armID: "control", traceText: Self.trace(suffixes: [10]), wireText: Self.workingWire)
        let treatment = CaptureTree(armID: "treatment", traceText: Self.trace(suffixes: [15]), wireText: Self.workingWire)
        let result = PairBill.reduce(pair: 2, control: control, treatment: treatment)
        switch result {
        case .success(let pairResult):
            #expect(pairResult.pair == 2)
        case .failure:
            Issue.record("expected both arms usable")
        }
    }
}
