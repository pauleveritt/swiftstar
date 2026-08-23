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

    public init(worker: WorkerId, executor: DispatchExecutor = .fullContext,
                ref: String?, reason: String?, summary: String) {
        self.worker = worker
        self.executor = executor
        self.ref = ref
        self.reason = reason
        self.summary = summary
    }

    /// The prompt text injected into the orchestrator's next turn (D4).
    public func injectionPrompt() -> String {
        if let ref {
            return "Worker \(worker.rawValue) returned candidate ref \(ref): \(summary)"
        }
        return "Worker \(worker.rawValue) refused: \(reason ?? summary)"
    }
}
