import Foundation
import SwiftStarKit

/// The text-contract harvest protocol, shared by both arms.
///
/// Both the repair loop and the build path have the same job once a
/// `textContract` turn comes back with no tool calls: parse the labeled blocks,
/// and — if there are none — ask once more for the emission before calling it a
/// contract failure. They used to do only the first half in common; the build
/// path bailed straight to `contractNotFollowed` while the repair loop
/// re-prompted, so the two arms were not measuring the same thing. This is the
/// one implementation both now call.
public enum TextContractHarvest {
    public struct Attempt {
        /// The turn whose text was harvested. When the follow-up ran, this is
        /// the follow-up: its text is what was parsed, and its token count is
        /// what a budget check must see.
        public var turn: TurnOutcome
        public var result: HarvestResult
        public var usedFollowUp: Bool
    }

    /// Two-turn emission protocol. Measured 2026-08-25: Mellum reasons *or*
    /// emits, never both in one turn. Allowed prose, it produces a correct
    /// diagnosis and stops at eos exactly where the file should start (captures
    /// 20260825-160310, -164557). Forbidden prose, it emits a flawless block
    /// whose body is a byte-identical copy of the file already in context
    /// (capture 20260825-163139).
    ///
    /// A turn that reasoned and stopped is not a contract failure — it is an
    /// unfinished turn. `runPhase` re-prompts the SAME pooled worker, whose
    /// session carries the prior assistant turn (`PoolOrchestrator` holds one
    /// engine session per `WorkerId` and never resets it between calls), so the
    /// follow-up is a continuation: the model conditions on its own reasoning
    /// rather than on a re-injected paraphrase of it.
    ///
    /// `onFollowUpTurn` runs before the follow-up's text is parsed, so a caller
    /// can reject a turn that exhausted the session.
    public static func run(
        firstTurn: TurnOutcome,
        packet: HandoffPacket,
        worktree: URL,
        emissionFollowUp: String?,
        capture: FileHandle?,
        runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome,
        onFollowUpTurn: (TurnOutcome) throws -> Void = { _ in }
    ) throws -> Attempt {
        let first = LabeledBlockParser.parse(firstTurn.text, writableFiles: packet.writableFiles)
        guard first.files.isEmpty,
              let emissionFollowUp,
              !firstTurn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return Attempt(turn: firstTurn, result: first, usedFollowUp: false)
        }

        let followUpPacket = HandoffPacket(
            taskText: emissionFollowUp,
            writableFiles: packet.writableFiles,
            validationCommand: packet.validationCommand,
            selfTestCommand: packet.selfTestCommand,
            baselines: packet.baselines,
            turnBudget: packet.turnBudget,
            toolCallBudget: packet.toolCallBudget,
            textContract: true,
            facts: packet.facts,
            redacts: packet.redacts,
            role: packet.role,
            sampling: packet.sampling)
        let followUp = try runPhase(followUpPacket, worktree, capture)
        try onFollowUpTurn(followUp)
        return Attempt(turn: followUp,
                       result: LabeledBlockParser.parse(followUp.text, writableFiles: packet.writableFiles),
                       usedFollowUp: true)
    }
}
