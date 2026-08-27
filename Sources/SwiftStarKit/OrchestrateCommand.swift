import Foundation

/// The composer's `/orchestrate` command: the text following the command is
/// treated as the worker-task prompt, dispatched as a subagent task in place
/// (no tab jump). An optional `--files` flag names the writable files
/// (worktree-relative, the Dispatch tab's convention); absent, the worker is
/// read-only. The command is case-insensitive and must start the input.
public enum OrchestrateCommand {
    public static let command = "/orchestrate"
    /// The flag that introduces the writable-file list. Reserved: a task that
    /// literally contains `--files` must not use this form.
    public static let filesFlag = "--files"

    public struct Request: Equatable, Sendable {
        public let task: String
        public let writableFiles: [String]
    }

    /// Parses a leading `/orchestrate` command. Returns nil when the input is
    /// not an orchestrate command. A bare command yields an empty task; a
    /// `--files` flag yields the comma-separated, trimmed list.
    public static func parse(_ input: String) -> Request? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return nil }
        let rest = trimmed.dropFirst(command.count)
        // The command must be a whole token: `/orchestratefoo` is not a command.
        if let first = rest.first, !first.isWhitespace { return nil }
        return parseRest(String(rest))
    }

    static func parseRest(_ rest: String) -> Request {
        let body = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let flagRange = body.range(of: filesFlag) else {
            return Request(task: body, writableFiles: [])
        }
        let task = String(body[..<flagRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let files = String(body[flagRange.upperBound...])
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Request(task: task, writableFiles: files)
    }
}
