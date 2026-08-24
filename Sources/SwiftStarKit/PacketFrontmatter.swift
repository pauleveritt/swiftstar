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
    public static func parse(_ document: String) throws -> HandoffPacket {
        let (frontmatter, body) = try split(document)
        let fields = parseFields(frontmatter)

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
    private static func split(_ document: String) throws -> (String, String) {
        let lines = document.components(separatedBy: "\n")
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
    /// lists are the only two value shapes v1 admits.
    private static func parseFields(_ frontmatter: String) -> (scalars: [String: String], lists: [String: [String]]) {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var parentKey: String?
        var listKey: String?

        for rawLine in frontmatter.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let indent = rawLine.prefix { $0 == " " }.count

            if line.hasPrefix("- ") {
                guard let key = listKey else { continue }
                lists[key, default: []].append(unquote(String(line.dropFirst(2))))
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))

            if indent == 0 { parentKey = nil }
            let qualified = if indent > 0, let parent = parentKey { "\(parent).\(key)" } else { key }

            if value.isEmpty {
                // A bare `key:` opens either a nested mapping or a list.
                if indent == 0 { parentKey = key }
                listKey = qualified
            } else {
                scalars[qualified] = value
                listKey = nil
            }
        }

        return (scalars, lists)
    }

    private static func unquote(_ value: String) -> String {
        var v = value.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}
