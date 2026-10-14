import Foundation

/// ↑/↓ recall of this conversation's earlier prompts (SU.8).
///
/// The arrows recall only while the field is empty or still shows the
/// prompt last recalled; once it's edited they move the cursor, so a draft
/// is never replaced. A nil result means "let the field have the key".
public struct PromptHistory: Equatable, Sendable {
    /// Position in the entries, nil when not recalling.
    private var index: Int?
    /// The text last put in the field, to tell an unedited recall.
    private var recalled: String?

    public init() {}

    /// The typed prompts, oldest first: never the app's own Analyze prompt
    /// (its shown label, or the full text a relaunched fork rebuilds), and
    /// repeats in a row collapsed to one.
    public static func entries(from rows: [TranscriptRow]) -> [String] {
        var result: [String] = []
        for row in rows {
            guard case .user(let text) = row,
                  text != EngineAnalysis.promptShown,
                  !text.hasSuffix(EngineAnalysis.instruction),
                  text != result.last else { continue }
            result.append(text)
        }
        return result
    }

    /// One older; at the oldest it stays there.
    public mutating func up(current: String, entries: [String]) -> String? {
        guard !entries.isEmpty, canRecall(current) else { return nil }
        // Entries can shrink under a position (a /rewind), so clamp it.
        let i = max(min(index ?? entries.count, entries.count) - 1, 0)
        return recall(i, in: entries)
    }

    /// One newer; past the newest the field empties and recall ends.
    public mutating func down(current: String, entries: [String]) -> String? {
        guard !entries.isEmpty, canRecall(current), let index else { return nil }
        guard index + 1 < entries.count else {
            reset()
            return ""
        }
        return recall(index + 1, in: entries)
    }

    /// An unedited recall continues; an empty field starts afresh from the
    /// newest; anything else is a draft, and keeps its arrows.
    private mutating func canRecall(_ current: String) -> Bool {
        if index != nil, current == recalled { return true }
        guard current.isEmpty else { return false }
        reset()
        return true
    }

    private mutating func recall(_ i: Int, in entries: [String]) -> String {
        index = i
        recalled = entries[i]
        return entries[i]
    }

    private mutating func reset() {
        index = nil
        recalled = nil
    }
}
