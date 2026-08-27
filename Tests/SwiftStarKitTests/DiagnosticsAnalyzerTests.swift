import Testing
@testable import SwiftStarKit

private func status(_ ctx: Int, _ tps: Double, ts: UInt64 = 0) -> StatusSnapshot {
    StatusSnapshot(ctxUsed: ctx, ctxSize: 150_000, prefillTPS: tps, genTPS: 0, ts: ts, generated: 0, state: "")
}

private func severity(_ f: Finding) -> Severity? {
    switch f {
    case .contextPosition(_, _, let s): return s
    case .prefillThroughput: return .healthy
    case .baselineDrift(_, _, _, let s): return s
    case .prefixCache(_, let s): return s
    case .compactionObserved: return .healthy
    case .compactionVerdict(_, let s): return s
    }
}

struct DiagnosticsAnalyzerTests {
    private let analyzer = DiagnosticsAnalyzer()

    @Test func shallowHealthySessionHasNoCriticalFindings() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(958, 300)),
            .status(status(3_400, 330)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_026, cached: 958, suffix: 68, rc: 0, ms: 575.8)]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains { if case .contextPosition = $0 { true } else { false } })
        #expect(findings.contains { if case .prefillThroughput = $0 { true } else { false } })
        #expect(!findings.contains { if case .baselineDrift = $0 { true } else { false } })
        #expect(!findings.contains { if case .compactionVerdict = $0 { true } else { false } })
        #expect(!findings.contains { (severity($0) ?? .healthy) == .critical })
    }

    @Test func deepDegradedSessionFlagsBaselineDriftAndVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_074, cached: 1_024, suffix: 50, rc: 0, ms: 1_234.5)]
        let findings = analyzer.analyze(events: events, trace: trace)

        // baseline 330, current 44 → ratio 7.5 → critical
        #expect(findings.contains {
            if case .baselineDrift(let b, let c, let r, .critical) = $0 {
                return b == 330 && c == 44 && r > 7.4 && r < 7.6
            }
            return false
        })
        // deep (92_500 >= 37_500) + degraded + cache healthy → willNotFixRate
        #expect(findings.contains {
            if case .compactionVerdict(.willNotFixRate(let hit), .critical) = $0 {
                return hit > 0.9
            }
            return false
        })
        #expect(findings.contains {
            if case .contextPosition(92_500, 150_000, .critical) = $0 { return true }
            return false
        })
    }

    @Test func missingCacheDataGivesUnknownVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let findings = analyzer.analyze(events: events, trace: [])
        #expect(findings.contains {
            if case .compactionVerdict(.unknown, _) = $0 { return true }
            return false
        })
    }

    @Test func lowCacheHitGivesMayRecoverCacheVerdict() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
            .status(status(92_500, 44)),
        ]
        let trace: [TraceEvent] = [.prefillSync(prompt: 1_074, cached: 107, suffix: 967, rc: 0, ms: 99.0)]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains {
            if case .compactionVerdict(.mayRecoverCache(let hit), _) = $0 { return hit < 0.2 }
            return false
        })
    }

    @Test func compactionObservedIsReportedPerEvent() {
        let events: [WireEvent] = [
            .hello(version: 1, capabilities: ["status", "ready", "ts"]),
            .status(status(3_400, 330)),
        ]
        let trace: [TraceEvent] = [
            .compaction(reason: "ctx grew", old: 150_000, new: 45_000, tailStart: 42_000, tail: 3_000),
        ]
        let findings = analyzer.analyze(events: events, trace: trace)
        #expect(findings.contains {
            if case .compactionObserved(let c) = $0 {
                return c.oldTokens == 150_000 && c.newTokens == 45_000 && c.tailTokens == 3_000
            }
            return false
        })
    }
}
