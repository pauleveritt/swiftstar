import Testing
@testable import SwiftStarKit

struct FindingTests {
    private let phraser = DeterministicPhraser()

    @Test func contextPositionPhraseCarriesNumbers() {
        let f = Finding.contextPosition(ctxUsed: 92_500, ctxSize: 150_000, severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("92,500") == false)  // Swift Int interpolation does not group digits
        #expect(s.contains("92500"))
        #expect(s.contains("150000"))
        #expect(s.contains("critical"))
    }

    @Test func baselineDriftPhraseCarriesRatio() {
        let f = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("44"))
        #expect(s.contains("330"))
        #expect(s.contains("7.5"))
    }

    @Test func willNotFixRatePhraseSaysCacheIsHealthy() {
        let f = Finding.compactionVerdict(verdict: .willNotFixRate(cacheHitFraction: 0.953), severity: .critical)
        let s = phraser.phrase(f)
        #expect(s.contains("already healthy"))
        #expect(s.contains("95%"))
    }

    @Test func mayRecoverCachePhraseSaysCacheMissing() {
        let f = Finding.compactionVerdict(verdict: .mayRecoverCache(cacheHitFraction: 0.1), severity: .warning)
        let s = phraser.phrase(f)
        #expect(s.contains("missing"))
        #expect(s.contains("10%"))
    }

    @Test func unknownVerdictPhraseAdmitsIt() {
        let f = Finding.compactionVerdict(verdict: .unknown, severity: .warning)
        let s = phraser.phrase(f)
        #expect(s.contains("unknown"))
    }

    @Test func severityHasLabel() {
        #expect(Severity.healthy.label == "healthy")
        #expect(Severity.warning.label == "warning")
        #expect(Severity.critical.label == "critical")
    }

    @Test func findingIsHashableForList() {
        let a = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        let b = Finding.baselineDrift(baselineTPS: 330, currentTPS: 44, ratio: 7.5, severity: .critical)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }
}
