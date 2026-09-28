import Testing
@testable import SwiftStarKit

struct EngineMetricsTests {
    @Test func pauseComputesRates() {
        var s = EngineMetricsState()
        EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
            prefillTokens: 682, prefillMs: 827.3, evalCount: 8, evalMs: 61.2, outputTokens: nil)))
        #expect(abs(s.prefillTPS! - 824) < 0.5)
        #expect(abs(s.generationTPS! - 130.7) < 0.5)
    }

    @Test func missingDurationGivesNil() {
        for ms in [0.0, nil] {
            var s = EngineMetricsState()
            EngineMetricsReducer.reduce(&s, .pause(PauseMetrics(
                prefillTokens: nil, prefillMs: nil, evalCount: 8, evalMs: ms, outputTokens: nil)))
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
}
