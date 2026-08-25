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

/// One acceptance grading: the pytest exit status and its combined output.
/// `passed` is `exit == 0`. Repair branches on this; the raw `output` becomes
/// the repair evidence (D6).
public struct GradeResult: Equatable, Sendable, Codable {
    public let exit: Int32
    public let output: String
    public var passed: Bool { exit == 0 }

    public init(exit: Int32, output: String) {
        self.exit = exit
        self.output = output
    }
}

/// Why a dispatch was not a candidate (D3). The receipt names the reason so the
/// caller can act on it without parsing prose. The five reasons are: a mutation
/// outside `writableFiles` (`.refusedTool`, naming the offending path), the
/// turn or tool-call budget exceeded (`.budgetExceeded`), the validation
/// command ran and exited non-zero (`.validationFailed`, with exit + digest),
/// the turn ended cleanly but mutated nothing (`.noChanges`), or repair
/// produced candidates for every allowed round without reaching a passing
/// grade (`.repairExhausted`).
public enum Receipt: Equatable, Sendable, Codable {
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
    /// Repair produced candidates for every allowed round without reaching a
    /// passing grade (D4).
    case repairExhausted
    /// The text-contract turn produced no usable labeled blocks (initiation
    /// failure). Distinct from `.noChanges` so the existing `noChanges+eos ->
    /// continue` branch cannot swallow it.
    case contractNotFollowed
}

/// One dispatch's outcome (D3/D4): either a candidate ref carrying the P9
/// `TurnOutcome` as the candidate's evidence **and the per-file baselines read
/// from the worktree at dispatch time** (D1 — the parent diffs the candidate
/// against these to detect drift on a file it was allowed to touch), or a typed
/// `Receipt` naming why not. The pure `WorktreeDispatch.verdict` leaves the
/// candidate `ref` empty **and the baselines empty** (it cannot read the
/// worktree — no I/O); the app-layer `WorktreeDispatcher` fills both after
/// committing the worktree's diff to the throwaway branch. The `TurnOutcome`
/// carries the host-authoritative facts (mutations, exit status, output digest,
/// `validationRan`) per D4 — a handoff packet's success is never inferred from
/// prose.
public enum DispatchOutcome: Equatable, Sendable {
    case candidate(ref: String, turnOutcome: TurnOutcome, baselines: [String: FileBaseline])
    case receipt(Receipt)
}
