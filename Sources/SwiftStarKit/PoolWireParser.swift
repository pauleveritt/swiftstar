import Foundation

/// One event from the pooled wire (D1): the event plus the worker id it was
/// emitted for. The `worker` field is optional (absent = orchestrator), so a
/// pre-pool single-session wire parses as worker 0.
public struct PoolWireEvent: Equatable, Sendable {
    public let worker: WorkerId
    public let event: AgentEvent
}

/// Streaming consumer for the pooled wire. Composes `AgentWireParser` (which
/// deliberately ignores the unknown `worker` field, keeping the single-session
/// consumers untouched) and reads `worker` out of the raw line before
/// delegating. The handshake is worker 0.
public struct PoolWireParser: Sendable {
    private var inner = AgentWireParser()
    public init() {}

    public mutating func feed(_ line: String) -> PoolWireEvent? {
        let worker = Self.extractWorker(line)
        guard let event = inner.feed(line) else { return nil }
        return PoolWireEvent(worker: worker, event: event)
    }

    private static func extractWorker(_ line: String) -> WorkerId {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let worker = object["worker"] as? NSNumber else {
            return .orchestrator
        }
        return WorkerId(rawValue: worker.intValue)
    }
}
