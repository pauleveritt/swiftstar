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
        var fence: (char: Character, count: Int)?
        func flush() {
            guard !prose.isEmpty else { return }
            out.append(paragraphs(prose))
            prose = []
        }
        for line in s.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                out.append(line)
                // CommonMark: a closing fence is the same character, at least
                // as long, with nothing after it.
                if let run = fenceRun(trimmed), run.char == open.char, run.count >= open.count,
                   trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace) {
                    fence = nil
                }
            } else if let run = fenceRun(trimmed) {
                flush()
                fence = run
                out.append(line)
            } else {
                prose.append(line)
            }
        }
        flush()
        return out.joined(separator: "\n")
    }

    /// A fence's opening run: three or more backticks or tildes (a backtick
    /// fence's info string can't contain a backtick).
    private static func fenceRun(_ line: String) -> (char: Character, count: Int)? {
        guard let c = line.first, c == "`" || c == "~" else { return nil }
        let n = line.prefix { $0 == c }.count
        guard n >= 3 else { return nil }
        if c == "`", line.dropFirst(n).contains("`") { return nil }
        return (c, n)
    }

    /// Prose lines, one paragraph at a time: a code span never pairs across a
    /// blank line. Blank lines pass through.
    private static func paragraphs(_ lines: [String]) -> String {
        var result: [String] = []
        var paragraph: [String] = []
        func end() {
            guard !paragraph.isEmpty else { return }
            result.append(outsideInlineCode(paragraph.joined(separator: "\n")))
            paragraph = []
        }
        for line in lines {
            if line.allSatisfy(\.isWhitespace) {
                end()
                result.append(line)
            } else {
                paragraph.append(line)
            }
        }
        end()
        return result.joined(separator: "\n")
    }

    /// Applies `prose(_:)` outside code spans. A span opens with a run of
    /// backticks and closes at the next run of the same length; an opening
    /// run with no closer is literal text (CommonMark).
    private static func outsideInlineCode(_ s: String) -> String {
        let chars = Array(s)
        var out = ""
        var pending = ""
        var i = 0
        func run(at k: Int) -> Int {
            var n = 0
            while k + n < chars.count, chars[k + n] == "`" { n += 1 }
            return n
        }
        while i < chars.count {
            guard chars[i] == "`" else {
                pending.append(chars[i])
                i += 1
                continue
            }
            let n = run(at: i)
            var j = i + n
            var close: Int?
            while j < chars.count {
                if chars[j] == "`" {
                    let m = run(at: j)
                    if m == n { close = j; break }
                    j += m
                } else {
                    j += 1
                }
            }
            if let close {
                out += prose(pending) + String(chars[i..<(close + n)])
                pending = ""
                i = close + n
            } else {
                pending += String(chars[i..<(i + n)])
                i += n
            }
        }
        return out + prose(pending)
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
