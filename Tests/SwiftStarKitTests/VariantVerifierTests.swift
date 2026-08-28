import Testing
import Foundation
@testable import SwiftStarKit

struct VariantVerifierTests {
    private let mellum = VariantRegistry.mellum

    @Test func cleanMellumIsAdmitted() {
        let mismatches = VariantVerifier.verify(mellum, metadata: makeMellumMetadata())
        #expect(mismatches.isEmpty)
    }

    @Test func wrongArchitectureIsNamed() {
        let meta = makeMellumMetadata(architecture: "laguna")
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .architecture(let expected, let actual) = mismatches[0] else {
            Issue.record("expected .architecture, got \(mismatches)")
            return
        }
        #expect(expected == "mellum")
        #expect(actual == "laguna")
    }

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

    @Test func wrongDownTypeIsNamed() {
        let meta = makeMellumMetadata(downType: .q5_0)
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.count == 28)
        guard case .downQuant(let layer, let expected, let actual) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == 0)
        #expect(expected == .q8_0)
        #expect(actual == .q5_0)
    }

    @Test func missingLayerIsAMismatchNotASkip() {
        // One down tensor absent — the verifier must report it, never silently
        // pass (I4).
        let meta = makeMellumMetadata(dropLayer: 5)
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == 5)
        #expect(expected == .q8_0)
        #expect(actual == nil)
    }

    @Test func mismatchMessageIsActionable() {
        let meta = makeMellumMetadata(architecture: "laguna")
        let mismatches = VariantVerifier.verify(mellum, metadata: meta)
        #expect(mismatches[0].message.contains("architecture"))
        #expect(mismatches[0].message.contains("laguna"))
        #expect(mismatches[0].message.contains("mellum"))
    }
}

struct LagunaXSVerifierTests {
    private let lagunaXS = VariantRegistry.lagunaXS

    @Test func cleanLagunaIsAdmitted() {
        let mismatches = VariantVerifier.verify(lagunaXS, metadata: makeLagunaMetadata())
        #expect(mismatches.isEmpty)
    }

    @Test func wrongArchitectureIsNamed() {
        let meta = makeLagunaMetadata(architecture: "mellum")
        let mismatches = VariantVerifier.verify(lagunaXS, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .architecture(let expected, let actual) = mismatches[0] else {
            Issue.record("expected .architecture, got \(mismatches)")
            return
        }
        #expect(expected == "laguna")
        #expect(actual == "mellum")
    }

    @Test func wrongDownTypeIsNamedAcrossRoutedLayers() {
        let meta = makeLagunaMetadata(downType: .q4_k)
        let mismatches = VariantVerifier.verify(lagunaXS, metadata: meta)
        #expect(mismatches.count == 39)
        guard case .downQuant(let layer, _, _) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == 1)  // dense layer 0 is not checked
    }

    @Test func missingRoutedLayerIsAMismatchNotASkip() {
        let meta = makeLagunaMetadata(dropLayer: 20)
        let mismatches = VariantVerifier.verify(lagunaXS, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatches[0] else {
            Issue.record("expected .downQuant, got \(mismatches)")
            return
        }
        #expect(layer == 20)
        #expect(expected == .q3_k)
        #expect(actual == nil)
    }
}

struct LagunaSVerifierTests {
    private let lagunaS = VariantRegistry.lagunaS

    @Test func cleanLagunaSIsAdmitted() {
        let mismatches = VariantVerifier.verify(lagunaS, metadata: makeLagunaSMetadata())
        #expect(mismatches.isEmpty)
    }

    @Test func wrongArchitectureIsNamed() {
        let meta = makeLagunaSMetadata(architecture: "mellum")
        let mismatches = VariantVerifier.verify(lagunaS, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .architecture(let expected, let actual) = mismatches[0] else {
            Issue.record("expected .architecture, got \(mismatches)")
            return
        }
        #expect(expected == "laguna")
        #expect(actual == "mellum")
    }

    /// The mixed layout's whole point: layers 1..<21 must be Q2_K, and layers
    /// 21..<48 must be Q3_K — swapping either segment's type is named across
    /// exactly that segment's layers, not the other one.
    @Test func wrongQ2SegmentTypeIsNamedOnlyOnQ2Layers() {
        let meta = makeLagunaSMetadata(q2Type: .q4_k)
        let mismatches = VariantVerifier.verify(lagunaS, metadata: meta)
        #expect(mismatches.count == 20)  // layers 1..<21
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(1..<21))
    }

    @Test func wrongQ3SegmentTypeIsNamedOnlyOnQ3Layers() {
        let meta = makeLagunaSMetadata(q3Type: .q4_k)
        let mismatches = VariantVerifier.verify(lagunaS, metadata: meta)
        #expect(mismatches.count == 27)  // layers 21..<48
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(21..<48))
    }

    @Test func denseLayerZeroIsNotChecked() {
        // Layer 0 is dense (ffn_down, not ffn_down_exps) — verifying it as
        // Q2_K would be a false positive on every clean file.
        let meta = makeLagunaSMetadata()
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == nil)
        let mismatches = VariantVerifier.verify(lagunaS, metadata: meta)
        #expect(!mismatches.contains { if case .downQuant(let layer, _, _) = $0 { return layer == 0 } else { return false } })
    }

    @Test func missingLayerInEitherSegmentIsAMismatchNotASkip() {
        let metaQ2 = makeLagunaSMetadata(dropLayer: 5)
        let mismatchesQ2 = VariantVerifier.verify(lagunaS, metadata: metaQ2)
        #expect(mismatchesQ2.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatchesQ2[0] else {
            Issue.record("expected .downQuant, got \(mismatchesQ2)")
            return
        }
        #expect(layer == 5)
        #expect(expected == .q2_k)
        #expect(actual == nil)

        let metaQ3 = makeLagunaSMetadata(dropLayer: 30)
        let mismatchesQ3 = VariantVerifier.verify(lagunaS, metadata: metaQ3)
        #expect(mismatchesQ3.count == 1)
        guard case .downQuant(let layer2, let expected2, let actual2) = mismatchesQ3[0] else {
            Issue.record("expected .downQuant, got \(mismatchesQ3)")
            return
        }
        #expect(layer2 == 30)
        #expect(expected2 == .q3_k)
        #expect(actual2 == nil)
    }
}

struct DeepSeekV4FlashVerifierTests {
    private let deepSeek = VariantRegistry.deepSeekV4Flash

    @Test func cleanDeepSeekIsAdmitted() {
        let mismatches = VariantVerifier.verify(deepSeek, metadata: makeDeepSeekMetadata())
        #expect(mismatches.isEmpty)
    }

    @Test func wrongArchitectureIsNamed() {
        let meta = makeDeepSeekMetadata(architecture: "laguna")
        let mismatches = VariantVerifier.verify(deepSeek, metadata: meta)
        #expect(mismatches.count == 1)
        guard case .architecture(let expected, let actual) = mismatches[0] else {
            Issue.record("expected .architecture, got \(mismatches)")
            return
        }
        #expect(expected == "deepseek4")
        #expect(actual == "laguna")
    }

    /// The mixed layout's whole point: layers 0..<37 must be Q2_K, and layers
    /// 37..<43 must be Q4_K — swapping either segment's type is named across
    /// exactly that segment's layers, not the other one.
    @Test func wrongQ2SegmentTypeIsNamedOnlyOnQ2Layers() {
        let meta = makeDeepSeekMetadata(q2Type: .q4_k)
        let mismatches = VariantVerifier.verify(deepSeek, metadata: meta)
        #expect(mismatches.count == 37)  // layers 0..<37
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(0..<37))
    }

    @Test func wrongQ4SegmentTypeIsNamedOnlyOnQ4Layers() {
        let meta = makeDeepSeekMetadata(q4Type: .q2_k)
        let mismatches = VariantVerifier.verify(deepSeek, metadata: meta)
        #expect(mismatches.count == 6)  // layers 37..<43
        let layers = Set(mismatches.compactMap { mismatch -> Int? in
            guard case .downQuant(let layer, _, _) = mismatch else { return nil }
            return layer
        })
        #expect(layers == Set(37..<43))
    }

    @Test func layerZeroIsCheckedUnlikeLaguna() {
        // DeepSeek has no dense leading layer — layer 0 is already MoE, so
        // (unlike Laguna) it must be verified like every other routed layer.
        let meta = makeDeepSeekMetadata()
        #expect(meta.tensorTypes["blk.0.ffn_down_exps.weight"] == .q2_k)
        let mismatches = VariantVerifier.verify(deepSeek, metadata: meta)
        #expect(mismatches.isEmpty)
    }

    @Test func missingLayerInEitherSegmentIsAMismatchNotASkip() {
        let metaQ2 = makeDeepSeekMetadata(dropLayer: 5)
        let mismatchesQ2 = VariantVerifier.verify(deepSeek, metadata: metaQ2)
        #expect(mismatchesQ2.count == 1)
        guard case .downQuant(let layer, let expected, let actual) = mismatchesQ2[0] else {
            Issue.record("expected .downQuant, got \(mismatchesQ2)")
            return
        }
        #expect(layer == 5)
        #expect(expected == .q2_k)
        #expect(actual == nil)

        let metaQ4 = makeDeepSeekMetadata(dropLayer: 40)
        let mismatchesQ4 = VariantVerifier.verify(deepSeek, metadata: metaQ4)
        #expect(mismatchesQ4.count == 1)
        guard case .downQuant(let layer2, let expected2, let actual2) = mismatchesQ4[0] else {
            Issue.record("expected .downQuant, got \(mismatchesQ4)")
            return
        }
        #expect(layer2 == 40)
        #expect(expected2 == .q4_k)
        #expect(actual2 == nil)
    }
}
