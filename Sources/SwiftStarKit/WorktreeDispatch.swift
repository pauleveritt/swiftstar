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
/// 5. **Candidate.** Otherwise → `.candidate(ref: "", turnOutcome:)`. The empty
///    `ref` is a sentinel; the app-layer dispatcher fills it after committing.
public enum WorktreeDispatch {
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
        // 5. Otherwise: a candidate. The pure verdict leaves the ref empty; the
        //    app-layer dispatcher fills it after committing the worktree.
        return .candidate(ref: "", turnOutcome: turnOutcome)
    }
}
