import Foundation

/// The complete resolved description of one spawn — the only thing an
/// arm-to-arm diff compares. Motivated by a 2026-08-30 A/B comparison that
/// silently differed by `--power 70` vs `100` and was read as an engine
/// speedup instead of a throttle setting (see `AgentCommand.powerRecord`).
/// `provenance.md` recorded the sampler and workspace, but nothing recorded
/// the app's own SHA/dirty state or the throttle, so the two captures looked
/// comparable when they were not.
///
/// Every field is passed in by the caller (`from(...)` takes already-resolved
/// values: SHAs, hashes, the OS build string, the wired-memory limit). This
/// type must stay a pure value — no process spawn, no socket, no file I/O —
/// because it lives in `SwiftStarKit`, the fast tier a build tripwire holds to
/// that contract.
public struct SpawnRecord: Equatable, Sendable, Codable {
    // MARK: - Engine (external/ds4)

    public let engineSHA: String
    public let engineDirty: Bool
    public let engineBinaryHash: String

    // MARK: - Harness (this app)

    /// The app's own git SHA — distinct from `engineSHA`. Without this an
    /// app-side A/B (a code change in SwiftStar itself, not in `external/ds4`)
    /// is invisible to the record, which is what the motivating incident
    /// actually was: two arms of the *same* engine build, spawned by two
    /// different app states.
    public let swiftstarSHA: String
    public let swiftstarDirty: Bool
    public let harnessBinaryHash: String

    // MARK: - Argv-only settings (each its own field, not folded into argv)

    public let maxTokens: Int
    /// The RAW `AgentSettings.thinkBudget` requested, not the value clamped
    /// into argv (`AgentCommand.argv` may halve it against `maxTokens` —
    /// see `AgentSettings.clampThinkBudget`, reflected in `sampler`
    /// below). Two requests that clamp to the same actual budget still
    /// differ here — the record says what was ASKED for.
    public let thinkBudget: Int
    public let seed: UInt64
    public let systemPromptHash: String
    public let runtimeFlags: [String]

    // MARK: - Posture and machine

    public let modelPath: String
    public let modelBytes: Int64
    public let modelHash: String
    public let variantID: String?
    public let contextSize: Int
    /// `AgentCommand.samplerRecord(settings:)` — the think decision actually
    /// wired into argv (noThink + clamped budget), rendered.
    public let sampler: String
    /// `AgentCommand.powerRecord(settings:)` — the 2026-08-30 defect, pinned.
    public let power: String
    /// The spawn-time think posture (`none` when `--nothink` is passed, else
    /// `default`) as its own comparable axis, distinct from `sampler`'s
    /// rendered string (which also carries the clamped budget, already its
    /// own field above).
    public let thinkPolicy: String
    public let tools: [String]
    public let shellAllowed: Bool
    public let hostTools: Bool
    public let workspace: String
    public let workspaceRef: String
    public let osBuild: String
    public let wiredLimitBytes: Int64
    /// Allowlisted subset of the spawn environment — see
    /// `environmentAllowlist`. The full process environment is not captured;
    /// most of it is irrelevant to what the engine does and would make every
    /// record differ trivially.
    public let environment: [String: String]
    /// Allowlisted subset of `UserDefaults` — see `userDefaultsKeys`.
    public let userDefaults: [String: String]

    // MARK: - Must-differ (expected to differ on every spawn; excluded from
    // `argv` but NOT excluded from `differingKeys` — callers comparing two
    // records for a *meaningful* difference subtract `mustDifferKeys`
    // themselves)

    public let captureDirectory: String
    public let startedAt: Date
    public let runIndex: Int

    // MARK: - Provenance / reproduction

    /// The literal argv this spawn used. Kept for provenance and
    /// reproduction, but deliberately EXCLUDED from `differingKeys(from:)` —
    /// its content is derived from the typed fields above, so a wholesale
    /// argv comparison would report a difference the typed fields already
    /// name, in a vocabulary (raw flag strings) the record does not otherwise
    /// speak.
    public let argv: [String]

    public init(
        engineSHA: String, engineDirty: Bool, engineBinaryHash: String,
        swiftstarSHA: String, swiftstarDirty: Bool, harnessBinaryHash: String,
        maxTokens: Int, thinkBudget: Int, seed: UInt64, systemPromptHash: String, runtimeFlags: [String],
        modelPath: String, modelBytes: Int64, modelHash: String, variantID: String?,
        contextSize: Int, sampler: String, power: String, thinkPolicy: String, tools: [String],
        shellAllowed: Bool, hostTools: Bool, workspace: String, workspaceRef: String,
        osBuild: String, wiredLimitBytes: Int64, environment: [String: String], userDefaults: [String: String],
        captureDirectory: String, startedAt: Date, runIndex: Int,
        argv: [String]
    ) {
        self.engineSHA = engineSHA
        self.engineDirty = engineDirty
        self.engineBinaryHash = engineBinaryHash
        self.swiftstarSHA = swiftstarSHA
        self.swiftstarDirty = swiftstarDirty
        self.harnessBinaryHash = harnessBinaryHash
        self.maxTokens = maxTokens
        self.thinkBudget = thinkBudget
        self.seed = seed
        self.systemPromptHash = systemPromptHash
        self.runtimeFlags = runtimeFlags
        self.modelPath = modelPath
        self.modelBytes = modelBytes
        self.modelHash = modelHash
        self.variantID = variantID
        self.contextSize = contextSize
        self.sampler = sampler
        self.power = power
        self.thinkPolicy = thinkPolicy
        self.tools = tools
        self.shellAllowed = shellAllowed
        self.hostTools = hostTools
        self.workspace = workspace
        self.workspaceRef = workspaceRef
        self.osBuild = osBuild
        self.wiredLimitBytes = wiredLimitBytes
        self.environment = environment
        self.userDefaults = userDefaults
        self.captureDirectory = captureDirectory
        self.startedAt = startedAt
        self.runIndex = runIndex
        self.argv = argv
    }

    /// Environment variables that change what a spawn resolves to (model
    /// selection, engine location, skills root) — see `AgentDefaultSettings`
    /// and `VariantRegistry`. Not the full process environment: most of it
    /// (`PATH`, `HOME`, ...) is spawn-irrelevant and would make every record
    /// differ trivially.
    public static let environmentAllowlist: [String] = [
        "DS4_DIR",
        "SUPERPOWERS_SKILLS_DIR",
        "SWIFTSTAR_MODEL",
        "SWIFTSTAR_DEFAULT_MODEL",
        "SWIFTSTAR_MODEL_DIR",
        "SWIFTSTAR_MELLUM_MODEL",
        "SWIFTSTAR_LAGUNA_XS_MODEL",
        "SWIFTSTAR_LAGUNA_S_MODEL",
        "SWIFTSTAR_DEEPSEEK_V4_FLASH_MODEL",
    ]

    /// `UserDefaults` keys that change spawn or dispatch behavior.
    /// `dispatchDumb` is read inside the wire loop and changes admission
    /// behavior, so it is an arm axis even though it never touches argv.
    public static let userDefaultsKeys: [String] = [
        "dispatchDumb", "sessionCaptureEnabled", "subagentPoolSize",
    ]

    /// Fields expected to differ on every spawn, even between two spawns of
    /// otherwise-identical configuration. `differingKeys(from:)` still
    /// reports them like any other field; a caller building a "did the
    /// CONFIGURATION change" check (e.g. a future `ArmDiff`) subtracts this
    /// set itself.
    public static let mustDifferKeys: Set<String> = ["captureDirectory", "startedAt", "runIndex"]

    /// Build a record from already-resolved facts. Pure: no process spawn, no
    /// file read, no network. Every SHA/hash/OS-build/limit is supplied by the
    /// caller, who resolved it however that's done at the call site (this
    /// type does not know how, and per the fast-tier rule for
    /// `SwiftStarKit`, must not find out).
    /// `argv` overrides the default `AgentCommand.argv(settings:)` — a
    /// pooled caller (`PoolEngine.argv`, `SwiftStarAppKit`; not a dependency
    /// of this Kit target) spawns with `--subagent-pool <N>` appended, and
    /// this record's own `argv` must reflect what the process actually ran
    /// with, or a caller reading it back (a capture's `provenance.md`, an
    /// eval arm's `SpawnRecord`) would believe a pooled spawn was a plain
    /// one. nil (every existing call site) keeps `argv` exactly as before.
    public static func from(
        settings: AgentSettings,
        engineSHA: String, engineDirty: Bool, engineBinaryHash: String,
        swiftstarSHA: String, swiftstarDirty: Bool, harnessBinaryHash: String,
        systemPromptHash: String,
        modelBytes: Int64, modelHash: String, variantID: String?,
        tools: [String], osBuild: String, wiredLimitBytes: Int64,
        workspaceRef: String,
        environment: [String: String], userDefaults: [String: String],
        captureDirectory: String, startedAt: Date, runIndex: Int,
        argv: [String]? = nil
    ) -> SpawnRecord {
        SpawnRecord(
            engineSHA: engineSHA, engineDirty: engineDirty, engineBinaryHash: engineBinaryHash,
            swiftstarSHA: swiftstarSHA, swiftstarDirty: swiftstarDirty, harnessBinaryHash: harnessBinaryHash,
            maxTokens: settings.maxTokens, thinkBudget: settings.thinkBudget,
            seed: settings.seed, systemPromptHash: systemPromptHash,
            runtimeFlags: settings.runtime?.argvFlags ?? [],
            modelPath: settings.modelPath.path, modelBytes: modelBytes, modelHash: modelHash, variantID: variantID,
            contextSize: settings.contextSize,
            sampler: AgentCommand.samplerRecord(settings: settings),
            power: AgentCommand.powerRecord(settings: settings),
            thinkPolicy: settings.noThink ? "none" : "default",
            tools: tools, shellAllowed: settings.shellAllowed, hostTools: true,
            workspace: settings.workspace.path, workspaceRef: workspaceRef,
            osBuild: osBuild, wiredLimitBytes: wiredLimitBytes,
            environment: environment, userDefaults: userDefaults,
            captureDirectory: captureDirectory, startedAt: startedAt, runIndex: runIndex,
            argv: argv ?? AgentCommand.argv(settings: settings))
    }

    /// The `provenance.md` facts this record backs — `AgentController`'s live
    /// session and any later capture-writing caller share this instead of
    /// each re-deriving the same lines from raw settings.
    public var provenanceFacts: [CaptureProvenance.Fact] {
        [
            .init("Model", "`\(URL(fileURLWithPath: modelPath).lastPathComponent)`"),
            .init("Build (`external/ds4` SHA)", "`\(engineSHA)`"),
            .init("Context", "\(contextSize)"),
            .init("Sampler", sampler),
            // The engine throttle is a spawn SETTING (`--power`), not a
            // measurement. Unrecorded, it turned a throttled app session and
            // an unthrottled drive re-run into an apparent 1.7x engine
            // speedup (see AgentCommand.powerRecord).
            .init("Power", power),
            .init("Workspace", "`\(workspace)`"),
            CaptureProvenance.startedAtFact(startedAt),
        ]
    }

    /// Swift property names (one vocabulary; this record is the authority —
    /// not wire keys, not argv flag names) that differ between `self` and
    /// `other`. `argv` is deliberately excluded — see its doc comment.
    public func differingKeys(from other: SpawnRecord) -> Set<String> {
        var keys: Set<String> = []
        if engineSHA != other.engineSHA { keys.insert("engineSHA") }
        if engineDirty != other.engineDirty { keys.insert("engineDirty") }
        if engineBinaryHash != other.engineBinaryHash { keys.insert("engineBinaryHash") }
        if swiftstarSHA != other.swiftstarSHA { keys.insert("swiftstarSHA") }
        if swiftstarDirty != other.swiftstarDirty { keys.insert("swiftstarDirty") }
        if harnessBinaryHash != other.harnessBinaryHash { keys.insert("harnessBinaryHash") }
        if maxTokens != other.maxTokens { keys.insert("maxTokens") }
        if thinkBudget != other.thinkBudget { keys.insert("thinkBudget") }
        if seed != other.seed { keys.insert("seed") }
        if systemPromptHash != other.systemPromptHash { keys.insert("systemPromptHash") }
        if runtimeFlags != other.runtimeFlags { keys.insert("runtimeFlags") }
        if modelPath != other.modelPath { keys.insert("modelPath") }
        if modelBytes != other.modelBytes { keys.insert("modelBytes") }
        if modelHash != other.modelHash { keys.insert("modelHash") }
        if variantID != other.variantID { keys.insert("variantID") }
        if contextSize != other.contextSize { keys.insert("contextSize") }
        if sampler != other.sampler { keys.insert("sampler") }
        if power != other.power { keys.insert("power") }
        if thinkPolicy != other.thinkPolicy { keys.insert("thinkPolicy") }
        if tools != other.tools { keys.insert("tools") }
        if shellAllowed != other.shellAllowed { keys.insert("shellAllowed") }
        if hostTools != other.hostTools { keys.insert("hostTools") }
        if workspace != other.workspace { keys.insert("workspace") }
        if workspaceRef != other.workspaceRef { keys.insert("workspaceRef") }
        if osBuild != other.osBuild { keys.insert("osBuild") }
        if wiredLimitBytes != other.wiredLimitBytes { keys.insert("wiredLimitBytes") }
        if environment != other.environment { keys.insert("environment") }
        if userDefaults != other.userDefaults { keys.insert("userDefaults") }
        if captureDirectory != other.captureDirectory { keys.insert("captureDirectory") }
        if startedAt != other.startedAt { keys.insert("startedAt") }
        if runIndex != other.runIndex { keys.insert("runIndex") }
        return keys
    }

    /// The element-wise difference between this record's `argv` and
    /// `other`'s, as `"self:X vs other:Y"`/`"self:X vs other:<missing>"`/
    /// `"other:Y vs self:<missing>"` entries in index order. Exists only so a
    /// later `ArmDiff` refusal message can be concrete about what changed on
    /// the actual command line, without `differingKeys` ever guarding on
    /// `argv` wholesale.
    public func argvElementDiff(from other: SpawnRecord) -> [String] {
        var diffs: [String] = []
        let count = Swift.max(argv.count, other.argv.count)
        for i in 0..<count {
            let mine = i < argv.count ? argv[i] : nil
            let theirs = i < other.argv.count ? other.argv[i] : nil
            if mine != theirs {
                diffs.append("[\(i)] \(mine ?? "<missing>") vs \(theirs ?? "<missing>")")
            }
        }
        return diffs
    }
}
