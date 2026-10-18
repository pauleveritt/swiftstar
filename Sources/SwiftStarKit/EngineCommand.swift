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
        source: URL, modelID: String? = nil, contextSize: Int? = nil, allowBash: Bool = false
    ) -> [String] {
        var args = ["tui", "--ndjson", "--source", source.path, "--commit", "HEAD"]
        if let id = modelID?.trimmedOrNil { args += ["--model-id", id] }
        if let n = contextSize, n > 0 { args += ["--context-size", String(n)] }
        if allowBash { args.append(allowBashFlag) }
        return args
    }

    /// ds4-engine's RUN.2 experiment (`tui_cli.py:622-631`): `run` maps a
    /// simple `cat`, `ls` or `grep` onto those tools and runs anything else
    /// as bash in the sandbox (SU.18).
    public static let allowBashFlag = "--allow-bash"

    /// Whether `argv` starts the engine with bash allowed. The engine reports
    /// no tool policy (SU.18, D3), so this is read from what was spawned,
    /// a `relaunch` argv included: the engine carries the flag in those.
    public static func allowsBash(_ argv: [String]) -> Bool {
        argv.contains(allowBashFlag)
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
    public static func resumeArguments(id: String, source: URL, allowBash: Bool = false) -> [String] {
        ["tui", "--ndjson", "--resume", id, "--source", source.path] + (allowBash ? [allowBashFlag] : [])
    }

    /// ds4-engine's report on one session, as its JSON contract (AN.4).
    public static func reportArguments(sessionDirectory: URL) -> [String] {
        ["report", sessionDirectory.path, "--json"]
    }

    /// The shell command that takes a finished session's changes.
    public static func applyCommand(sessionDirectory: URL) -> String {
        "\(executableName) apply \(sessionDirectory.lastPathComponent)"
    }
}
