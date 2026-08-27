import Testing
import Foundation
@testable import SwiftStarKit

struct WireEventParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private static let handshake = #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":0}"#

    @Test func helloParsesHandshake() {
        var parser = WireEventParser()
        let event = parser.feed(Self.handshake)
        #expect(event == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"]))
    }

    @Test func firstNonBlankLineMustBeHandshake() {
        var parser = WireEventParser()
        let line = #"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":0}"#
        if case .refused = parser.feed(line) {} else { Issue.record("expected .refused for non-handshake first line") }
    }

    @Test func unknownVersionRefuses() {
        var parser = WireEventParser()
        let line = #"{"t":"hello","v":99,"caps":["status","ready","ts"],"ts":0}"#
        if case .refused = parser.feed(line) {} else { Issue.record("expected .refused for unknown version") }
    }

    @Test func missingRequiredCapRefuses() {
        var parser = WireEventParser()
        let line = #"{"t":"hello","v":1,"caps":["status","ready"],"ts":0}"#
        if case .refused = parser.feed(line) {} else { Issue.record("expected .refused for missing ts cap") }
    }

    @Test func malformedFirstLineRefuses() {
        var parser = WireEventParser()
        if case .refused(let payload) = parser.feed("not json") { #expect(payload == "not json") }
        else { Issue.record("expected .refused") }
    }

    @Test func statusCarriesTs() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        let line = #"{"t":"status","state":"prefill","prefill_done":2,"prefill_total":142,"prefill_tps":5.8,"generated":0,"gen_tps":0.0,"ctx_used":1100,"ctx_size":32768,"power":100,"error":"","ts":12345}"#
        #expect(parser.feed(line) == .status(StatusSnapshot(ctxUsed: 1100, ctxSize: 32768, prefillTPS: 5.8, genTPS: 0.0, ts: 12345, generated: 0, state: "prefill", power: 100)))
    }

    @Test func statusCarriesErrorAndPower() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        let line = #"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":87,"error":"engine failure","ts":1}"#
        #expect(parser.feed(line) == .status(StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0, ts: 1, generated: 0, state: "idle", power: 87, error: "engine failure")))
    }

    @Test func readyLineParsesPlannedBytes() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        let line = #"{"t":"ready","kv_bytes":1686110208,"scratch_bytes":784752,"model_bytes":48257070080,"planned_bytes":49943965040,"ts":1}"#
        #expect(parser.feed(line) == .ready(plannedBytes: 49_943_965_040))
    }

    @Test func bareReadyHasNilBudget() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        #expect(parser.feed(#"{"t":"ready","ts":1}"#) == .ready(plannedBytes: nil))
    }

    @Test func otherKindsAreIgnoredNotRefused() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        for line in [#"{"t":"text","s":"hi","ts":1}"#, #"{"t":"think","s":"...","ts":1}"#,
                     #"{"t":"tool","phase":"start","idx":0,"ts":1}"#, #"{"t":"queued","ts":1}"#] {
            if case .ignored = parser.feed(line) {} else { Issue.record("expected .ignored for \(line)") }
        }
    }

    @Test func malformedLineAfterHandshakeIsIgnored() {
        var parser = WireEventParser()
        _ = parser.feed(Self.handshake)
        if case .ignored(let payload) = parser.feed("not json") { #expect(payload == "not json") }
        else { Issue.record("expected .ignored") }
    }

    @Test func blankLineIsNil() {
        var parser = WireEventParser()
        #expect(parser.feed("") == nil)
        #expect(parser.feed("   ") == nil)
    }

    @Test func goldenNdjsonParsesWithoutRefusing() throws {
        // The recaptured fixture (P5) starts with the handshake; every non-blank
        // line after it parses to hello/status/ready/ignored, never nil, and both
        // telemetry kinds appear.
        let text = try String(contentsOf: Self.fixturesRoot.appendingPathComponent("golden.ndjson"), encoding: .utf8)
        var parser = WireEventParser()
        var statuses = 0, readies = 0, sawHello = false
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let s = String(line)
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            switch parser.feed(s) {
            case .hello: sawHello = true
            case .status: statuses += 1
            case .ready: readies += 1
            case .ignored: break
            case .refused(let payload): Issue.record("unexpected refusal: \(payload)")
            case nil: Issue.record("non-blank line produced nil: \(s)")
            }
        }
        #expect(sawHello)
        #expect(statuses > 0)
        #expect(readies > 0)
    }
}
