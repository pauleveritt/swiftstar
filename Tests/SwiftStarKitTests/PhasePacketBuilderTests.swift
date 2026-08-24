import Testing
import Foundation
@testable import SwiftStarKit

struct PhasePacketBuilderTests {
    private func build(sharedContext: String = "shared spec", redacts: [String] = []) -> HandoffPacket {
        PhasePacketBuilder.build(
            phaseText: "Phase 2: the board.",
            writableNote: "You may write only these files:\n- app.py",
            preamble: "preamble",
            sharedContext: sharedContext,
            writableFiles: ["app.py"],
            validationCommand: "python -c 'import app'",
            selfTestCommand: "pytest -q",
            toolCallBudget: 30,
            redacts: redacts,
            sampling: SamplingPolicy(think: .off, maxTokens: 8192, temperature: 0)
        )
    }

    /// The assembly order is the whole point: `sharedContext` is appended after
    /// the phase text, and it is where the historical contamination lived. If it
    /// were not in `taskText`, validating the dispatched packet would not see it.
    @Test func assembledTaskTextIncludesSharedContext() {
        let packet = build(sharedContext: "the list lives in models.py")
        #expect(packet.taskText.contains("the list lives in models.py"))
    }

    /// The regression Fable caught: a leak in the appended shared context must be
    /// caught by validating the *dispatched* packet.
    @Test func redactedStringLeakedViaSharedContextIsCaught() {
        let packet = build(sharedContext: "use field(default_factory=...)",
                           redacts: ["default_factory"])

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }

    @Test func cleanPhasePacketValidates() {
        let packet = build(sharedContext: "build the board", redacts: ["default_factory"])
        #expect(HandoffPacketValidator.validate(packet) == .valid)
    }

    @Test func samplingAndBudgetSurviveOntoThePacket() {
        let packet = build()
        #expect(packet.sampling.think == .off)
        #expect(packet.toolCallBudget == 30)
        #expect(packet.role == .implement)
    }
}
