import Testing
import Foundation
import SwiftStarKit
@testable import SwiftStarAppKit

/// P12.5: `PoolOrchestrator.init` grew a `workers: Int = 3` parameter (default
/// unchanged) threaded straight into `PoolEngine.argv(settings:workers:)`, so
/// a caller that needs an extra independent KV-cache session (a decompose
/// dispatch on its own worker id) can bump the pool without touching
/// `PoolOrchestrator`'s internals. `PoolEngine.argv` is a pure function — no
/// process spawn — so the formula itself is covered here without the
/// `SWIFTSTAR_INTEGRATION` gate `PoolOrchestratorTests`/`PoolEngineTests` use
/// for their process-spawning cases.
struct PoolEngineArgvTests {
    private func settings() -> AgentSettings {
        AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 8192,
            workspace: URL(fileURLWithPath: "/tmp/w"),
            shellAllowed: false)
    }

    @Test func defaultCallSiteShapeStillProducesPoolThree() {
        // What `PoolOrchestrator.init(settings:)` (no `workers:` argument)
        // resolves to today, byte-for-byte — the existing-call-sites-unchanged
        // half of the requirement.
        let argv = PoolEngine.argv(settings: settings(), workers: 3)
        #expect(argv.contains("--subagent-pool"))
        let idx = argv.firstIndex(of: "--subagent-pool")!
        #expect(argv[argv.index(after: idx)] == "3")
    }

    /// The decompose arm's shape: one more independent KV-cache session so
    /// WorkerId(3) cannot collide with the engine's untagged startup
    /// handshake or with implement/repair's workers 1/2 (D1).
    @Test func fourWorkersProducesPoolFour() {
        let argv = PoolEngine.argv(settings: settings(), workers: 4)
        let idx = argv.firstIndex(of: "--subagent-pool")!
        #expect(argv[argv.index(after: idx)] == "4")
    }

    @Test func poolFlagIsAppendedAfterTheBaseAgentArgv() {
        let base = AgentCommand.argv(settings: settings())
        let argv = PoolEngine.argv(settings: settings(), workers: 4)
        #expect(Array(argv.prefix(base.count)) == base)
        #expect(Array(argv.suffix(2)) == ["--subagent-pool", "4"])
    }
}
