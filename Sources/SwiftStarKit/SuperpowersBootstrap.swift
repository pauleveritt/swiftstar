import Foundation

/// The deterministic Superpowers skills INDEX prompt (P8 design D1).
///
/// `build` reads each `<skillsDir>/*/SKILL.md`, extracts the first `name:` and
/// `description:` front-matter lines, and renders a sorted index plus a
/// disclosure protocol pointing at `.swiftstar/skills/<name>/SKILL.md`. Either
/// field falls back to the skill's directory name when absent. A missing or
/// empty skills dir degrades to an empty `skillNames` and a
/// "No skills available in this workspace." prompt — the bootstrap never
/// fabricates skills the agent cannot `read` (D3/D5).
public struct SuperpowersBootstrap: Sendable {
    public let indexPrompt: String
    public let skillNames: [String]

    public static func build(skillsDir: URL) -> SuperpowersBootstrap {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsDir.path),
              let entries = try? fm.contentsOfDirectory(atPath: skillsDir.path)
        else {
            return SuperpowersBootstrap(indexPrompt: degrade, skillNames: [])
        }

        var skills: [(name: String, description: String)] = []
        for entry in entries {
            let skillDir = skillsDir.appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: skillDir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let md = skillDir.appendingPathComponent("SKILL.md")
            guard fm.fileExists(atPath: md.path) else { continue }
            let (name, desc) = parseSkill(at: md, fallback: entry)
            skills.append((name, desc))
        }

        guard !skills.isEmpty else {
            return SuperpowersBootstrap(indexPrompt: degrade, skillNames: [])
        }
        skills.sort { $0.name < $1.name }
        let indexLines = skills.map { "- \($0.name): \($0.description)" }
        let prompt = [header, disclosure, ""] + indexLines
        return SuperpowersBootstrap(
            indexPrompt: prompt.joined(separator: "\n"),
            skillNames: skills.map { $0.name }
        )
    }

    // MARK: - Prompt pieces

    private static let header =
        "You have Superpowers skills available. Load one before the work it covers."
    private static let disclosure =
        "To load a skill, read its SKILL.md inside the workspace (.swiftstar/skills/<name>/SKILL.md)."
    private static let degrade = "No skills available in this workspace."

    // MARK: - SKILL.md front-matter

    /// Scan a SKILL.md for the first `name:` and `description:` lines. The first
    /// match wins (the front-matter sits at the top), so a stray `name:` later in
    /// the body cannot mislead. Either field falls back to `fallback` (the skill
    /// directory name) when absent.
    private static func parseSkill(at url: URL, fallback: String) -> (name: String, description: String) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var name: String? = nil
        var description: String? = nil
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if name == nil, let v = fieldValue(line, key: "name") {
                name = stripQuotes(v)
            }
            if description == nil, let v = fieldValue(line, key: "description") {
                description = stripQuotes(v)
            }
            if name != nil && description != nil { break }
        }
        return (name ?? fallback, description ?? fallback)
    }

    /// If `line` begins with `<key>:` (optionally spaced), return the trimmed
    /// remainder; a non-empty value, else nil.
    private static func fieldValue(_ line: String, key: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let k = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard k == key else { return nil }
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// Strip a single surrounding `"` pair if present (the brainstorming skill
    /// ships its description quoted).
    private static func stripQuotes(_ s: String) -> String {
        var v = s
        if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }
}
