import Testing
import Foundation
@testable import SwiftStarKit

struct DiagnosticsEvidenceFloorTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private static func wireEvents(_ dir: String, _ file: String) -> [WireEvent] {
        let url = repoRoot.appendingPathComponent("fixtures/\(dir)/\(file)")
        let text = try! String(contentsOf: url, encoding: .utf8)
        var parser = WireEventParser()
        var events: [WireEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { events.append(e) }
        }
        return events
    }

    private static func traceEvents(_ dir: String, _ file: String) -> [TraceEvent] {
        let url = repoRoot.appendingPathComponent("fixtures/\(dir)/\(file)")
        let text = try! String(contentsOf: url, encoding: .utf8)
        var parser = TraceParser()
        var events: [TraceEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { events.append(e) }
        }
        return events
    }

    private static func criticalFindings(_ findings: [Finding]) -> [Finding] {
        findings.filter {
            switch $0 {
            case .contextPosition(_, _, let s): return s == .critical
            case .prefillThroughput: return false
            case .baselineDrift(_, _, _, let s): return s == .critical
            case .prefixCache(_, let s): return s == .critical
            case .compactionObserved: return false
            case .compactionVerdict(_, let s): return s == .critical
            }
        }
    }

    @Test func acceptsKnownGoodGoldenCapture() {
        let analyzer = DiagnosticsAnalyzer()
        let events = Self.wireEvents("agent", "golden.ndjson")
        let trace = Self.traceEvents("agent", "golden.trace")
        let findings = analyzer.analyze(events: events, trace: trace)

        // The golden capture is two shallow, healthy turns: no critical findings,
        // no baseline drift, no compaction verdict.
        #expect(Self.criticalFindings(findings).isEmpty)
        #expect(!findings.contains { if case .baselineDrift = $0 { true } else { false } })
        #expect(!findings.contains { if case .compactionVerdict = $0 { true } else { false } })
        // Prefix cache IS healthy and reported.
        #expect(findings.contains { if case .prefixCache(let hit, .healthy) = $0 { return hit > 0.9 }; return false })
    }

    @Test func rejectsKnownBrokenPathologicalFixture() {
        let analyzer = DiagnosticsAnalyzer()
        let events = Self.wireEvents("diagnostics", "pathological.ndjson")
        let trace = Self.traceEvents("diagnostics", "pathological.trace")
        let findings = analyzer.analyze(events: events, trace: trace)

        #expect(findings.contains { if case .contextPosition(92_500, 150_000, .critical) = $0 { true } else { false } })
        #expect(findings.contains { if case .baselineDrift(330, 44, _, .critical) = $0 { true } else { false } })
        #expect(findings.contains { if case .compactionVerdict(.willNotFixRate(let hit), .critical) = $0 { hit > 0.9 } else { false } })
    }
}
