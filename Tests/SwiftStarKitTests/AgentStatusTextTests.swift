import Foundation
import Testing
@testable import SwiftStarKit

struct AgentStatusTextTests {
    // MARK: state → message mapping

    @Test func mapsAllEightWireStates() {
        #expect(AgentStatusText.stateMessage("idle") == "Ready")
        #expect(AgentStatusText.stateMessage("prefill") == "Prefilling…")
        #expect(AgentStatusText.stateMessage("generating") == "Working…")
        #expect(AgentStatusText.stateMessage("compacting") == "Compacting…")
        #expect(AgentStatusText.stateMessage("draining") == "Draining…")
        #expect(AgentStatusText.stateMessage("saving") == "Saving…")
        #expect(AgentStatusText.stateMessage("error") == "Error")
        #expect(AgentStatusText.stateMessage("stopped") == "Stopped")
    }

    @Test func unknownStateFallsBackToBusy() {
        #expect(AgentStatusText.stateMessage("") == "Working…")
        #expect(AgentStatusText.stateMessage("some-new-state") == "Working…")
    }

    // MARK: fixed-width rate line

    @Test func rateLineIsFixedWidth() {
        #expect(AgentStatusText.promptDecodeLine(
            promptTPS: 1234, decodeTPS: 67, message: "Prefilling…")
            == "Prompt 1234 / Decode   67 tok/s — Prefilling…")
    }

    // MARK: TPS ratchet — the 2989d2c lesson: hold the last nonzero reading
    // (the wire reports only one of prefill/gen as nonzero per event).

    @Test func ratchetKeepsLastNonzero() {
        #expect(AgentStatusText.ratchet(previous: 0, new: 5) == 5)
        #expect(AgentStatusText.ratchet(previous: 5, new: 0) == 5)
        #expect(AgentStatusText.ratchet(previous: 5, new: 7) == 7)
        #expect(AgentStatusText.ratchet(previous: 0, new: 0) == 0)
    }
}
