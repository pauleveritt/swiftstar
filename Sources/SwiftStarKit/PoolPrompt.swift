import Foundation

/// The inbound prompt line (D1): how the app addresses a worker's turn on the
/// pooled wire. A bare line (no `worker`) is the orchestrator (worker 0). The
/// encoder is the single authority; the C patch and the fake both consume it.
public struct PoolPrompt: Equatable, Sendable {
    public let worker: WorkerId
    public let text: String
    public init(worker: WorkerId, text: String) { self.worker = worker; self.text = text }

    /// `{"t":"prompt","worker":N,"s":"..."}` — keys sorted for determinism.
    public func encode() -> String {
        let obj: [String: Any] = ["t": "prompt", "worker": worker.rawValue, "s": text]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
