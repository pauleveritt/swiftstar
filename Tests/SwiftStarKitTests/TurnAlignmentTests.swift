import Testing
import Foundation
@testable import SwiftStarKit

/// Pairs each `TurnOutcome` with the turn that actually produced it. The app
/// writes an outcome only when a `ready` carrying turn data (stop_reason /
/// generated / ctx_used) closes a turn the user started; the engine's startup
/// prefill ends in a field-less ready and writes none (AgentController: the
/// outcome builder is nil at startup). Indexing outcomes by plain turn number
/// misattributes outcome[0] to the phantom startup turn — observed on
/// captures/live/20260827-200648, where summary reported turn 1 (the prefill)
/// as "ctx 13728 tools 62" and "tools 0" for the turn that actually made 62
/// calls. The fix: outcome k pairs with the k-th turn whose terminal ready
/// carries data.
struct TurnAlignmentTests {
    private static func status(_ state: String, ctx: Int, gen: Int = 0) -> WireEvent {
        .status(StatusSnapshot(ctxUsed: ctx, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                               ts: 0, generated: gen, state: state))
    }

    private static func outcome(task: String, generated: Int, ctx: Int,
                                stop: TurnStopReason = .eos) -> TurnOutcome {
        TurnOutcome(model: "m", build: "b", sampler: "s", task: task,
                    generatedTokens: generated, ctxUsed: ctx, stopReason: stop, toolCalls: [])
    }

    @Test func outcomePairsWithTheTurnWhoseTerminalReadyCarriesData() {
        // The exact shape of captures/live/20260827-200648: startup prefill
        // ends in idle + a field-less ready (no builder -> no outcome); the
        // user turn ends in a ready carrying stop_reason/generated/ctx_used.
        let events: [WireEvent] = [
            Self.status("prefill", ctx: 1179),
            Self.status("idle", ctx: 1179),
            .ready(plannedBytes: nil, stopReason: nil, generated: nil, ctxUsed: nil),
            Self.status("prefill", ctx: 1179),
            Self.status("generating", ctx: 1240, gen: 6),
            .ready(plannedBytes: nil, stopReason: "interrupt", generated: 2, ctxUsed: 13728),
            Self.status("idle", ctx: 13730),
        ]
        let outcome = Self.outcome(task: "Take a look in this project.",
                                   generated: 2, ctx: 13728, stop: .interrupt)
        let aligned = TurnAlignment.align(events: events, outcomes: [outcome])
        #expect(aligned.count == 2)
        #expect(aligned[0].outcome == nil)
        #expect(aligned[0].statuses.last?.ctxUsed == 1179)
        #expect(aligned[1].outcome == outcome)
    }

    @Test func outcomePairsWithTheFirstTurnWhenItsReadyCarriesData() {
        // No startup phantom (a session whose very first ready already carries
        // turn data) must pair outcome[0] with turn 0 — never a +1 shift.
        let events: [WireEvent] = [
            Self.status("prefill", ctx: 1026),
            Self.status("generating", ctx: 1100, gen: 10),
            .ready(plannedBytes: nil, stopReason: "eos", generated: 12, ctxUsed: 120),
            Self.status("idle", ctx: 120),
        ]
        let outcome = Self.outcome(task: "one", generated: 12, ctx: 120)
        let aligned = TurnAlignment.align(events: events, outcomes: [outcome])
        #expect(aligned.count == 1)
        #expect(aligned[0].outcome == outcome)
    }

    @Test func outcomesPairInOrderAcrossMultipleUserTurns() {
        let events: [WireEvent] = [
            // turn 1: prefill -> ready(eos, 12, 120) -> idle
            Self.status("prefill", ctx: 1026),
            .ready(plannedBytes: nil, stopReason: "eos", generated: 12, ctxUsed: 120),
            Self.status("idle", ctx: 120),
            // turn 2: prefill -> ready(eos, 3, 9) -> idle
            Self.status("prefill", ctx: 9),
            .ready(plannedBytes: nil, stopReason: "eos", generated: 3, ctxUsed: 9),
            Self.status("idle", ctx: 9),
        ]
        let a = Self.outcome(task: "first", generated: 12, ctx: 120)
        let b = Self.outcome(task: "second", generated: 3, ctx: 9)
        let aligned = TurnAlignment.align(events: events, outcomes: [a, b])
        #expect(aligned.count == 2)
        #expect(aligned[0].outcome == a)
        #expect(aligned[1].outcome == b)
    }

    @Test func turnWithoutATerminalReadyConsumesNoOutcome() {
        // A user turn the engine never closed with a ready (killed mid-turn)
        // writes no outcome; the next turn's outcome must not drift.
        let events: [WireEvent] = [
            Self.status("prefill", ctx: 1026),
            Self.status("generating", ctx: 1100, gen: 10),
            Self.status("idle", ctx: 1100),
            Self.status("prefill", ctx: 9),
            .ready(plannedBytes: nil, stopReason: "eos", generated: 3, ctxUsed: 9),
            Self.status("idle", ctx: 9),
        ]
        let b = Self.outcome(task: "second", generated: 3, ctx: 9)
        let aligned = TurnAlignment.align(events: events, outcomes: [b])
        #expect(aligned.count == 2)
        #expect(aligned[0].outcome == nil)
        #expect(aligned[1].outcome == b)
    }

    @Test func openTurnStillBeingGeneratedHasNoOutcome() {
        // The in-progress turn (no closing idle, no ready yet) is reported but
        // pairs with nothing.
        let events: [WireEvent] = [
            Self.status("prefill", ctx: 1179),
            Self.status("generating", ctx: 1240, gen: 6),
        ]
        let aligned = TurnAlignment.align(events: events, outcomes: [])
        #expect(aligned.count == 1)
        #expect(aligned[0].outcome == nil)
        #expect(aligned[0].statuses.last?.ctxUsed == 1240)
    }

    @Test func closingIdleIsTheTurnsLastStatus() {
        // The closing idle settles the turn's ctx (compaction lands at idle),
        // so it must be the turn's LAST status — the outcome-less fallback in
        // `cmdSummary` reads `statuses.last`. A fixture where idle DIFFERS from
        // the preceding status (13728 -> 13730, observed live) is what pins this;
        // every pre-fix fixture had them equal, so the regression was invisible.
        let events: [WireEvent] = [
            Self.status("prefill", ctx: 1179),
            Self.status("generating", ctx: 13728, gen: 6),
            Self.status("idle", ctx: 13730),
        ]
        let aligned = TurnAlignment.align(events: events, outcomes: [])
        #expect(aligned.count == 1)
        #expect(aligned[0].statuses.last?.ctxUsed == 13730)
        #expect(aligned[0].statuses.first?.ctxUsed == 1179)
    }
}
