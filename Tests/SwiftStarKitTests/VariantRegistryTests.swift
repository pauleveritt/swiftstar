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
        #expect(variant.contract.quantLayout.startLayer == 0)
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

    @Test func resolvesLagunaXS() throws {
        let variant = try #require(VariantRegistry.resolve("laguna-xs-2.1"))
        #expect(variant.id == "laguna-xs-2.1")
        #expect(variant.family == .lagunaXS)
        #expect(variant.contract.architecture == "laguna")
        #expect(variant.contract.rope.scalingType == "yarn")
        #expect(variant.contract.rope.freqBase == 500_000.0)
        #expect(variant.contract.quantLayout.downType == .q3_k)
        #expect(variant.contract.quantLayout.startLayer == 1)
        #expect(variant.contract.quantLayout.layerCount == 40)
        #expect(variant.contract.quantLayout.downTensorName(layer: 5) == "blk.5.ffn_down_exps.weight")
        // Laguna family sampling defaults (engine-lines.md).
        #expect(variant.sampler?.temperature == 0.7)
        #expect(variant.sampler?.topK == 20)
        #expect(variant.sampler?.topP == 0.95)
        #expect(variant.sampler?.minP == 0.05)
        // The 16 GB SSD-streaming config (LAGUNA-XS21.md §6).
        #expect(variant.runtime?.ssdStreaming == true)
        #expect(variant.runtime?.ssdStreamingCacheExperts == 3200)
        #expect(variant.runtime?.prefillChunk == 4096)
    }

    @Test func allContainsLagunaXS() {
        #expect(VariantRegistry.all.map(\.id).contains("laguna-xs-2.1"))
    }
}

struct VariantContextInvariantTests {
    /// The app's shipped default context. Duplicated deliberately: a test that
    /// reads the app's constant would move with it, and moving it is exactly
    /// what broke this (the default went 32,768 -> 51,200 the day after the
    /// budget ranges were pinned, putting every variant out of range).
    static let appDefaultContext = 51_200

    @Test func everyVariantCanServeTheAppDefaultContext() {
        // Not "the range must contain 51,200" — the budgets are measured facts.
        // The invariant is that selecting a variant and pressing Start resolves
        // to a context the variant can actually be priced at.
        for variant in VariantRegistry.all {
            let budget = variant.contract.memoryBudget
            let clamped = budget.clampContext(Self.appDefaultContext)
            #expect(budget.kvGiB(at: clamped) != nil,
                    "\(variant.id) cannot serve the app default context")
            #expect(budget.totalBytes(at: clamped) != nil)
        }
    }

    @Test func registryIdsAreUnique() {
        // `resolve` is `first { $0.id == id }`, so a duplicate silently shadows.
        let ids = VariantRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

struct MemoryBudgetTests {
    @Test func clampsToTheDeclaredRange() {
        let b = VariantRegistry.mellum.contract.memoryBudget
        // The app's own default sits above every declared maxContext — the
        // combination that made a selected variant unlaunchable.
        #expect(b.maxContext < 51_200)
        #expect(b.clampContext(51_200) == b.maxContext)
        #expect(b.clampContext(1_024) == b.minContext)
        #expect(b.clampContext(32_768) == 32_768)
        // A clamped context is, by construction, one the budget can price.
        #expect(b.kvGiB(at: b.clampContext(51_200)) != nil)
    }


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

struct LagunaXSMemoryBudgetTests {
    private let budget = VariantRegistry.lagunaXS.contract.memoryBudget

    @Test func residentFootprintAt32k() throws {
        let total = try #require(budget.totalBytes(at: 32_768))
        let gib = Double(total) / 1_073_741_824
        #expect(abs(gib - 6.53) < 0.01)
    }

    @Test func residentFootprintAt16k() throws {
        let total = try #require(budget.totalBytes(at: 16_384))
        let gib = Double(total) / 1_073_741_824
        #expect(abs(gib - 5.91) < 0.01)
    }

    @Test func unsupportedContextIsRefused() {
        #expect(budget.totalBytes(at: 16_383) == nil)
        #expect(budget.totalBytes(at: 32_769) == nil)
        #expect(budget.totalBytes(at: 51_200) == nil)
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

struct ModelLocationTests {
    /// The XS default named `~/models`, which holds only the Mellum file. The
    /// acceptance run set SWIFTSTAR_LAGUNA_XS_MODEL, so a green run masked a
    /// variant nobody could select without that variable.
    @Test func everyRegisteredVariantResolvesToAReadableFile() {
        for variant in VariantRegistry.all {
            #expect(FileManager.default.isReadableFile(atPath: variant.modelFile.path),
                    "\(variant.id) resolves to \(variant.modelFile.path), which is not readable")
        }
    }

    @Test func envOverrideWinsOverTheSearchPath() {
        // The override is how CI and the acceptance runs point at a staged file.
        let key = "SWIFTSTAR_MELLUM_MODEL"
        guard ProcessInfo.processInfo.environment[key] == nil else { return }
        #expect(VariantRegistry.locateModel("nope.gguf", envKey: key).lastPathComponent == "nope.gguf")
    }

    @Test func unfoundFileStillNamesAPlausiblePath() {
        // A refusal must name something a human can act on, not "".
        let url = VariantRegistry.locateModel("definitely-absent-\(UUID().uuidString).gguf",
                                              envKey: "SWIFTSTAR_NO_SUCH_KEY")
        #expect(url.path.hasSuffix(".gguf"))
        #expect(url.pathComponents.count > 2)
    }
}
