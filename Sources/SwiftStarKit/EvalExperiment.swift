import Foundation

/// One arm of a paired A/B: an identifier and the `SpawnRecord`-shaped
/// overrides it applies over `EvalExperiment.common`. Kept as a flat
/// dictionary rather than a partial `SpawnRecord` because most fields are
/// never varied by any experiment — see `EvalValue`.
public struct Arm: Codable, Equatable, Sendable {
    public let id: String
    public let overrides: [String: EvalValue]

    public init(id: String, overrides: [String: EvalValue]) {
        self.id = id
        self.overrides = overrides
    }
}

/// The handful of JSON scalar shapes a spawn override actually needs.
/// `EvalExperiment`'s committed file speaks in these, not raw `Any` — every
/// value round-trips through exactly one case, so a caller building a spawn
/// from `common`/`overrides` never has to guess a dynamic type.
public enum EvalValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case list([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let l = try? container.decode([String].self) {
            self = .list(l)
        } else {
            throw DecodingError.typeMismatch(
                EvalValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "unsupported EvalValue shape"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .bool(let b): try container.encode(b)
        case .list(let l): try container.encode(l)
        }
    }

    /// This value's shape, without the payload — lets
    /// `EvalExperiment.overrideKeyVocabulary` describe which shapes an
    /// override key accepts without constructing a dummy value of each.
    public var kind: EvalValueKind {
        switch self {
        case .string: return .string
        case .int: return .int
        case .bool: return .bool
        case .list: return .list
        }
    }
}

/// The four `EvalValue` shapes, named. See `EvalValue.kind`.
public enum EvalValueKind: String, Sendable {
    case string, int, bool, list
}

/// Which `AgentCommand` shape a spawn uses. Not the model, not the tools —
/// just the harness entry point (`swiftstar-drive`'s bare loop, the app's
/// chat session, `quick`, or `orchestrate`).
public enum EvalMode: String, Codable, Equatable, Sendable {
    case bare, chat, quick, orchestrate
}

/// Why a committed experiment file was refused. Every case is a decision
/// `EvalExperiment.parse` made about the file's own content — never about
/// the runtime facts `ArmDiff` checks (those come from a live `SpawnRecord`,
/// long after the file has already been trusted or not).
public enum EvalExperimentError: Error, Equatable {
    /// The file declared more than one axis under `variable`. An A/B design
    /// varies exactly one thing; two declared variables is not a smaller
    /// mistake than an undeclared one, it is the same mistake `ArmDiff`
    /// exists to catch, moved earlier — before any arm has been spawned.
    case multipleVariables([String])
    case tooFewPairs(Int)
    /// `variable` named something that is not an actual `SpawnRecord`
    /// property (and not the special-cased `"gitRef"`). Without this gate a
    /// typo'd variable — `"hosttools"` for `"hostTools"` — would parse, and
    /// `ArmDiff.admit` would then refuse every run with a message that names
    /// the *real* property instead of the typo, which is a much later and
    /// much more confusing place to discover the mistake.
    case unknownVariable(String)
    case unknownMode(String)
    /// `runOrder()` derives seeds from `name` and the pair index — the one
    /// place a seed is decided. A file that also declares `variable: "seed"`
    /// would let two things set the same axis, and whichever set it last
    /// would silently win.
    case seedIsNotAnAxis
    /// `SpawnRecord.differingKeys(from:)` deliberately never emits `"argv"`
    /// (see its doc comment) — it is derived from the typed fields, not an
    /// axis of its own. A file that declared `variable: "argv"` would still
    /// PARSE, and then `ArmDiff.admit` would refuse every run (nothing ever
    /// differs by the literal key `"argv"`) with a message that never
    /// mentions argv, which is a much later and much more confusing place to
    /// discover the mistake. argv is recorded, for provenance, but never
    /// diffed wholesale — the axes to declare instead are the typed fields it
    /// is built from: `maxTokens`, `thinkBudget`, `seed`, `systemPromptHash`,
    /// `runtimeFlags` (or the specific flag's own field, where one exists).
    case argvIsNotAnAxis
    /// `variable == "gitRef"` (fable-fixes review, F2): per-arm engine
    /// builds are not implemented — every arm resolves its engine from the
    /// SAME `DS4_DIR` (`ExperimentVerb.swift`'s `engineDir`), so there is no
    /// way for two arms of one `swiftstar-eval experiment` invocation to
    /// actually run different engine builds. The design's own `ArmDiff`
    /// gitRef path only ever fires this refusal when `swiftstarSHA` differs,
    /// which cannot happen within one invocation either — so admitting
    /// `variable: "gitRef"` here was a check that could never fail, not a
    /// guard. Refused outright instead: comparing two engine builds needs
    /// two separate invocations, not one experiment file.
    case gitRefNotSupported
    /// `common`/`arm.overrides` named a key with no settable `AgentSettings`
    /// input — see `EvalExperiment.overrideKeyVocabulary`. Without this gate
    /// `applyOverride`'s old `default: break` silently dropped it: an
    /// experiment written straight from this design's own example doc used
    /// `ctx`, `shell`, `hostTools`, `variant`, `gitRef` — none recognized —
    /// and ran both arms at their defaults, admitted as if the treatment had
    /// applied (fable-fixes review, F1). `context` names where the bad key
    /// was declared (`"common"`, or `"arm \"<id>\""`).
    case unknownOverrideKey(key: String, context: String, accepted: [String])
    /// The key IS in `overrideKeyVocabulary`, but the JSON value's shape does
    /// not match what `applyOverride` requires for it (e.g.
    /// `"contextSize": "big"` where an int is required) — the other half of
    /// F1's silent-drop: `applyOverride`'s per-case `if case ... = value`
    /// pattern match fails silently on a type mismatch exactly like an
    /// unrecognized key does.
    case mistypedOverrideValue(key: String, context: String, accepted: [String])
}

/// The committed pre-registration for one `swiftstar-eval` run: what is being
/// compared, what would falsify the claim, and exactly one declared axis of
/// difference. `ArmDiff` enforces that axis against what actually spawned;
/// this type is the gate that the *declaration itself* is sane — one
/// variable, a real property name, enough pairs to say anything.
///
/// Pure: no process spawn, no file I/O — `parse` takes already-read `Data`,
/// per `SwiftStarKit`'s fast-tier contract.
public struct EvalExperiment: Codable, Equatable, Sendable {
    public let name: String
    public let question: String
    public let falsifier: String
    public let variable: String
    public let pairs: Int
    public let mode: EvalMode
    public let promptFile: String
    public let captureSelection: String
    public let arms: [Arm]
    public let common: [String: EvalValue]

    public init(
        name: String, question: String, falsifier: String, variable: String, pairs: Int,
        mode: EvalMode, promptFile: String, captureSelection: String,
        arms: [Arm], common: [String: EvalValue]
    ) {
        self.name = name
        self.question = question
        self.falsifier = falsifier
        self.variable = variable
        self.pairs = pairs
        self.mode = mode
        self.promptFile = promptFile
        self.captureSelection = captureSelection
        self.arms = arms
        self.common = common
    }

    public static let defaultPairs = 5
    public static let minimumPairs = 3

    /// `variable` is free-form text in the committed file — `ArmDiff` takes
    /// it as-is and never checks it against the real API. This is the one
    /// place that does: the Swift property names `SpawnRecord.differingKeys`
    /// actually uses, plus `"gitRef"` (the engine-ref special case
    /// `ArmDiff.engineBuildKeys` covers). `seed` and `argv` are deliberately
    /// absent — see `EvalExperimentError.seedIsNotAnAxis` and
    /// `.argvIsNotAnAxis`.
    static let spawnRecordProperties: Set<String> = [
        "engineSHA", "engineDirty", "engineBinaryHash",
        "swiftstarSHA", "swiftstarDirty", "harnessBinaryHash",
        "maxTokens", "thinkBudget", "systemPromptHash", "runtimeFlags",
        "modelPath", "modelBytes", "modelHash", "variantID", "contextSize",
        "sampler", "power", "thinkPolicy", "tools", "shellAllowed", "hostTools",
        "workspace", "workspaceRef", "osBuild", "wiredLimitBytes",
        "environment", "userDefaults", "captureDirectory", "startedAt",
        "runIndex",
    ]

    /// Accepted `common`/`arm.overrides` keys, and the `EvalValueKind`s each
    /// one accepts — `applyOverride`'s own vocabulary
    /// (`Sources/swiftstar-eval/ExperimentVerb.swift`), reproduced here so
    /// `parse` can enforce it BEFORE any arm runs (fable-fixes review, F1).
    /// `applyOverride`'s old `default: break` silently dropped anything
    /// outside this set — an unknown key, or a recognized key with the wrong
    /// JSON shape — which is how an experiment written straight from this
    /// design's own (since-corrected) example doc ran both arms at their
    /// defaults and was admitted as a valid comparison.
    ///
    /// Note this is a DIFFERENT, smaller vocabulary than
    /// `spawnRecordProperties` above: that one names every property `ArmDiff`
    /// can compare (including pure outputs of a spawn — SHAs, hashes,
    /// `osBuild` — that no override can ever set); this one names only the
    /// properties an override actually has a settable input for.
    ///
    /// `workspace` (`RunWorkspace`-managed, never an override), `hostTools`
    /// (always on — `AgentCommand.argv` passes it unconditionally, no
    /// per-spawn toggle exists) and `gitRef` (per-arm engine builds are not
    /// implemented — see `EvalExperimentError.gitRefNotSupported`) are
    /// deliberately absent: declaring any of them today would silently do
    /// nothing, the exact defect this vocabulary exists to catch.
    public static let overrideKeyVocabulary: [String: Set<EvalValueKind>] = [
        "tools": [.list],
        "power": [.bool, .string, .int],
        "maxTokens": [.int],
        "thinkBudget": [.int],
        "contextSize": [.int],
        "modelPath": [.string],
        "shellAllowed": [.bool, .string],
        "thinkPolicy": [.string],
    ]

    /// Refuses any key in `overrides` that is not in `overrideKeyVocabulary`,
    /// or whose value's shape does not match what that key accepts.
    /// `context` names where `overrides` came from (`"common"`, or
    /// `"arm \"<id>\""`) for the thrown error's message.
    private static func validateOverrides(_ overrides: [String: EvalValue], context: String) throws {
        for key in overrides.keys.sorted() {
            let value = overrides[key]!
            guard let acceptedKinds = overrideKeyVocabulary[key] else {
                throw EvalExperimentError.unknownOverrideKey(
                    key: key, context: context, accepted: overrideKeyVocabulary.keys.sorted())
            }
            guard acceptedKinds.contains(value.kind) else {
                throw EvalExperimentError.mistypedOverrideValue(
                    key: key, context: context,
                    accepted: acceptedKinds.map(\.rawValue).sorted())
            }
        }
    }

    /// Either a single declared axis, or — when the file mistakenly lists
    /// more than one — the list itself, so `parse` can report exactly what
    /// was declared instead of a generic type-mismatch.
    private enum VariableField: Decodable {
        case one(String)
        case many([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                self = .one(s)
                return
            }
            if let list = try? container.decode([String].self) {
                self = .many(list)
                return
            }
            throw DecodingError.typeMismatch(
                VariableField.self,
                .init(codingPath: decoder.codingPath, debugDescription: "variable must be a string or an array of strings"))
        }
    }

    private struct RawFile: Decodable {
        let name: String
        let question: String
        let falsifier: String
        let variable: VariableField
        let pairs: Int?
        let mode: String
        let promptFile: String
        let captureSelection: String
        let arms: [Arm]
        let common: [String: EvalValue]?
    }

    /// Parse and validate a committed experiment file. `exploratory` lowers
    /// the pair floor to 1 — an exploratory run makes no causal claim (see
    /// `EvalReport`'s `NOT A CAUSAL CLAIM` stamp), so it does not need enough
    /// pairs to state a same-sign-by-chance figure.
    public static func parse(_ data: Data, exploratory: Bool) throws -> EvalExperiment {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)

        let variable: String
        switch raw.variable {
        case .many(let declared):
            throw EvalExperimentError.multipleVariables(declared)
        case .one(let declared):
            variable = declared
        }

        guard let mode = EvalMode(rawValue: raw.mode) else {
            throw EvalExperimentError.unknownMode(raw.mode)
        }

        guard variable != "seed" else {
            throw EvalExperimentError.seedIsNotAnAxis
        }
        guard variable != "argv" else {
            throw EvalExperimentError.argvIsNotAnAxis
        }
        guard variable != "gitRef" else {
            throw EvalExperimentError.gitRefNotSupported
        }
        guard spawnRecordProperties.contains(variable) else {
            throw EvalExperimentError.unknownVariable(variable)
        }

        try validateOverrides(raw.common ?? [:], context: "common")
        for arm in raw.arms {
            try validateOverrides(arm.overrides, context: "arm \"\(arm.id)\"")
        }

        let pairs = raw.pairs ?? defaultPairs
        let minimum = exploratory ? 1 : minimumPairs
        guard pairs >= minimum else {
            throw EvalExperimentError.tooFewPairs(pairs)
        }

        return EvalExperiment(
            name: raw.name, question: raw.question, falsifier: raw.falsifier,
            variable: variable, pairs: pairs, mode: mode,
            promptFile: raw.promptFile, captureSelection: raw.captureSelection,
            arms: raw.arms, common: raw.common ?? [:])
    }

    /// FNV-1a over `"<name>#<pair>"` — deterministic across processes and
    /// across Swift versions, unlike `Hashable`/`hashValue`, which is salted
    /// per-process and would make a committed file's run order unreproducible
    /// from one invocation to the next.
    private static func seed(name: String, pair: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(name)#\(pair)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The spawn order for the whole experiment: ABBA across pairs, both
    /// arms of a pair sharing one seed. Odd pairs run `[arms[0], arms[1]]`;
    /// even pairs run the reverse — counterbalancing so a systematic drift
    /// over the session (thermal throttling, memory pressure) does not fall
    /// entirely on one arm. Seeds come from `name` and the pair index alone,
    /// so the committed file — not wall-clock time, not process state — is
    /// the whole determinant of the run order.
    public func runOrder() -> [(pair: Int, armID: String, seed: UInt64)] {
        guard arms.count == 2 else { return [] }
        let first = arms[0]
        let second = arms[1]
        var order: [(pair: Int, armID: String, seed: UInt64)] = []
        for p in 1...pairs {
            let s = Self.seed(name: name, pair: p)
            let sequence = p.isMultiple(of: 2) ? [second, first] : [first, second]
            for arm in sequence {
                order.append((pair: p, armID: arm.id, seed: s))
            }
        }
        return order
    }

    /// The human-readable pre-registration: what is being asked, and what
    /// would falsify it, committed before any arm runs.
    public var preregistration: String {
        """
        \(name)

        Question: \(question)
        Falsifier: \(falsifier)
        Variable: \(variable)
        Pairs: \(pairs)
        Mode: \(mode.rawValue)
        """
    }
}
