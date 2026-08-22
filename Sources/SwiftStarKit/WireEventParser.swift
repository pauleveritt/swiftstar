import Foundation

/// One wire-carried metrics sample from a `status` event. `power` (throttle %)
/// and `error` are deliberately not extracted (Settings/supervisor concerns).
public struct StatusSnapshot: Equatable, Sendable {
    public let ctxUsed: Int
    public let ctxSize: Int
    public let prefillTPS: Double
    public let genTPS: Double
}

/// One modelled event from the NDJSON telemetry wire. `.ignored` carries the
/// raw line for anything not modelled — the wire can grow and this parser will
/// not refuse it (binding rule 7: no handshake before P5).
public enum WireEvent: Equatable, Sendable {
    case status(StatusSnapshot)
    case ready(plannedBytes: Int64?)
    case ignored(String)
}

/// Streaming NDJSON telemetry consumer, shaped like `SSEParser`: feed one wire
/// line at a time; it returns an event or nil.
public struct WireEventParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> WireEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = object["t"] as? String
        else { return .ignored(trimmed) }

        switch t {
        case "status":
            return .status(StatusSnapshot(
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
                ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
                prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
                genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0
            ))
        case "ready":
            return .ready(plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value)
        default:
            return .ignored(trimmed)
        }
    }
}
