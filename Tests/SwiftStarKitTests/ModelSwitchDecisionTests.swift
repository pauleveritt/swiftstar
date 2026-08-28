import Foundation
import Testing
@testable import SwiftStarKit

struct ModelSwitchDecisionTests {
    private let engineDir = URL(fileURLWithPath: "/engine")
    private let workspace = URL(fileURLWithPath: "/workspace")
    private let runningFile = URL(fileURLWithPath: "/models/laguna-s.gguf")
    private let targetFile = URL(fileURLWithPath: "/models/laguna-xs.gguf")

    private func settings(
        modelFile: URL, contextSize: Int = 32768, runtime: EngineRuntimeConfig? = nil
    ) -> AgentSettings {
        AgentSettings(
            engineDir: engineDir, modelPath: modelFile, contextSize: contextSize,
            workspace: workspace, runtime: runtime)
    }

    @Test func appliesWhenAdmittedChangedIdle() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
            admission: .admitted) == .apply)
    }

    @Test func refusedWhileGeneratingEvenWhenAdmittedAndChanged() {
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: true, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
            admission: .admitted)
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("generating"))
    }

    @Test func refusedWhileConsultingEvenWhenAdmittedAndChanged() {
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: true,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
            admission: .admitted)
        guard case .refused(let message) = decision else {
            Issue.record("expected refusal, got \(decision)")
            return
        }
        #expect(message.contains("consult"))
    }

    @Test func noChangeWhenSameSettings() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: runningFile),
            admission: .admitted) == .noChange)
    }

    @Test func noChangeWhenSameSettingsRegardlessOfAdmission() {
        let reason = FeasibilityReason(
            message: "needs 12.0 GiB but only 6.0 GiB available",
            deficitBytes: 1, availableBytes: 1, plannedBytes: 2)
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: runningFile),
            admission: .infeasible(reason)) == .noChange)
    }

    @Test func noChangeWhenSameSettingsRegardlessOfContractMismatch() {
        let mismatches: [VariantMismatch] = [.architecture(expected: "laguna", actual: "mellum")]
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: runningFile),
            admission: .contractMismatch(mismatches)) == .noChange)
    }

    @Test func appliesForCustomPathWithNilAdmission() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
            admission: nil) == .apply)
    }

    @Test func refusedWithContractMismatchMessages() {
        let mismatches: [VariantMismatch] = [
            .architecture(expected: "laguna", actual: "mellum"),
            .rope(expected: "scalingType=yarn freqBase=500000.0", actual: "scalingType=nope freqBase=1.0"),
        ]
        let decision = ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
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
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile),
            targetSettings: settings(modelFile: targetFile),
            admission: .infeasible(reason))
        #expect(decision == .refused("needs 12.0 GiB but only 6.0 GiB available"))
    }

    @Test func sameFileDifferentPathSpellingIsNoChange() {
        let spelled = URL(fileURLWithPath: "/models/../models/laguna-s.gguf")
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: spelled),
            targetSettings: settings(modelFile: runningFile),
            admission: .admitted) == .noChange)
    }

    @Test func appliesWhenOnlyContextSizeChanged() {
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile, contextSize: 32768),
            targetSettings: settings(modelFile: runningFile, contextSize: 51200),
            admission: .admitted) == .apply)
    }

    @Test func appliesWhenOnlyRuntimeChanged() {
        let ssd = EngineRuntimeConfig(ssdStreaming: true, ssdStreamingCacheExperts: 3200, prefillChunk: nil)
        #expect(ModelSwitchEvaluator.decide(
            isGenerating: false, isConsulting: false,
            runningSettings: settings(modelFile: runningFile, runtime: nil),
            targetSettings: settings(modelFile: runningFile, runtime: ssd),
            admission: .admitted) == .apply)
    }
}
