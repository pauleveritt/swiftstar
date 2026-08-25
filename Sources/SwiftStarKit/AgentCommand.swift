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
    /// Per-round generation cap (`-n`): bounds a single assistant round's
    /// tokens (thinking + text). 0 = engine default. The agent test sets this
    /// to bound a think-loop that otherwise fills the whole context.
    public var maxTokens: Int
    /// `--nothink` (DS4_THINK_NONE): disable the reasoning/think phase so the
    /// worker emits tool calls directly instead of deliberating. false = the
    /// engine default (DS4_THINK_HIGH).
    public var noThink: Bool
    /// `--think-budget`: per-round ceiling on *thinking* tokens, distinct from
    /// `maxTokens`, which caps the round's total generation. At the ceiling the
    /// engine forces `</think>` and bans reopening for the rest of that round,
    /// so a model that drafts a complete answer and then never transitions to
    /// acting is bounded without amputating reasoning the way `noThink` does.
    /// 0 = disabled. Must stay smaller than `maxTokens`, or the forced
    /// transition lands with no room left to act.
    public var thinkBudget: Int
    /// `--seed`: sampling seed for reproducible non-greedy runs. 0 = engine
    /// default (time-derived). Non-zero pins the run so a stochastic cell can
    /// be replicated or swept.
    public var seed: UInt64
    /// The system prompt (D1): passed inline as `-sys <text>` after `--shell`.
    /// nil omits the flag. The app passes the Superpowers bootstrap (P8).
    public var systemPrompt: String?

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        workspace: URL,
        shellAllowed: Bool = false,
        maxTokens: Int = 0,
        noThink: Bool = false,
        thinkBudget: Int = 0,
        seed: UInt64 = 0,
        systemPrompt: String? = nil
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.workspace = workspace
        self.shellAllowed = shellAllowed
        self.maxTokens = maxTokens
        self.noThink = noThink
        self.thinkBudget = thinkBudget
        self.seed = seed
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
            // P9: the app owns tool execution — always pass `--host-tools` so the
            // agent emits `tool_request` and blocks on `tool_result` (D1).
            "--host-tools",
        ]
        if settings.maxTokens > 0 {
            argv.append(contentsOf: ["-n", String(settings.maxTokens)])
        }
        if settings.noThink {
            argv.append("--nothink")
        }
        if settings.thinkBudget > 0 {
            argv.append(contentsOf: ["--think-budget", String(settings.thinkBudget)])
        }
        if settings.seed > 0 {
            argv.append(contentsOf: ["--seed", String(settings.seed)])
        }
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
