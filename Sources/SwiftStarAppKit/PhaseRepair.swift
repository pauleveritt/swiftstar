import Foundation
import SwiftStarKit

/// P12.8 (D4): repair a phase that failed its `validationCommand`. Commits the
/// failed phase's work to a throwaway ref and runs `RepairLoop` once against the
/// phase's own import check. The `grade` closure is a trivial always-pass (D3):
/// `finalize` returns `.candidate` only after validation already passed, so the
/// import check is the real gate and `grade` cannot meaningfully fail. Throws
/// `RepairLoopError.sessionExhausted` upward for the caller to map to a stop.
public enum PhaseRepair {

    public enum Outcome: Sendable {
        case repaired(ref: String, worktree: WorktreeDispatcher.Worktree)
        case exhausted(receipt: Receipt)
    }

    public static func run(
        repo: URL,
        failedWorktree: WorktreeDispatcher.Worktree,
        packet: HandoffPacket,
        validation: ValidationResult,
        packetBuilder: (RepairContext) throws -> HandoffPacket,
        runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome,
        capture: FileHandle? = nil,
        captureDir: URL? = nil,
        emissionFollowUp: String? = nil
    ) throws -> Outcome {
        let failedRef = try WorktreeDispatcher.commitForRepair(failedWorktree, packet: packet, in: repo)
        let result = try RepairLoop.run(
            repo: repo,
            failedRef: failedRef,
            initialGrade: GradeResult(exit: validation.exit, output: validation.output),
            writableFiles: packet.writableFiles,
            packetBuilder: packetBuilder,
            runPhase: runPhase,
            grade: { _ in GradeResult(exit: 0, output: "") },
            capture: capture,
            captureDir: captureDir,
            emissionFollowUp: emissionFollowUp)
        switch result {
        case .passed(let ref, _, let wt):
            return .repaired(ref: ref, worktree: wt)
        case .exhausted(_, let receipt):
            return .exhausted(receipt: receipt)
        }
    }
}
