import Foundation

public enum PacketFrontmatterError: Error, Equatable {
    case missingFrontmatter
    case malformed(String)
}

/// Parses the authorable packet form — YAML frontmatter for the declared
/// fields, the markdown body as task text — into a `HandoffPacket`.
///
/// The parser is hand-rolled against the v1 schema rather than pulling in a
/// general YAML dependency: the schema is a closed set of scalars and string
/// lists, and a parser that accepts only that shape rejects malformed packets
/// that a permissive one would quietly accept.
///
/// `baselines` are intentionally not parseable. They are read from the worktree
/// at dispatch time and never authored, so a packet file cannot assert them.
public enum PacketFrontmatter {
    /// The only schema version this parser understands. Bumping this without a
    /// matching parser change is exactly the mistake rule 1 exists to catch.
    private static let supportedPacketVersion = 1

    public static func parse(_ document: String) throws -> HandoffPacket {
        let (frontmatter, body) = try split(document)
        let fields = try parseFields(frontmatter)

        try requireKnownPacketVersion(fields.scalars["packet"])

        guard let writable = fields.lists["workspace.writable"] else {
            throw PacketFrontmatterError.malformed("workspace.writable is required")
        }

        return HandoffPacket(
            taskText: body.trimmingCharacters(in: .whitespacesAndNewlines),
            writableFiles: writable,
            validationCommand: fields.scalars["validation.command"],
            selfTestCommand: fields.scalars["validation.selfTest"],
            baselines: [:],
            turnBudget: try intValue(fields.scalars["budget.turns"], "budget.turns", default: 1),
            toolCallBudget: try intValue(fields.scalars["budget.toolCalls"], "budget.toolCalls", default: 0),
            facts: fields.lists["facts"] ?? [],
            redacts: fields.lists["redacts"] ?? [],
            role: try enumValue(fields.scalars["role"], "role", default: .implement),
            sampling: SamplingPolicy(
                think: try enumValue(fields.scalars["sampling.think"], "sampling.think", default: .bounded),
                maxTokens: try intValue(fields.scalars["budget.maxTokens"], "budget.maxTokens", default: 8192),
                temperature: try doubleValue(fields.scalars["sampling.temp"], "sampling.temp", default: 0)
            )
        )
    }

    /// `packet` is the schema version. Absent or unrecognized must fail
    /// closed — a parser that guessed the schema for an unstated or unknown
    /// version would be accepting fields it cannot actually promise to have
    /// parsed correctly. This is enforced at parse time, not in
    /// `HandoffPacketValidator`, because `HandoffPacket` itself carries no
    /// version field: by the time a packet exists as a `HandoffPacket`, the
    /// schema it was read under has already been decided.
    private static func requireKnownPacketVersion(_ raw: String?) throws {
        guard let raw else {
            throw PacketFrontmatterError.malformed("packet: version is required")
        }
        // `Int(raw)` alone would accept non-canonical literals like a
        // leading-zero `"01"` or an explicit-plus `"+1"` — both parse to the
        // integer 1 but are not how a version 1 packet should be written.
        // Round-tripping through `String(_:)` catches anything that isn't
        // already in canonical form.
        guard let version = Int(raw), String(version) == raw, version == supportedPacketVersion else {
            throw PacketFrontmatterError.malformed("packet: unsupported version \"\(raw)\"")
        }
    }

    /// A present-but-unrecognized value is an error, never a silent default.
    /// Absent is fine — the schema has defaults — but `think: false` (YAML
    /// boolean muscle memory) or a typo'd role must not quietly change what the
    /// packet means.
    private static func enumValue<T: RawRepresentable>(
        _ raw: String?, _ key: String, default fallback: T
    ) throws -> T where T.RawValue == String {
        guard let raw else { return fallback }
        guard let value = T(rawValue: raw) else {
            throw PacketFrontmatterError.malformed("\(key): unrecognized value \"\(raw)\"")
        }
        return value
    }

    private static func intValue(_ raw: String?, _ key: String, default fallback: Int) throws -> Int {
        guard let raw else { return fallback }
        guard let value = Int(raw) else {
            throw PacketFrontmatterError.malformed("\(key): \"\(raw)\" is not an integer")
        }
        return value
    }

    private static func doubleValue(_ raw: String?, _ key: String, default fallback: Double) throws -> Double {
        guard let raw else { return fallback }
        guard let value = Double(raw) else {
            throw PacketFrontmatterError.malformed("\(key): \"\(raw)\" is not a number")
        }
        return value
    }

    /// Splits `---`-fenced frontmatter from the markdown body.
    ///
    /// CRLF is normalized to LF up front rather than trimmed line-by-line: a
    /// CRLF document is plausible input (this repo already models
    /// `LineEnding.crlf` for worktree files), and `.whitespaces` — used
    /// throughout this parser to trim fence and key/value lines — does not
    /// strip `\r`, so an untouched CRLF fence line never compares equal to
    /// `"---"` and the parser threw the misleading `missingFrontmatter`.
    private static func split(_ document: String) throws -> (String, String) {
        let normalized = document.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw PacketFrontmatterError.missingFrontmatter
        }
        guard let closing = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            throw PacketFrontmatterError.malformed("frontmatter fence is never closed")
        }
        let frontmatter = lines[1..<closing].joined(separator: "\n")
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return (frontmatter, body)
    }

    /// Flattens the schema's one-level nesting into dotted keys — `budget:` with
    /// an indented `toolCalls:` becomes `budget.toolCalls`. Scalars and string
    /// lists are the only two value shapes v1 admits, plus the `|` block
    /// scalar as an alternate way to author a (potentially multi-line) scalar.
    private static func parseFields(_ frontmatter: String) throws -> (scalars: [String: String], lists: [String: [String]]) {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var parentKey: String?
        var listKey: String?

        let rawLines = frontmatter.components(separatedBy: "\n")
        var index = 0

        while index < rawLines.count {
            let rawLine = rawLines[index]
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                index += 1
                continue
            }

            let indent = rawLine.prefix { $0 == " " }.count

            if line.hasPrefix("- ") {
                guard let key = listKey else {
                    index += 1
                    continue
                }
                let item = stripTrailingComment(String(line.dropFirst(2)))
                    .trimmingCharacters(in: .whitespaces)
                lists[key, default: []].append(unquote(item))
                index += 1
                continue
            }

            guard let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            let strippedValue = stripTrailingComment(rawValue).trimmingCharacters(in: .whitespaces)

            if indent == 0 { parentKey = nil }
            let qualified = if indent > 0, let parent = parentKey { "\(parent).\(key)" } else { key }

            if isBlockScalarIndicator(strippedValue) {
                let (content, nextIndex) = try consumeBlockScalar(rawLines, from: index + 1, parentIndent: indent)
                scalars[qualified] = content
                listKey = nil
                index = nextIndex
                continue
            }

            let value = unquote(strippedValue)

            if value.isEmpty {
                // A bare `key:` opens either a nested mapping or a list.
                if indent == 0 { parentKey = key }
                listKey = qualified
            } else {
                scalars[qualified] = value
                listKey = nil
            }
            index += 1
        }

        return (scalars, lists)
    }

    /// `|` (and its chomping variants `|-`/`|+`) is YAML's literal block
    /// scalar indicator — the natural way to author a multi-line value like a
    /// shell command. Folded (`>`) style is out of scope for v1: nothing in
    /// the schema needs it, and admitting only what is used keeps the parser
    /// able to reject what it does not understand instead of guessing.
    private static func isBlockScalarIndicator(_ value: String) -> Bool {
        value == "|" || value == "|-" || value == "|+"
    }

    /// Consumes every line more indented than `parentIndent` as the block
    /// scalar's content, dedenting by the first content line's indentation
    /// (per YAML: that line sets the block's indentation level). Blank lines
    /// inside the block are kept as empty lines; trailing blank lines are
    /// clipped, matching `|`'s default "clip" chomping (a single trailing
    /// newline, i.e. no trailing blank entries once joined).
    ///
    /// A later content line indented *less* than the established block
    /// indent (but still more than `parentIndent`, so it isn't the block's
    /// end) is a YAML syntax error, not something to dedent-and-truncate: a
    /// naive `dropFirst(min(blockIndent, line.count))` would silently drop
    /// real leading characters from that line instead of failing. Per this
    /// parser's "reject what you don't understand" philosophy, throw.
    private static func consumeBlockScalar(
        _ rawLines: [String], from start: Int, parentIndent: Int
    ) throws -> (content: String, nextIndex: Int) {
        var lines: [String] = []
        var blockIndent: Int?
        var index = start

        while index < rawLines.count {
            let candidate = rawLines[index]
            if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append("")
                index += 1
                continue
            }
            let candidateIndent = candidate.prefix { $0 == " " }.count
            if candidateIndent <= parentIndent { break }
            if let blockIndent {
                guard candidateIndent >= blockIndent else {
                    throw PacketFrontmatterError.malformed(
                        "block scalar content line is indented less than the block's established indent"
                    )
                }
            } else {
                blockIndent = candidateIndent
            }
            lines.append(String(candidate.dropFirst(blockIndent!)))
            index += 1
        }

        while lines.last == "" { lines.removeLast() }
        return (lines.joined(separator: "\n"), index)
    }

    /// Truncates at a `#` that starts a trailing comment — one preceded by
    /// whitespace (or at the very start) and outside of quotes — leaving a
    /// `#` that is part of the scalar's actual quoted content untouched.
    ///
    /// Quote tracking only applies to a scalar that is *itself* quoted YAML —
    /// i.e. one whose first non-space character is `"` or `'`. A plain
    /// scalar's apostrophe (`don't`) is just a literal character, not YAML
    /// single-quoting, and must not make the stripper think the rest of the
    /// line is "inside a quote" and let a real trailing comment survive.
    private static func stripTrailingComment(_ value: String) -> String {
        let firstNonSpace = value.first { $0 != " " && $0 != "\t" }
        let isQuotedScalar = firstNonSpace == "\"" || firstNonSpace == "'"

        var inSingleQuote = false
        var inDoubleQuote = false
        var previousWasSpace = true
        var result = ""

        for char in value {
            if isQuotedScalar {
                if char == "\"" && !inSingleQuote { inDoubleQuote.toggle() }
                if char == "'" && !inDoubleQuote { inSingleQuote.toggle() }
            }

            if char == "#" && !inSingleQuote && !inDoubleQuote && previousWasSpace {
                break
            }

            result.append(char)
            previousWasSpace = (char == " " || char == "\t")
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}
