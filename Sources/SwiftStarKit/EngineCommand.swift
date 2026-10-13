import Foundation

public enum EngineResolution: Equatable, Sendable {
    case found(String)
    case notFound(searched: [String])
}

public enum EngineCommand {
    public static let executableName = "ds4-dogfood"

    /// The engine's argv, plus `--model-id` / `--context-size` when set. A blank
    /// model id or a non-positive context size means "engine default".
    public static func arguments(
        source: URL, modelID: String? = nil, contextSize: Int? = nil
    ) -> [String] {
        var args = ["tui", "--ndjson", "--source", source.path, "--commit", "HEAD"]
        if let id = modelID?.trimmedOrNil { args += ["--model-id", id] }
        if let n = contextSize, n > 0 { args += ["--context-size", String(n)] }
        return args
    }

    /// Looks for the engine executable: the settings path, then each `PATH`
    /// entry, then `~/.local/bin`.
    public static func resolveExecutable(
        settingsPath: String?, pathEnv: String?, home: URL,
        isExecutable: (String) -> Bool
    ) -> EngineResolution {
        var candidates: [String] = []
        if let settingsPath, !settingsPath.isEmpty { candidates.append(settingsPath) }
        for dir in (pathEnv ?? "").split(separator: ":") where !dir.isEmpty {
            candidates.append("\(dir)/\(executableName)")
        }
        candidates.append(home.appendingPathComponent(".local/bin/\(executableName)").path)
        if let hit = candidates.first(where: isExecutable) { return .found(hit) }
        return .notFound(searched: candidates)
    }

    /// Resuming a listed session (SU.7a): no `--commit`, which the engine
    /// refuses on resume, and no model or context flags, so the conversation
    /// keeps its own.
    public static func resumeArguments(id: String, source: URL) -> [String] {
        ["tui", "--ndjson", "--resume", id, "--source", source.path]
    }

    /// The session report (AN.1's `session_last.py`) for one session. At
    /// AN.4 this becomes `ds4-dogfood last --session`.
    public static func reportArguments(script: URL, sessionDirectory: URL) -> (executable: String, arguments: [String]) {
        ("/usr/bin/python3", ["-I", "-B", script.path, "--session", sessionDirectory.path])
    }

    /// The shell command that takes a finished session's changes.
    public static func applyCommand(sessionDirectory: URL) -> String {
        "\(executableName) apply \(sessionDirectory.lastPathComponent)"
    }
}
