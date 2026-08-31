/// The verb registry shared across `swiftstar-eval`'s tasks. Pure and
/// fast-tier: no processes, no sockets, no file I/O — see `BRIEF.md`'s eval-cli
/// design decisions.
///
/// Each task that adds verbs extends `knownVerbs` rather than hand-rolling its
/// own parser: Task 6 registers the ten `swiftstar-analyze` verbs here; Task 5
/// (landing separately) adds `run`; Task 7 adds `experiment` and `verdict`.
/// The executable target owns each verb's actual argv parsing and behavior —
/// this type only answers "is this a verb swiftstar-eval knows about".
public enum EvalArguments {
    /// Verb names `swiftstar-eval` accepts, growing as later tasks land.
    public static let knownVerbs: Set<String> = [
        // Task 6 — moved from `swiftstar-analyze` unchanged.
        "list", "summary", "trace", "diff", "rereads",
        "findings", "taxonomy", "validate", "report", "index",
    ]

    public static func isKnownVerb(_ name: String) -> Bool {
        knownVerbs.contains(name)
    }
}
