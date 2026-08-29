import Testing
import Foundation
@testable import SwiftStarKit

// MARK: - Cross-variant tables
//
// The verifier enforces the same three facts (architecture, rope, down-quant)
// for every variant. The checks below that are genuinely identical in shape
// across variants are expressed once, driven by a small per-variant table —
// the next variant needs one new row, not a new copy of the test bodies.
// Checks that are unique to one variant's contract shape (a single rope-only
// assertion, the mixed-segment "layer zero" behaviour that is opposite between
// Laguna S and DeepSeek, etc.) stay as standalone tests below the tables.

/// A variant plus its clean-metadata factory and the "wrong architecture"
/// probe value — the two facts every `cleanXIsAdmitted` / `wrongArchitecture-
/// IsNamed` pair actually varies on.
struct VerifierVariantCase: Sendable, CustomTestStringConvertible {
    let name: String
    let variant: Variant
    let makeClean: @Sendable () -> GGUFMetadata
    let wrongArchitecture: String
    let makeWithArchitecture: @Sendable (String) -> GGUFMetadata
    var testDescription: String { name }
}

private let verifierVariantCases: [VerifierVariantCase] = [
    .init(name: "mellum", variant: VariantRegistry.mellum,
          makeClean: { makeMellumMetadata() },
          wrongArchitecture: "laguna",
          makeWithArchitecture: { makeMellumMetadata(architecture: $0) }),
    .init(name: "lagunaXS", variant: VariantRegistry.lagunaXS,
          makeClean: { makeLagunaMetadata() },
          wrongArchitecture: "mellum",
          makeWithArchitecture: { makeLagunaMetadata(architecture: $0) }),
    .init(name: "lagunaS", variant: VariantRegistry.lagunaS,
          makeClean: { makeLagunaSMetadata() },
          wrongArchitecture: "mellum",
          makeWithArchitecture: { makeLagunaSMetadata(architecture: $0) }),
    .init(name: "deepSeekV4Flash", variant: VariantRegistry.deepSeekV4Flash,
          makeClean: { makeDeepSeekMetadata() },
          wrongArchitecture: "laguna",
          makeWithArchitecture: { makeDeepSeekMetadata(architecture: $0) }),
]

struct VariantVerifierCrossVariantTests {
    @Test(arguments: verifierVariantCases)
    func cleanVariantIsAdmitted(_ c: VerifierVariantCase) {
        let mismatches = VariantVerifier.verify(c.variant, metadata: c.makeClean())
        #expect(mismatches.isEmpty)
    }

    @Test(arguments: verifierVariantCases)
    func wrongArchitectureIsNamed(_ c: VerifierVariantCase) {
        let meta = c.makeWithArchitecture(c.wrongArchitecture)
        let mismatches = VariantVerifier.verify(c.variant, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .architecture(let expected, let actual) = mismatches[0] else {
            Issue.record("expected .architecture, got \(mismatches)")
            return
        }
        #expect(expected == c.variant.contract.architecture)
        #expect(actual == c.wrongArchitecture)
    }
}

/// The single-segment variants (Mellum, Laguna XS): one uniform down type
/// over `startLayer..<layerCount`. Laguna S and DeepSeek's mixed layouts get
/// their own table below — a single `expectedDownType` can't express two
/// segments.
struct SingleSegmentVerifierCase: Sendable, CustomTestStringConvertible {
    let name: String
    let variant: Variant
    let makeWithDownType: @Sendable (GGUFType) -> GGUFMetadata
    let makeWithDroppedLayer: @Sendable (Int) -> GGUFMetadata
    let expectedDownType: GGUFType
    let wrongDownType: GGUFType
    let startLayer: Int
    let layerCount: Int
    let dropLayerToTest: Int
    var testDescription: String { name }
}

private let singleSegmentVerifierCases: [SingleSegmentVerifierCase] = [
    .init(name: "mellum", variant: VariantRegistry.mellum,
          makeWithDownType: { makeMellumMetadata(downType: $0) },
          makeWithDroppedLayer: { makeMellumMetadata(dropLayer: $0) },
          expectedDownType: .q8_0, wrongDownType: .q5_0,
          startLayer: 0, layerCount: 28, dropLayerToTest: 5),
    .init(name: "lagunaXS", variant: VariantRegistry.lagunaXS,
          makeWithDownType: { makeLagunaMetadata(downType: $0) },
          makeWithDroppedLayer: { makeLagunaMetadata(dropLayer: $0) },
          expectedDownType: .q3_k, wrongDownType: .q4_k,
          startLayer: 1, layerCount: 40, dropLayerToTest: 20),
]

struct SingleSegmentVerifierTests {
    @Test(arguments: singleSegmentVerifierCases)
    func wrongDownTypeIsNamedAcrossRoutedLayers(_ c: SingleSegmentVerifierCase) {
        let meta = c.makeWithDownType(c.wrongDownType)
        let mismatches = VariantVerifier.verify(c.variant, metadata: meta)
        #expect(mismatches.count == c.layerCount - c.startLayer)
        guard case .downQuant(let layer, let expected, let actual) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == c.startLayer)  // dense leading layers, if any, are skipped
        #expect(expected == c.expectedDownType)
        #expect(actual == c.wrongDownType)
    }

    @Test(arguments: singleSegmentVerifierCases)
    func missingRoutedLayerIsAMismatchNotASkip(_ c: SingleSegmentVerifierCase) {
        // One down tensor absent — the verifier must report it, never silently
        // pass (I4).
        let meta = c.makeWithDroppedLayer(c.dropLayerToTest)
        let mismatches = VariantVerifier.verify(c.variant, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == c.dropLayerToTest)
        #expect(expected == c.expectedDownType)
        #expect(actual == nil)
    }
}

/// The mixed-segment variants (Laguna S, DeepSeek): two disjoint layer ranges,
/// each with its own down type. Both variants' whole point is the same —
/// swapping one segment's type is named only across that segment's layers,
/// never the other one — so the shape below is shared; only the layer ranges
/// and types differ.
struct MixedSegmentVerifierCase: Sendable, CustomTestStringConvertible {
    let name: String
    let variant: Variant
    let makeWithFirstSegmentType: @Sendable (GGUFType) -> GGUFMetadata
    let makeWithSecondSegmentType: @Sendable (GGUFType) -> GGUFMetadata
    let makeWithDroppedLayer: @Sendable (Int) -> GGUFMetadata
    let firstSegmentLayers: Range<Int>
    let secondSegmentLayers: Range<Int>
    let firstSegmentType: GGUFType
    let secondSegmentType: GGUFType
    let wrongFirstSegmentType: GGUFType
    let wrongSecondSegmentType: GGUFType
    let dropLayerInFirstSegment: Int
    let dropLayerInSecondSegment: Int
    var testDescription: String { name }
}

private let mixedSegmentVerifierCases: [MixedSegmentVerifierCase] = [
    .init(name: "lagunaS", variant: VariantRegistry.lagunaS,
          makeWithFirstSegmentType: { makeLagunaSMetadata(q2Type: $0) },
          makeWithSecondSegmentType: { makeLagunaSMetadata(q3Type: $0) },
          makeWithDroppedLayer: { makeLagunaSMetadata(dropLayer: $0) },
          firstSegmentLayers: 1..<21, secondSegmentLayers: 21..<48,
          firstSegmentType: .q2_k, secondSegmentType: .q3_k,
          wrongFirstSegmentType: .q4_k, wrongSecondSegmentType: .q4_k,
          dropLayerInFirstSegment: 5, dropLayerInSecondSegment: 30),
    .init(name: "deepSeekV4Flash", variant: VariantRegistry.deepSeekV4Flash,
          makeWithFirstSegmentType: { makeDeepSeekMetadata(q2Type: $0) },
          makeWithSecondSegmentType: { makeDeepSeekMetadata(q4Type: $0) },
          makeWithDroppedLayer: { makeDeepSeekMetadata(dropLayer: $0) },
          firstSegmentLayers: 0..<37, secondSegmentLayers: 37..<43,
          firstSegmentType: .q2_k, secondSegmentType: .q4_k,
          wrongFirstSegmentType: .q4_k, wrongSecondSegmentType: .q2_k,
          dropLayerInFirstSegment: 5, dropLayerInSecondSegment: 40),
]

struct MixedSegmentVerifierTests {
    @Test(arguments: mixedSegmentVerifierCases)
    func wrongFirstSegmentTypeIsNamedOnlyOnFirstSegmentLayers(_ c: MixedSegmentVerifierCase) {
        let meta = c.makeWithFirstSegmentType(c.wrongFirstSegmentType)
        let mismatches = VariantVerifier.verify(c.variant, metadata: meta)
        #expect(mismatches.count == c.firstSegmentLayers.count)
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(c.firstSegmentLayers))
    }

    @Test(arguments: mixedSegmentVerifierCases)
    func wrongSecondSegmentTypeIsNamedOnlyOnSecondSegmentLayers(_ c: MixedSegmentVerifierCase) {
        let meta = c.makeWithSecondSegmentType(c.wrongSecondSegmentType)
        let mismatches = VariantVerifier.verify(c.variant, metadata: meta)
        #expect(mismatches.count == c.secondSegmentLayers.count)
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(c.secondSegmentLayers))
    }

    @Test(arguments: mixedSegmentVerifierCases)
    func missingLayerInEitherSegmentIsAMismatchNotASkip(_ c: MixedSegmentVerifierCase) {
        let metaFirst = c.makeWithDroppedLayer(c.dropLayerInFirstSegment)
        let mismatchesFirst = VariantVerifier.verify(c.variant, metadata: metaFirst)
        #expect(mismatchesFirst.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatchesFirst[0] else {
            Issue.record("expected .downQuant, got \(mismatchesFirst)")
            return
        }
        #expect(layer == c.dropLayerInFirstSegment)
        #expect(expected == c.firstSegmentType)
        #expect(actual == nil)

        let metaSecond = c.makeWithDroppedLayer(c.dropLayerInSecondSegment)
        let mismatchesSecond = VariantVerifier.verify(c.variant, metadata: metaSecond)
        #expect(mismatchesSecond.count == 1)
        guard case .downQuant(let layer2, let expected2, let actual2) = mismatchesSecond[0] else {
            Issue.record("expected .downQuant, got \(mismatchesSecond)")
            return
        }
        #expect(layer2 == c.dropLayerInSecondSegment)
        #expect(expected2 == c.secondSegmentType)
        #expect(actual2 == nil)
    }
}

// MARK: - Standalone, variant-specific tests
//
// Each of these checks a fact that only exists for one variant's contract
// (Mellum's rope fields aren't re-probed per variant elsewhere; the "is layer
// zero checked" behaviour is *opposite* between Laguna S and DeepSeek, so it
// can't be collapsed into one shared assertion) — parameterizing them would
// hide the very thing they're pinning.

struct VariantVerifierTests {
    private let mellum = VariantRegistry.mellum

    @Test func missingArchitectureIsNamed() {
        let meta = makeMellumMetadata(architecture: nil)
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.contains { if case .architecture = $0 { true } else { false } })
    }

    @Test func wrongRopeScalingTypeIsNamed() {
        let meta = makeMellumMetadata(scalingType: "linear")
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .rope = mismatches[0] else {
            Issue.record("expected .rope, got \(mismatches)")
            return
        }
    }

    @Test func wrongRopeFreqBaseIsNamed() {
        let meta = makeMellumMetadata(freqBase: 10_000.0)
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .rope = mismatches[0] else {
            Issue.record("expected .rope, got \(mismatches)")
            return
        }
    }

    @Test func mismatchMessageIsActionable() {
        let meta = makeMellumMetadata(architecture: "laguna")
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches[0].message.contains("architecture"))
        #expect(mismatches[0].message.contains("laguna"))
        #expect(mismatches[0].message.contains("mellum"))
    }
}

struct LagunaSVerifierTests {
    @Test func denseLayerZeroIsNotChecked() {
        // Layer 0 is dense (ffn_down, not ffn_down_exps) — verifying it as
        // Q2_K would be a false positive on every clean file.
        let meta = makeLagunaSMetadata()
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == nil)
        let mismatches = VariantVerifier.verify(VariantRegistry.lagunaS, metadata: meta)
        #expect(!mismatches.contains { if case .downQuant(let layer, _, _) = $0 { return layer == 0 } else { return false } })
    }
}

struct DeepSeekV4FlashVerifierTests {
    @Test func layerZeroIsCheckedUnlikeLaguna() {
        // DeepSeek has no dense leading layer — layer 0 is already MoE, so
        // (unlike Laguna) it must be verified like every other routed layer.
        let meta = makeDeepSeekMetadata()
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == .q2_k)
        let mismatches = VariantVerifier.verify(VariantRegistry.deepSeekV4Flash, metadata: meta)
        #expect(mismatches.isEmpty)
    }
}
