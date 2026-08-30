import Testing
import Foundation
@testable import SwiftStarKit

/// A capture's wire span is not its turn duration. In an app capture the wire
/// opens when the engine starts and the turn does not begin until the human has
/// finished typing — measured on `captures/live/20260830-180004`, 52.8s of the
/// 9.6-minute wire is pre-prompt, and the turn itself is 8.7 minutes. Reading
/// the whole span as "the turn took 9.6 min" overstates it by 22%, and compares
/// an app capture against a `swiftstar-drive` capture (which submits its prompt
/// immediately) on unequal terms.
struct TurnSpanTests {
    private func s(_ state: String, at micros: UInt64) -> StatusSnapshot {
        StatusSnapshot(ctxUsed: 0, ctxSize: 51_200, prefillTPS: 0, genTPS: 0,
                       ts: micros, generated: 0, state: state)
    }

    @Test func leadingIdleIsSeparatedFromTurnWork() {
        let span = TurnSpan.measure([
            s("idle", at: 0),
            s("idle", at: 50_000_000),        // +50s: engine up, human still typing
            s("prefill", at: 52_800_000),     // +52.8s: the turn actually starts
            s("generating", at: 100_000_000),
            s("idle", at: 573_600_000),       // +573.6s: turn ends
        ])
        #expect(span?.leadInSeconds == 52.8)
        #expect(span?.workSeconds == 520.8)
    }

    /// A drive capture submits immediately: no lead-in to strip, and the two
    /// readings agree.
    @Test func aCaptureWithNoLeadInReportsZero() {
        let span = TurnSpan.measure([
            s("prefill", at: 0),
            s("generating", at: 10_000_000),
            s("idle", at: 256_900_000),
        ])
        #expect(span?.leadInSeconds == 0)
        #expect(span?.workSeconds == 256.9)
    }

    /// Never invent a duration from a turn that did no work.
    @Test func allIdleHasNoSpan() {
        #expect(TurnSpan.measure([s("idle", at: 0), s("idle", at: 5_000_000)]) == nil)
    }

    @Test func emptyHasNoSpan() {
        #expect(TurnSpan.measure([]) == nil)
    }

    /// One sample is a point, not a span — but it did start work, so the lead-in
    /// is still known.
    @Test func oneWorkingSampleSpansNothing() {
        let span = TurnSpan.measure([s("idle", at: 0), s("prefill", at: 3_000_000)])
        #expect(span?.leadInSeconds == 3.0)
        #expect(span?.workSeconds == 0)
    }

    /// `ts` is CLOCK_MONOTONIC microseconds since boot. A wire that goes
    /// backwards is corrupt; report nothing rather than a negative duration.
    @Test func nonMonotonicTimestampsAreRefused() {
        #expect(TurnSpan.measure([s("prefill", at: 10_000_000),
                                  s("generating", at: 5_000_000)]) == nil)
    }
}
