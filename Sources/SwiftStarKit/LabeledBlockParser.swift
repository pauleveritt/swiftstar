import Foundation

/// The pinned directive a text-contract packet inserts in place of the
/// "use your write tool" note (spec Section 1).
public enum TextContract {
    public static let directive = """
    Do not call tools. For each file you change, emit a heading line: one or more hash signs followed \
    by the file path (relative to the workspace root), with no spaces — for example: #app.py. \
    Immediately after the heading line, emit a fenced code block: three backticks on their own line, \
    the complete file contents, then three backticks on their own line. A fenced code block with no \
    preceding heading line is ignored.
    """
}

/// One parsed text-contract turn: the files the model emitted as labeled
/// blocks (first-complete-block-wins), plus the diagnostics the failure
/// classification needs. Pure — no I/O.
public struct HarvestResult: Equatable, Sendable {
    public let files: [(path: String, content: String)]
    public let outOfGrantHeadings: [String]
    public let duplicateCounts: [String: Int]

    public init(files: [(path: String, content: String)],
                outOfGrantHeadings: [String],
                duplicateCounts: [String: Int]) {
        self.files = files
        self.outOfGrantHeadings = outOfGrantHeadings
        self.duplicateCounts = duplicateCounts
    }

    public static func == (lhs: HarvestResult, rhs: HarvestResult) -> Bool {
        guard lhs.outOfGrantHeadings == rhs.outOfGrantHeadings,
              lhs.duplicateCounts == rhs.duplicateCounts,
              lhs.files.count == rhs.files.count else { return false }
        for (a, b) in zip(lhs.files, rhs.files) {
            guard a.path == b.path, a.content == b.content else { return false }
        }
        return true
    }
}

/// Fail-closed parser for the text output contract (spec Section 1). The rules:
/// a heading `### \u{0060}path\u{0060}` is accepted only if its *normalized* path
/// exactly equals an allowlist entry; it must be immediately followed (optional
/// one blank line) by a fenced block; an unterminated fence is dropped; a fence
/// with no accepted heading is ignored; a heading inside a fenced body does not
/// flip attribution; first complete block per file wins, duplicates counted;
/// an out-of-grant heading is dropped and recorded.
public enum LabeledBlockParser {
    public static func parse(_ text: String, writableFiles: [String]) -> HarvestResult {
        let allowlist = Set(writableFiles.map(normalize))
        var files: [(path: String, content: String)] = []
        var seen = Set<String>()
        var duplicateCounts: [String: Int] = [:]
        var outOfGrant: [String] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < lines.count {
            if isFence(lines[i]) {
                // A fence with no accepted heading: skip to its close.
                i += 1
                while i < lines.count, !isFence(lines[i]) { i += 1 }
                i += 1
                continue
            }
            if let path = headingPath(lines[i]) {
                var j = i + 1
                if j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                    j += 1  // optional single blank line
                }
                if j < lines.count, isFence(lines[j]) {
                    var body: [String] = []
                    var k = j + 1
                    var closed = false
                    while k < lines.count {
                        if isFence(lines[k]) { closed = true; break }
                        body.append(lines[k])
                        k += 1
                    }
                    if closed {
                        let norm = normalize(path)
                        if allowlist.contains(norm) {
                            if seen.contains(norm) {
                                duplicateCounts[norm, default: 0] += 1
                            } else {
                                seen.insert(norm)
                                files.append((norm, body.joined(separator: "\n")))
                            }
                        } else {
                            outOfGrant.append(path)
                        }
                    }
                    i = k + 1
                    continue
                }
                // Heading with no fence before the next line: dropped, not carried forward.
                i += 1
                continue
            }
            i += 1
        }
        return HarvestResult(files: files, outOfGrantHeadings: outOfGrant, duplicateCounts: duplicateCounts)
    }

    static func normalize(_ path: String) -> String {
        var p = path
        while p.hasPrefix("./") { p.removeFirst(2) }
        p = p.replacingOccurrences(of: "//", with: "/")
        p = p.replacingOccurrences(of: "/./", with: "/")
        while p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    static func headingPath(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("#") else { return nil }
        var rest = t
        while rest.hasPrefix("#") { rest.removeFirst() }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        // Backtick-quoted form (### `path`)
        if rest.hasPrefix("`"), rest.hasSuffix("`"), rest.count >= 2 {
            let inner = rest.dropFirst().dropLast()
            guard !inner.contains("`") else { return nil }
            return String(inner)
        }
        // Bare form (#path, to end of line)
        guard !rest.contains("`") else { return nil }
        return rest
    }
}
