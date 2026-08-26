import Foundation

/// Split a spec (or a model's decompose reply) on `## Phase` headers (P12.5,
/// D2). The text before the first phase (the title, intro, and any shared
/// "data model" section) is returned as the `preamble`, and is prepended to
/// every packet so shared contract facts reach the worker even though they are
/// not phase text.
///
/// **The offset-0 fix.** The split key is `"\n## Phase "` — a phase heading
/// preceded by a newline. Every host spec fixture already opens with a title
/// line before its first `## Phase` heading, so that leading `"\n"` is already
/// present in the text and the split "just works" for them. A model's
/// decompose reply is the one shape that breaks this: the single most likely
/// reply opens directly with `"## Phase 1: …"`, with nothing — not even a
/// newline — before it. Splitting on `"\n## Phase "` then finds no match at
/// all for a single-phase reply (0 phases, not 1), or drops the reply's first
/// phase into `preamble` for a multi-phase reply (the boundary before phase 1
/// is invisible to the splitter, but the boundary before phase 2 is not). This
/// is normalized by prepending a single `"\n"` **only when the text already
/// begins with `"## Phase "`** — i.e. only in the exact offset-0 case that
/// needs it. A text that opens with a title line (every host spec) does not
/// begin with `"## Phase "` and is left untouched, so the split point the
/// splitter finds is byte-identical to today's output.
///
/// (The P12.5 design doc's own prose states the guard the other way around —
/// "prepend only when the text does *not* already begin with `## Phase `" —
/// but that reading is self-contradicting: applied literally, it leaves the
/// offset-0 bug it exists to fix completely unfixed (a bare `"## Phase 1: …"`
/// reply still parses to 0 phases, since nothing gets prepended to it), while
/// prepending a stray leading `"\n"` to every ordinary spec's preamble instead
/// — exactly the regression round 2 of the design's own review flagged. The
/// guard implemented here is the one that actually satisfies both of the
/// design's own stated outcomes: the offset-0 reply gets 1 phase, and every
/// existing host spec fixture's `(preamble, phases)` output is unchanged.)
public func decompose(_ text: String) -> (preamble: String, phases: [String]) {
    let normalized = text.hasPrefix("## Phase ") ? "\n" + text : text
    let parts = normalized.components(separatedBy: "\n## Phase ")
    let preamble = parts.first ?? ""
    let phases = parts.dropFirst().map { "## Phase " + $0 }
    return (preamble, phases)
}

/// The decompose role's follow-up/fail-closed decision (P12.5, D3), extracted
/// as a pure function of one turn's shape so it is unit-testable without a
/// real engine. Mirrors `TextContractHarvest.run`'s two-turn shape (harvest,
/// then one emission follow-up before giving up) without any of its file-block
/// parsing — decompose's deliverable is prose phase headings, not files.
public enum DecomposeDecision: Equatable, Sendable {
    /// The text parsed into at least one phase; these replace the host split's
    /// `phases` for the run (the host's `preamble` is kept regardless — D1).
    case parsed(phases: [String])
    /// Zero phases parsed on the first turn, but the turn's shape (stopped at
    /// `.eos` with non-blank text) suggests the model reasoned instead of
    /// emitting — send exactly one follow-up turn before giving up (D3), the
    /// same reason-then-stop protection P15 needed for the repair/build arms.
    case needsFollowUp
    /// Zero phases parsed with no follow-up left to try — either this already
    /// *is* the follow-up's result, or the first turn's shape doesn't fit the
    /// reason-then-stop pattern (blank text, or a stop reason other than
    /// `.eos`, e.g. a session-exhaustion stop that a follow-up turn could not
    /// recover from anyway). This is model failure #1 (D2): the run fails
    /// closed, no fallback to the host split.
    case failedClosed
}

public enum DecomposeDispatch {
    /// Decide what to do with one decompose turn's raw text. `isFollowUp` is
    /// `true` only when evaluating the *second* turn (the emission follow-up
    /// already ran) — a second zero-phase result always fails closed, never
    /// requests a third turn.
    public static func decide(text: String, stopReason: TurnStopReason, isFollowUp: Bool) -> DecomposeDecision {
        let (_, phases) = decompose(text)
        if !phases.isEmpty { return .parsed(phases: phases) }
        if isFollowUp { return .failedClosed }
        guard stopReason == .eos, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failedClosed
        }
        return .needsFollowUp
    }
}

/// The `role: .decompose` packet itself (P12.5, D1). Built directly as a
/// `HandoffPacket` — not via `PhasePacketBuilder.build`, which requires a
/// non-optional `validationCommand` and whose downstream (`TextContractHarvest`
/// / `LabeledBlockParser`) requires a non-empty `writableFiles` to harvest
/// anything, neither of which applies to a mutation-free query turn.
///
/// **Exempt from `HandoffPacketValidator.validate` by construction (D1):** the
/// validator itself rejects `writableFiles.isEmpty` and a `nil`
/// `validationCommand` (see `HandoffPacketValidatorTests`), so a decompose
/// packet built here would *always* fail that gate — it must never be passed
/// to it. No call site in `swiftstar-agenttest/main.swift` does.
///
/// Lives in `SwiftStarKit` (rather than alongside `repairPacket` in
/// `main.swift`, which the design doc suggested mirroring the *shape* of) so
/// the packet's shape is unit-testable from `SwiftStarKitTests` — an
/// executable target's `main.swift` top-level code cannot be `@testable
/// import`ed, so the pure builder has to live in the library target for the
/// test plan's "packet is built directly with `writableFiles: []`" bullet to
/// be a real test rather than an unverified claim.
public enum DecomposePacket {
    /// The one-shot decompose directive: read the full spec text (embedded
    /// directly in `taskText`, not fetched via a `read` tool call — a
    /// one-shot prose-in/prose-out turn has no reason to depend on a tool
    /// round trip for input that fits directly in the prompt) and re-emit it
    /// as `## Phase <N>: <title>` blocks.
    ///
    /// `turnBudget`/`toolCallBudget` are smaller than an implement packet's
    /// (100,000 / typically 30): decompose neither writes files nor needs
    /// that generation headroom, so a smaller sensible default is used
    /// instead of copying the implement packet's budget verbatim — a
    /// judgment call, since the design doc left the exact numbers to the
    /// implementer ("match... or a smaller sensible default — your call").
    public static func build(specText: String) -> HandoffPacket {
        let directive = ([
            "You are the decompose role. Read the specification text below in",
            "full, then re-emit it as one or more phase blocks. Each phase block",
            "starts with a heading line in exactly this form:",
            "\"## Phase <N>: <short title>\" (N starting at 1, counting up),",
            "followed by a short task description of what that phase must",
            "accomplish. Preserve every requirement in the specification —",
            "reorganize it into phases, but do not drop, merge away, or invent",
            "requirements.",
            "Emit only the phase blocks. Do not call any tool, do not write any",
            "file, and do not include any text before the first heading or after",
            "the last phase's description.",
        ]).joined(separator: " ")
        let taskText = ([directive, "Specification:", specText]).joined(separator: "\n\n")
        return HandoffPacket(
            taskText: taskText,
            writableFiles: [],
            validationCommand: nil,
            selfTestCommand: nil,
            baselines: [:],
            turnBudget: 20_000,
            toolCallBudget: 5,
            textContract: false,
            facts: [],
            redacts: [],
            role: .decompose,
            sampling: SamplingPolicy())
    }

    /// Turn 2 of decompose's own two-turn emission protocol (D3) — mirrors
    /// `repairEmissionFollowUp`'s role in `main.swift`, scaled to decompose's
    /// prose-only shape. Sent on the same worker/session so the model
    /// continues rather than re-deriving.
    public static let emissionFollowUpText =
        "Stop reasoning. Emit the phase headings now, in the exact format requested, nothing else."

    public static func followUp() -> HandoffPacket {
        HandoffPacket(
            taskText: emissionFollowUpText,
            writableFiles: [],
            validationCommand: nil,
            selfTestCommand: nil,
            baselines: [:],
            turnBudget: 20_000,
            toolCallBudget: 5,
            textContract: false,
            facts: [],
            redacts: [],
            role: .decompose,
            sampling: SamplingPolicy())
    }
}
