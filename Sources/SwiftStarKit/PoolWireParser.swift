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
    /// P23 (D3): the inner parser's advertised caps, forwarded so the
    /// controller can gate outbound feature fields after the handshake.
    public var optionalCaps: Set<String> { inner.optionalCaps }
    public init() {}

    public mutating func feed(_ line: String) -> PoolWireEvent? {
        let worker = Self.worker(of: line)
        guard let event = inner.feed(line) else { return nil }
        return PoolWireEvent(worker: worker, event: event)
    }

    /// The worker a raw wire line belongs to (`.orchestrator` when the field is
    /// absent — a pre-pool single-session wire). Public so consumers that parse
    /// with the single-session `WireEventParser` (Diagnostics, `swiftstar-analyze`)
    /// can drop worker-tagged lines first: folding a subagent's counters into
    /// the orchestrator's session produces a merged fiction, not a session.
    public static func worker(of line: String) -> WorkerId {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let worker = object["worker"] as? NSNumber else {
            return .orchestrator
        }
        return WorkerId(rawValue: worker.intValue)
    }
}
