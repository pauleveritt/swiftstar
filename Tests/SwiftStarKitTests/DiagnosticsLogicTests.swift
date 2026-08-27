import Testing
@testable import SwiftStarKit

private func status(_ ctx: Int, _ tps: Double, ts: UInt64 = 0) -> StatusSnapshot {
    StatusSnapshot(ctxUsed: ctx, ctxSize: 150_000, prefillTPS: tps, genTPS: 0, ts: ts, generated: 0, state: "")
}

struct DiagnosticsLogicTests {
    @Test func baselineTakesMaxLowContextPrefill() {
        let statuses = [
            status(3_400, 330), status(10_000, 200), status(50_000, 90), status(92_500, 44),
        ]
        #expect(DiagnosticsLogic.baselineTPS(statuses) == 330)
    }

    @Test func baselineIgnoresOutlierViaMedian() {
        // A single garbage prefill sample (100k) must not poison the baseline
        // the way a no-floor .max() would: the median of [200, 330, 100k] is
        // 330, not 100k.
        let statuses = [
            status(1_000, 330), status(2_000, 200), status(3_000, 100_000),
        ]
        #expect(DiagnosticsLogic.baselineTPS(statuses) == 330)
    }

    @Test func baselineIgnoresHighContextAndZeroRate() {
        let statuses = [
            status(3_400, 0), status(20_000, 180), status(92_500, 44),
        ]
        // 3_400 has zero rate; 20_000 is above baselineWindowTokens; so no baseline.
        #expect(DiagnosticsLogic.baselineTPS(statuses) == nil)
    }

    @Test func currentTakesLastNonZeroRate() {
        let statuses = [
            status(3_400, 330), status(50_000, 90), status(92_500, 44), status(92_500, 0),
        ]
        #expect(DiagnosticsLogic.currentTPS(statuses) == 44)
    }

    @Test func degradationSeverityBands() {
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 1.5) == .healthy)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 2.0) == .warning)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 3.5) == .critical)
        #expect(DiagnosticsLogic.degradationSeverity(ratio: 7.5) == .critical)
    }

    @Test func prefixCacheSeverityBands() {
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.98) == .healthy)
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.50) == .healthy)
        #expect(DiagnosticsLogic.prefixCacheSeverity(hitFraction: 0.49) == .warning)
    }
}
