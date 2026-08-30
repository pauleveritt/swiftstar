import Foundation

/// One phase of a tool event on the NDJSON agent wire (json-events.md). The
/// raw `phase` string maps 1:1; `param_begin`/`param_value`/`param_end` use
/// the underscored wire spellings.
public enum AgentToolPhase: String, Equatable, Sendable {
    case start
    case tool
    case paramBegin = "param_begin"
    case paramValue = "param_value"
    case paramEnd = "param_end"
    case output
    case finish
}

/// The structured payload of one `tool` event line. Which fields are present
/// depends on the phase (json-events.md "tool" table): `tool` carries `name`;
/// `param_begin` carries `kind`+`name`; `param_value`/`output` carry `s`;
/// `finish` carries optional `status` + always `calls`.
public struct AgentToolEvent: Equatable, Sendable {
    public let phase: AgentToolPhase
    public let idx: Int
    public let name: String?
    public let paramKind: String?
    public let paramName: String?
    public let value: String?
    public let status: String?
    public let calls: Int?
    /// The wire's monotonic timestamp, when the engine included one. Tool
    /// cards use the start/finish pair to show a real execution duration.
    public let ts: UInt64?

    public init(phase: AgentToolPhase, idx: Int, name: String?, paramKind: String?,
                paramName: String?, value: String?, status: String?, calls: Int?,
                ts: UInt64? = nil) {
        self.phase = phase
        self.idx = idx
        self.name = name
        self.paramKind = paramKind
        self.paramName = paramName
        self.value = value
        self.status = status
        self.calls = calls
        self.ts = ts
    }
}

/// One modelled event from the NDJSON agent wire. `.ignored` carries the raw
/// line for anything not modelled — the wire can grow and this parser will not
/// refuse it. `.refused` is the binding-rule-7 loud failure: a first line that
/// is not a v1 handshake with the required capabilities.
public enum AgentEvent: Equatable, Sendable {
    case hello(version: Int, capabilities: [String])
    case status(StatusSnapshot)
    case ready(plannedBytes: Int64?, stopReason: String?, generated: Int?, ctxUsed: Int?)
    case queued
    case text(String)
    case think(String)
    case tool(AgentToolEvent)
    /// P9: a host-tools `tool_request` — the bidirectional wire's emission. The
    /// agent asks the host to run `name` with `params` (reusing the transcript's
    /// `ToolParam`); the host answers with a `tool_result` line on stdin.
    case toolRequest(idx: Int, name: String, params: [ToolParam])
    /// P9: a malformed `tool_request` the host could not parse. A **loud
    /// refusal**, not `.ignored`: the engine emits one request then blocks on
    /// its result, so an `.ignored` malformed request would let the controller
    /// skip the `tool_result` and the engine would block forever. The
    /// controller writes an `ok:false` `tool_result` (idx best-effort, 0 if
    /// unparseable) so the engine unblocks and the agent sees the refusal.
    case toolRequestRefused(idx: Int, reason: String)
    case ignored(String)
    case refused(String)
}

/// Streaming NDJSON consumer for the `ds4-agent` wire (`--json-events`),
/// shaped like `WireEventParser` (and, formerly, the Chat surface's
/// `SSEParser`, retired 2026-08-26): feed one wire line at a time; it
/// returns an event or nil. The first non-blank line must be the v1 `hello`
/// handshake whose caps include `text`, `tool`, `status` and `ts` (binding
/// rule 7). Deliberately a sibling of `WireEventParser`, not an extension of
/// it: the telemetry consumers (`MetricsReducer`, `DiagnosticsAnalyzer`) switch
/// exhaustively over `WireEvent`, and the transcript needs `text`/`think`/
/// `tool`/`queued` with different required caps (D3). The one shared type is
/// `StatusSnapshot`.
public struct AgentWireParser: Sendable {
    private var sawHandshake = false
    private static let requiredCaps: Set<String> = ["text", "tool", "status", "ts"]
    /// P23 (D3): every capability the handshake advertised, recorded so the
    /// app can gate outbound feature fields. Deliberately NOT part of
    /// `requiredCaps`: the required set governs what the app must be able to
    /// PARSE to read the wire safely; `optionalCaps` records what an older
    /// engine may not offer, and an absent feature field must not refuse
    /// startup — only the send.
    public private(set) var optionalCaps: Set<String> = []

    public init() {}

    public mutating func feed(_ line: String) -> AgentEvent? {
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
                optionalCaps = Set(caps)
                return .hello(version: v, capabilities: caps)
            }
            return .refused(trimmed)
        }

        switch t {
        case "hello":
            return .ignored(trimmed)  // a second handshake is not an error, just unmodelled
        // P23: both field lists live in `WireStatusDecoder` so this parser and
        // `WireEventParser` cannot drift again — the `power`/`error` drop was
        // exactly that drift.
        case "status":
            return .status(WireStatusDecoder.status(from: object))
        case "ready":
            let r = WireStatusDecoder.ready(from: object)
            return .ready(
                plannedBytes: r.plannedBytes,
                stopReason: r.stopReason,
                generated: r.generated,
                ctxUsed: r.ctxUsed
            )
        case "queued":
            return .queued
        case "text":
            return .text(object["s"] as? String ?? "")
        case "think":
            return .think(object["s"] as? String ?? "")
        case "tool":
            if let toolEvent = parseTool(object) { return .tool(toolEvent) }
            return .ignored(trimmed)
        case "tool_request":
            if let req = parseToolRequest(object) {
                return .toolRequest(idx: req.idx, name: req.name, params: req.params)
            }
            // A malformed tool_request is a LOUD refusal, not `.ignored`: the
            // engine emits one request then blocks on its result, so skipping
            // the result (as `.ignored` did) would hang the wire. Surface a
            // dedicated refusal carrying a best-effort idx (0 if unparseable)
            // so the controller can write an `ok:false` `tool_result` and
            // unblock the engine.
            let idx = (object["idx"] as? NSNumber)?.intValue ?? 0
            return .toolRequestRefused(idx: idx, reason: "malformed tool_request: \(trimmed)")
        default:
            return .ignored(trimmed)
        }
    }

    /// `name` is overloaded on the wire: the `tool` phase carries the tool
    /// name, `param_begin` carries the parameter name. Read it per-phase, and
    /// return nil for an unknown phase so `feed` can ignore the line.
    private func parseTool(_ object: [String: Any]) -> AgentToolEvent? {
        guard let rawPhase = object["phase"] as? String,
              let phase = AgentToolPhase(rawValue: rawPhase) else { return nil }
        let idx = (object["idx"] as? NSNumber)?.intValue ?? 0
        switch phase {
        case .tool:
            return AgentToolEvent(phase: phase, idx: idx, name: object["name"] as? String,
                                  paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil,
                                  ts: (object["ts"] as? NSNumber)?.uint64Value)
        case .paramBegin:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: object["kind"] as? String, paramName: object["name"] as? String,
                                  value: nil, status: nil, calls: nil,
                                  ts: (object["ts"] as? NSNumber)?.uint64Value)
        case .paramValue, .output:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: object["s"] as? String,
                                  status: nil, calls: nil,
                                  ts: (object["ts"] as? NSNumber)?.uint64Value)
        case .finish:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: nil,
                                  status: object["status"] as? String,
                                  calls: (object["calls"] as? NSNumber)?.intValue,
                                  ts: (object["ts"] as? NSNumber)?.uint64Value)
        case .start, .paramEnd:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil,
                                  ts: (object["ts"] as? NSNumber)?.uint64Value)
        }
    }

    /// P9: parse a `tool_request` payload (the host-tools bidirectional wire).
    /// `idx` defaults to 0; `name` is required (nil → the line is unmodelled, not
    /// a fatal refusal — the wire can grow and the parser tolerates malformed
    /// cases); `params` is optional and each entry must carry `name`+`value`
    /// strings, preserved in order.
    private func parseToolRequest(_ object: [String: Any]) -> (idx: Int, name: String, params: [ToolParam])? {
        guard let name = object["name"] as? String else { return nil }
        let idx = (object["idx"] as? NSNumber)?.intValue ?? 0
        var params: [ToolParam] = []
        if let arr = object["params"] as? [[String: Any]] {
            for p in arr {
                guard let pn = p["name"] as? String, let pv = p["value"] as? String else { return nil }
                params.append(ToolParam(name: pn, value: pv))
            }
        }
        return (idx, name, params)
    }
}
