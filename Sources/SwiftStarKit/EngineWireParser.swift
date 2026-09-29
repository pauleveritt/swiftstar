import Foundation

/// Decodes one line of `ds4-dogfood tui --ndjson` stdout into an `EngineEvent`.
public struct EngineWireParser: Sendable {
    private var sawReady = false

    public init() {}

    public mutating func parse(_ line: String) -> EngineEvent {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return undecodable(line, "not a JSON object") }
        guard let kind = object["kind"] as? String else {
            return undecodable(line, "line has no kind")
        }
        if !sawReady {
            guard kind == "ready" else {
                return .protocolError("expected ready first, got \(kind)")
            }
            let version = Self.int(object["protocol"])
            guard version == 1 else {
                return .protocolError("unsupported engine protocol \(version.map(String.init) ?? "none"); expected protocol 1")
            }
            sawReady = true
            return .ready
        }
        switch kind {
        case "status":
            return .loading(Self.text(object, kind: kind))
        case "input":
            return .awaitingInput
        case "error":
            return .error(Self.text(object, kind: kind))
        case "close":
            return .closed(capturePath: nil)
        case "queued":
            return .queued(count: Self.int(object["count"]) ?? 1)
        case "event":
            guard let event = object["event"] as? [String: Any],
                  let eventKind = event["kind"] as? String
            else { return .ignored }
            return Self.decode(event, kind: eventKind)
        default:
            // ready (again), diagnostic, stopping, quitting, unknown.
            return .ignored
        }
    }

    /// Only the handshake is fatal: before `ready` an undecodable line is a
    /// protocol error; afterwards it is shown as a notice and the session goes on.
    private func undecodable(_ line: String, _ why: String) -> EngineEvent {
        if !sawReady { return .protocolError("\(why): \(line.prefix(80))") }
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .ignored }
        return .notice("Engine output: \(line.prefix(200))")
    }

    private static func decode(_ e: [String: Any], kind: String) -> EngineEvent {
        switch kind {
        case "session":
            return .session(EngineSessionInfo(
                id: e["session_id"] as? String ?? "",
                modelID: e["model_id"] as? String,
                contextSize: int(e["context_size"])))
        case "prompt":
            return .prompt(e["text"] as? String ?? "")
        case "narration":
            return .narration(e["text"] as? String ?? "")
        case "thinking":
            return .thinking(e["text"] as? String ?? "")
        case "tool_start":
            return .toolStart(tool(e))
        case "tool_end":
            return .toolEnd(tool(e), ok: (e["status"] as? String) == "ok", durationMs: double(e["duration_ms"]))
        case "tool_result":
            return .toolResult(EngineToolResult(
                tool: tool(e),
                resultKind: e["result_kind"] as? String ?? "",
                preview: e["preview"] as? String ?? "",
                truncated: e["truncated"] as? Bool ?? false))
        case "answer":
            return .answer(EngineAnswer(
                text: e["text"] as? String ?? "",
                contextUsed: int(e["context_used"]),
                contextSize: int(e["context_size"]),
                durationMs: double(e["duration_ms"]),
                reason: e["reason"] as? String))
        case "checkpoint":
            guard let snap = e["snapshot"] as? [String: Any],
                  let evalCount = int(snap["eval_count"])
            else { return .ignored }
            return .pause(PauseMetrics(
                prefillTokens: int(snap["prefill_tokens"]),
                prefillMs: double(snap["sync_ms"]),
                evalCount: evalCount,
                evalMs: double(snap["eval_ms"]),
                outputTokens: int(snap["output_tokens"])))
        case "memory":
            let plan = e["engine_plan"] as? [String: Any]
            return .memory(EngineMemory(
                allocatedBytes: int64(e["gpu_allocated_bytes"]),
                budgetBytes: int64(e["gpu_budget_bytes"]),
                planGiB: double(plan?["total_gib"])))
        case "interrupted":
            return .interrupted(contextUsed: int(e["context_used"]), contextSize: int(e["context_size"]))
        case "terminal":
            return .turnEnded(outcome: e["outcome"] as? String ?? "unknown")
        case "steering_applied", "steering_unconfirmed":
            return .steering(applied: kind == "steering_applied", text: e["text"] as? String)
        case "mentions":
            let attached = e["attached"] as? [String] ?? []
            let missing = e["missing"] as? [String] ?? []
            if !missing.isEmpty {
                let extra = attached.isEmpty ? "" : " (attached: \(attached.joined(separator: ", ")))"
                return .refused("Not found: \(missing.joined(separator: ", "))\(extra)")
            }
            return attached.isEmpty ? .ignored : .notice("Attached: \(attached.joined(separator: ", "))")
        case "compacting":
            return .notice("Compacting…")
        case "compacted":
            let tokens = int(e["tokens"]).map { " (\($0) tokens)" } ?? ""
            return .notice("Conversation compacted" + tokens)
        case "compact_failed":
            return .refused("Not compacted: " + text(e, kind: kind))
        case "telemetry_error":
            return .notice("Telemetry error: " + (e["error"] as? String ?? "unknown"))
        case "clear":
            return .notice("Conversation cleared")
        case "native_start":
            return .generating(true)
        case "native_end":
            return .generating(false)
        case "closed":
            return .closed(capturePath: e["capture_path"] as? String)
        case "exported":
            let path = e["path"] as? String
            return .notice(path.map { "Exported to \($0)" } ?? "Exported")
        case "status_report":
            return .notice(statusLine(e))
        case "help", "models":
            return .notice(text(e, kind: kind))
        case _ where kind.hasSuffix("_refused"):
            return .refused(text(e, kind: kind))
        default:
            return .ignored
        }
    }

    /// One readable line from the `status_report` payload.
    private static func statusLine(_ e: [String: Any]) -> String {
        var parts: [String] = []
        if let id = e["model_id"] as? String { parts.append(id) }
        if let used = int(e["context_used"]) {
            if let size = int(e["context_size"]) {
                parts.append("context \(used) / \(size) tokens")
            } else {
                parts.append("context \(used) tokens")
            }
        }
        if let a = int64(e["gpu_allocated_bytes"]) {
            var s = "GPU \(gib(a))"
            if let b = int64(e["gpu_budget_bytes"]) { s += " / \(gib(b))" }
            parts.append(s)
        }
        if let n = int(e["prompts"]) { parts.append("\(n) prompts") }
        return parts.isEmpty ? "status" : "Status: " + parts.joined(separator: " · ")
    }

    private static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f GiB", Double(bytes) / 1_073_741_824)
    }

    private static func tool(_ e: [String: Any]) -> EngineTool {
        EngineTool(op: e["op"] as? String ?? "", path: e["path"] as? String)
    }

    /// The payload's human text: `text`, else `reason`, else `message`, else
    /// the joined `lines` (`help`, `models`), else the kind name; never empty.
    private static func text(_ p: [String: Any], kind: String) -> String {
        for key in ["text", "reason", "message"] {
            if let s = p[key] as? String, !s.isEmpty { return s }
        }
        if let lines = p["lines"] as? [String], !lines.isEmpty {
            return lines.joined(separator: "\n")
        }
        return kind
    }

    private static func number(_ v: Any?) -> NSNumber? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n
    }
    private static func int(_ v: Any?) -> Int? { number(v)?.intValue }
    private static func int64(_ v: Any?) -> Int64? { number(v)?.int64Value }
    private static func double(_ v: Any?) -> Double? { number(v)?.doubleValue }
}
