import Foundation
import Testing
@testable import SwiftStarKit

struct ModelSwitchDecisionTests {
    private let running = URL(fileURLWithPath: "/models/laguna-s.gguf")
    private let target = URL(fileURLWithPath: "/models/laguna-xs.gguf")

    @Test func appliesWhenAdmittedChangedIdle() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .admitted) == .apply)
    }

    @Test func refusedWhileGeneratingEvenWhenAdmittedAndChanged() {
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: true, runningModelFile: running, targetModelFile: target,
            admission: .admitted)
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("generating"))
    }

    @Test func noChangeWhenSameModelFile() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: running,
            admission: .admitted) == .noChange)
    }

    @Test func noChangeWhenSameModelFileRegardlessOfAdmission() {
        let reason = FeasibilityReason(
            message: "needs 12.0 GiB but only 6.0 GiB available",
            deficitBytes: 1, availableBytes: 1, plannedBytes: 2)
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: running,
            admission: .infeasible(reason)) == .noChange)
    }

    @Test func noChangeWhenSameModelFileRegardlessOfContractMismatch() {
        let mismatches: [VariantMismatch] = [.architecture(expected: "laguna", actual: "mellum")]
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: running,
            admission: .contractMismatch(mismatches)) == .noChange)
    }

    @Test func appliesForCustomPathWithNilAdmission() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: nil) == .apply)
    }

    @Test func refusedWithContractMismatchMessages() {
        let mismatches: [VariantMismatch] = [
            .architecture(expected: "laguna", actual: "mellum"),
            .rope(expected: "scalingType=yarn freqBase=500000.0", actual: "scalingType=nope freqBase=1.0"),
        ]
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .contractMismatch(mismatches))
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("architecture mismatch"))
        #expect(message.contains("rope mismatch"))
    }

    @Test func refusedWithFeasibilityMessage() {
        let reason = FeasibilityReason(
            message: "needs 12.0 GiB but only 6.0 GiB available",
            deficitBytes: 1, availableBytes: 1, plannedBytes: 2)
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: running, targetModelFile: target,
            admission: .infeasible(reason))
        #expect(decision == .refused("needs 12.0 GiB but only 6.0 GiB available"))
    }

    @Test func sameFileDifferentPathSpellingIsNoChange() {
        let spelled = URL(fileURLWithPath: "/models/../models/laguna-s.gguf")
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, runningModelFile: spelled, targetModelFile: running,
            admission: .admitted) == .noChange)
    }
}
