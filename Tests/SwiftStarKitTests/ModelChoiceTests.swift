import Testing
@testable import SwiftStarKit

struct ModelChoiceTests {
    @Test func customTrailsWithNoVariants() {
        let list = ModelChoice.list(variants: [])
        #expect(list.map(\.id) == ["custom"])
    }

    @Test func variantsLeadAndCustomTrails() {
        // No separate "default" entry: Laguna S is a registry variant now, and
        // it's what effectiveSelectedVariantID resolves to when nothing is
        // configured — a hardcoded default row would just duplicate it.
        let variants = VariantRegistry.all
        #expect(!variants.isEmpty)
        let list = ModelChoice.list(variants: variants)
        #expect(list.map(\.id) == variants.map(\.id) + ["custom"])
    }

    @Test func lagunaSAppearsExactlyOnce() {
        let list = ModelChoice.list(variants: VariantRegistry.all)
        #expect(list.filter { $0.id == VariantRegistry.lagunaS.id }.count == 1)
    }
}
