import Foundation

public enum EngineResolution: Equatable, Sendable {
    case found(String)
    case notFound(searched: [String])
}

public enum EngineCommand {
    public static let executableName = "ds4-dogfood"

    /// The P28 argv, plus `--model-id` / `--context-size` when set. A blank
    /// model id or a non-positive context size means "engine default".
    public static func arguments(
        source: URL, modelID: String? = nil, contextSize: Int? = nil
    ) -> [String] {
        var args = ["tui", "--ndjson", "--source", source.path, "--commit", "HEAD"]
        if let id = trimmedModelID(modelID) { args += ["--model-id", id] }
        if let n = contextSize, n > 0 { args += ["--context-size", String(n)] }
        return args
    }

    private static func trimmedModelID(_ id: String?) -> String? {
        guard let t = id?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// True while a session runs (`session` non-nil) and Settings name a model
    /// or context size other than the loaded one. Unset settings never differ,
    /// and a field the session did not report is not compared (a restart
    /// could never satisfy it).
    public static func restartNeeded(
        session: EngineSessionInfo?, modelID: String?, contextSize: Int?
    ) -> Bool {
        guard let session else { return false }
        if let id = trimmedModelID(modelID), let loaded = session.modelID, id != loaded { return true }
        if let n = contextSize, n > 0, let loaded = session.contextSize, n != loaded { return true }
        return false
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

    /// The shell command that takes a finished session's changes.
    public static func applyCommand(sessionDirectory: URL) -> String {
        "\(executableName) apply \(sessionDirectory.lastPathComponent)"
    }
}

/// How the engine process ended, as `Process.terminationReason` reports it.
public enum EngineTermination: Equatable, Sendable {
    /// A normal exit; the code is the exit status.
    case exit
    /// An uncaught signal; the code is the signal number.
    case signal
}

public struct EngineExit: Equatable, Sendable {
    public let code: Int32
    public let message: String

    /// `forced` means SwiftStar itself escalated to SIGKILL after the quit
    /// timed out; `terminated` that it sent SIGTERM (not escalated further).
    /// Both are our doing, not a crash.
    public static func describe(
        code: Int32, stderrTail: String, sawReady: Bool,
        reason: EngineTermination = .exit, forced: Bool = false, terminated: Bool = false
    ) -> EngineExit {
        if forced {
            return EngineExit(code: code, message: "ended by force after the quit timed out")
        }
        if reason == .signal {
            if terminated && code == SIGTERM {
                return EngineExit(code: code, message: "ended after the quit timed out")
            }
            let name = signalName(code).map { " (\($0))" } ?? ""
            return EngineExit(code: code, message: "killed by signal \(code)\(name)")
        }
        if terminated && reason == .exit && code == 130 {
            // The engine catches our SIGTERM and exits 130; that is our doing.
            return EngineExit(code: code, message: "ended after the quit timed out")
        }
        let tail = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastLine = stderrTail.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last(where: { !$0.isEmpty }) ?? ""
        let message: String
        switch code {
        case 0:
            message = "ended"
        case 130:
            message = "interrupted"
        case _ where code == 2 || !sawReady:
            message = "refused to start: " + (lastLine.isEmpty ? "exit code \(code)" : lastLine)
        case 1:
            message = "ended without a clean answer — see the session directory" + (tail.isEmpty ? "" : "\n\(tail)")
        default:
            message = "exited with code \(code)" + (tail.isEmpty ? "" : "\n\(tail)")
        }
        return EngineExit(code: code, message: message)
    }

    /// The process could not be launched at all: there is no exit status, so
    /// the message is the reason, not "refused to start" or an exit code.
    public static func launchFailure(path: String, reason: String) -> EngineExit {
        EngineExit(code: -1, message: "could not launch \(path): \(reason)")
    }

    private static func signalName(_ n: Int32) -> String? {
        let names: [Int32: String] = [
            1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT",
            8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE",
            14: "SIGALRM", 15: "SIGTERM",
        ]
        return names[n]
    }
}
