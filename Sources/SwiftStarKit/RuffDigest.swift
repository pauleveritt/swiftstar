import Foundation

/// Groups ruff JSON diagnostics by (rule code, file) so each group maps to one
/// class of edit; emits ≤2 groups plus counts. Total over `CommandOutput`.
public enum RuffDigest {
    public struct Diagnostic: Equatable, Sendable {
        public let code: String
        public let file: String
        public let line: Int
        public let column: Int
        public let message: String
    }

    static let maxGroups = 2

    public static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest {
        let diagnostics = parseRuffJSON(out.stdout)
        let summary = summarize(out: out, command: command, artifactPath: artifactPath,
                                diagnostics: diagnostics)
        return ToolDigest(summary: summary, command: command,
                          artifactPath: artifactPath,
                          outputDigest: ToolDigest.sha256(out.stdout))
    }

    static func parseRuffJSON(_ stdout: String) -> [Diagnostic] {
        guard let data = stdout.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { item in
            guard let code = item["code"] as? String,
                  let message = item["message"] as? String,
                  let file = item["filename"] as? String,
                  let loc = item["location"] as? [String: Any],
                  let row = loc["row"] as? Int,
                  let column = loc["column"] as? Int else { return nil }
            return Diagnostic(code: code, file: file, line: row, column: column, message: message)
        }
    }

    static func summarize(out: CommandOutput, command: String, artifactPath: String,
                          diagnostics: [Diagnostic]) -> String {
        let exitLabel = out.timedOut ? "timed out" : "exit \(out.exit)"
        var lines: [String] = []
        if diagnostics.isEmpty && !out.timedOut && out.exit == 0 {
            lines.append("ruff: 0 diagnostics, all clean (\(exitLabel))")
        } else if diagnostics.isEmpty {
            lines.append("ruff: could not parse (\(exitLabel))")
        } else {
            let files = Set(diagnostics.map(\.file)).count
            lines.append("ruff: \(diagnostics.count) diagnostics, \(files) file\(files == 1 ? "" : "s") (\(exitLabel))")
        }
        lines.append("Ran: \(command)")
        let groups = group(diagnostics)
        for (i, group) in groups.prefix(maxGroups).enumerated() {
            let files = Set(group.map(\.file)).count
            lines.append("[\(i + 1)] \(group[0].code) — \(group.count) in \(files) file\(files == 1 ? "" : "s")")
            let rep = group[0]
            lines.append("    \(rep.file):\(rep.line):\(rep.column) \(rep.message)")
        }
        if groups.count > maxGroups {
            lines.append("and \(groups.count - maxGroups) more rule groups (see full output)")
        }
        lines.append("full output: \(artifactPath)")
        return lines.joined(separator: "\n")
    }

    static func group(_ diagnostics: [Diagnostic]) -> [[Diagnostic]] {
        var byKey: [(key: (String, String), items: [Diagnostic])] = []
        for d in diagnostics {
            let key = (d.code, d.file)
            if let i = byKey.firstIndex(where: { $0.key == key }) {
                byKey[i].items.append(d)
            } else {
                byKey.append((key: key, items: [d]))
            }
        }
        return byKey.sorted { $0.items.count > $1.items.count }.map(\.items)
    }
}
