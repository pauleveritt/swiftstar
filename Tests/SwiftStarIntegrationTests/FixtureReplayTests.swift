import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FixtureReplayTests {
    @Test func bundledFixtureMatchesRepoFixture() throws {
        guard let bundled = Bundle.module.url(forResource: "golden", withExtension: "ndjson") else {
            Issue.record("bundled golden.ndjson missing")
            return
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent/golden.ndjson")
        #expect(try Data(contentsOf: bundled) == Data(contentsOf: repo))
    }

    @Test func replayYieldsStatusAndReadyThroughReducer() async {
        var parser = WireEventParser()
        let reducer = MetricsReducer()
        var state = MetricsState()
        var sawStatus = false, sawBudget = false
        for await line in FixtureReplay.lines(cadenceNanoseconds: 1_000) {
            if let event = parser.feed(line) {
                reducer.reduce(&state, event)
                if case .status = event { sawStatus = true }
                if case .ready(let p) = event, p != nil { sawBudget = true }
            }
        }
        #expect(sawStatus)
        #expect(sawBudget)
        #expect(state.ctxUsed != nil)
        #expect(state.memoryBudgetPlannedBytes == 49_943_965_040)
    }
}
