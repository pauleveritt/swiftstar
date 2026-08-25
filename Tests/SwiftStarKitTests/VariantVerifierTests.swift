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
