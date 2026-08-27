import Foundation

/// The reserved routing discriminator (D10): which executor shape ran the
/// worker. `.fullContext` is the only case in v1; the specialized one-command
/// worker is the future case A-routing adds without churning the contract.
public enum DispatchExecutor: String, Codable, Equatable, Sendable {
    case fullContext
}

/// The bounded result that folds back from a worker into the orchestrator's
/// next turn (D4). A candidate ref (a real commit) or a refusal reason — never
/// the worker's transcript. `Codable` so the pool ledger can persist it.
public struct DispatchReceipt: Codable, Equatable, Sendable {
    public let worker: WorkerId
    public let executor: DispatchExecutor
    public let ref: String?
    public let reason: String?
    public let summary: String
    /// A consult (read-only) worker's full answer text — the value of the turn,
    /// not a verdict. nil for implementer receipts (which carry a ref/reason).
    /// Carried on the receipt so the answer survives where the verdict does and
    /// the controller needs no separate per-worker text stash.
    public let answerText: String?

    public init(worker: WorkerId, executor: DispatchExecutor = .fullContext,
                ref: String?, reason: String?, summary: String, answerText: String? = nil) {
        self.worker = worker
        self.executor = executor
        self.ref = ref
        self.reason = reason
        self.summary = summary
        self.answerText = answerText
    }

    /// The prompt text injected into the orchestrator's next turn (D4). A
    /// refusal is named by its `reason`; a candidate by its `ref` (or, while
    /// the worktree commit is still pending, as a candidate without a ref).
    public func injectionPrompt() -> String {
        // A consult's answer IS its delivery, so it wins over the verdict: a
        // read-only worker's verdict is always a refusal, and folding
        // "Worker N refused: noChanges" back would describe the contract rather
        // than the answer. Only reached when the direct send was refused.
        if let answerText, !answerText.isEmpty {
            return "→ consulted (worker \(worker.rawValue)): \(answerText)"
        }
        if let reason {
            return "Worker \(worker.rawValue) refused: \(reason)"
        }
        if let ref {
            return "Worker \(worker.rawValue) returned candidate ref \(ref): \(summary)"
        }
        return "Worker \(worker.rawValue) returned a candidate (ref pending): \(summary)"
    }
}
