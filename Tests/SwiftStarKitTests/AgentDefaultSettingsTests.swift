import Testing
import Foundation
@testable import SwiftStarKit

/// Item 5b (P22 cleanup): `AgentController.defaultSettings()`'s resolution
/// logic, extracted into `AgentDefaultSettings` so it is unit-testable —
/// `Sources/SwiftStar` has no test target. Each test builds an isolated
/// `UserDefaults` suite (never `.standard`) so this suite cannot read or
/// leave behind the developer's real app defaults.
struct AgentDefaultSettingsTests {
    /// `UserDefaults(suiteName:)` persists to `~/Library/Preferences/<name>.plist`
    /// (observed directly -- not just in-memory) the moment a test calls
    /// `.set`, so every test must remove it when done or repeated test runs
    /// litter the developer's real Library folder with one throwaway plist
    /// per test, forever. `removePersistentDomain(forName:)` alone clears the
    /// in-memory domain but — observed directly too — does not reliably
    /// unlink the file, so this also deletes it straight from disk.
    private func scratchDefaults() -> (defaults: UserDefaults, name: String) {
        let name = "AgentDefaultSettingsTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func cleanUp(_ defaults: UserDefaults, _ name: String) {
        defaults.removePersistentDomain(forName: name)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    // MARK: - defaultModelFallback

    @Test func defaultModelFallbackUsesTheHardcodedLagunaPathByDefault() {
        let url = AgentDefaultSettings.defaultModelFallback(environment: [:])
        #expect(url.path == "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
    }

    @Test func defaultModelFallbackHonorsEnvOverride() {
        let url = AgentDefaultSettings.defaultModelFallback(
            environment: ["SWIFTSTAR_DEFAULT_MODEL": "/tmp/custom.gguf"])
        #expect(url.path == "/tmp/custom.gguf")
    }

    // MARK: - engineDir: UserDefaults > DS4_DIR > <cwd>/external/ds4

    @Test func engineDirPrefersUserDefaultsOverEnv() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set("/from/defaults", forKey: "engineDir")
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: ["DS4_DIR": "/from/env"], projectRoot: nil)
        #expect(settings.engineDir.path == "/from/defaults")
    }

    @Test func engineDirFallsBackToEnvWhenUserDefaultsUnset() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: ["DS4_DIR": "/from/env"], projectRoot: nil)
        #expect(settings.engineDir.path == "/from/env")
    }

    @Test func engineDirFallsBackToCwdExternalDs4WhenNothingSet() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("external/ds4")
        #expect(settings.engineDir.path == expected.path)
    }

    // MARK: - effectiveSelectedVariantID: the single source both
    // `resolve` and `AgentController.startAgent()`'s admission gate read, so
    // they can't disagree about which variant (if any) is in play.

    @Test func effectiveVariantIsTheStoredChoiceWhenSet() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(VariantRegistry.mellum.id, forKey: "selectedVariantID")
        let id = AgentDefaultSettings.effectiveSelectedVariantID(defaults: defaults, environment: [:])
        #expect(id == VariantRegistry.mellum.id)
    }

    @Test func effectiveVariantIsLagunaSWhenNothingConfigured() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let id = AgentDefaultSettings.effectiveSelectedVariantID(defaults: defaults, environment: [:])
        #expect(id == VariantRegistry.lagunaS.id)
    }

    @Test func effectiveVariantIsNilWhenAnExplicitModelPathIsSetWithNoStoredVariant() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set("/tmp/explicit.gguf", forKey: "modelPath")
        let id = AgentDefaultSettings.effectiveSelectedVariantID(defaults: defaults, environment: [:])
        #expect(id == nil)
    }

    @Test func effectiveVariantIsNilWhenSwiftstarModelEnvIsSetWithNoStoredVariant() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let id = AgentDefaultSettings.effectiveSelectedVariantID(
            defaults: defaults, environment: ["SWIFTSTAR_MODEL": "/tmp/env.gguf"])
        #expect(id == nil)
    }

    // MARK: - model resolution defers to VariantResolver

    @Test func modelPathResolvesLagunaSVariantWhenNothingSet() {
        // P22: nothing-configured now resolves to Laguna S's Variant, not the
        // literal fallback constant — the fallback stays reachable only when
        // an explicit modelPath/SWIFTSTAR_MODEL still needs to win with no
        // variant selected (see effectiveSelectedVariantID).
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.modelPath == VariantRegistry.lagunaS.modelFile)
        // Laguna S now declares the SSD-streaming runtime (P22 SSD-across-the-
        // line, engine divergence #13), so the default settings carry it — this
        // IS evidence the Variant was resolved.
        #expect(settings.runtime == VariantRegistry.lagunaS.runtime)
        #expect(settings.runtime?.ssdStreaming == true)
    }

    @Test func modelPathFallsBackToTheLiteralWhenAnExplicitModelPathIsSet() {
        // An explicit modelPath with no variant selected must still win — the
        // genuine escape hatch effectiveSelectedVariantID preserves.
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set("/tmp/explicit-model-path.gguf", forKey: "modelPath")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.modelPath.path == "/tmp/explicit-model-path.gguf")
        #expect(settings.runtime == nil)
    }

    @Test func modelPathHonorsEnvSwiftstarModelOverride() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: ["SWIFTSTAR_MODEL": "/tmp/env-model.gguf"], projectRoot: nil)
        #expect(settings.modelPath.path == "/tmp/env-model.gguf")
    }

    @Test func modelPathResolvesASelectedVariant() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(VariantRegistry.mellum.id, forKey: "selectedVariantID")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.modelPath == VariantRegistry.mellum.modelFile)
        #expect(settings.runtime == VariantRegistry.mellum.runtime)
    }

    // MARK: - context clamp: only when a Variant is resolved

    @Test func contextSizeIsClampedToASelectedVariantsMaxContext() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(VariantRegistry.mellum.id, forKey: "selectedVariantID")
        defaults.set(999_999, forKey: "contextSize")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        let expectedMax = VariantRegistry.mellum.contract.memoryBudget.clampContext(999_999)
        #expect(settings.contextSize == expectedMax)
        #expect(settings.contextSize < 999_999, "the clamp must actually reduce an over-large request")
    }

    @Test func contextSizeIsANoOpClampAtTheAppDefaultWithNoSelectedVariant() {
        // Nothing-selected resolves to Laguna S (maxContext 51,200), which
        // exactly covers the app's shipped default of 51,200 — the common
        // case clamps to itself.
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(51_200, forKey: "contextSize")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.contextSize == 51_200)
    }

    @Test func contextSizeIsStillClampedForLagunaSOutsideItsRange() {
        // Laguna S has a Variant now too (P22) — an out-of-range request is
        // clamped the same as an explicitly-selected Mellum/XS would be, not
        // left unclamped as it was before Laguna S had a Variant at all.
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(4_096, forKey: "contextSize")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.contextSize == VariantRegistry.lagunaS.contract.memoryBudget.minContext)
    }

    @Test func contextSizeIsUnclampedWhenAnExplicitModelPathWinsOverAnyVariant() {
        // The one remaining unclamped path: an explicit modelPath with no
        // variant selected resolves through the literal fallback, which has no
        // Variant/MemoryBudget to clamp against.
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set("/tmp/explicit-model-path.gguf", forKey: "modelPath")
        defaults.set(12345, forKey: "contextSize")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.contextSize == 12345)
    }

    @Test func contextSizeDefaultsTo51200WhenUnset() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.contextSize == 51_200)
    }

    // MARK: - workspace: UserDefaults > projectRoot > home

    @Test func workspacePrefersUserDefaultsOverProjectRoot() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set("/from/defaults-ws", forKey: "agentWorkspace")
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: [:], projectRoot: URL(fileURLWithPath: "/from/project-root"))
        #expect(settings.workspace.path == "/from/defaults-ws")
    }

    @Test func workspaceFallsBackToProjectRootWhenUserDefaultsUnset() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: [:], projectRoot: URL(fileURLWithPath: "/from/project-root"))
        #expect(settings.workspace.path == "/from/project-root")
    }

    @Test func workspaceFallsBackToHomeWhenNothingResolves() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.workspace == FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: - shellAllowed: deny by default

    @Test func shellAllowedDefaultsToFalse() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.shellAllowed == false)
    }

    @Test func shellAllowedHonorsUserDefaultsTrue() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(true, forKey: "agentShellAllowed")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.shellAllowed == true)
    }

    // MARK: - power savings

    @Test func powerSavingsDefaultsToEnabled() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.powerSavingEnabled == true)
        #expect(AgentCommand.argv(settings: settings).contains("--power"))
    }

    @Test func powerSavingsHonorsAnExplicitOptOut() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(false, forKey: "agentPowerSavingEnabled")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.powerSavingEnabled == false)
        #expect(!AgentCommand.argv(settings: settings).contains("--power"))
    }

    // MARK: - think budget (P23)

    /// The app sets a think budget by default. It is a guardrail, not a tuning
    /// knob: an ordinary round spends ~25 think tokens, so 2,048 never fires
    /// normally — but the 2026-08-28 probe reproduced a run that spent 15,873
    /// of 16,384 tokens reasoning and never answered.
    @Test func thinkBudgetDefaultsToTheRunawayGuardrail() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.thinkBudget == 2048)
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("--think-budget"))
        #expect(argv.contains("2048"))
    }

    /// Zero disables the flag entirely rather than passing `--think-budget 0`,
    /// which the engine would read as a live ceiling of zero. Sibling refusal
    /// case for the default above (binding rule 4).
    @Test func aZeroThinkBudgetOmitsTheFlag() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(0, forKey: "agentThinkBudget")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.thinkBudget == 0)
        #expect(!AgentCommand.argv(settings: settings).contains("--think-budget"))
    }

    /// `thinkBudget` must stay below `maxTokens` or the forced `</think>` lands
    /// with no room left to act (AgentCommand's own doc comment). The app sets
    /// no `maxTokens`, so the pair only binds when a caller sets both — the
    /// agent test does.
    @Test func thinkBudgetIsClampedBelowAnExplicitMaxTokens() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(4096, forKey: "agentThinkBudget")
        var settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(AgentSettings.clampThinkBudget(settings) == 4096)  // maxTokens unset
        settings.maxTokens = 2048
        #expect(AgentSettings.clampThinkBudget(settings) == 1024)  // min(4096, 2048/2)
    }
}
