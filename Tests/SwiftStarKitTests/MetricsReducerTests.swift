import Testing
@testable import SwiftStarKit

struct MetricsReducerTests {
    @Test func ratchetHoldsLastNonZeroRates() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 100, ctxSize: 32768, prefillTPS: 5.8, genTPS: 0, ts: 0, generated: 0, state: "")))
        #expect(state.prefillTPS == 5.8)
        #expect(state.genTPS == 0)
        // Generation phase: prefill drops to 0, gen becomes non-zero.
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 200, ctxSize: 32768, prefillTPS: 0, genTPS: 12.3, ts: 0, generated: 0, state: "")))
        #expect(state.prefillTPS == 5.8)  // ratcheted — does not flicker to 0
        #expect(state.genTPS == 12.3)
        // Idle: both zero — both hold.
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 200, ctxSize: 32768, prefillTPS: 0, genTPS: 0, ts: 0, generated: 0, state: "")))
        #expect(state.prefillTPS == 5.8)
        #expect(state.genTPS == 12.3)
    }

    @Test func statusUpdatesContext() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        #expect(state.ctxUsed == nil)
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0, genTPS: 0, ts: 0, generated: 0, state: "")))
        #expect(state.ctxUsed == 958)
        #expect(state.ctxSize == 32768)
    }

    @Test func missingCtxDoesNotBlankTheRing() {
        // A status event whose ctx_used/ctx_size were zero-filled (absent on
        // the wire) must not blank the ring — one incomplete event would
        // otherwise empty the dial until the next complete one.
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0, genTPS: 0, ts: 0, generated: 0, state: "")))
        reducer.reduce(&state, .status(StatusSnapshot(ctxUsed: 0, ctxSize: 0, prefillTPS: 0, genTPS: 0, ts: 0, generated: 0, state: "")))
        #expect(state.ctxUsed == 958)
        #expect(state.ctxSize == 32768)
    }

    @Test func readySetsBudget() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .ready(plannedBytes: 49_943_965_040))
        #expect(state.memoryBudgetPlannedBytes == 49_943_965_040)
    }

    @Test func ignoredIsNoOp() {
        var state = MetricsState()
        var reducer = MetricsReducer()
        reducer.reduce(&state, .ignored("x"))
        #expect(state == MetricsState())
    }
}
