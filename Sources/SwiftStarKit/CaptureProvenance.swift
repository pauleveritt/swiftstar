import Foundation

/// Shared `provenance.md` rendering (item 6, P22 cleanup): `AgentController`'s
/// live-session provenance and `swiftstar-drive`'s `CaptureWriter` each render
/// a human-readable manifest with the same shape (a title, a bulleted fact
/// list, a closing note) but different facts — the app has a sampler and
/// workspace grant the drive doesn't spawn with; the drive has a full command
/// line the app doesn't need (its argv is already known/stable). Sharing the
/// assembly keeps that shared shape from drifting further while letting each
/// producer keep its own exact facts, wording, and field order.
///
/// `swiftstar-agenttest` writes `run-config.json` instead of a `provenance.md`
/// at all (a harness-specific shape covering repair-round bookkeeping
/// `provenance.md` was never meant for) and is not part of this — there is
/// nothing to share there.
public enum CaptureProvenance {
    /// One rendered fact line: `- label: value`.
    public struct Fact: Sendable {
        public let label: String
        public let value: String
        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    /// `Started (wall-clock)`, ISO8601-formatted — the one fact both current
    /// producers render identically, so neither has to restate the
    /// formatting.
    public static func startedAtFact(_ date: Date) -> Fact {
        Fact("Started (wall-clock)", ISO8601DateFormatter().string(from: date))
    }

    /// Render `# title`, a blank line, `facts` as a bulleted list (in the
    /// order given — callers control field order and which facts they have),
    /// a blank line, then `closingNote` verbatim.
    public static func render(title: String, facts: [Fact], closingNote: String) -> String {
        let factLines = facts.map { "- \($0.label): \($0.value)" }.joined(separator: "\n")
        return """
        # \(title)

        \(factLines)

        \(closingNote)
        """
    }
}
