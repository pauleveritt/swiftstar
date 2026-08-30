import Foundation

/// One window of a file, rendered in the engine's own `read` result format
/// (`external/ds4/ds4_agent.c:8102-8174`), bounded by a byte budget the engine
/// does not need.
///
/// The budget exists because every host tool result is condensed at 8000 bytes
/// by `ToolCallbackResponder` before it reaches the model. A window that
/// overflowed would be cut into head+tail and its middle would never arrive —
/// which is exactly the failure P24.1 fixes. Budgeting here instead buys the
/// guarantee that makes the result honest:
///
/// > the header's line range always names exactly the lines present in the
/// > body, and the output never exceeds `byteBudget`.
///
/// Pure: no I/O, no model. The caller reads the file and owns continuation
/// state.
public struct ReadWindowRequest: Equatable, Sendable {
    public let startLine: Int
    public let maxLines: Int?
    public let whole: Bool
    public let raw: Bool

    public init(startLine: Int = 1, maxLines: Int? = nil,
                whole: Bool = false, raw: Bool = false) {
        self.startLine = startLine
        self.maxLines = maxLines
        self.whole = whole
        self.raw = raw
    }
}

public struct ReadWindowResult: Equatable, Sendable {
    /// Header + body, always ≤ the requested byte budget.
    public let text: String
    /// 1-based line to continue from, or nil when the window reached EOF.
    /// nil is the executor's signal to clear the continuation (D4).
    public let nextLine: Int?
    /// Last line number present in the body (equals the start index when the
    /// body is empty).
    public let lastLine: Int
    public let totalLines: Int

    public init(text: String, nextLine: Int?, lastLine: Int, totalLines: Int) {
        self.text = text
        self.nextLine = nextLine
        self.lastLine = lastLine
        self.totalLines = totalLines
    }
}

public enum ReadWindow {
    /// The engine's context tier (`ds4_agent.c:8090`, constants `:7885-7889`).
    public static func defaultLines(contextSize: Int) -> Int {
        if contextSize > 0 && contextSize <= 8192 { return 120 }
        if contextSize > 0 && contextSize <= 16384 { return 240 }
        return 500
    }

    /// D2: the byte budget scales with context for the same reason the line
    /// default does. `contextSize / 2` bytes is ≈ `contextSize / 8` tokens, so
    /// one tool result is ~12.5% of context at any tier — never half of a 4k
    /// window. The ceiling is the condenser's 8000-byte cap less header
    /// headroom; the floor keeps a pathological setting from starving the read.
    public static func byteBudget(contextSize: Int) -> Int {
        min(7000, max(1024, contextSize / 2))
    }

    public static func render(text: String, path: String,
                              request: ReadWindowRequest,
                              defaultLines: Int,
                              byteBudget: Int = 7000) -> ReadWindowResult {
        let lines = splitLines(text)
        let total = lines.count
        let startIdx = min(max(request.startLine, 1) - 1, total)

        // The ceiling: `whole` means "to EOF", otherwise max_lines or the tier.
        // A non-positive `max_lines` is *absent*, not a request for one line —
        // `ds4_agent.c:8125` (`if (max_lines <= 0) max_lines = default`). Serving
        // 1 and then advertising `call more with count=0` would be a second
        // contract behind one tool name, and a slow-drip paging loop.
        let requested = request.maxLines.flatMap { $0 > 0 ? $0 : nil } ?? defaultLines
        let ceiling = request.whole ? total - startIdx : requested
        let ceilingEnd = min(total, startIdx + max(ceiling, 0))

        // Reserve the worst-case header so the body budget cannot overflow the
        // total. The real header is never longer than this one.
        let reserved = request.raw
            ? bareNote(lastLine: total, total: total, count: requested).utf8.count
            : header(path: path, start: startIdx + 1, end: total,
                     total: total, truncated: true, count: requested).utf8.count
        let bodyBudget = max(0, byteBudget - reserved)

        var body = ""
        var used = 0
        var endIdx = startIdx
        while endIdx < ceilingEnd {
            let rendered = request.raw
                ? lines[endIdx] + "\n"
                : "\(endIdx + 1) \(lines[endIdx])\n"
            let cost = rendered.utf8.count
            if used + cost > bodyBudget {
                // D6: always make progress. A first line that alone exceeds the
                // budget is truncated in-band rather than dropped, so
                // continue_offset can advance and `more` cannot loop forever.
                if endIdx == startIdx {
                    let marker = "[line \(endIdx + 1) truncated at "
                    let room = max(0, bodyBudget - marker.utf8.count - 32)
                    let cut = utf8Prefix(lines[endIdx], budget: room)
                    body += (request.raw ? cut : "\(endIdx + 1) \(cut)")
                    body += "\n[line \(endIdx + 1) truncated at \(cut.utf8.count)"
                    body += " of \(lines[endIdx].utf8.count) bytes]\n"
                    endIdx += 1
                }
                break
            }
            body += rendered
            used += cost
            endIdx += 1
        }

        let truncated = endIdx < total
        let lastLine = endIdx
        let out: String
        if request.raw {
            out = body + (truncated
                ? bareNote(lastLine: lastLine, total: total, count: requested)
                : "")
        } else {
            out = header(path: path, start: total == 0 ? 0 : startIdx + 1,
                         end: lastLine, total: total,
                         truncated: truncated, count: requested) + body
        }
        return ReadWindowResult(text: out,
                                nextLine: truncated ? lastLine + 1 : nil,
                                lastLine: lastLine, totalLines: total)
    }

    // MARK: - the engine's strings (ds4_agent.c:8138-8154), ported verbatim

    private static func header(path: String, start: Int, end: Int, total: Int,
                               truncated: Bool, count: Int) -> String {
        truncated
            ? "\(path): lines \(start)-\(end) of \(total); continue_offset=\(end + 1); call more with count=\(count) to read the next chunk\n"
            : "\(path): lines \(start)-\(end) of \(total)\n"
    }

    private static func bareNote(lastLine: Int, total: Int, count: Int) -> String {
        "[Read truncated at line \(lastLine) of \(total). continue_offset=\(lastLine + 1). Call more with count=\(count) to read the next chunk.]\n"
    }

    /// A faithful port of `agent_split_lines` (`ds4_agent.c:7926-7944`): a line
    /// runs to the next `\r` or `\n`; a `\r\n` pair is one terminator; the
    /// terminator is excluded from the content; and a trailing terminator does
    /// not create a final empty line. Splitting on `\n` alone would give a
    /// different line *numbering* for CR and CRLF files — the coordinate system
    /// `start_line`, `continue_offset` and `edit` all share.
    private static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        while true {
            let scalar = pending ?? iterator.next()
            pending = nil
            guard let s = scalar else { break }
            if s == "\n" {
                lines.append(String(current)); current = String.UnicodeScalarView()
            } else if s == "\r" {
                // "\r\n" is a single terminator; a lone "\r" is also one.
                if let next = iterator.next(), next != "\n" { pending = next }
                lines.append(String(current)); current = String.UnicodeScalarView()
            } else {
                current.append(s)
            }
        }
        if !current.isEmpty { lines.append(String(current)) }
        return lines
    }

    /// Longest prefix of `s` that fits `budget` UTF-8 bytes, cut on a codepoint
    /// boundary (never mid-scalar, so the output is always valid UTF-8).
    private static func utf8Prefix(_ s: String, budget: Int) -> String {
        if s.utf8.count <= budget { return s }
        var out = ""
        var used = 0
        for ch in s {
            let n = String(ch).utf8.count
            if used + n > budget { break }
            out.append(ch)
            used += n
        }
        return out
    }
}
