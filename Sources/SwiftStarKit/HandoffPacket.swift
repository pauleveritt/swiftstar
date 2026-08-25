import Foundation

/// One file's line-ending classification, read from the worktree at dispatch
/// time (D1). `lf` = only LF; `crlf` = only CRLF; `mixed` = both present. A
/// `String`-raw `Codable` so a serialized `FileBaseline` stays human-readable.
public enum LineEnding: String, Codable, Equatable, Sendable, CaseIterable {
    case lf
    case crlf
    case mixed
}

/// One file's baseline at dispatch time (D1): the SHA-256 of its bytes, its
/// line-ending classification, and its Unix mode bits — each read from the
/// worktree, never guessed. The dispatcher revision-checks mutations against
/// `writableFiles`; the baselines let the parent detect drift a candidate
/// introduces on files it was allowed to touch (a changed file differs from
/// its baseline). `Codable` so a `HandoffPacket` round-trips through JSON.
public struct FileBaseline: Codable, Equatable, Sendable {
    public let sha256: String
    public let lineEnding: LineEnding
    public let mode: UInt32

    public init(sha256: String, lineEnding: LineEnding, mode: UInt32) {
        self.sha256 = sha256
        self.lineEnding = lineEnding
        self.mode = mode
    }
}

/// Which pipeline role a packet is addressed to. Roles differ by their bounding
/// policy — how much deliberation is useful and how expensive failure is — not
/// by persona text.
public enum PacketRole: String, Codable, Equatable, Sendable, CaseIterable {
    case decompose
    case implement
    case repair
}

/// How much the worker is allowed to deliberate. `off` amputates reasoning
/// (cheap and reliable on fully-pinned work, but forfeits judgment), `on` is
/// unbounded, `bounded` reasons under a token ceiling. Per-packet rather than
/// per-process: a decompose packet and an implement packet want different
/// answers, and a global flag cannot express that.
public enum ThinkMode: String, Codable, Equatable, Sendable, CaseIterable {
    case off
    case on
    case bounded
}

public struct SamplingPolicy: Codable, Equatable, Sendable {
    public let think: ThinkMode
    public let maxTokens: Int
    public let temperature: Double

    public init(think: ThinkMode = .bounded, maxTokens: Int = 8192, temperature: Double = 0) {
        self.think = think
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

/// The typed handoff contract (D1): the task text, the exact writable files
/// (relative to the worktree root), the validation command the parent will
/// actually run, an optional self-test command the worker may also run (P11
/// agenttest: the worker's feedback loop — a pytest run against its own tests),
/// a per-file baseline read from the worktree, and the turn and tool-call
/// budgets. The worker gets `read`/`write`/`edit` (no `bash`) under these
/// budgets; every mutation is revision-checked against `writableFiles`.
/// `Codable` so the parent can persist and replay a dispatch.
public struct HandoffPacket: Codable, Equatable, Sendable {
    public let taskText: String
    public let writableFiles: [String]
    public let validationCommand: String?
    public let selfTestCommand: String?
    public var baselines: [String: FileBaseline]
    public let turnBudget: Int
    public let toolCallBudget: Int
    public let textContract: Bool
    /// Pinned decisions the worker must not re-derive. Ambiguity converts
    /// directly into deliberation for some models, so an unstated contract is a
    /// cost, not a neutral omission.
    public let facts: [String]
    /// Strings this packet deliberately withholds. The validator asserts none
    /// of them appear anywhere in the rendered packet — the gate that keeps an
    /// experiment cell from silently leaking its own answer.
    public let redacts: [String]
    /// Which role this packet addresses; selects the bounding policy.
    public let role: PacketRole
    /// How much deliberation this packet's worker is allowed.
    public let sampling: SamplingPolicy

    public init(taskText: String, writableFiles: [String], validationCommand: String?,
                selfTestCommand: String? = nil,
                baselines: [String: FileBaseline], turnBudget: Int, toolCallBudget: Int,
                textContract: Bool = false,
                facts: [String] = [],
                redacts: [String] = [],
                role: PacketRole = .implement,
                sampling: SamplingPolicy = SamplingPolicy()) {
        self.facts = facts
        self.role = role
        self.sampling = sampling
        self.taskText = taskText
        self.writableFiles = writableFiles
        self.validationCommand = validationCommand
        self.selfTestCommand = selfTestCommand
        self.baselines = baselines
        self.turnBudget = turnBudget
        self.toolCallBudget = toolCallBudget
        self.textContract = textContract
        self.redacts = redacts
    }

    /// Decoded by hand so a packet persisted before `facts`/`redacts` existed
    /// still replays: the synthesized conformance treats a missing key as an
    /// error, which would break every stored dispatch on the day the fields
    /// were added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskText = try container.decode(String.self, forKey: .taskText)
        writableFiles = try container.decode([String].self, forKey: .writableFiles)
        validationCommand = try container.decodeIfPresent(String.self, forKey: .validationCommand)
        selfTestCommand = try container.decodeIfPresent(String.self, forKey: .selfTestCommand)
        baselines = try container.decode([String: FileBaseline].self, forKey: .baselines)
        turnBudget = try container.decode(Int.self, forKey: .turnBudget)
        toolCallBudget = try container.decode(Int.self, forKey: .toolCallBudget)
        textContract = try container.decodeIfPresent(Bool.self, forKey: .textContract) ?? false
        facts = try container.decodeIfPresent([String].self, forKey: .facts) ?? []
        redacts = try container.decodeIfPresent([String].self, forKey: .redacts) ?? []
        role = try container.decodeIfPresent(PacketRole.self, forKey: .role) ?? .implement
        sampling = try container.decodeIfPresent(SamplingPolicy.self, forKey: .sampling) ?? SamplingPolicy()
    }
}
