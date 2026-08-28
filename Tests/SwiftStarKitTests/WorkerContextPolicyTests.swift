import Testing
import Foundation
@testable import SwiftStarKit

struct WorkerContextPolicyTests {
    /// Local copies of the defaults fixture (the ones in
    /// AgentDefaultSettingsTests are private to that suite): an isolated
    /// UserDefaults suite, removed from disk afterwards so repeated runs do
    /// not litter ~/Library/Preferences.
    private func scratchDefaults() -> (defaults: UserDefaults, name: String) {
        let name = "WorkerContextPolicyTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func cleanUp(_ defaults: UserDefaults, _ name: String) {
        defaults.removePersistentDomain(forName: name)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(name).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    @Test func defaultIs8192() {
        #expect(WorkerContextPolicy.defaultContext == 8192)
    }

    @Test func clampKeepsInsideParentAndFloor() {
        #expect(WorkerContextPolicy.clamp(requested: 8192, parentContext: 32768) == 8192)
        #expect(WorkerContextPolicy.clamp(requested: 4096, parentContext: 32768) == 4096)
    }

    @Test func clampFloorsBelowTheMinimum() {
        // Below 4,096 the scratch savings stop and the engine's own floor
        // applies (D8: the clamp is [4096, parent]).
        #expect(WorkerContextPolicy.clamp(requested: 2048, parentContext: 32768) == 4096)
    }

    @Test func clampCapsAtTheParent() {
        // A worker context can never bypass admission: it cannot exceed the
        // parent's own admitted context.
        #expect(WorkerContextPolicy.clamp(requested: 16384, parentContext: 8192) == 8192)
        #expect(WorkerContextPolicy.clamp(requested: 1_000_000, parentContext: 51200) == 51200)
    }

    @Test func zeroInheritsTheParent() {
        #expect(WorkerContextPolicy.clamp(requested: 0, parentContext: 32768) == 32768)
    }

    /// A parent smaller than the floor still wins — the cap is the binding
    /// constraint, because exceeding it is the case that bypasses admission.
    @Test func aParentBelowTheFloorStillCaps() {
        #expect(WorkerContextPolicy.clamp(requested: 8192, parentContext: 2048) == 2048)
    }

    @Test func resolvesFromUserDefaultsWithDefault() {
        let (defaults, name) = scratchDefaults()
        defer { cleanUp(defaults, name) }
        #expect(WorkerContextPolicy.resolve(defaults: defaults) == 8192)
        defaults.set(4096, forKey: "workerContextSize")
        #expect(WorkerContextPolicy.resolve(defaults: defaults) == 4096)
    }
}
