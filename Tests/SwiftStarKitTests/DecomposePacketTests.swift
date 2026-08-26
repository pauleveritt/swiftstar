import Testing
import Foundation
@testable import SwiftStarKit

/// P12.5 (D1): the `role: .decompose` packet's shape. Built directly (not via
/// `PhasePacketBuilder.build`), `writableFiles: []`, `validationCommand: nil`,
/// dispatched on a fourth pool worker (`WorkerId(3)`) that the dispatch code
/// in `swiftstar-agenttest/main.swift` owns — not reproduced here, since it is
/// a call-site fact about an argument to `PoolOrchestrator.runPhase`, not a
/// property of the packet value itself. What *is* a property of the packet
/// value, and is covered here: the packet is built with an empty writable
/// grant and no validation command, which is exactly why it cannot pass
/// `HandoffPacketValidator.validate` and must be (and is, by inspection of
/// every call site in `main.swift`) exempt from it.
struct DecomposePacketTests {
    @Test func writableFilesIsEmpty() {
        let packet = DecomposePacket.build(specText: "# Spec\n\n## Phase 1: A\n\ndo it")
        #expect(packet.writableFiles.isEmpty)
    }

    @Test func validationCommandAndSelfTestCommandAreNil() {
        let packet = DecomposePacket.build(specText: "spec text")
        #expect(packet.validationCommand == nil)
        #expect(packet.selfTestCommand == nil)
    }

    @Test func roleIsDecompose() {
        let packet = DecomposePacket.build(specText: "spec text")
        #expect(packet.role == .decompose)
    }

    @Test func textContractIsFalse() {
        // Decompose is prose in / prose out via `outcome.text` directly, not
        // the file-block harvest `textContract: true` routes through
        // (`TextContractHarvest`/`LabeledBlockParser` are keyed on
        // `writableFiles`, which is empty here — they would harvest nothing).
        let packet = DecomposePacket.build(specText: "spec text")
        #expect(packet.textContract == false)
    }

    @Test func samplingIsTheProjectDefault() {
        let packet = DecomposePacket.build(specText: "spec text")
        #expect(packet.sampling == SamplingPolicy())
    }

    @Test func taskTextEmbedsTheFullSpecText() {
        let spec = "# Roadmap\n\n## Phase 1 — Home Page\n\nDo the thing."
        let packet = DecomposePacket.build(specText: spec)
        #expect(packet.taskText.contains(spec))
    }

    @Test func budgetsArePositiveAndDeliberatelySmallerThanImplements() {
        let packet = DecomposePacket.build(specText: "spec text")
        #expect(packet.turnBudget > 0)
        #expect(packet.toolCallBudget > 0)
        // Documented judgment call: smaller than `phasePacket`'s 100,000 /
        // (typically 30) — decompose writes nothing and needs no comparable
        // generation headroom.
        #expect(packet.turnBudget < 100_000)
    }

    /// The load-bearing structural fact (D1): this packet's own declared shape
    /// is what makes it impossible to pass `HandoffPacketValidator.validate`
    /// — proving the exemption is necessary, not merely convenient. (Whether
    /// any call site actually *does* pass it there is a property of
    /// `main.swift`'s control flow, confirmed by inspection: no call site
    /// does.)
    @Test func packetShapeWouldFailHandoffPacketValidator() {
        let packet = DecomposePacket.build(specText: "spec text")

        let result = HandoffPacketValidator.validate(packet)

        guard case .invalid(let reasons) = result else {
            Issue.record("expected .invalid, got \(result)")
            return
        }
        #expect(reasons.contains { $0.contains("writableFiles is empty") })
        #expect(reasons.contains { $0.contains("validation.command is required") })
    }

    // MARK: - the follow-up packet (D3, turn 2)

    @Test func followUpPacketAlsoHasEmptyWritableFilesAndDecomposeRole() {
        let packet = DecomposePacket.followUp()
        #expect(packet.writableFiles.isEmpty)
        #expect(packet.validationCommand == nil)
        #expect(packet.role == .decompose)
        #expect(packet.taskText == DecomposePacket.emissionFollowUpText)
    }

    @Test func followUpDirectiveAsksForEmissionNotReasoning() {
        let text = DecomposePacket.emissionFollowUpText.lowercased()
        #expect(text.contains("stop reasoning"))
        #expect(text.contains("emit"))
    }
}
