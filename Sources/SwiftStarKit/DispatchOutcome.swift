import Foundation

/// The result of running the packet's `validationCommand` parent-side (D3):
/// the command's exit status and an output digest. `passed` is `exit == 0`.
/// The pure `WorktreeDispatch.verdict` maps a non-passing result to
/// `.validationFailed`; a passing (or absent) one falls through to the
/// candidate/noChanges check. The app-layer `WorktreeDispatcher` produces this
/// by running the command; the pure verdict consumes it.
public struct ValidationResult: Equatable, Sendable {
    public let exit: Int32
    public let digest: String
    public var passed: Bool { exit == 0 }

    public init(exit: Int32, digest: String) {
        self.exit = exit
        self.digest = digest
    }
}

/// Why a dispatch was not a candidate (D3). The receipt names the reason so the
/// caller can act on it without parsing prose. The four reasons are: a mutation
/// outside `writableFiles` (`.refusedTool`, naming the offending path), the
/// turn or tool-call budget exceeded (`.budgetExceeded`), the validation
/// command ran and exited non-zero (`.validationFailed`, with exit + digest),
/// or the turn ended cleanly but mutated nothing (`.noChanges`).
public enum Receipt: Equatable, Sendable {
    /// A mutation was outside `writableFiles`; the associated value names the
    /// offending path (the first one observed outside the contract).
    case refusedTool(String)
    /// The turn exceeded `turnBudget` (generated tokens) or the tool-call
    /// count exceeded `toolCallBudget`.
    case budgetExceeded
    /// The validation command ran and exited non-zero; carries the exit status
    /// and an output digest so the caller can show what failed.
    case validationFailed(exit: Int32, digest: String)
    /// The turn ended cleanly but mutated nothing — nothing to commit.
    case noChanges
}

/// One dispatch's outcome (D3/D4): either a candidate ref carrying the P9
/// `TurnOutcome` as the candidate's evidence, or a typed `Receipt` naming why
/// not. The pure `WorktreeDispatch.verdict` leaves the candidate `ref` empty
/// (it cannot commit); the app-layer `WorktreeDispatcher` fills it after
/// committing the worktree's diff to the throwaway branch. The `TurnOutcome`
/// carries the host-authoritative facts (mutations, exit status, output digest,
/// `validationRan`) per D4 — a handoff packet's success is never inferred from
/// prose.
public enum DispatchOutcome: Equatable, Sendable {
    case candidate(ref: String, turnOutcome: TurnOutcome)
    case receipt(Receipt)
}
