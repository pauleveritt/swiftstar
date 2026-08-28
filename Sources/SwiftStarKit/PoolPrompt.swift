import Foundation

/// The inbound prompt line (D1): how the app addresses a worker's turn on the
/// pooled wire. A bare line (no `worker`) is the orchestrator (worker 0). The
/// encoder is the single authority; the C patch and the fake both consume it.
public struct PoolPrompt: Equatable, Sendable {
    public let worker: WorkerId
    public let text: String
    /// P23 (D2): the per-turn think override, absent = engine default. Sent
    /// only when the engine advertised `think_override` (D3 — never send an
    /// unadvertised field); the absent byte shape is what keeps old engines
    /// and every existing fixture valid.
    public let think: ThinkEffort?
    /// P23 (D8): the worker's context size, absent = the engine default (the
    /// parent's). The app clamps it through the same `MemoryBudget` arithmetic
    /// the parent uses before it ever reaches the wire.
    public let contextSize: Int?

    public init(worker: WorkerId, text: String,
                think: ThinkEffort? = nil, contextSize: Int? = nil) {
        self.worker = worker
        self.text = text
        self.think = think
        self.contextSize = contextSize
    }

    /// `{"t":"prompt","worker":N,"s":"...","think":"none","ctx":8192}` — keys
    /// sorted for determinism; both P23 fields emitted only when non-nil, so
    /// the absent-field encoding is byte-identical to pre-P23.
    public func encode() -> String {
        var obj: [String: Any] = ["t": "prompt", "worker": worker.rawValue, "s": text]
        if let think { obj["think"] = think.rawValue }
        if let contextSize { obj["ctx"] = contextSize }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
