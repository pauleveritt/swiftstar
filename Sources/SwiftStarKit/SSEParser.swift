import Foundation

/// Finish reasons observed on the wire. Forward-compatible: unknown reasons
/// are preserved under `.other`, never refused.
public enum SSEFinishReason: Equatable, Sendable {
    case stop
    case other(String)
}

/// One modelled event from the SSE wire. `.ignored` carries the raw payload
/// for any line the parser does not model — the wire can grow and this parser
/// will not refuse it.
public enum SSEEvent: Equatable, Sendable {
    case roleAssistant
    case reasoning(String)
    case content(String)
    case finish(SSEFinishReason)
    case done
    case ignored(String)
}

/// Streaming SSE consumer. Feed it one wire line at a time; it returns an
/// event or nil. No handshake is required or refused (binding rule 7: the
/// wire announces itself from P5, not before).
public struct SSEParser: Sendable {
    public init() {}

    public mutating func feed(_ line: String) -> SSEEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }  // blank/comment/event: lines
        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard
            let data = payload.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let choice = choices.first
        else { return .ignored(payload) }
        if let reason = choice["finish_reason"] as? String, !reason.isEmpty {
            return .finish(reason == "stop" ? .stop : .other(reason))
        }
        guard let delta = choice["delta"] as? [String: Any] else { return .ignored(payload) }
        if let role = delta["role"] as? String, role == "assistant" { return .roleAssistant }
        if let reasoning = delta["reasoning_content"] as? String { return .reasoning(reasoning) }
        if let content = delta["content"] as? String { return .content(content) }
        return .ignored(payload)
    }
}
