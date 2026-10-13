import Foundation

/// Renderer-agnostic markdown preparation, ported from the DS4 Control agent
/// window (provenance: `MarkdownText.swift`/`AgentItemView.swift` in the
/// agent-mode worktree; facts cross, code does not). The view layer runs these
/// before handing text to the renderer; being pure, they are tested here in
/// Kit rather than in the view target.
public enum MarkdownPreprocess {
    /// LaTeX cleanup so the model's math reads as text rather than raw source.
    /// Strips wrappers and maps common symbols — not a TeX engine; unknown
    /// macros pass through. Code is left exactly as written: fenced blocks
    /// (```` ``` ```` or `~~~`) and inline code spans are not touched, so
    /// `echo $$` or `grep '\(a\)'` survive.
    public static func deLaTeXed(_ s: String) -> String {
        var out: [String] = []
        var prose: [String] = []
        var fence: String?
        func flush() {
            guard !prose.isEmpty else { return }
            out.append(outsideInlineCode(prose.joined(separator: "\n")))
            prose = []
        }
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                out.append(line)
                if trimmed.hasPrefix(open) { fence = nil }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fence = String(trimmed.prefix(3))
                out.append(line)
            } else {
                prose.append(line)
            }
        }
        flush()
        return out.joined(separator: "\n")
    }

    /// Applies `prose(_:)` to the text between inline code spans. An unclosed
    /// backtick is literal text, as in CommonMark.
    private static func outsideInlineCode(_ s: String) -> String {
        let parts = s.components(separatedBy: "`")
        let closedSpans = parts.count % 2 == 1 ? parts.count : parts.count - 1
        return parts.enumerated().map { i, part in
            i % 2 == 1 && i < closedSpans ? part : prose(part)
        }.joined(separator: "`")
    }

    private static func prose(_ s: String) -> String {
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
}
