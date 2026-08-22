public enum TranscriptRow: Equatable, Sendable {
    case reasoning(String)
    case content(String)
    case finished
    case system(String)
}

/// Reduces wire events to display rows. Kept in Kit so the chat view is thin
/// and the mapping is tested in the fast tier.
public struct ChatTranscript: Equatable, Sendable {
    public private(set) var rows: [TranscriptRow] = []

    public init() {}

    public mutating func apply(_ event: SSEEvent) {
        switch event {
        case .roleAssistant, .ignored, .done:
            break
        case .reasoning(let text):
            rows.append(.reasoning(text))
        case .content(let text):
            rows.append(.content(text))
        case .finish:
            rows.append(.finished)
        }
    }

    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message))
    }
}
