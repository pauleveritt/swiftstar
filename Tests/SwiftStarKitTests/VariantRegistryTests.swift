import Testing
import Foundation
@testable import SwiftStarKit

struct VariantRegistryTests {
    @Test func resolvesMellum() throws {
        let variant = try #require(VariantRegistry.resolve("mellum-2.1"))
        #expect(variant.id == "mellum-2.1")
        #expect(variant.family == .mellum)
        #expect(variant.contract.architecture == "mellum")
        #expect(variant.contract.rope.scalingType == "yarn")
        #expect(variant.contract.rope.freqBase == 500_000.0)
        #expect(variant.contract.quantLayout.downType == .q8_0)
        #expect(variant.contract.quantLayout.layerCount == 28)
        #expect(variant.contract.quantLayout.downTensorName(layer: 3) == "blk.3.ffn_down_exps.weight")
        // JetBrains' published Mellum sampling (ds4.c:63358).
        #expect(variant.sampler?.temperature == 0.6)
        #expect(variant.sampler?.topK == 20)
        #expect(variant.sampler?.topP == 0.95)
        #expect(variant.sampler?.minP == 0.0)
    }

    @Test func unknownIDIsNil() {
        #expect(VariantRegistry.resolve("nope") == nil)
    }

    @Test func allContainsMellum() {
        #expect(VariantRegistry.all.map(\.id).contains("mellum-2.1"))
    }
}

struct MemoryBudgetTests {
    private let budget = VariantRegistry.mellum.contract.memoryBudget

    @Test func kvAnchors() {
        #expect(budget.kvGiB(at: 16_384) == 0.26)
        #expect(budget.kvGiB(at: 32_768) == 0.48)
        #expect(budget.kvGiB(at: 40_960) == 0.59)
    }

    @Test func kvInterpolatesLinearly() {
        // Midpoint of the 16k..32k segment: t=0.25 -> 0.26 + 0.22*0.25 = 0.315.
        let kv = try? #require(budget.kvGiB(at: 20_480))
        #expect(kv == 0.315)
    }

    @Test func unsupportedContextIsNil() {
        #expect(budget.kvGiB(at: 16_383) == nil)
        #expect(budget.kvGiB(at: 40_961) == nil)
        #expect(budget.totalBytes(at: 65_536) == nil)
    }

    @Test func totalAt40kIsDocumentedTotal() throws {
        let total = try #require(budget.totalBytes(at: 40_960))
        // 9.33 weights + 0.4 scratch + 0.59 KV = 10.32 GiB.
        let gib = Double(total) / 1_073_741_824
        #expect(abs(gib - 10.32) < 0.001)
    }

    @Test func totalAt32kIsLowerThan40k() throws {
        let t32 = try #require(budget.totalBytes(at: 32_768))
        let t40 = try #require(budget.totalBytes(at: 40_960))
        #expect(t32 < t40)
    }
}

struct VariantResolverTests {
    @Test func variantBeatsLegacyPath() {
        let variant = VariantRegistry.mellum
        let (url, resolved) = VariantResolver.resolveModelFile(
            selectedVariantID: "mellum-2.1",
            modelPath: "/legacy/path.gguf",
            envModel: nil,
            fallback: URL(fileURLWithPath: "/fallback.gguf")
        )
        #expect(url == variant.modelFile)
        #expect(resolved?.id == "mellum-2.1")
    }

    @Test func customSentinelFallsThroughToLegacy() {
        let (url, resolved) = VariantResolver.resolveModelFile(
            selectedVariantID: "custom",
            modelPath: "/legacy/path.gguf",
            envModel: nil,
            fallback: URL(fileURLWithPath: "/fallback.gguf")
        )
        #expect(url.path == "/legacy/path.gguf")
        #expect(resolved == nil)
    }

    @Test func nilSelectionUsesEnvThenFallback() {
        let (url1, r1) = VariantResolver.resolveModelFile(
            selectedVariantID: nil, modelPath: nil,
            envModel: "/env.gguf", fallback: URL(fileURLWithPath: "/fallback.gguf"))
        #expect(url1.path == "/env.gguf")
        #expect(r1 == nil)

        let (url2, r2) = VariantResolver.resolveModelFile(
            selectedVariantID: nil, modelPath: nil,
            envModel: nil, fallback: URL(fileURLWithPath: "/fallback.gguf"))
        #expect(url2.path == "/fallback.gguf")
        #expect(r2 == nil)
    }
}
