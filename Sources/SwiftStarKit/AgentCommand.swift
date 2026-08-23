import Foundation

/// The agent launch settings. Pure value type; defaults live in the app.
public struct AgentSettings: Equatable, Sendable {
    public var engineDir: URL
    public var modelPath: URL
    public var contextSize: Int
    /// The workspace grant (D1): the agent's cwd and the file tools'
    /// confinement root. The app always passes it (D2).
    public var workspace: URL
    /// The shell toggle (D1/D2): false = `--shell off` (bash removed from
    /// schema and refused in dispatch). The app's default posture is deny.
    public var shellAllowed: Bool
    /// The system prompt (D1): passed inline as `-sys <text>` after `--shell`.
    /// nil omits the flag. The app passes the Superpowers bootstrap (P8).
    public var systemPrompt: String?

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        workspace: URL,
        shellAllowed: Bool = false,
        systemPrompt: String? = nil
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.workspace = workspace
        self.shellAllowed = shellAllowed
        self.systemPrompt = systemPrompt
    }
}

/// The one argv contract: what the app spawns (as `Process.arguments`, after
/// `Process` prepends the executable path as argv[0]) and what the fake agent
/// validates. The binary path itself is NOT part of the returned array.
public enum AgentCommand {
    public static func argv(settings: AgentSettings) -> [String] {
        var argv: [String] = [
            "-m", settings.modelPath.path,
            "-c", String(settings.contextSize),
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", settings.workspace.path,
            "--shell", settings.shellAllowed ? "on" : "off",
        ]
        if let systemPrompt = settings.systemPrompt {
            argv.append(contentsOf: ["-sys", systemPrompt])
        }
        return argv
    }

    /// The executable to spawn for these settings.
    public static func binaryPath(settings: AgentSettings) -> URL {
        settings.engineDir.appendingPathComponent("ds4-agent")
    }
}
