import Foundation

/// One wire-carried metrics sample from a `status` event. `power` (throttle %)
/// and `error` are deliberately not extracted (Settings/supervisor concerns).
/// `ts` is monotonic microseconds since boot (`clock_gettime(CLOCK_MONOTONIC)`);
/// only deltas are meaningful (P5, fork divergence #7).
public struct StatusSnapshot: Equatable, Sendable {
    public let ctxUsed: Int
    public let ctxSize: Int
    public let prefillTPS: Double
    public let genTPS: Double
    public let ts: UInt64
    /// The wire's `status.state` string (`idle`, `prefill`, `generating`, …).
    /// Added in P7: the agent controller infers turn end from the `idle`
    /// transition (D6). Metrics and Diagnostics read only the numeric fields.
    public let state: String
}

/// One modelled event from the NDJSON telemetry wire. `.ignored` carries the
/// raw line for anything not modelled — the wire can grow and this parser will
/// not refuse it. `.refused` is the binding-rule-7 loud failure: a first line
/// that is not a known handshake.
public enum WireEvent: Equatable, Sendable {
    case hello(version: Int, capabilities: [String])
    case status(StatusSnapshot)
    case ready(plannedBytes: Int64?)
    case ignored(String)
    case refused(String)
}

/// Streaming NDJSON telemetry consumer, shaped like `SSEParser`: feed one wire
/// line at a time; it returns an event or nil. The first non-blank line must be
/// the `hello` handshake (binding rule 7); anything else is refused loudly.
public struct WireEventParser: Sendable {
    private var sawHandshake = false
    private static let requiredCaps: Set<String> = ["status", "ready", "ts"]

    public init() {}

    public mutating func feed(_ line: String) -> WireEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = object["t"] as? String
        else {
            if !sawHandshake { sawHandshake = true; return .refused(trimmed) }
            return .ignored(trimmed)
        }

        if !sawHandshake {
            sawHandshake = true
            if t == "hello",
               let v = (object["v"] as? NSNumber)?.intValue, v == 1,
               let caps = object["caps"] as? [String],
               Self.requiredCaps.isSubset(of: Set(caps)) {
                return .hello(version: v, capabilities: caps)
            }
            return .refused(trimmed)
        }

        switch t {
        case "hello":
            return .ignored(trimmed)  // a second handshake is not an error, just unmodelled
        case "status":
            return .status(StatusSnapshot(
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
                ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
                prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
                genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0,
                ts: (object["ts"] as? NSNumber)?.uint64Value ?? 0,
                state: (object["state"] as? String) ?? ""
            ))
        case "ready":
            return .ready(plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value)
        default:
            return .ignored(trimmed)
        }
    }
}
