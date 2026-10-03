import Testing
@testable import SwiftStarKit

struct EngineMetricsTests {
    @Test func pauseComputesRates() {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: 682, prefillMs: 827.3, evalCount: 8, evalMs: 61.2)))
        #expect(abs(s.prefillTPS! - 824) < 0.5)
        #expect(abs(s.generationTPS! - 130.7) < 0.5)
    }

    @Test func missingDurationGivesNil() {
        for ms in [0.0, nil] {
            var s = EngineMetricsState()
            EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
                prefillTokens: nil, prefillMs: nil, evalCount: 8, evalMs: ms)))
            #expect(s.generationTPS == nil)
        }
    }

    @Test func answerAndMemoryFillContextAndGPU() throws {
        var s = EngineMetricsState()
        for e in try EngineTranscriptTests.events(fromFixture: "tool-read.ndjson") {
            EngineMetricsReducer.reduce(&s, e)
        }
        #expect(s.contextUsed! > 0)
        #expect(s.contextSize == 20000)
        #expect(s.gpuBudgetBytes! > 0)
        #expect(s.planGiB! > 0)
    }

    // Payload: session event carries context_size (fixtures/engine/tool-read.ndjson line 3).
    @Test func sessionEventSetsWindow() {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .session(EngineSessionInfo(id: "s", modelID: "m", contextSize: 20000)))
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

    @Test func interruptedUpdatesContext() {
        var s = EngineMetricsState(contextUsed: 10, contextSize: 100)
        EngineMetricsReducer.reduce(&s, .interrupted(contextUsed: 512, contextSize: 20000))
        #expect(s.contextUsed == 512)
        #expect(s.contextSize == 20000)
        EngineMetricsReducer.reduce(&s, .interrupted(contextUsed: nil, contextSize: nil))
        #expect(s.contextUsed == 512)
    }
}
