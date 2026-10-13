import Testing
@testable import SwiftStarKit

struct EngineMetricsTests {
    @Test func pauseComputesRates() throws {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: 682, prefillMs: 827.3, evalCount: 8, evalMs: 61.2)))
        #expect(abs(try #require(s.prefillTPS) - 824) < 0.5)
        #expect(abs(try #require(s.generationTPS) - 130.7) < 0.5)
    }

    @Test(arguments: [0.0, nil]) func missingDurationGivesNil(_ ms: Double?) {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: nil, prefillMs: nil, evalCount: 8, evalMs: ms)))
        #expect(s.generationTPS == nil)
    }

    @Test func answerAndMemoryFillContextAndGPU() throws {
        var s = EngineMetricsState()
        for e in try Fixtures.events("tool-read.ndjson") {
            EngineMetricsReducer.reduce(&s, e)
        }
        #expect(try #require(s.contextUsed) > 0)
        #expect(s.contextSize == 20000)
        #expect(try #require(s.gpuBudgetBytes) > 0)
        #expect(try #require(s.planGiB) > 0)
    }

    // Payload: session event carries context_size (fixtures/engine/tool-read.ndjson line 3).
    @Test func sessionEventSetsWindow() {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .session(EngineSessionInfo(modelID: "m", contextSize: 20000)))
        #expect(s.contextSize == 20000)
        #expect(s.contextUsed == nil)
    }

    @Test func pauseMissingFieldsKeepThePriorRate() {
        // Every other reduce case falls back to the prior value on a missing
        // field (contextUsed, contextSize, gpu*); .pause did not, so a
        // checkpoint that happens to omit prefill/eval fields would blank a
        // rate the UI already knew, not just fail to update it.
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: 682, prefillMs: 827.3, evalCount: 8, evalMs: 61.2)))
        let (prefill, generation) = (s.prefillTPS, s.generationTPS)
        #expect(prefill != nil && generation != nil)
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: nil, prefillMs: nil, evalCount: 0, evalMs: nil)))
        #expect(s.prefillTPS == prefill)
        #expect(s.generationTPS == generation)
    }

    // SU.6b: a prefix-cache hit's tokens are loaded, not prefilled. Numbers
    // from session 20261013-154825-session-last: a hit of 944 tokens loaded
    // in 20 ms, then a checkpoint of 1146 prefill tokens in 1084 ms.
    private static let hitPause = EngineEvent.pause(PauseMetrics(
        prefillTokens: 1146, prefillMs: 1084, evalCount: 8, evalMs: 61.2))

    private static func cache(_ outcome: String) -> EngineEvent {
        .prefixCache(EnginePrefixCache(outcome: outcome, tokens: 944, loadMs: 20, fillMs: nil))
    }

    @Test func prefixHitLeavesCachedTokensOut() throws {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, Self.cache("hit"))
        EngineMetricsReducer.reduce(&s, Self.hitPause)
        #expect(abs(try #require(s.prefillTPS) - 189.8) < 0.5)
        #expect(s.prefixCache?.outcome == "hit")
    }

    @Test func prefixMissKeepsTheRate() throws {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, Self.cache("miss"))
        EngineMetricsReducer.reduce(&s, Self.hitPause)
        #expect(abs(try #require(s.prefillTPS) - 1057.2) < 0.5)
    }

    @Test func newSessionDropsTheCorrection() throws {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, Self.cache("hit"))
        EngineMetricsReducer.reduce(&s, .session(EngineSessionInfo(modelID: "m", contextSize: 10)))
        EngineMetricsReducer.reduce(&s, Self.hitPause)
        #expect(abs(try #require(s.prefillTPS) - 1057.2) < 0.5)
        #expect(s.prefixCache == nil)
    }

    /// interruptedUpdatesContext, resumedSetsContextUsed.
    @Test func interruptedAndResumedSetContext() {
        var s = EngineMetricsState(contextUsed: 10, contextSize: 100)
        EngineMetricsReducer.reduce(&s, .interrupted(contextUsed: 512, contextSize: 20000))
        #expect(s.contextUsed == 512)
        #expect(s.contextSize == 20000)
        EngineMetricsReducer.reduce(&s, .interrupted(contextUsed: nil, contextSize: nil))
        #expect(s.contextUsed == 512)
        EngineMetricsReducer.reduce(&s, .resumed(EngineResumed(
            sessionID: "s", turns: [], rewoundTo: 1, filesChanged: 0, contextUsed: 1071)))
        #expect(s.contextUsed == 1071)
    }
}
