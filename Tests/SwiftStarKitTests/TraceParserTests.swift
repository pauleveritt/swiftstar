import Testing
import Foundation
@testable import SwiftStarKit

struct TraceParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    @Test func parsesCompactionLine() {
        var p = TraceParser()
        let line = #"2026-08-22 14:41:09.813 compacted reason="ctx grew" old=150000 new=45000 tail_start=42000 tail=3000"#
        #expect(p.feed(line) == .compaction(reason: "ctx grew", old: 150000, new: 45000, tailStart: 42000, tail: 3000))
    }

    @Test func parsesCompactionWithEscapedReason() {
        var p = TraceParser()
        let line = #"2026-08-22 14:41:09.813 compacted reason="said \"hi\" and\ncontinued" old=100 new=40 tail_start=30 tail=10"#
        #expect(p.feed(line) == .compaction(reason: "said \"hi\" and\ncontinued", old: 100, new: 40, tailStart: 30, tail: 10))
    }

    @Test func parsesPrefillSyncWithToolRound() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:10.704 prefill sync done tool_round=0 prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        #expect(p.feed(line) == .prefillSync(prompt: 1026, cached: 958, suffix: 68, rc: 0, ms: 575.820))
    }

    @Test func parsesPrefillSyncWithoutToolRound() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:10.704 prefill sync done prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        #expect(p.feed(line) == .prefillSync(prompt: 1026, cached: 958, suffix: 68, rc: 0, ms: 575.820))
    }

    @Test func ignoresUnknownLines() {
        var p = TraceParser()
        let line = "2026-08-22 14:41:09.831 sysprompt kv hit file=./.ds4/kvcache/sysprompt.kv tokens=958"
        #expect(p.feed(line) == .ignored(line))
        let tokenLine = "2026-08-22 14:41:09.831 token index=0 id=2 bytes=11 text=\"x\" hex=78"
        #expect(p.feed(tokenLine) == .ignored(tokenLine))
    }

    @Test func goldenTraceParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.trace")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = TraceParser()
        var events: [TraceEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = p.feed(s) { events.append(e) }
        }
        let syncs = events.filter { if case .prefillSync = $0 { return true } else { return false } }
        #expect(syncs.count == 2)  // golden.trace has two turns, each with one prefill sync
    }
}

/// P12.7 piece 2: `TraceSummary.sum` — whole-run Σprompt/Σcached/Σsuffix,
/// summing the engine's own reported fields verbatim (never deriving suffix
/// as prompt - cached). Pure and isolated from `main.swift` so it has real
/// unit coverage independent of a live engine run.
struct TraceSummaryTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    /// golden.trace has exactly two `prefill sync done` lines (grepped
    /// directly from the fixture):
    ///   prompt=1026 cached=958  suffix=68
    ///   prompt=1150 cached=1132 suffix=18
    /// so the whole-run totals are 1026+1150=2176, 958+1132=2090, 68+18=86.
    @Test func goldenTraceSumsBothPrefillSyncLines() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.trace")
        let text = try String(contentsOf: url, encoding: .utf8)
        let totals = TraceSummary.sum(traceText: text)
        #expect(totals == TraceTokenTotals(sumPrompt: 2176, sumCached: 2090, sumSuffix: 86))
    }

    @Test func emptyTraceSumsToZero() {
        #expect(TraceSummary.sum(traceText: "") == TraceTokenTotals())
        #expect(TraceSummary.sum(events: []) == TraceTokenTotals())
    }

    @Test func traceWithNoPrefillSyncLinesSumsToZero() {
        let text = """
        2026-08-22 14:41:09.813 compacted reason="ctx grew" old=150000 new=45000 tail_start=42000 tail=3000
        2026-08-22 14:41:09.831 sysprompt kv hit file=./.ds4/kvcache/sysprompt.kv tokens=958
        """
        #expect(TraceSummary.sum(traceText: text) == TraceTokenTotals())
    }

    @Test func oneLineSumsToItsOwnFields() {
        let line = "2026-08-22 14:41:10.704 prefill sync done tool_round=0 prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        #expect(TraceSummary.sum(traceText: line) == TraceTokenTotals(sumPrompt: 1026, sumCached: 958, sumSuffix: 68))
    }

    /// Multiple `.prefillSync` lines interleaved with a compaction line and an
    /// ignored (unmodeled) line — both must be skipped without affecting the sum.
    @Test func multipleLinesInterleavedWithNonSyncEventsSumCorrectly() {
        let text = """
        2026-08-22 14:41:09.813 compacted reason="ctx grew" old=150000 new=45000 tail_start=42000 tail=3000
        2026-08-22 14:41:10.704 prefill sync done tool_round=0 prompt=1026 cached=958 suffix=68 rc=0 575.820 ms
        2026-08-22 14:41:10.831 sysprompt kv hit file=./.ds4/kvcache/sysprompt.kv tokens=958
        2026-08-22 14:41:17.111 prefill sync done tool_round=1 prompt=1150 cached=1132 suffix=18 rc=0 164.369 ms
        """
        let totals = TraceSummary.sum(traceText: text)
        #expect(totals == TraceTokenTotals(sumPrompt: 2176, sumCached: 2090, sumSuffix: 86))
    }

    /// `sum(events:)` directly, bypassing the line parser — the same three
    /// fields, plus proof that a non-`.prefillSync` event (`.compaction`,
    /// `.ignored`) contributes nothing.
    @Test func sumOverEventsSkipsNonPrefillSyncCases() {
        let events: [TraceEvent] = [
            .compaction(reason: "x", old: 1, new: 2, tailStart: 3, tail: 4),
            .prefillSync(prompt: 100, cached: 40, suffix: 60, rc: 0, ms: 1.0),
            .ignored("some unmodeled line"),
            .prefillSync(prompt: 200, cached: 150, suffix: 50, rc: 0, ms: 2.0),
        ]
        #expect(TraceSummary.sum(events: events) == TraceTokenTotals(sumPrompt: 300, sumCached: 190, sumSuffix: 110))
    }
}
