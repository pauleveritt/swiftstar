import Foundation

/// A parsed composer command (P19.1 D10). A bare prompt (no leading slash) is
/// the default agent mode and is **not** a command. `/chat` is read-only
/// consultation; `/orchestrate` is the coordination loop (its app behavior is
/// P20-forward). Names must agree with `docs/glossary.md`.
public enum Command: Equatable, Sendable {
    case chat(task: String)
    case orchestrate(task: String, writableFiles: [String])
}

/// Typed command parsing, replacing the ad-hoc `OrchestrateCommand` hasPrefix
/// hack. A command must start the input and be a whole token (`/chatfoo` is not
/// a command). `--files` (comma-separated, trimmed) is orchestrate-only.
public enum CommandRouter {
    public static let filesFlag = "--files"

    public static func parse(_ input: String) -> Command? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        if let chat = match(trimmed, command: "/chat") { return .chat(task: chat) }
        if let orch = match(trimmed, command: "/orchestrate") {
            let (task, files) = splitFiles(orch)
            return .orchestrate(task: task, writableFiles: files)
        }
        return nil
    }

    private static func match(_ input: String, command: String) -> String? {
        guard input.lowercased().hasPrefix(command) else { return nil }
        let rest = input.dropFirst(command.count)
        guard let first = rest.first, first.isWhitespace else {
            return input.lowercased() == command.lowercased() ? "" : nil
        }
        return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitFiles(_ body: String) -> (String, [String]) {
        guard let r = body.range(of: filesFlag) else { return (body, []) }
        let task = String(body[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let files = String(body[r.upperBound...])
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (task, files)
    }
}
