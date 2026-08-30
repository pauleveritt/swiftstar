import Foundation

/// Whether a capture tree can answer "what did my last session do".
///
/// The old predicate (`swiftstar-analyze`) was "wire.ndjson is non-empty",
/// which an agent spawned and left idle satisfies: it emits a handshake, a
/// run of `status` samples, and the engine's field-less startup `ready` —
/// ~4 KB of wire, zero work. Observed 2026-08-30: `--latest` resolved to
/// `live/20260830-163255` (a zero-turn shell opened one minute later) and
/// reported it as the user's last session, shadowing `live/20260830-155556`
/// with 3 turns and 53 tool calls.
///
/// The separator is whether the wire records *work*, on ANY worker. Two
/// shapes rule out the tempting alternatives:
///
/// - "has a completed turn" (a `ready` carrying `stop_reason`/`generated`/
///   `ctx_used`) wrongly rejects a session killed mid-turn —
///   `agenttest/20260829-125901` has 258 tool events and 34 tool requests but
///   never reached a closing ready, and is prime debugging evidence.
/// - reading the orchestrator's stream alone wrongly rejects a pooled capture
///   whose work happened on a subagent — `agenttest/20260829-122222` has all
///   1141 generated tokens on worker 1.
public enum CaptureUsability {
    /// Whether one event is something only a working session emits. `status`,
    /// `queued`, and the handshake are startup noise; a `ready` counts only
    /// when it carries turn data (the startup prefill's does not).
    public static func recordsWork(_ event: AgentEvent) -> Bool {
        switch event {
        case .text, .think, .tool, .toolRequest, .toolRequestRefused:
            return true
        case .ready(_, let stopReason, let generated, let ctxUsed):
            return stopReason != nil || generated != nil || ctxUsed != nil
        case .hello, .status, .queued, .ignored, .refused:
            return false
        }
    }

    /// Whether a whole wire records work. Feed every line, from every worker.
    public static func recordsWork(wireLines: [String]) -> Bool {
        // One parser per worker: `AgentWireParser` requires the handshake as
        // its first line, and a subagent's stream does not repeat it — feeding
        // worker-tagged lines to the orchestrator's parser is what produces
        // the "merged fiction" `PoolWireParser.worker(of:)` exists to prevent.
        // A worker's parser is primed with the shared handshake instead.
        var parsers: [WorkerId: AgentWireParser] = [:]
        var handshake: String?
        for line in wireLines {
            let worker = PoolWireParser.worker(of: line)
            if parsers[worker] == nil {
                var fresh = AgentWireParser()
                if let handshake, worker != .orchestrator { _ = fresh.feed(handshake) }
                parsers[worker] = fresh
            }
            guard let event = parsers[worker]?.feed(line) else { continue }
            if case .hello = event { handshake = line }
            if recordsWork(event) { return true }
        }
        return false
    }
}
