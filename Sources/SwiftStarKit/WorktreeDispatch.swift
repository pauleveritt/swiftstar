import Foundation

/// The pure `request → verdict` mapping (D3/D4): given the handoff packet, the
/// mutations observed in the turn, the P9 `TurnOutcome`, and the validation
/// result, decide candidate versus receipt. Pure — no I/O, no git; the
/// app-layer `WorktreeDispatcher` commits the worktree and fills the candidate
/// ref.
///
/// The decision order (a receipt names the first reason that applies):
/// 1. **Revision check.** A mutation path outside `packet.writableFiles` is a
///    contract violation → `.refusedTool(path)` (the first offending path). This
///    takes precedence over budget and noChanges so a contract violation is
///    always reported even when the turn also blew the budget.
/// 2. **Budget check.** `turnOutcome.toolCalls.count > packet.toolCallBudget`
///    or `turnOutcome.generatedTokens > packet.turnBudget` → `.budgetExceeded`.
///    At the limit (==) the turn is still a candidate.
/// 3. **Validation check.** A non-nil `validation` that did not pass (exit ≠ 0)
///    → `.validationFailed(exit:digest:)`. A passing result (exit == 0) or an
///    absent one (no `validationCommand` was set) falls through.
/// 4. **No changes.** No observed mutations → `.noChanges` (nothing to commit).
/// 5. **Candidate.** Otherwise → `.candidate(ref: "", turnOutcome:, baselines: [:])`. The
///    empty `ref` and empty `baselines` are sentinels; the app-layer dispatcher
///    fills the ref after committing and the baselines from the worktree.
public enum WorktreeDispatch {
    /// Relativize a finished `TurnOutcome`'s mutations to `worktree` (P10/D4):
    /// the P9 host executor records absolute paths (the confined
    /// `resolvedPath` under the worktree, resolved through symlinks by
    /// `confinedRealPath`), but `packet.writableFiles` is worktree-relative,
    /// so the revision check compares apples-to-apples only after this strip.
    /// A path without the worktree prefix (already relative, or an escape the
    /// grant already refused) is kept unchanged.
    ///
    /// FINDING 1: the host executor's `confinedRealPath` resolves symlinks
    /// (`URL.resolvingSymlinksInPath()`), so a mutation recorded under a
    /// symlinked worktree root (macOS `/tmp` -> `/private/tmp`, a user symlink,
    /// or any path whose real form differs from its standardized form) is the
    /// symlink-resolved absolute path. `standardizedFileURL` does NOT resolve
    /// symlinks, so stripping against it alone mis-relativizes the mutation
    /// (the prefix does not match) and the verdict refuses an allowed write.
    /// The fix: strip against the symlink-resolved worktree path (and fall back
    /// to the standardized path, so a mutation already in the standardized form
    /// still strips). `resolvingSymlinksInPath()` does touch the filesystem
    /// (it stat's the path components); this is the one I/O `relativize` needs
    /// to match the executor's already-resolved mutations — the verdict itself
    /// stays pure.
    public static func relativize(outcome: TurnOutcome, worktree: URL) -> TurnOutcome {
        let wtStd = worktree.standardizedFileURL.path
        let wtReal = worktree.resolvingSymlinksInPath().path
        var o = outcome
        o.mutations = outcome.mutations.map { mut in
            // Prefer the symlink-resolved prefix (the executor records resolved
            // paths); fall back to the standardized prefix (a mutation already
            // in the non-resolved form, e.g. a scripted test mutation).
            if wtReal != wtStd, mut.hasPrefix(wtReal + "/") {
                return String(mut.dropFirst(wtReal.count + 1))
            }
            if mut.hasPrefix(wtStd + "/") { return String(mut.dropFirst(wtStd.count + 1)) }
            return mut
        }
        return o
    }
    public static func verdict(
        packet: HandoffPacket,
        allowedMutations: [String],
        turnOutcome: TurnOutcome,
        validation: ValidationResult?
    ) -> DispatchOutcome {
        // 1. Revision check: a mutation outside `writableFiles` is refused.
        for path in allowedMutations where !packet.writableFiles.contains(path) {
            return .receipt(.refusedTool(path))
        }
        // 2. Budget check: tool-call count or turn tokens over the caps.
        if turnOutcome.toolCalls.count > packet.toolCallBudget
            || turnOutcome.generatedTokens > packet.turnBudget {
            return .receipt(.budgetExceeded)
        }
        // 3. Validation: ran and failed -> receipt with exit + digest.
        if let validation, !validation.passed {
            return .receipt(.validationFailed(exit: validation.exit, digest: validation.digest))
        }
        // 4. No mutations -> nothing to commit.
        if allowedMutations.isEmpty {
            return .receipt(.noChanges)
        }
        // 5. Otherwise: a candidate. The pure verdict leaves the ref empty and
        //    the baselines empty (it cannot read the worktree — no I/O); the
        //    app-layer dispatcher fills both after committing the worktree.
        return .candidate(ref: "", turnOutcome: turnOutcome, baselines: [:])
    }
}
