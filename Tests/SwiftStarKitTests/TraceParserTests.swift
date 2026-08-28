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

/// The engine's `--trace` token dumps embed raw bytes, and a truncated
/// multibyte sequence is a real occurrence, not a hypothetical: in
/// `captures/live/20260827-200648/agent.trace` the engine wrote
/// `text=" \xe2\x8c"` (an incomplete 3-byte lead) at byte 246,007, which made
/// the strict all-or-nothing `String(contentsOf:encoding:.utf8)` read of the
/// whole 2.3 MB file return nil — the analyzer then reported "no trace" and
/// Σsuffix 0 for a session with 28 real prefill syncs. The read must be
/// lossy: malformed subsequences become U+FFFD, every other line still parses.
struct TraceLossyReadTests {
    /// sync + token-dump-with-truncated-multibyte + sync, exactly the shape
    /// of the failing live trace: valid lines on both sides of the bad byte.
    private static func traceDataWithTruncatedSequence() -> Data {
        let sync1 = "2026-08-22 14:41:10.704 prefill sync done prompt=1026 cached=958 suffix=68 rc=0 575.820 ms"
        let sync2 = "2026-08-22 14:41:11.001 prefill sync done tool_round=1 prompt=1150 cached=1132 suffix=18 rc=0 164.369 ms"
        let bad: [UInt8] = [0x32, 0x30, 0x32, 0x36, 0x2D, 0x30, 0x38, 0x2D, 0x32, 0x32, 0x20, 0x31, 0x34, 0x3A, 0x34, 0x31, 0x3A, 0x31, 0x30, 0x2E, 0x37, 0x30, 0x35, 0x20, 0x74, 0x6F, 0x6B, 0x65, 0x6E, 0x20, 0x69, 0x6E, 0x64, 0x65, 0x78, 0x3D, 0x30, 0x20, 0x69, 0x64, 0x3D, 0x32, 0x20, 0x62, 0x79, 0x74, 0x65, 0x73, 0x3D, 0x33, 0x20, 0x74, 0x65, 0x78, 0x74, 0x3D, 0x22, 0x20, 0xE2, 0x8C, 0x22, 0x20, 0x68, 0x65, 0x78, 0x3D, 0x32, 0x30, 0x65, 0x32, 0x38, 0x63, 0x0A]
        var data = Data((sync1 + "\n").utf8)
        data.append(contentsOf: bad)
        data.append(Data((sync2 + "\n").utf8))
        return data
    }

    /// The fixture itself must be genuinely invalid UTF-8 — this guard keeps
    /// the test honest if someone "fixes" it by making the bad byte valid.
    @Test func fixtureIsGenuinelyInvalidUtf8() {
        #expect(String(data: Self.traceDataWithTruncatedSequence(), encoding: .utf8) == nil)
    }

    @Test func lossyDecodeKeepsPrefillSyncsAroundInvalidTokenBytes() {
        let events = TraceParser.parse(data: Self.traceDataWithTruncatedSequence())
        let syncs = events.compactMap { e -> (prompt: Int, suffix: Int)? in
            if case .prefillSync(let prompt, _, let suffix, _, _) = e { return (prompt, suffix) }
            return nil
        }
        #expect(syncs.map(\.prompt) == [1026, 1150])
        #expect(syncs.map(\.suffix) == [68, 18])
    }

    /// The call-site path (`swiftstar-analyze` and the app both read a URL):
    /// a file read through the same lossy decode yields the syncs too.
    @Test func lossyFileReadKeepsPrefillSyncs() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trace-lossy-read-\(UUID().uuidString).trace")
        try Self.traceDataWithTruncatedSequence().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let events = TraceParser.read(url: url)
        let syncs = events.compactMap { e -> Int? in
            if case .prefillSync(_, _, let suffix, _, _) = e { return suffix }
            return nil
        }
        #expect(syncs == [68, 18])
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
    /// directly from the fixture, P23 recapture):
    ///   prompt=1017 cached=951  suffix=66
    ///   prompt=1119 cached=1103 suffix=16
    /// so the whole-run totals are 1017+1119=2136, 951+1103=2054, 66+16=82.
    /// These counts drift on every recapture (generation cadence varies
    /// run-to-run — the P7/P9 precedent), unlike `planned_bytes` above.
    @Test func goldenTraceSumsBothPrefillSyncLines() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.trace")
        let text = try String(contentsOf: url, encoding: .utf8)
        let totals = TraceSummary.sum(traceText: text)
        #expect(totals == TraceTokenTotals(sumPrompt: 2136, sumCached: 2054, sumSuffix: 82))
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
