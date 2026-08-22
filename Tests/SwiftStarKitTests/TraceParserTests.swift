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
