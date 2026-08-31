import Testing
import Foundation
@testable import SwiftStarKit

/// `ArmDiff` (task 2, eval-cli): refuses to compare two arms of an A/B when
/// they differ by anything the experiment did not declare. Motivated by the
/// same 2026-08-30 incident as `SpawnRecord` — two arms silently differed by
/// `--power 70` vs `100` and were read as an engine speedup.
struct ArmDiffTests {
    private func settings(
        contextSize: Int = 16384,
        powerSavingEnabled: Bool = false,
        maxTokens: Int = 0,
        noThink: Bool = false,
        thinkBudget: Int = 0,
        seed: UInt64 = 0
    ) -> AgentSettings {
        AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: contextSize,
            workspace: URL(fileURLWithPath: "/Users/me/Work"),
            shellAllowed: false,
            powerSavingEnabled: powerSavingEnabled,
            maxTokens: maxTokens,
            noThink: noThink,
            thinkBudget: thinkBudget,
            seed: seed)
    }

    private func record(
        settings s: AgentSettings,
        engineSHA: String = "engine-sha",
        engineBinaryHash: String = "engine-hash",
        swiftstarSHA: String = "app-sha",
        hostTools: Bool = true,
        contextSize: Int? = nil
    ) -> SpawnRecord {
        SpawnRecord(
            engineSHA: engineSHA, engineDirty: false, engineBinaryHash: engineBinaryHash,
            swiftstarSHA: swiftstarSHA, swiftstarDirty: false, harnessBinaryHash: "app-hash",
            maxTokens: s.maxTokens, thinkBudget: s.thinkBudget, seed: s.seed,
            systemPromptHash: "sysprompt-hash", runtimeFlags: [],
            modelPath: s.modelPath.path, modelBytes: 123, modelHash: "model-hash", variantID: "laguna-xs",
            contextSize: contextSize ?? s.contextSize,
            sampler: AgentCommand.samplerRecord(settings: s),
            power: AgentCommand.powerRecord(settings: s),
            thinkPolicy: s.noThink ? "none" : "default",
            tools: ["read", "write", "bash"], shellAllowed: s.shellAllowed, hostTools: hostTools,
            workspace: s.workspace.path, workspaceRef: "workspace-ref",
            osBuild: "25A5327a", wiredLimitBytes: 999,
            environment: [:], userDefaults: [:],
            captureDirectory: "captures/live/20260830-000000",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000), runIndex: 0,
            argv: AgentCommand.argv(settings: s))
    }

    @Test func admitsWhenOnlyTheDeclaredVariableDiffers() {
        let a = record(settings: settings(), hostTools: true)
        let b = record(settings: settings(), hostTools: false)
        let result = ArmDiff.admit(a, b, variable: "hostTools", declaredRefs: nil)
        #expect(result == .success(["hostTools"]))
    }

    // The 2026-08-30 failure, asserted directly: an arm-A/B declared to
    // differ only by hostTools also silently differed by power.
    @Test func refusesTheUndeclaredThrottle() {
        let a = record(settings: settings(powerSavingEnabled: false), hostTools: true)
        let b = record(settings: settings(powerSavingEnabled: true), hostTools: false)
        let result = ArmDiff.admit(a, b, variable: "hostTools", declaredRefs: nil)
        switch result {
        case .success:
            Issue.record("expected a refusal naming power")
        case .failure(let refusal):
            #expect(refusal.undeclared == ["power"])
        }
    }

    // An early draft admitted this by allowlisting `argv` wholesale under
    // `gitRef` — this test exists so that defect cannot come back.
    @Test func gitRefDoesNotAdmitArgvOnlySettings() {
        // maxTokens=100 clamps both requests to the same actual budget (50),
        // so sampler/argv come out identical and only thinkBudget (the raw
        // request) differs — see SpawnRecordTests.argvOnlySettingsAreTheirOwnFields.
        let a = record(settings: settings(maxTokens: 100, thinkBudget: 60), engineSHA: "sha-x")
        let b = record(settings: settings(maxTokens: 100, thinkBudget: 500), engineSHA: "sha-y")
        let result = ArmDiff.admit(a, b, variable: "gitRef", declaredRefs: nil)
        switch result {
        case .success:
            Issue.record("expected a refusal naming thinkBudget")
        case .failure(let refusal):
            #expect(refusal.undeclared == ["thinkBudget"])
        }
    }

    @Test func gitRefAdmitsTheBuildKeys() {
        let a = record(settings: settings(), engineSHA: "sha-x", engineBinaryHash: "hash-x")
        let b = record(settings: settings(), engineSHA: "sha-y", engineBinaryHash: "hash-y")
        let result = ArmDiff.admit(a, b, variable: "gitRef", declaredRefs: ("sha-x", "sha-y"))
        #expect(result == .success(["engineSHA", "engineBinaryHash"]))
    }

    @Test func refusesWhenResolvedShaDoesNotMatchTheDeclaredRef() {
        let a = record(settings: settings(), engineSHA: "sha-y") // resolved to Y, not the declared X
        let b = record(settings: settings(), engineSHA: "sha-y")
        let result = ArmDiff.admit(a, b, variable: "gitRef", declaredRefs: ("sha-x", "sha-y"))
        switch result {
        case .success:
            Issue.record("expected a refusal: arm A resolved to a SHA other than its declared ref")
        case .failure(let refusal):
            #expect(refusal.message.contains("sha-x"))
            #expect(refusal.message.contains("sha-y"))
        }
    }

    @Test func refusesAnAppSideGitRefExperiment() {
        let a = record(settings: settings(), swiftstarSHA: "app-sha-1")
        let b = record(settings: settings(), swiftstarSHA: "app-sha-2")
        let result = ArmDiff.admit(a, b, variable: "gitRef", declaredRefs: nil)
        switch result {
        case .success:
            Issue.record("expected a refusal: swiftstarSHA differs under a gitRef (engine) experiment")
        case .failure(let refusal):
            #expect(refusal.undeclared == ["swiftstarSHA"])
            #expect(refusal.message.contains("harness"))
        }
    }

    // hostTools genuinely differs (true vs false) here — the declared
    // variable must actually differ (F1's second hole) even in a test whose
    // point is the must-differ allowlist, not the variable itself.
    @Test func admitsTheMustDifferAllowlist() {
        let a = SpawnRecord(
            engineSHA: "e", engineDirty: false, engineBinaryHash: "eb",
            swiftstarSHA: "s", swiftstarDirty: false, harnessBinaryHash: "sb",
            maxTokens: 0, thinkBudget: 0, seed: 0, systemPromptHash: "sp", runtimeFlags: [],
            modelPath: "/m", modelBytes: 1, modelHash: "mh", variantID: nil,
            contextSize: 100, sampler: "sampler", power: "power", thinkPolicy: "default",
            tools: [], shellAllowed: false, hostTools: true,
            workspace: "/w", workspaceRef: "wr", osBuild: "os", wiredLimitBytes: 1,
            environment: [:], userDefaults: [:],
            captureDirectory: "captures/a", startedAt: Date(timeIntervalSince1970: 1), runIndex: 0,
            argv: [])
        let b = SpawnRecord(
            engineSHA: "e", engineDirty: false, engineBinaryHash: "eb",
            swiftstarSHA: "s", swiftstarDirty: false, harnessBinaryHash: "sb",
            maxTokens: 0, thinkBudget: 0, seed: 0, systemPromptHash: "sp", runtimeFlags: [],
            modelPath: "/m", modelBytes: 1, modelHash: "mh", variantID: nil,
            contextSize: 100, sampler: "sampler", power: "power", thinkPolicy: "default",
            tools: [], shellAllowed: false, hostTools: false,
            workspace: "/w", workspaceRef: "wr", osBuild: "os", wiredLimitBytes: 1,
            environment: [:], userDefaults: [:],
            captureDirectory: "captures/b", startedAt: Date(timeIntervalSince1970: 2), runIndex: 1,
            argv: [])
        let result = ArmDiff.admit(a, b, variable: "hostTools", declaredRefs: nil)
        #expect(result == .success(["captureDirectory", "hostTools", "startedAt", "runIndex"]))
    }

    // Fable-fixes review, F1's second hole: an experiment declares a
    // variable, but the two arms are IDENTICAL on that axis — the treatment
    // never applied. `differingKeys` has nothing undeclared to complain
    // about, so the old code admitted this; it must now be refused.
    @Test func refusesWhenTheDeclaredVariableDoesNotActuallyDiffer() {
        let a = record(settings: settings(), hostTools: true)
        let b = record(settings: settings(), hostTools: true) // "treatment" never applied
        let result = ArmDiff.admit(a, b, variable: "hostTools", declaredRefs: nil)
        switch result {
        case .success:
            Issue.record("expected a refusal: the declared variable never actually differed")
        case .failure(let refusal):
            #expect(refusal.message.contains("hostTools"))
        }
    }

    // The allowlist is fixed, not widened by whatever the caller declares:
    // a `ctx` (contextSize) difference is refused even though every other
    // key matches.
    @Test func refusesAnUndeclaredContextSize() {
        let a = record(settings: settings(), contextSize: 4096)
        let b = record(settings: settings(), contextSize: 8192)
        let result = ArmDiff.admit(a, b, variable: "hostTools", declaredRefs: nil)
        switch result {
        case .success:
            Issue.record("expected a refusal naming contextSize")
        case .failure(let refusal):
            #expect(refusal.undeclared == ["contextSize"])
        }
    }
}
