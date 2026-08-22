public enum TranscriptRow: Equatable, Sendable {
    case reasoning(String)
    case content(String)
    case finished
    case system(String)
}

/// Reduces wire events to display rows. Kept in Kit so the chat view is thin
/// and the mapping is tested in the fast tier.
///
/// Consecutive `.content` deltas coalesce into a single row so a streamed
/// answer renders as one flowing paragraph rather than one fragment per
/// SSE chunk. `.finish` discards the reason deliberately — the transcript
/// only needs "the turn ended"; P6's analyzer will read the raw capture.
/// `appendSystem` is the non-wire sibling: engine status lines and user
/// messages are not SSE events, so they enter through a separate mutator.
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
            if case .content(let existing)? = rows.last {
                rows[rows.count - 1] = .content(existing + text)
            } else {
                rows.append(.content(text))
            }
        case .finish:
            rows.append(.finished)
        }
    }

    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message))
    }
}
