import Foundation

/// Renderer-agnostic markdown preparation, ported from the DS4 Control agent
/// window (provenance: `MarkdownText.swift`/`AgentItemView.swift` in the
/// agent-mode worktree; facts cross, code does not). The view layer runs these
/// before handing text to the renderer; being pure, they are tested here in
/// Kit rather than in the view target.
public enum MarkdownPreprocess {
    /// LaTeX cleanup so the model's math reads as text rather than raw source.
    /// Strips wrappers and maps common symbols — not a TeX engine; unknown
    /// macros pass through.
    public static func deLaTeXed(_ s: String) -> String {
        var t = s
        for d in ["\\[", "\\]", "\\(", "\\)", "$$"] { t = t.replacingOccurrences(of: d, with: "") }
        t = t.replacingOccurrences(
            of: #"\\boxed\s*\{([^{}]*)\}"#, with: "**$1**", options: .regularExpression)
        t = t.replacingOccurrences(
            of: #"\\text\s*\{([^{}]*)\}"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(
            of: #"\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}"#, with: "$1/$2", options: .regularExpression)
        let symbols: [(String, String)] = [
            ("times", "×"), ("cdots", "⋯"), ("cdot", "·"), ("div", "÷"), ("pm", "±"),
            ("leq", "≤"), ("geq", "≥"), ("neq", "≠"), ("approx", "≈"), ("equiv", "≡"),
            ("infty", "∞"), ("rightarrow", "→"), ("Rightarrow", "⇒"), ("to", "→"),
            ("ldots", "…"), ("sqrt", "√"), ("pi", "π"), ("theta", "θ"), ("alpha", "α"),
            ("beta", "β"), ("sum", "∑"),
        ]
        for (name, sym) in symbols {
            t = t.replacingOccurrences(
                of: "\\\\" + name + "(?![A-Za-z])", with: sym, options: .regularExpression)
        }
        return t
    }

    /// Tags stripped from answer content: tool plumbing and reasoning tags
    /// (reasoning arrives separately via the `think` wire events and renders in
    /// the disclosure, so inline `<thinking>`/`<think>` in content is redundant).
    private static let strippedTags: Set<String> = [
        "tool_call", "tool_response", "tool_result", "thinking", "think",
    ]

    /// Drop whole `<tag>…</tag>` blocks for tags in `strippedTags` — both
    /// multi-line blocks and a single line that opens and closes inline. Tags
    /// are only recognized when the line *starts* with the tag, which is how
    /// the engine emits them; unrelated `<` text in prose is left untouched. An
    /// unterminated block (e.g. mid-stream) stays hidden until it closes.
    public static func stripTaggedBlocks(_ s: String) -> String {
        var out: [String] = []
        var lines = s.components(separatedBy: .newlines)[...]
        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("<"), let tag = extractOpeningTag(trimmed),
                strippedTags.contains(tag)
            else {
                out.append(line)
                continue
            }
            if trimmed.contains("</\(tag)>") { continue }  // inline open+close → drop this line only
            while let next = lines.first,
                extractClosingTag(next.trimmingCharacters(in: .whitespaces)) != tag
            {
                lines = lines.dropFirst()
            }
            lines = lines.dropFirst()  // consume the closing tag line (no-op at EOF)
        }
        return out.joined(separator: "\n")
    }

    private static func extractOpeningTag(_ s: String) -> String? {
        guard s.hasPrefix("<"), !s.hasPrefix("</"), s.hasSuffix(">") else { return nil }
        let name = s.dropFirst().dropLast().prefix { $0.isLetter || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    private static func extractClosingTag(_ s: String) -> String? {
        guard s.hasPrefix("</"), s.hasSuffix(">") else { return nil }
        let name = s.dropFirst(2).dropLast().prefix { $0.isLetter || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

}
