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

    // MARK: - model resolution defers to VariantResolver

    @Test func modelPathFallsBackToDefaultModelFallbackWhenNothingSet() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.modelPath == AgentDefaultSettings.defaultModelFallback(environment: [:]))
        #expect(settings.runtime == nil, "the hardcoded Laguna S fallback has no Variant")
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

    @Test func contextSizeIsUnclampedWithNoSelectedVariant() {
        let (defaults, scratchName) = scratchDefaults()
        defer { cleanUp(defaults, scratchName) }
        defaults.set(12345, forKey: "contextSize")
        let settings = AgentDefaultSettings.resolve(defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.contextSize == 12345, "Laguna S (no Variant) keeps the requested size")
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
}
