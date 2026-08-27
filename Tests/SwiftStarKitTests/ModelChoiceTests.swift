import Testing
@testable import SwiftStarKit

struct ModelChoiceTests {
    @Test func defaultLeadsAndCustomTrails() {
        let list = ModelChoice.list(variants: [])
        #expect(list.map(\.id) == ["default", "custom"])
    }

    @Test func variantsAreInterleaved() {
        let variants = VariantRegistry.all
        #expect(!variants.isEmpty)
        let list = ModelChoice.list(variants: variants)
        #expect(list.map(\.id) == ["default"] + variants.map(\.id) + ["custom"])
    }
}
