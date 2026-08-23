import Testing
@testable import SwiftStarKit

struct EnvelopeMathTests {
    @Test func overheadRatioIsRealizedOverCeiling() {
        #expect(EnvelopeMath.overheadRatio(realizedWin: 4.2) == 1.0)
        #expect(EnvelopeMath.overheadRatio(realizedWin: 2.1) == 0.5)
    }
    @Test func reportCarriesAllEnvelopeArms() {
        let r = EnvelopeMath.report(
            winByPerturbation: [.canonical: 2.5, .taskTextBloat2x: 1.1],
            tokensEvaluated: 900, tokensNominal: 1000,
            peakResidentMB: 41000, snapshotSaveCount: 0, snapshotRestoreCount: 0)
        #expect(r.winByPerturbation[.canonical] == 2.5)
        #expect(r.tokensEvaluated == 900)
        #expect(r.snapshotSaveCount == 0)
        #expect(r.overheadRatio == EnvelopeMath.overheadRatio(realizedWin: 2.5))
    }
    @Test func zeroWinIsNotANumberHazard() {
        // a realized win of 0 (the pool did no better than deep) → ratio 0, not NaN
        #expect(EnvelopeMath.overheadRatio(realizedWin: 0) == 0)
    }
    @Test func perturbationsAreDeterministic() {
        let t = "fix a.swift"
        #expect(PacketPerturbation.canonical.apply(to: t) == t)
        #expect(PacketPerturbation.taskTextBloat2x.apply(to: t).count > t.count)
        #expect(PacketPerturbation.taskTextBloat2x.apply(to: t) == PacketPerturbation.taskTextBloat2x.apply(to: t))
        #expect(PacketPerturbation.packetCountSweepCounts == [1, 2, 4, 8])
    }
    @Test func bloatArmsScaleByTheAdvertisedFactor() {
        let t = String(repeating: "x", count: 140)  // 140 chars
        let b15 = PacketPerturbation.taskTextBloat15x.apply(to: t)
        let b2 = PacketPerturbation.taskTextBloat2x.apply(to: t)
        #expect((200...220).contains(b15.count))   // ~1.5x (210)
        #expect((270...290).contains(b2.count))    // ~2x (280)
    }
}
