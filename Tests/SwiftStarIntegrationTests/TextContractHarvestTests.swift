import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

/// The text-contract harvest protocol, tested once for both arms.
///
/// Before this existed, the repair arm had the two-turn emission follow-up and
/// the build arm did not: a build turn that harvested nothing went straight to
/// `contractNotFollowed` with no second ask. Both arms now call the same
/// function, so the protocol cannot drift between them again.
struct TextContractHarvestTests {
    private func packet(_ task: String) -> HandoffPacket {
        HandoffPacket(taskText: task, writableFiles: ["app.py", "models.py"],
                      validationCommand: "true", baselines: [:],
                      turnBudget: 100, toolCallBudget: 5,
                      textContract: true, role: .implement,
                      sampling: SamplingPolicy())
    }

    private func turn(_ text: String, stop: TurnStopReason = .eos) -> TurnOutcome {
        var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                            generatedTokens: 10, ctxUsed: 10, stopReason: stop, toolCalls: [])
        o.text = text
        return o
    }

    @Test func harvestsTheFirstTurnWhenItAlreadyCarriesBlocks() throws {
        var followUps = 0
        let attempt = try TextContractHarvest.run(
            firstTurn: turn("#app.py\nx = 1\n"), packet: packet("build"),
            worktree: URL(fileURLWithPath: "/tmp"), emissionFollowUp: "EMIT NOW",
            capture: nil,
            runPhase: { _, _, _ in followUps += 1; return self.turn("") })
        #expect(attempt.result.files.count == 1)
        #expect(!attempt.usedFollowUp)
        #expect(followUps == 0)
    }

    @Test func rePromptsOnceWhenTheFirstTurnHarvestsNothing() throws {
        var seenTasks: [String] = []
        let attempt = try TextContractHarvest.run(
            firstTurn: turn("Here is my plan. First I will create app.py:"),
            packet: packet("build"), worktree: URL(fileURLWithPath: "/tmp"),
            emissionFollowUp: "EMIT NOW", capture: nil,
            runPhase: { pkt, _, _ in
                seenTasks.append(pkt.taskText)
                return self.turn("#app.py\nx = 1\n")
            })
        #expect(attempt.usedFollowUp)
        #expect(seenTasks == ["EMIT NOW"])
        #expect(attempt.result.files.count == 1)
        // The emitting turn replaces the reasoning turn as the round's outcome.
        #expect(attempt.turn.text.contains("#app.py"))
    }

    @Test func doesNotRePromptWhenTheFirstTurnWasEmpty() throws {
        // Nothing to continue from: a follow-up would condition on no prior
        // reasoning, which is the byte-identical-copy failure mode.
        var followUps = 0
        let attempt = try TextContractHarvest.run(
            firstTurn: turn("   \n"), packet: packet("build"),
            worktree: URL(fileURLWithPath: "/tmp"), emissionFollowUp: "EMIT NOW",
            capture: nil,
            runPhase: { _, _, _ in followUps += 1; return self.turn("#app.py\nx = 1\n") })
        #expect(followUps == 0)
        #expect(attempt.result.files.isEmpty)
    }

    @Test func theFollowUpPacketKeepsTheGrantAndTheTextContract() throws {
        var seen: HandoffPacket?
        _ = try TextContractHarvest.run(
            firstTurn: turn("prose"), packet: packet("build"),
            worktree: URL(fileURLWithPath: "/tmp"), emissionFollowUp: "EMIT NOW",
            capture: nil,
            runPhase: { pkt, _, _ in seen = pkt; return self.turn("#app.py\nx = 1\n") })
        #expect(seen?.textContract == true)
        #expect(seen?.writableFiles == ["app.py", "models.py"])
        #expect(seen?.validationCommand == "true")
    }

    @Test func aRepeatedHeadingStillHarvestsTheFirstPassWithoutAFollowUp() throws {
        var followUps = 0
        let attempt = try TextContractHarvest.run(
            firstTurn: turn("#app.py\nfirst = 1\n#app.py\nsecond = 2\n"),
            packet: packet("build"), worktree: URL(fileURLWithPath: "/tmp"),
            emissionFollowUp: "EMIT NOW", capture: nil,
            runPhase: { _, _, _ in followUps += 1; return self.turn("") })
        #expect(attempt.result.files.count == 1)
        #expect(attempt.result.files[0].content == "first = 1")
        #expect(attempt.result.degenerateRepetition)
        #expect(followUps == 0)
    }

    @Test func theFollowUpTurnIsInspectableBeforeItIsHarvested() throws {
        // The repair arm must be able to reject a follow-up that exhausted the
        // session before its text is used.
        var inspected: TurnStopReason?
        _ = try TextContractHarvest.run(
            firstTurn: turn("prose"), packet: packet("build"),
            worktree: URL(fileURLWithPath: "/tmp"), emissionFollowUp: "EMIT NOW",
            capture: nil,
            runPhase: { _, _, _ in self.turn("#app.py\nx = 1\n", stop: .limit) },
            onFollowUpTurn: { inspected = $0.stopReason })
        #expect(inspected == .limit)
    }
}
