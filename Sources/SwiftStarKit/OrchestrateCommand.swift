import Foundation

/// The composer's `/orchestrate` command: the text following the command is
/// treated as the worker-task prompt, routed to the manual dispatch surface
/// (Dispatch tab) where the user completes the packet (writable files,
/// validation). Command is case-insensitive and must start the input.
public enum OrchestrateCommand {
    public static let command = "/orchestrate"

    /// The task text after a leading `/orchestrate`, or nil when the input is
    /// not an orchestrate command. A bare `/orchestrate` yields "" (route with
    /// an empty draft — the user types the task in the dispatch form).
    public static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(command) else { return nil }
        let rest = trimmed.dropFirst(command.count)
        // The command must be a whole token: `/orchestratefoo` is not a command.
        if let first = rest.first, !first.isWhitespace { return nil }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
