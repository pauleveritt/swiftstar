import Foundation
import SwiftStarKit

/// A multi-phase effort that ends in ONE candidate ref (P11 addendum D3).
///
/// Each phase runs in a disposable worktree branched from the *prior phase's
/// commit* (not `HEAD`), so phase N's checkout already contains phases 1..N-1's
/// committed code — the code folds forward through the checkout, while context
/// folds forward through the packet (D4). `commitBack` returns the final
/// candidate ref and discards the intermediate worktrees, keeping the last one
/// as `finalWorktree` for grading. On a phase receipt the transaction stops: no
/// partial chain, `candidateRef` stays nil.
public final class WorktreeTransaction {
    private let repo: URL
    private var worktrees: [WorktreeDispatcher.Worktree] = []
    /// The current head ref (a commit SHA after the first candidate, else `"HEAD"`).
    public private(set) var head = "HEAD"
    public private(set) var candidateRef: String?
    /// The worktree of the last *candidate* phase — retained for grading.
    public private(set) var finalWorktree: WorktreeDispatcher.Worktree?

    public init(repo: URL) {
        self.repo = repo
    }

    public func preparePhase(packet: HandoffPacket) throws -> WorktreeDispatcher.Worktree {
        let wt = try WorktreeDispatcher.prepare(packet: packet, in: repo, baseRef: head)
        worktrees.append(wt)
        return wt
    }

    public func finalizePhase(_ worktree: WorktreeDispatcher.Worktree, packet: HandoffPacket,
                              turnOutcome: TurnOutcome,
                              validation: ValidationResult?) throws -> DispatchOutcome {
        let outcome = try WorktreeDispatcher.finalize(
            worktree, packet: packet, turnOutcome: turnOutcome, validation: validation, in: repo)
        switch outcome {
        case .candidate(let ref, _, _):
            head = try WorktreeDispatcher.resolve(ref: ref, in: repo)
            candidateRef = ref
            finalWorktree = worktree
        case .receipt:
            break  // no head advance; the transaction stops
        }
        return outcome
    }

    /// Return the final candidate ref, discarding every intermediate worktree but
    /// KEEPING `finalWorktree` for grading (the caller grades there, then calls
    /// `discardFinal`). Returns nil when no phase produced a candidate.
    public func commitBack() -> String? {
        for wt in worktrees where wt.url != finalWorktree?.url {
            WorktreeDispatcher.discard(wt, in: repo)
        }
        worktrees = finalWorktree.map { [$0] } ?? []
        return candidateRef
    }

    public func discardFinal() {
        if let f = finalWorktree { WorktreeDispatcher.discard(f, in: repo) }
        worktrees.removeAll()
        finalWorktree = nil
    }

    public func abort() {
        discardFinal()
        head = "HEAD"
        candidateRef = nil
    }
}
