import Foundation

/// One arm's already-read capture contents. Pure value: the caller does the
/// file I/O (reading `wire.ndjson`/`agent.trace`/`wire.trace` from a capture
/// directory) and hands the text in — `SwiftStarKit` is the fast test tier
/// (no processes, no sockets, no file I/O; a build tripwire enforces this),
/// so nothing in this file may open a file itself.
public struct CaptureTree: Equatable, Sendable {
    public let armID: String
    public let traceText: String
    public let wireText: String

    public init(armID: String, traceText: String, wireText: String) {
        self.armID = armID
        self.traceText = traceText
        self.wireText = wireText
    }
}

/// One pair's paired-bill comparison: each arm's Σsuffix and the delta
/// between them. The only additively meaningful trace metric — see
/// `cmdDiff`'s comment in `swiftstar-analyze` — is Σsuffix; Σprompt is
/// cumulative across tool rounds and double-counts.
public struct PairResult: Equatable, Sendable {
    public let pair: Int
    public let controlSuffix: Int
    public let treatmentSuffix: Int
    public let delta: Int

    public init(pair: Int, controlSuffix: Int, treatmentSuffix: Int, delta: Int) {
        self.pair = pair
        self.controlSuffix = controlSuffix
        self.treatmentSuffix = treatmentSuffix
        self.delta = delta
    }
}

/// Why a pair was dropped whole. A pair is the unit of evidence in a paired
/// design — one arm alone says nothing about the delta the experiment
/// exists to measure, so a drop names the pair and both would-be readings
/// are discarded together, not just the unusable one.
public enum PairDrop: Error, Equatable {
    case unusable(arm: String, reason: String)
}

/// Reduces two capture trees (one pair, two arms) to a single paired delta.
/// Moved out of `swiftstar-analyze`'s `cmdDiff` (P24's guardrail) so the CLI
/// verb and a future `swiftstar-eval` run share one implementation instead of
/// two copies drifting apart.
public enum PairBill {
    /// Σsuffix over a `--trace` file's text — the engine's own reported
    /// `suffix` field on every `prefill sync done` line, summed. Delegates to
    /// `TraceSummary.sum(traceText:)`, which already does exactly this;
    /// `PairBill` does not re-derive the parse.
    public static func suffixTotal(trace: String) -> Int {
        TraceSummary.sum(traceText: trace).sumSuffix
    }

    /// Reduce one pair. Either arm recording no work drops the whole pair —
    /// see `PairDrop`'s doc comment — checked before either Σsuffix is even
    /// computed, so a dropped pair never contributes a lone reading.
    public static func reduce(
        pair: Int, control: CaptureTree, treatment: CaptureTree
    ) -> Result<PairResult, PairDrop> {
        guard isUsable(control) else {
            return .failure(.unusable(arm: control.armID, reason: "wire records no work"))
        }
        guard isUsable(treatment) else {
            return .failure(.unusable(arm: treatment.armID, reason: "wire records no work"))
        }
        let controlSuffix = suffixTotal(trace: control.traceText)
        let treatmentSuffix = suffixTotal(trace: treatment.traceText)
        return .success(PairResult(
            pair: pair, controlSuffix: controlSuffix, treatmentSuffix: treatmentSuffix,
            delta: treatmentSuffix - controlSuffix))
    }

    private static func isUsable(_ tree: CaptureTree) -> Bool {
        let lines = tree.wireText.split(whereSeparator: \.isNewline).map(String.init)
        return CaptureUsability.recordsWork(wireLines: lines)
    }
}
