import Testing
import Foundation
@testable import SwiftStarKit

/// P25 Cycle 3: the oracle for `VariantRegistry.deepSeekV4Flash`'s
/// `MemoryBudget`.
///
/// This is a Swift port of ds4-control's `Feasibility.swift` Metal-allocator
/// formulas for the DeepSeek V4 Flash shape (`metalContextBytes`,
/// `metalSharedGraphWorkspaceBytes`, `metalSessionGraphBytes`,
/// `metalIndexerScratchBytes`), kept here as TEST-SIDE reference code — never
/// shipped — so the exact allocator math stays checkable without carrying its
/// full complexity into the app. The shipped `MemoryBudget` is three
/// constants (weights/scratch/three KV anchors) because the design doc found
/// this whole model is affine in `ctx` above the 4,096-token prefill cap; this
/// test is what proves that claim rather than merely asserting it.
///
/// If a future `external/ds4` pin changes the allocator, THIS test is what
/// will disagree with the shipped constants — re-derive the constants, do not
/// widen the tolerance (`docs/harvest/ds4-control.md`'s "re-fetch, never
/// carry forward" discipline for every numeric fact).
private enum DeepSeekFlashMetalOracle {
    // Metal shape constants for `.flash` (ds4-control Feasibility.swift:118-125).
    static let layers = 43
    static let ratio4Layers = 21
    static let ratio128Layers = 20
    static let longPromptPrefillCap = 4096
    static let embeddingWidth = 4096
    static let attentionHeads = 64
    static let headWidth = 512
    static let outputGroups = 8
    static let queryRank = 1024
    static let outputRank = 1024
    static let expertCount = 256
    static let expertsUsed = 6
    static let expertWidth = 2048
    static let indexerHeads = 64
    static let indexerHeadWidth = 128
    static let indexerTopK = 512
    static let hyperConnections = 4
    static let vocabularySize = 129_280

    static func prefillCap(_ ctx: Int) -> Int {
        ctx > 4096 ? min(longPromptPrefillCap, ctx) : ctx
    }

    /// Mirrors `metalContextBytes` (Feasibility.swift:176-207).
    static func contextBytes(_ ctx: Int) -> Int64 {
        guard ctx > 0 else { return 0 }
        let pc = prefillCap(ctx)
        let rawWindow = min(128, ctx)
        let wanted = rawWindow + pc
        let cappedWanted = min(wanted, ctx)
        let rawCap = max(rawWindow, min(((cappedWanted + 255) / 256) * 256, 8192))

        let ratio4Cap = ctx / 4 + 2
        let ratio128Cap = ctx / 128 + 2
        let rawBytes = Int64(layers) * Int64(rawCap) * 512 * 4
        let ratio4AttentionBytes = Int64(ratio4Cap) * 512 * 2
        let ratio4IndexerBytes = Int64(ratio4Cap) * 128 * 4
        let ratio4Bytes = Int64(ratio4Layers) * (ratio4AttentionBytes + ratio4IndexerBytes)
        let ratio128Bytes = Int64(ratio128Layers) * (Int64(ratio128Cap) * 512 * 2)
        let scratchMatricesBytes = 2 * Int64(ratio4Cap) * Int64(pc) * 4
        let attentionStageCap = pc / 4 + 2
        let attentionStageBytes = Int64(attentionStageCap) * 512 * 4

        return rawBytes + ratio4Bytes + ratio128Bytes + scratchMatricesBytes + attentionStageBytes
    }

    /// Mirrors `metalSharedGraphWorkspaceBytes` (Feasibility.swift:213-257).
    static func sharedGraphBytes(_ ctx: Int) -> Int64 {
        guard ctx > 0 else { return 0 }
        let pc = Int64(prefillCap(ctx))
        let hyperConnectionWidth = Int64(hyperConnections * embeddingWidth)
        let hyperConnectionMixWidth = Int64(2 * hyperConnections + hyperConnections * hyperConnections)
        let queryWidth = Int64(attentionHeads * headWidth)
        let groupedOutputWidth = Int64(outputGroups * outputRank)
        let groupTemporaryWidth = Int64(headWidth * (attentionHeads / outputGroups))
        let indexerQueryWidth = Int64(indexerHeads * indexerHeadWidth)
        let compressionWidth = Int64(2 * max(headWidth, indexerHeadWidth))

        let floatElementsPerToken =
            1
            + 8 * Int64(embeddingWidth)
            + Int64(expertsUsed) * Int64(embeddingWidth)
            + 3 * Int64(expertsUsed) * Int64(expertWidth)
            + 2 * Int64(expertsUsed)
            + 2 * Int64(expertCount)
            + 3 * Int64(expertWidth)
            + 4 * hyperConnectionWidth
            + Int64(outputRank)
            + groupTemporaryWidth
            + groupedOutputWidth
            + 2 * queryWidth
            + Int64(indexerHeads)
            + indexerQueryWidth
            + 2 * compressionWidth
            + 2 * Int64(headWidth)
            + 2 * Int64(queryRank)
            + 2 * hyperConnectionMixWidth

        let floatBytes = pc * floatElementsPerToken * 4
        let halfQueryBytes = pc * queryWidth * 2
        let seedBytes = Int64(layers) * 64 * Int64(expertsUsed) * 4

        return floatBytes + halfQueryBytes + seedBytes
    }

    /// Mirrors `metalSessionGraphBytes` (Feasibility.swift:262-318).
    static func sessionGraphBytes(_ ctx: Int) -> Int64 {
        guard ctx > 0 else { return 0 }
        let pc = Int64(prefillCap(ctx))
        let hyperConnectionWidth = Int64(hyperConnections * embeddingWidth)
        let hyperConnectionMixWidth = Int64(2 * hyperConnections + hyperConnections * hyperConnections)
        let queryWidth = Int64(attentionHeads * headWidth)
        let groupedOutputWidth = Int64(outputGroups * outputRank)
        let indexerQueryWidth = Int64(indexerHeads * indexerHeadWidth)
        let compressionWidth = Int64(2 * max(headWidth, indexerHeadWidth))
        let selectedIndexElements = Int64(indexerTopK) * pc

        let decodeElements =
            2 * hyperConnectionWidth
            + 2 * hyperConnectionMixWidth
            + 2 * Int64(embeddingWidth)
            + 2 * Int64(queryRank)
            + queryWidth
            + 2 * Int64(headWidth)
            + 2 * compressionWidth
            + 4 * Int64(indexerHeadWidth)
            + indexerQueryWidth
            + Int64(indexerHeads)
            + selectedIndexElements
            + queryWidth
            + groupedOutputWidth
            + Int64(embeddingWidth)
            + hyperConnectionWidth
            + 2 * Int64(embeddingWidth)
            + 3 * Int64(expertWidth)
            + Int64(embeddingWidth)
            + 2 * Int64(expertCount)
            + 2 * Int64(expertsUsed)
            + 3 * Int64(expertsUsed) * Int64(expertWidth)
            + Int64(expertsUsed) * Int64(embeddingWidth)
            + Int64(embeddingWidth)
            + hyperConnectionWidth
            + 2 * Int64(hyperConnections)
            + 2 * Int64(embeddingWidth)
            + Int64(vocabularySize)

        let ratio4StateElements = Int64(ratio4Layers) * 32 * Int64(headWidth + indexerHeadWidth)
        let ratio128StateElements = Int64(ratio128Layers) * 256 * Int64(headWidth)
        let stateElements = ratio4StateElements + ratio128StateElements

        return (decodeElements + stateElements) * 4
    }

    /// Mirrors `metalIndexerScratchBytes` (Feasibility.swift:324-358).
    static func indexerScratchBytes(_ ctx: Int) -> Int64 {
        guard ctx > 0 else { return 0 }
        let pc = prefillCap(ctx)
        guard pc > 0 else { return 0 }

        func upperBounds(endPosition: Int, tokens: Int) -> (selection: Int64, sorted: Int64) {
            let compressedRows = endPosition / 4
            guard compressedRows > indexerTopK else { return (0, 0) }
            let selection = Int64(2) * Int64(compressedRows) * Int64(tokens) * 4
            let sorted = Int64(indexerTopK) * Int64(tokens) * 4
            return (selection, sorted)
        }

        let partialTokens = ctx % pc
        let lastFullEnd = ctx - partialTokens
        let zero: (selection: Int64, sorted: Int64) = (0, 0)
        let full = lastFullEnd > 0 ? upperBounds(endPosition: lastFullEnd, tokens: pc) : zero
        let partial = partialTokens > 0 ? upperBounds(endPosition: ctx, tokens: partialTokens) : zero

        return max(full.selection, partial.selection) + max(full.sorted, partial.sorted)
    }

    /// The GPU-wired working set for one resident session at this context —
    /// everything `requiredWiredMB` sums except the weights themselves.
    static func totalAllocBytes(_ ctx: Int) -> Int64 {
        contextBytes(ctx) + sessionGraphBytes(ctx) + sharedGraphBytes(ctx) + indexerScratchBytes(ctx)
    }
}

struct DeepSeekV4FlashMemoryOracleTests {
    /// Exact GGUF bytes for the q2-q4-imatrix artifact (measured via `stat`,
    /// matches the published Hugging Face SHA-256 per `antirez/ds4#635`).
    private static let ggufBytes: Int64 = 97_591_747_456
    private static let tolerance: Int64 = 25 * 1_024 * 1_024  // 25 MiB — measured worst case is 20 MiB

    private var variant: Variant { VariantRegistry.deepSeekV4Flash }

    private func oracleTotalBytes(at ctx: Int) -> Int64 {
        Self.ggufBytes + DeepSeekFlashMetalOracle.totalAllocBytes(ctx)
    }

    @Test func shippedBudgetAgreesWithTheOracleAtEachDeclaredAnchor() throws {
        for ctx in [16_384, 32_768, 40_960] {
            let shipped = try #require(variant.contract.memoryBudget.totalBytes(at: ctx))
            let oracle = oracleTotalBytes(at: ctx)
            let delta = abs(shipped - oracle)
            #expect(delta <= Self.tolerance,
                    "ctx \(ctx): shipped \(shipped) vs oracle \(oracle), delta \(delta) bytes exceeds tolerance")
        }
    }

    @Test func shippedBudgetAgreesWithTheOracleAcrossTheExtrapolatedRange() throws {
        // Every context the variant declares as supported, not just the three
        // anchors — this is what actually tests the affine claim.
        let samples = [51_200, 65_536, 150_000, 262_144, 393_216, 524_288]
        for ctx in samples {
            let shipped = try #require(variant.contract.memoryBudget.totalBytes(at: ctx),
                                        "ctx \(ctx) should be within the declared range")
            let oracle = oracleTotalBytes(at: ctx)
            let delta = abs(shipped - oracle)
            #expect(delta <= Self.tolerance,
                    "ctx \(ctx): shipped \(shipped) vs oracle \(oracle), delta \(delta) bytes exceeds tolerance")
        }
    }

    @Test func oracleWeightsPlusAllocFitsWithinTheOSDefaultMetalLimitAtMaxContext() {
        // The design doc's measured envelope on a 128 GiB M5 Max:
        // recommendedMaxWorkingSetSize = 115,448,725,504 B (107.52 GiB).
        // maxContext (524,288) was chosen to sit just inside that with no
        // sysctl — this pins the choice against the oracle, not just intuition.
        let metalDefaultLimit: Int64 = 115_448_725_504
        let atMax = oracleTotalBytes(at: 524_288)
        #expect(atMax <= metalDefaultLimit,
                "524,288 was chosen to fit the OS-default Metal limit; oracle says \(atMax) > \(metalDefaultLimit)")
    }
}
