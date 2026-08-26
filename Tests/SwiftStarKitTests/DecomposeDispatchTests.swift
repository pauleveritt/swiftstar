import Testing
import Foundation
@testable import SwiftStarKit

/// P12.5 (D3): the follow-up/fail-closed decision, extracted as a pure
/// function of one turn's shape (`DecomposeDispatch.decide`) specifically so
/// it is unit-testable without a real engine — the actual `orch.runPhase` I/O
/// call in `swiftstar-agenttest/main.swift` is not exercised here at all.
struct DecomposeDispatchTests {
    @Test func textThatParsesGoesStraightToParsedRegardlessOfStopReason() {
        let text = "## Phase 1: A\n\ndo it\n\n## Phase 2: B\n\ndo more"

        let decision = DecomposeDispatch.decide(text: text, stopReason: .eos, isFollowUp: false)

        guard case .parsed(let phases) = decision else {
            Issue.record("expected .parsed, got \(decision)")
            return
        }
        #expect(phases.count == 2)
    }

    /// The exact D3 trigger: zero phases, but the turn stopped cleanly at
    /// `.eos` having produced non-blank text — "reasoned instead of emitting,"
    /// not "produced nothing" or "got cut off mid-generation."
    @Test func zeroPhasesAtEosWithNonBlankTextOnFirstTurnNeedsFollowUp() {
        let decision = DecomposeDispatch.decide(
            text: "Let me think about how to split this spec into phases...",
            stopReason: .eos, isFollowUp: false)

        #expect(decision == .needsFollowUp)
    }

    /// A second zero-phase result — the follow-up already ran — fails closed
    /// unconditionally. No third turn, regardless of stop reason or text.
    @Test func zeroPhasesOnTheFollowUpTurnAlwaysFailsClosed() {
        let decision = DecomposeDispatch.decide(
            text: "Still just reasoning, no headings.",
            stopReason: .eos, isFollowUp: true)

        #expect(decision == .failedClosed)
    }

    @Test func blankTextOnFirstTurnFailsClosedWithoutAFollowUp() {
        // Nothing to continue from — a follow-up on an empty turn cannot be a
        // continuation of anything, so there is no reasoned-then-stopped shape
        // to rescue.
        let decision = DecomposeDispatch.decide(text: "   \n  ", stopReason: .eos, isFollowUp: false)

        #expect(decision == .failedClosed)
    }

    @Test func sessionExhaustionStopFailsClosedEvenWithNonBlankText() {
        // A `.limit`/`.contextFull` stop is session exhaustion, not
        // reason-then-stop — a follow-up turn on an exhausted session cannot
        // recover, so this must not request one.
        let decision = DecomposeDispatch.decide(
            text: "Some partial reasoning that got cut off",
            stopReason: .limit, isFollowUp: false)

        #expect(decision == .failedClosed)
    }

    @Test func oneParsedPhaseIsEnoughToSucceed() {
        let decision = DecomposeDispatch.decide(
            text: "## Phase 1: Only one\n\ndo the one thing", stopReason: .eos, isFollowUp: false)

        guard case .parsed(let phases) = decision else {
            Issue.record("expected .parsed, got \(decision)")
            return
        }
        #expect(phases.count == 1)
    }
}
