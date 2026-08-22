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

    @Test func statusLineParsesSnapshot() {
        var parser = WireEventParser()
        let line = #"{"t":"status","state":"prefill","prefill_done":2,"prefill_total":142,"prefill_tps":5.8,"generated":0,"gen_tps":0.0,"ctx_used":1100,"ctx_size":32768,"power":100,"error":""}"#
        #expect(parser.feed(line) == .status(StatusSnapshot(ctxUsed: 1100, ctxSize: 32768, prefillTPS: 5.8, genTPS: 0.0)))
    }

    @Test func readyLineParsesPlannedBytes() {
        var parser = WireEventParser()
        let line = #"{"t":"ready","kv_bytes":1686110208,"scratch_bytes":784752,"model_bytes":48257070080,"planned_bytes":49943965040}"#
        #expect(parser.feed(line) == .ready(plannedBytes: 49_943_965_040))
    }

    @Test func bareReadyHasNilBudget() {
        var parser = WireEventParser()
        #expect(parser.feed(#"{"t":"ready"}"#) == .ready(plannedBytes: nil))
    }

    @Test func otherKindsAreIgnoredNotRefused() {
        var parser = WireEventParser()
        for line in [#"{"t":"text","s":"hi"}"#, #"{"t":"think","s":"..."}"#,
                     #"{"t":"tool","phase":"start","idx":0}"#, #"{"t":"queued"}"#] {
            if case .ignored = parser.feed(line) {} else { Issue.record("expected .ignored for \(line)") }
        }
    }

    @Test func malformedLineIsIgnoredNotRefused() {
        var parser = WireEventParser()
        if case .ignored(let payload) = parser.feed("not json") { #expect(payload == "not json") }
        else { Issue.record("expected .ignored") }
    }

    @Test func blankLineIsNil() {
        var parser = WireEventParser()
        #expect(parser.feed("") == nil)
        #expect(parser.feed("   ") == nil)
    }

    @Test func goldenNdjsonParsesWithoutRefusing() throws {
        // Real invariants, not counts: every non-blank fixture line parses to
        // status/ready/ignored, never nil, and both telemetry kinds appear.
        let text = try String(contentsOf: Self.fixturesRoot.appendingPathComponent("golden.ndjson"), encoding: .utf8)
        var parser = WireEventParser()
        var statuses = 0, readies = 0
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline }) {
            let s = String(line)
            if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            switch parser.feed(s) {
            case .status: statuses += 1
            case .ready: readies += 1
            case .ignored: break
            case nil: Issue.record("non-blank line produced nil: \(s)")
            }
        }
        #expect(statuses > 0)
        #expect(readies > 0)
    }
}
