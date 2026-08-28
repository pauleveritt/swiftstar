import Foundation

/// The one place `status` and `ready` fields are read off the wire.
///
/// `AgentWireParser` and `WireEventParser` stay separate types with separate
/// event enums — their consumers switch exhaustively over different cases, and
/// that split is deliberate. What was NOT deliberate was two byte-identical
/// copies of the field extraction: `status.power` and `status.error` were added
/// to one and not the other, so the parser feeding the running app returned
/// zero-value defaults for both across several phases, and a live consumer
/// reading `.power`/`.error` off `AgentController.lastStatus` never saw the
/// engine's own values. A field added here now reaches both consumers or
/// neither (P23).
public enum WireStatusDecoder {
    public static func status(from object: [String: Any]) -> StatusSnapshot {
        StatusSnapshot(
            ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
            ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
            prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
            genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0,
            ts: (object["ts"] as? NSNumber)?.uint64Value ?? 0,
            generated: (object["generated"] as? NSNumber)?.intValue ?? 0,
            state: (object["state"] as? String) ?? "",
            power: (object["power"] as? NSNumber)?.doubleValue ?? 0,
            error: (object["error"] as? String) ?? ""
        )
    }

    /// The `ready` payload. Every field is optional because `ready` is emitted
    /// twice with different shapes: once at startup carrying the memory plan,
    /// and once per turn end carrying the outcome.
    public struct Ready: Equatable, Sendable {
        public let plannedBytes: Int64?
        public let stopReason: String?
        public let generated: Int?
        public let ctxUsed: Int?
    }

    public static func ready(from object: [String: Any]) -> Ready {
        Ready(
            plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value,
            stopReason: object["stop_reason"] as? String,
            generated: (object["generated"] as? NSNumber)?.intValue,
            ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue
        )
    }
}
