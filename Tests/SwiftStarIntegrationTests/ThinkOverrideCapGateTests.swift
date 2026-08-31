import Testing
import Foundation
import SwiftStarKit

/// P23 (D3): the app must never send a per-turn feature field the engine did
/// not advertise. The *decision* is pure and fast-tier tested
/// (`TurnThinkPolicyTests`), and the *encoding* is too (`PoolPromptTests`);
/// what those cannot reach is the wiring — that the live send actually passes
/// `advertisedCaps.contains(...)` rather than a hardcoded `true`.
///
/// `AgentController` lives in the `SwiftStar` executable target, which is not a
/// dependency of this test target (and an executable target is not importable
/// here), so the wiring is asserted at source level — the same pattern
/// `PoolEngineArgvTests.poolEngineArgvIsTheOnlyPooledArgvBuilder` established
/// in part 1 for exactly this reason.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ThinkOverrideCapGateTests {
    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: FakeAgentHarness.repoRoot.appendingPathComponent(relativePath),
                   encoding: .utf8)
    }

    /// The orchestrator turn's send resolves through the policy with the caps
    /// the handshake actually advertised.
    @Test func injectGatesTheOverrideOnTheAdvertisedCap() throws {
        let controller = try source("Sources/SwiftStar/AgentController.swift")
        #expect(controller.contains("capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap)"),
                "inject must gate the think override on the advertised cap, not assume it")
        #expect(controller.contains("advertisedCaps = parser.optionalCaps"),
                "the caps must be recorded from the handshake")
        #expect(controller.contains("advertisedCaps = []"),
                "caps must be cleared per spawn — a re-spawn must not inherit the previous engine's advertisement")
    }

    /// `/quick` refuses rather than silently running a normal turn when the
    /// engine cannot honor a no-think override.
    @Test func quickRefusesWithoutTheCap() throws {
        let controller = try source("Sources/SwiftStar/AgentController.swift")
        #expect(controller.contains("guard advertisedCaps.contains(TurnThinkPolicy.overrideCap) else"),
                "/quick must refuse without the cap")
        #expect(controller.contains("/quick unavailable"),
                "the refusal must be visible in the transcript, not silent")
    }

    /// The dispatch path gates both fields. The ctx field matters as much as
    /// think: an engine that never claimed the key would run the worker at the
    /// parent's context, which is a silent budget overrun rather than a
    /// visible refusal.
    @Test func dispatchGatesBothPerTurnFields() throws {
        let loop = try source("Sources/SwiftStar/AgentPoolTurnLoop.swift")
        #expect(loop.contains("capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap)"),
                "the worker's think must be gated on the advertised cap")
        #expect(loop.contains("advertisedCaps.contains(TurnThinkPolicy.overrideCap)\n            ? WorkerContextPolicy.clamp"),
                "the worker's ctx must be gated on the advertised cap too")
        #expect(loop.contains("TurnThinkPolicy.effort(for: packet.sampling.think)"),
                "the worker's think must come from its packet's declared sampling")
    }

    /// A pool worker's attach-handshake `ready` (no stop_reason/generated —
    /// same shape as worker 0's boot ready) must not finish the turn early.
    /// The decision itself is unit-tested directly
    /// (`AgentWireParserTests.readyIsTurnEndOnlyWhenItCarriesClosingFields`);
    /// this only asserts the live call site actually consults it.
    @Test func workerReadyGatesOnTurnEndBeforeFinishing() throws {
        let loop = try source("Sources/SwiftStar/AgentPoolTurnLoop.swift")
        #expect(loop.contains("guard AgentEvent.readyIsTurnEnd(stopReason: stopReason, generated: generated) else { break }"),
                "a bare attach-handshake ready must not finish the worker's turn")
    }

    /// The composed guarantee, at the level this target *can* execute: with no
    /// cap the policy yields no override and the envelope carries no field, so
    /// the bytes on the wire are byte-identical to pre-P23.
    @Test func withoutTheCapTheEnvelopeIsBytewisePreP23() {
        let decision = TurnThinkPolicy.decide(requested: .off, family: .lagunaS, capAdvertised: false)
        #expect(decision == .useDefault)
        let effort: ThinkEffort? = { if case .override(let e) = decision { return e } else { return nil } }()
        #expect(PoolPrompt(worker: .orchestrator, text: "go", think: effort).encode()
                == #"{"s":"go","t":"prompt","worker":0}"#)
    }
}
