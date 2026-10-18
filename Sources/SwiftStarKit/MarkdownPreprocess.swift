import Foundation

/// Renderer-agnostic markdown preparation, run by the view before it hands text
/// to the renderer. Pure, so it is tested here in Kit.
public enum MarkdownPreprocess {
    /// LaTeX cleanup so the model's math reads as text rather than raw source.
    /// Strips wrappers and maps common symbols — not a TeX engine; unknown
    /// macros pass through. Code is left exactly as written: fenced blocks
    /// (```` ``` ```` or `~~~`), indented code blocks and inline code spans
    /// are not touched, so `echo $$` or `grep '\(a\)'` survive. An indented
    /// line counts as code after a blank line or more indented code; straight
    /// after paragraph text it's a lazy continuation and stays prose. An
    /// indented paragraph inside a list item is kept raw too, and an indented
    /// fence marker opens a fence, as under a list item (SU.6a, D4). Block
    /// quote and list markers are looked past, so `- ```sh` and `> ```` open
    /// fences too (SU.17, finding 7).
    public static func deLaTeXed(_ s: String) -> String {
        walk(s, prose: prose, span: { _, span in span })
    }

    /// Inline code spans whose text `resolve` maps to a file become links to
    /// it (SU.16, D7): `` `Package.swift` `` becomes
    /// `` [`Package.swift`](swiftstar-file:Package.swift) ``. Code blocks,
    /// prose and a span already inside a link stay as written. `resolve`
    /// returns the relative path to link, or nil.
    public static func fileLinks(_ s: String, resolve: (String) -> String?) -> String {
        walk(s, prose: { $0 }, span: { context, span in
            guard !context.inLink else { return span }
            let ticks = span.prefix { $0 == "`" }.count
            var text = String(span.dropFirst(ticks).dropLast(ticks))
            // CommonMark strips one space each side when both are there.
            if text.count >= 2, text.first == " ", text.last == " " { text = String(text.dropFirst().dropLast()) }
            guard let path = resolve(text) else { return span }
            return "[\(span)](\(FileLink.destination(path)))"
        })
    }

    /// Where a code span sits: right after `[` and right before `](`, it's
    /// already a link's text.
    struct SpanContext {
        let inLink: Bool
    }

    /// The block walk both passes share: `prose` rewrites text outside code
    /// spans, `span` rewrites each whole span (backticks included). Code
    /// blocks pass through untouched.
    private static func walk(
        _ s: String, prose: (String) -> String, span: (SpanContext, String) -> String
    ) -> String {
        var out: [String] = []
        var lines: [String] = []
        var fence: (char: Character, count: Int)?
        /// The previous line ended a block: blank, kept code, or the start.
        var afterBreak = true
        func flush() {
            guard !lines.isEmpty else { return }
            out.append(paragraphs(lines, prose: prose, span: span))
            lines = []
        }
        for line in s.components(separatedBy: "\n") {
            let body = blockBody(line)
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                out.append(line)
                // CommonMark: a closing fence is the same character, at least
                // as long, with nothing after it.
                if let run = fenceRun(trimmed), run.char == open.char, run.count >= open.count,
                   trimmed.dropFirst(run.count).allSatisfy(\.isWhitespace) {
                    fence = nil
                    afterBreak = true
                }
            } else if let run = fenceRun(trimmed) {
                // Checked before indented code: models indent fences under
                // list items, and their code must stay as written.
                flush()
                fence = run
                out.append(line)
                afterBreak = false
            } else if afterBreak, body.hasPrefix("    ") || body.hasPrefix("\t") {
                flush()
                out.append(line)
            } else {
                lines.append(line)
                afterBreak = trimmed.isEmpty  // `>` alone is a blank line in a quote
            }
        }
        flush()
        return out.joined(separator: "\n")
    }

    /// The line past its block quote (`>`) and list (`-`, `*`, `+`, `1.`,
    /// `1)`) markers, each with the space after it: where a fence or indented
    /// code inside them starts. A marker needs that space, so `*a*` is text.
    static func blockBody(_ line: String) -> Substring {
        var rest = Substring(line)
        while true {
            let lead = rest.prefix { $0 == " " }
            guard lead.count < 4 else { return rest }
            let after = rest.dropFirst(lead.count)
            if after.first == ">" {
                let inner = after.dropFirst()
                rest = inner.first == " " ? inner.dropFirst() : inner
                continue
            }
            let digits = after.prefix(while: \.isNumber)
            let marker = digits.isEmpty ? after.prefix(1) : after.prefix(digits.count + 1)
            let isBullet = digits.isEmpty && ["-", "*", "+"].contains(marker)
            let isNumber = !digits.isEmpty && digits.count <= 9 && [".", ")"].contains(marker.last)
            guard isBullet || isNumber, after.dropFirst(marker.count).first == " " else { return rest }
            rest = after.dropFirst(marker.count + 1)
        }
    }

    /// A fence's opening run: three or more backticks or tildes (a backtick
    /// fence's info string can't contain a backtick).
    private static func fenceRun(_ line: some StringProtocol) -> (char: Character, count: Int)? {
        guard let c = line.first, c == "`" || c == "~" else { return nil }
        let n = line.prefix { $0 == c }.count
        guard n >= 3 else { return nil }
        if c == "`", line.dropFirst(n).contains("`") { return nil }
        return (c, n)
    }

    /// Prose lines, one paragraph at a time: a code span never pairs across a
    /// blank line. Blank lines pass through.
    private static func paragraphs(
        _ lines: [String], prose: (String) -> String, span: (SpanContext, String) -> String
    ) -> String {
        var result: [String] = []
        var paragraph: [String] = []
        func end() {
            guard !paragraph.isEmpty else { return }
            result.append(inlineCode(paragraph.joined(separator: "\n"), prose: prose, span: span))
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

    /// Applies `prose` outside code spans and `span` to each span. A span
    /// opens with a run of backticks and closes at the next run of the same
    /// length; an opening run with no closer is literal text (CommonMark).
    private static func inlineCode(
        _ s: String, prose: (String) -> String, span: (SpanContext, String) -> String
    ) -> String {
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
                let after = String(chars[(close + n)...].prefix(2))
                let context = SpanContext(inLink: pending.hasSuffix("[") && after == "](")
                out += prose(pending) + span(context, String(chars[i..<(close + n)]))
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
