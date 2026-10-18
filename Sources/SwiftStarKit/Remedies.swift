import Foundation

/// One remedy an Analyze offers (AN.3): a line for the project's
/// instructions file, proposed by the analysis model or by the engine's
/// report (`fromEngine` holds its reason).
public struct Remedy: Equatable, Sendable, Identifiable {
    public let line: String
    public let fromEngine: String?
    /// The instructions file already has this line, so there's nothing to add.
    public let alreadyThere: Bool

    public var id: String { line }

    /// The line as a checkbox's label: without its list marker, which the
    /// file keeps.
    public var label: String { Remedies.normalized(line) }

    public init(line: String, fromEngine: String?, alreadyThere: Bool) {
        self.line = line
        self.fromEngine = fromEngine
        self.alreadyThere = alreadyThere
    }
}

/// AN.3's rules, pure: where the model's remedies are, how they merge with
/// the engine's, and what the instructions file becomes.
public enum Remedies {
    /// The fence tag the analysis instruction asks for.
    public static let tag = "agents-md"
    /// The heading remedies go under, added once.
    public static let heading = "## From Analyze"

    /// The lines of the last `agents-md` block in the fork's rows, from
    /// `firstRow` on: in a narration, or an answer and its reply. A later
    /// block, from a follow-up question, replaces an earlier one (D1).
    public static func parse(rows: [TranscriptRow], from firstRow: Int) -> [String] {
        guard firstRow < rows.count else { return [] }
        for row in rows[max(firstRow, 0)...].reversed() {
            let texts: [String] = switch row {
            case .narration(let t): [t]
            case .answer(let a, let reply): [reply, a.text].compactMap { $0 }
            default: []
            }
            for text in texts {
                if let lines = lastBlock(in: text) { return lines }
            }
        }
        return []
    }

    /// The last fenced block tagged `agents-md` in `text`, its non-blank lines.
    static func lastBlock(in text: String) -> [String]? {
        var found: [String]?
        var current: [String]?
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if current != nil {
                if line.hasPrefix("```") {
                    found = current
                    current = nil
                } else if !line.isEmpty {
                    current?.append(line)
                }
            } else if line.hasPrefix("```"), line.dropFirst(3).trimmingCharacters(in: .whitespaces) == tag {
                current = []
            }
        }
        return found
    }

    /// The model's lines, then the engine's not already among them, each
    /// marked when `existing` (the instructions file's text) has it (D2, D3).
    /// An engine `diff` is one added line: its leading `+` is dropped.
    public static func merged(
        model: [String], engine: [(line: String, why: String)], existing: String?
    ) -> [Remedy] {
        let have = Set((existing ?? "").components(separatedBy: "\n").map(normalized))
        var seen: [String: Int] = [:]
        var out: [Remedy] = []
        func add(_ line: String, why: String?) {
            let key = normalized(line)
            guard !key.isEmpty else { return }
            if let i = seen[key] {
                // A model line the engine also proposes keeps the engine's reason.
                if let why, out[i].fromEngine == nil {
                    out[i] = Remedy(line: out[i].line, fromEngine: why, alreadyThere: out[i].alreadyThere)
                }
                return
            }
            seen[key] = out.count
            out.append(Remedy(line: line, fromEngine: why, alreadyThere: have.contains(key)))
        }
        model.forEach { add($0, why: nil) }
        engine.forEach { add($0.line.hasPrefix("+") ? String($0.line.dropFirst()) : $0.line, why: $0.why) }
        return out
    }

    /// A line compared without surrounding space or a list marker.
    static func normalized(_ line: String) -> String {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") || t.hasPrefix("* ") { t.removeFirst(2) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// The instructions file: `AGENTS.md`, else `CLAUDE.md` when only it
    /// exists, else a new `AGENTS.md`, as the engine reads them (D4).
    public static func file(agentsExists: Bool, claudeExists: Bool) -> String {
        !agentsExists && claudeExists ? "CLAUDE.md" : "AGENTS.md"
    }

    /// `existing` with `lines` added under `heading`, which is added once;
    /// a line already in the file is skipped.
    public static func applied(to existing: String?, lines: [String]) -> String {
        var text = existing ?? ""
        let have = Set(text.components(separatedBy: "\n").map(normalized))
        let new = lines.filter { !have.contains(normalized($0)) }
        if !text.contains(heading) {
            if !text.isEmpty { text = text.trimmingTrailingNewlines() + "\n\n" }
            text += heading + "\n\n"
        } else if !text.hasSuffix("\n") {
            text += "\n"
        }
        return text + new.map { $0 + "\n" }.joined()
    }

    /// The banner's Done, saying what it will add (D3).
    public static func doneTitle(count: Int, file: String) -> String {
        count == 0 ? "Done" : "Done · add \(count) line\(count == 1 ? "" : "s") to \(file)"
    }

    /// The row after Done (D4).
    public static func appliedNotice(count: Int, file: String) -> String {
        "Added \(count) line\(count == 1 ? "" : "s") to \(file). The engine reads the committed copy, so commit it to take effect."
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var s = self
        while s.hasSuffix("\n") { s.removeLast() }
        return s
    }
}
