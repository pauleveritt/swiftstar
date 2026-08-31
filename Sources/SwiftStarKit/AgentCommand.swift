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
    /// Whether the engine should target a reduced GPU duty cycle. The app's
    /// persisted setting defaults on; explicit value-type callers retain the
    /// engine default unless they opt in.
    public var powerSavingEnabled: Bool
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
    /// P23 (D8): the context size for subagent-pool workers, clamped to
    /// [4,096, parent] at dispatch time. 0 = inherit the parent's context.
    /// Not an argv flag — it rides the per-turn prompt envelope's `ctx` key,
    /// so a worker's context is chosen per dispatch rather than per spawn.
    public var workerContextSize: Int

    /// The think budget to actually pass, honouring `thinkBudget`'s own
    /// constraint that it stay below `maxTokens` — otherwise the engine's
    /// forced `</think>` lands with no room left to act. The app sets no
    /// `maxTokens` (0 = engine default), so this only binds when a caller sets
    /// both; `swiftstar-agenttest` does. Returns 0 when the flag should be
    /// omitted entirely, since `--think-budget 0` reads as a live ceiling of
    /// zero rather than "disabled".
    public static func clampThinkBudget(_ settings: AgentSettings) -> Int {
        guard settings.thinkBudget > 0 else { return 0 }
        guard settings.maxTokens > 0 else { return settings.thinkBudget }
        return Swift.min(settings.thinkBudget, settings.maxTokens / 2)
    }
    /// The system prompt (D1): passed inline as `-sys <text>` after `--shell`.
    /// nil omits the flag. The app passes the Superpowers bootstrap (P8).
    public var systemPrompt: String?
    /// `--trace <path>`: the engine's diagnostic trace side-channel (compaction
    /// events, prefill-sync token accounting — see `TraceParser`). The engine
    /// writes to this path directly, independent of stdin/stdout/stderr; it is
    /// read from disk after the run, not streamed. nil omits the flag (P12.7
    /// piece 1). Optional so every existing caller that doesn't set it is
    /// unaffected — `swiftstar-drive` sets its own `tracePath` independently of
    /// this struct and is untouched by this field.
    public var tracePath: URL?
    /// Launch-time engine flags (SSD streaming etc.) declared by a selected
    /// variant; nil = engine defaults. Wired into argv (P13 Laguna XS arm).
    public var runtime: EngineRuntimeConfig?

    /// The moderate duty-cycle target used by the app's power-saving mode.
    /// The engine documents 70% as a useful compromise between sustained load
    /// and throughput, without changing model output.
    public static let powerSavingPercent = 70

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        workspace: URL,
        shellAllowed: Bool = false,
        powerSavingEnabled: Bool = false,
        maxTokens: Int = 0,
        noThink: Bool = false,
        thinkBudget: Int = 0,
        seed: UInt64 = 0,
        workerContextSize: Int = WorkerContextPolicy.defaultContext,
        systemPrompt: String? = nil,
        tracePath: URL? = nil,
        runtime: EngineRuntimeConfig? = nil
    ) {
        self.workerContextSize = workerContextSize
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.workspace = workspace
        self.shellAllowed = shellAllowed
        self.powerSavingEnabled = powerSavingEnabled
        self.maxTokens = maxTokens
        self.noThink = noThink
        self.thinkBudget = thinkBudget
        self.seed = seed
        self.systemPrompt = systemPrompt
        self.tracePath = tracePath
        self.runtime = runtime
    }
}

/// The one argv contract: what the app spawns (as `Process.arguments`, after
/// `Process` prepends the executable path as argv[0]) and what the fake agent
/// validates. The binary path itself is NOT part of the returned array.
public enum AgentCommand {
    /// The engine throttle this spawn uses, for `provenance.md`.
    ///
    /// `--power` is a setting, not a measurement: the engine's `power_percent`
    /// defaults to 100 and the app drops to 70 whenever power-saving is on. It
    /// reaches the wire on every `status` event, but a reader who does not know
    /// to grep for it sees only the consequence. On
    /// `captures/live/20260830-180004` (app, `--power 70`) against a
    /// `swiftstar-drive` re-run of the same prompt and model (engine default
    /// 100), prefill and decode were both ~1.7x faster in the drive run on ~the
    /// same volume of work — a gap first read as an engine improvement.
    /// Recording it here is what makes two captures comparable at a glance.
    public static func powerRecord(settings: AgentSettings) -> String {
        effectivePowerSavingEnabled(settings)
            ? "\(AgentSettings.powerSavingPercent) (`--power \(AgentSettings.powerSavingPercent)`)"
            : "100 (engine default; no `--power`)"
    }

    /// `settings.powerSavingEnabled`, forced off for a Laguna variant
    /// (`runtime.ssdStreaming` — the family's own signal, set by both S and
    /// XS, absent everywhere else): `ds4.c`'s Laguna load path refuses to
    /// start at all when `power_percent < 100`, unconditionally, alongside
    /// steering/MTP/DSpark/first-token-diagnostic ("Laguna S 2.1 currently
    /// supports the standard local graph path only") — power-saving's
    /// UserDefaults-true default (`AgentDefaultSettings.resolve`) would
    /// otherwise pick a variant the engine immediately refuses to load.
    private static func effectivePowerSavingEnabled(_ settings: AgentSettings) -> Bool {
        settings.powerSavingEnabled && settings.runtime?.ssdStreaming != true
    }

    /// The spawn's think configuration, for `provenance.md`. Reports what argv
    /// actually passes — including the CLAMPED think budget, which
    /// `clampThinkBudget` may halve against `maxTokens`.
    ///
    /// Per-turn overrides (P23) are deliberately not here: they postdate the
    /// spawn and belong in `outcomes.ndjson`, which records them per turn. What
    /// this replaces is a hardcoded `think=default` that read as "engine
    /// defaults" on sessions that were spawned with `--nothink`.
    public static func samplerRecord(settings: AgentSettings) -> String {
        var s = settings.noThink ? "think=none (`--nothink`)" : "think=default"
        let budget = AgentSettings.clampThinkBudget(settings)
        if budget > 0 { s += ", budget=\(budget)" }
        return s
    }

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
            // P23: per-turn think overrides (think/ctx on the prompt envelope).
            // Unconditional like --host-tools: the app pins the engine (the
            // submodule bump in this phase shipped the flag); a DS4_DIR build
            // without it fails loudly at option-parse, never silently.
            "--per-turn-think",
        ]
        if effectivePowerSavingEnabled(settings) {
            argv.append(contentsOf: ["--power", String(AgentSettings.powerSavingPercent)])
        }
        if settings.maxTokens > 0 {
            argv.append(contentsOf: ["-n", String(settings.maxTokens)])
        }
        if settings.noThink {
            argv.append("--nothink")
        }
        let budget = AgentSettings.clampThinkBudget(settings)
        if budget > 0 {
            argv.append(contentsOf: ["--think-budget", String(budget)])
        }
        if settings.seed > 0 {
            argv.append(contentsOf: ["--seed", String(settings.seed)])
        }
        if let systemPrompt = settings.systemPrompt {
            argv.append(contentsOf: ["-sys", systemPrompt])
        }
        if let tracePath = settings.tracePath {
            argv.append(contentsOf: ["--trace", tracePath.path])
        }
        if let runtime = settings.runtime {
            argv.append(contentsOf: runtime.argvFlags)
        }
        return argv
    }

    /// The executable to spawn for these settings.
    public static func binaryPath(settings: AgentSettings) -> URL {
        settings.engineDir.appendingPathComponent("ds4-agent")
    }

    /// The full spawn environment: `DS4_METAL_*_SOURCE` (absolute shader paths,
    /// F1 — the engine chdir's to `--workspace`, so cwd-relative shaders would
    /// not resolve) plus `DS4_LOCK_FILE` (the per-mode instance lock — the
    /// app's single Agent surface, with a distinct lock for dispatched
    /// attempts). Merges into (and returns) `base`.
    public static func engineEnvironment(engineDir: URL, lockFile: String, base: [String: String]) -> [String: String] {
        var env = base
        let metalDir = engineDir.appendingPathComponent("metal", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: metalDir.path) {
            for name in names where name.hasSuffix(".metal") {
                let stem = String(name.dropLast(".metal".count))
                env["DS4_METAL_\(stem.uppercased())_SOURCE"] = metalDir.appendingPathComponent(name).path
            }
        }
        env["DS4_LOCK_FILE"] = lockFile
        return env
    }
}
