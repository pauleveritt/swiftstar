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
    /// Byte offset **within `startLine`** to resume from. Non-zero only when a
    /// previous window truncated that line mid-way because it alone exceeded
    /// the budget; it is how the rest of an over-long line stays reachable.
    public let startByteOffset: Int

    public init(startLine: Int = 1, maxLines: Int? = nil,
                whole: Bool = false, raw: Bool = false,
                startByteOffset: Int = 0) {
        self.startLine = startLine
        self.maxLines = maxLines
        self.whole = whole
        self.raw = raw
        self.startByteOffset = max(0, startByteOffset)
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
    /// When non-nil, `nextLine` is the line already partly delivered and this
    /// is the byte offset within it to resume from.
    public let nextByteOffset: Int?

    public init(text: String, nextLine: Int?, lastLine: Int, totalLines: Int,
                nextByteOffset: Int? = nil) {
        self.text = text
        self.nextLine = nextLine
        self.lastLine = lastLine
        self.totalLines = totalLines
        self.nextByteOffset = nextByteOffset
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

    /// A missing `start_line` means "from the top"; a non-positive one clamps
    /// to line 1. Shared by `render` and by `ReadRepeatCounter`'s same-window
    /// key so both treat a request's identity the same way.
    public static func effectiveStartLine(_ startLine: Int?) -> Int {
        max(startLine ?? 1, 1)
    }

    /// A non-positive or absent `max_lines` is *absent*, not a request for one
    /// line (`ds4_agent.c:8125`) — it resolves to the tier default. Shared by
    /// `render` and by `ReadRepeatCounter`'s same-window key so a bare read and
    /// its equivalent explicit window are never counted as two different ones.
    public static func effectiveMaxLines(_ maxLines: Int?, default defaultLines: Int) -> Int {
        maxLines.flatMap { $0 > 0 ? $0 : nil } ?? defaultLines
    }

    public static func render(text: String, path: String,
                              request: ReadWindowRequest,
                              defaultLines: Int,
                              byteBudget: Int = 7000) -> ReadWindowResult {
        let lines = splitLines(text)
        let total = lines.count
        let startIdx = min(effectiveStartLine(request.startLine) - 1, total)

        // The ceiling: `whole` means "to EOF", otherwise max_lines or the tier.
        // Serving 1 and then advertising `call more with count=0` would be a
        // second contract behind one tool name, and a slow-drip paging loop.
        let requested = effectiveMaxLines(request.maxLines, default: defaultLines)
        let ceiling = request.whole ? total - startIdx : requested
        let ceilingEnd = min(total, startIdx + max(ceiling, 0))

        // Reserve the worst-case header so the body budget cannot overflow the
        // total. The real header is never longer than this one.
        let reserved = request.raw
            ? bareNote(lastLine: total, total: total, continueAt: total + 1,
                       count: requested).utf8.count
            : header(path: path, start: startIdx + 1, end: total, total: total,
                     continueAt: total + 1, truncated: true, count: requested).utf8.count
        let bodyBudget = max(0, byteBudget - reserved)

        var body = ""
        var used = 0
        var endIdx = startIdx
        // Set when the first line was delivered only in part: the byte offset
        // within it to resume from. The rest of an over-long line has to stay
        // reachable, or the window budget recreates the very bug P24.1 fixes
        // (content the model can ask for and never receive).
        var partialResume: Int?

        while endIdx < ceilingEnd {
            // Only the first line of the window can carry a resume offset.
            let dropped = endIdx == startIdx ? request.startByteOffset : 0
            let content = dropped > 0 ? utf8Drop(lines[endIdx], bytes: dropped) : lines[endIdx]
            let rendered = request.raw
                ? content + "\n"
                : "\(endIdx + 1) \(content)\n"
            let cost = rendered.utf8.count
            if used + cost > bodyBudget {
                // D6: always make progress. A line that alone exceeds the budget
                // is truncated in-band and becomes the continuation point, so
                // the next `more` resumes inside it rather than skipping it.
                if endIdx == startIdx {
                    let lineBytes = lines[endIdx].utf8.count
                    // Reserve the marker at its worst case (both counts at their
                    // largest) plus the line-number prefix, so the cut can never
                    // push the result past the budget. Measured, not guessed —
                    // a magic reserve here overflowed by 8 bytes.
                    let worstMarker = markerLine(line: endIdx + 1, shown: lineBytes,
                                                 total: lineBytes)
                    let prefix = request.raw ? "" : "\(endIdx + 1) "
                    let room = max(0, bodyBudget - worstMarker.utf8.count - prefix.utf8.count)
                    let cut = utf8Prefix(content, budget: room)
                    let shown = dropped + cut.utf8.count
                    body += prefix + cut
                    body += markerLine(line: endIdx + 1, shown: shown, total: lineBytes)
                    if shown < lineBytes { partialResume = shown } else { endIdx += 1 }
                }
                break
            }
            body += rendered
            used += cost
            endIdx += 1
        }

        // A partly-delivered line is not behind us: the window ends *inside* it.
        let truncated = partialResume != nil || endIdx < total
        let lastLine = partialResume != nil ? startIdx + 1 : endIdx
        let continueAt = partialResume != nil ? startIdx + 1 : lastLine + 1
        let out: String
        if request.raw {
            out = body + (truncated
                ? bareNote(lastLine: lastLine, total: total,
                           continueAt: continueAt, count: requested)
                : "")
        } else {
            out = header(path: path, start: total == 0 ? 0 : startIdx + 1,
                         end: lastLine, total: total, continueAt: continueAt,
                         truncated: truncated, count: requested) + body
        }
        return ReadWindowResult(text: out,
                                nextLine: truncated ? continueAt : nil,
                                lastLine: lastLine, totalLines: total,
                                nextByteOffset: partialResume)
    }

    // MARK: - the engine's strings (ds4_agent.c:8138-8154), ported verbatim

    /// `continueAt` is normally `end + 1`, but equals `end` when the window
    /// stopped *inside* that line — the engine has no such case (it has no byte
    /// budget), so this is the one place the format carries a value the engine
    /// would not produce, with the same shape.
    private static func header(path: String, start: Int, end: Int, total: Int,
                               continueAt: Int, truncated: Bool, count: Int) -> String {
        truncated
            ? "\(path): lines \(start)-\(end) of \(total); continue_offset=\(continueAt); call more with count=\(count) to read the next chunk\n"
            : "\(path): lines \(start)-\(end) of \(total)\n"
    }

    private static func bareNote(lastLine: Int, total: Int, continueAt: Int,
                                 count: Int) -> String {
        "[Read truncated at line \(lastLine) of \(total). continue_offset=\(continueAt). Call more with count=\(count) to read the next chunk.]\n"
    }

    /// The in-band notice that a single line was delivered only in part.
    private static func markerLine(line: Int, shown: Int, total: Int) -> String {
        "\n[line \(line) truncated at \(shown) of \(total) bytes; call more to continue this line]\n"
    }

    /// Drop `bytes` UTF-8 bytes from the front of `s`, on a codepoint boundary.
    private static func utf8Drop(_ s: String, bytes: Int) -> String {
        if bytes <= 0 { return s }
        if bytes >= s.utf8.count { return "" }
        var used = 0
        var idx = s.startIndex
        while idx < s.endIndex, used < bytes {
            used += String(s[idx]).utf8.count
            idx = s.index(after: idx)
        }
        return String(s[idx...])
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
