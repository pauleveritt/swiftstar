import Foundation

/// Recovers files a model wrote *inside its reasoning* but never emitted as tool
/// calls.
///
/// Laguna Q2_K on the hard spec produces a complete, correct file set inside its
/// think stream and then never acts — measured 3/3, with zero tool calls and zero
/// text, every run capped at `-n` mid-deliberation. The work exists; only the
/// transition from thinking to acting fails. Harvesting is the host recovering
/// work the model already did, which is strictly better than discarding a turn.
///
/// Two rules keep this honest:
/// - **Never widen the grant.** A block is kept only when the nearest preceding
///   filename is in `writableFiles`. Harvest cannot create files the packet did
///   not authorize.
/// - **Never keep a truncated block.** An unterminated trailing fence is the
///   token cap cutting mid-draft; writing it would overwrite a good earlier draft
///   with a broken one.
public enum ThinkHarvest {
    /// How far back to look for the filename that labels a block. Generous
    /// enough for a sentence of preamble, tight enough that an unrelated mention
    /// several paragraphs earlier does not capture the block.
    private static let labelWindow = 400

    public static func harvest(think: String, writableFiles: [String]) -> [String: String] {
        var found: [String: String] = [:]
        let ns = think as NSString

        // Only fully-closed fences: the regex requires a terminating ```, so a
        // trailing unterminated block is never matched.
        guard let re = try? NSRegularExpression(pattern: "```[a-zA-Z]*\\n(.*?)```",
                                                options: [.dotMatchesLineSeparators]) else {
            return [:]
        }

        for m in re.matches(in: think, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: m.range(at: 1))
            let windowStart = max(0, m.range.location - labelWindow)
            let before = ns.substring(with: NSRange(location: windowStart,
                                                    length: m.range.location - windowStart))
            guard let path = nearestWritableName(in: before, writableFiles: writableFiles) else {
                continue
            }
            // Later drafts refine earlier ones, so last writer wins.
            found[path] = body
        }
        return found
    }

    /// The last mention of a granted path in `text`. Matched longest-first so
    /// `templates/home.html` wins over a bare `home.html` that is a suffix of it.
    private static func nearestWritableName(in text: String, writableFiles: [String]) -> String? {
        var best: (path: String, index: String.Index)?
        for path in writableFiles.sorted(by: { $0.count > $1.count }) {
            var searchEnd = text.endIndex
            // Walk backwards past matches that are really part of a longer
            // filename: `app.py` occurs inside `tests/test_app.py`, and taking
            // it would hand the test file's body to `app.py`.
            while let r = text.range(of: path, options: .backwards,
                                     range: text.startIndex..<searchEnd) {
                if isWholePath(text, r) {
                    if best == nil || r.lowerBound > best!.index { best = (path, r.lowerBound) }
                    break
                }
                guard r.lowerBound > text.startIndex else { break }
                searchEnd = r.lowerBound
            }
        }
        return best?.path
    }

    /// True when the match is not embedded in a longer path token — the
    /// character before it must not continue an identifier or a path segment.
    private static func isWholePath(_ text: String, _ range: Range<String.Index>) -> Bool {
        guard range.lowerBound > text.startIndex else { return true }
        let prev = text[text.index(before: range.lowerBound)]
        return !(prev.isLetter || prev.isNumber || prev == "_" || prev == "/" || prev == "-" || prev == ".")
    }
}
