/// `EvalArguments.parse`'s documented signature (Task 5's brief) returns
/// `Result<EvalInvocation, String>` — a plain message, not a typed error
/// hierarchy, since every caller (the CLI) does the same thing with it:
/// print it to stderr and exit non-zero. `@retroactive` because `String` is
/// declared in the standard library, not this module.
extension String: @retroactive Error {}

/// The verb registry shared across `swiftstar-eval`'s tasks. Pure and
/// fast-tier: no processes, no sockets, no file I/O — see `BRIEF.md`'s eval-cli
/// design decisions.
///
/// Each task that adds verbs extends `knownVerbs` rather than hand-rolling its
/// own parser: Task 6 registers the ten `swiftstar-analyze` verbs here; Task 5
/// adds `run` (this file); Task 7 adds `experiment` and `verdict`.
/// The executable target owns each verb's actual argv parsing and behavior —
/// this type only answers "is this a verb swiftstar-eval knows about", plus
/// (for verbs that declare a `FlagSpec` table below) whether a given argv is
/// shaped like that verb's documented flag set.
public enum EvalArguments {
    /// Verb names `swiftstar-eval` accepts, growing as later tasks land.
    public static let knownVerbs: Set<String> = [
        // Task 6 — moved from `swiftstar-analyze` unchanged.
        "list", "summary", "trace", "diff", "rereads",
        "findings", "taxonomy", "validate", "report", "index",
        // Task 5.
        "run",
    ]

    public static func isKnownVerb(_ name: String) -> Bool {
        knownVerbs.contains(name)
    }

    /// One accepted `--flag` for a verb with a declared spec.
    public struct FlagSpec: Equatable, Sendable {
        public let name: String
        public let takesValue: Bool
        public init(_ name: String, takesValue: Bool) {
            self.name = name
            self.takesValue = takesValue
        }
    }

    /// `swiftstar-eval run`'s documented flag set (Task 5's brief, plus the
    /// `CAPTURE_*` replacements binding rule 4 requires — see
    /// `captureEnvKnobFlags` below). A setting that lives only in an
    /// environment variable lands in no provenance (`SpawnRecord` only
    /// records the allowlisted env in `SpawnRecord.environmentAllowlist`,
    /// which `DS4_DIR` is the sole survivor of here) — this is how a
    /// `--power 70` vs `100` difference was lost and an A/B misread
    /// (`AgentCommand.powerRecord`'s doc comment).
    public static let runFlags: [FlagSpec] = [
        FlagSpec("--prompt", takesValue: true),
        FlagSpec("--mode", takesValue: true),
        FlagSpec("--variant", takesValue: true),
        FlagSpec("--gguf", takesValue: true),
        FlagSpec("--ctx", takesValue: true),
        FlagSpec("--power", takesValue: true),
        FlagSpec("--shell", takesValue: true),
        FlagSpec("--workspace", takesValue: true),
        FlagSpec("--host-tools", takesValue: false),
        FlagSpec("--per-turn-think", takesValue: false),
        FlagSpec("--seed", takesValue: true),
        FlagSpec("--tools", takesValue: true),
        FlagSpec("--dry-run", takesValue: false),
    ]

    static let verbFlagSpecs: [String: [FlagSpec]] = ["run": runFlags]

    /// Every former `CAPTURE_*` env knob (`swiftstar-drive`/
    /// `swiftstar-agenttest`), mapped to the named `run` flag that replaces
    /// it. `CAPTURE_PROMPTS_FILE` maps to `--prompt`'s own `@file` form
    /// (a run is one ad-hoc prompt, so there is no separate multi-prompt
    /// flag); `--host-tools`/`--per-turn-think` map to flags that exist for
    /// this table's sake even though `AgentSession`'s spawn already passes
    /// both unconditionally (`AgentCommand.argv`) — `run` goes down the
    /// app's own spawn path, which never had a way to turn either off.
    /// `DS4_DIR` is the one knob binding rule 4 names as surviving outside
    /// this table (it stays an env var, not a flag).
    public static let captureEnvKnobFlags: [String: String] = [
        "CAPTURE_GGUF": "--gguf",
        "CAPTURE_CTX": "--ctx",
        "CAPTURE_WORKSPACE": "--workspace",
        "CAPTURE_SHELL": "--shell",
        "CAPTURE_HOST_TOOLS": "--host-tools",
        "CAPTURE_POWER": "--power",
        "CAPTURE_PER_TURN_THINK": "--per-turn-think",
        "CAPTURE_PROMPTS_FILE": "--prompt",
    ]

    /// One parsed invocation: the verb plus its `--flag value` pairs
    /// (value-less flags map to `"true"`) and any leftover positional
    /// arguments.
    public struct EvalInvocation: Equatable, Sendable {
        public let verb: String
        public let flags: [String: String]
        public let positional: [String]
        public init(verb: String, flags: [String: String], positional: [String]) {
            self.verb = verb
            self.flags = flags
            self.positional = positional
        }
    }

    /// Parse `argv` (verb first, e.g. `["run", "--prompt", "hi"]`). A verb
    /// with no declared `FlagSpec` table (the ten analyzer verbs, which parse
    /// their own argv positionally) accepts everything as `positional` — this
    /// function only validates the verbs that opted into flag validation.
    public static func parse(_ argv: [String]) -> Result<EvalInvocation, String> {
        guard let verb = argv.first, !verb.isEmpty else {
            return .failure("swiftstar-eval: missing verb")
        }
        guard isKnownVerb(verb) else {
            return .failure("swiftstar-eval: unknown verb '\(verb)'")
        }
        let rest = Array(argv.dropFirst())
        guard let specs = verbFlagSpecs[verb] else {
            return .success(EvalInvocation(verb: verb, flags: [:], positional: rest))
        }
        var flags: [String: String] = [:]
        var positional: [String] = []
        var i = 0
        while i < rest.count {
            let token = rest[i]
            guard token.hasPrefix("--") else {
                positional.append(token)
                i += 1
                continue
            }
            guard let spec = specs.first(where: { $0.name == token }) else {
                return .failure("swiftstar-eval \(verb): unknown flag '\(token)'")
            }
            if spec.takesValue {
                guard i + 1 < rest.count else {
                    return .failure("swiftstar-eval \(verb): '\(token)' requires a value")
                }
                flags[spec.name] = rest[i + 1]
                i += 2
            } else {
                flags[spec.name] = "true"
                i += 1
            }
        }
        return .success(EvalInvocation(verb: verb, flags: flags, positional: positional))
    }
}
