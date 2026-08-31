import Foundation

/// The outcome of a `swiftstar-eval` run, named by what happened to the
/// falsifier — never by whether the claim "held," which inverts the polarity
/// of good news: a falsifier that gets a chance to bite and doesn't is the
/// good outcome, and a name built around "held" reads that as a failure.
/// `unrecorded` is its own case (not folded into `claimSurvives`) because a
/// run that never produced enough evidence to check the falsifier is a
/// different failure than one that checked it and it survived.
public enum FalsifierVerdict: String, Codable, Equatable, Sendable {
    case unrecorded
    case claimSurvives
    case claimFalsified
}

/// Renders one `swiftstar-eval` run to a human-readable report. Every number
/// in it is additive or a count — never a ratio. A ratio (`2.2x`, `120%`) is
/// exactly the shape that turned a `--power 70` vs `100` throttle into an
/// apparent engine speedup (see `SpawnRecord`'s doc comment): a single
/// headline figure invites being read out of context, quoted without its
/// spread, or compared across runs that were never paired. Per-pair deltas
/// and their spread carry the same information without inviting that.
public enum EvalReport {
    /// `unrecorded` is deliberately not "success" — nothing was determined,
    /// so a caller (a script, a CI gate) must not treat it as a pass. `2` is
    /// the conventional "indeterminate" exit code, distinct from `0` (the
    /// falsifier had its chance and the claim survived) and `1` (the
    /// falsifier fired).
    public static func exitCode(for verdict: FalsifierVerdict) -> Int32 {
        switch verdict {
        case .unrecorded: return 2
        case .claimSurvives: return 0
        case .claimFalsified: return 1
        }
    }

    /// Number of same-sign-by-chance arrangements: with `n` paired deltas,
    /// each independently as likely to land on either side of zero, the
    /// chance every one lands on the same side as the first is
    /// `1 / 2^(n-1)` — stated so the reader is not left to compute it before
    /// judging whether "all five pairs moved the same way" is itself
    /// evidence, or just what happens one run in sixteen anyway.
    static func sameSignChance(pairCount: Int) -> Int {
        guard pairCount > 0 else { return 1 }
        return 1 << (pairCount - 1)
    }

    public static func render(
        _ experiment: EvalExperiment,
        pairs: [PairResult],
        drops: [PairDrop],
        verdict: FalsifierVerdict,
        attempt: Int,
        exploratory: Bool
    ) -> String {
        var lines: [String] = []

        lines.append("=== \(experiment.name) === (attempt \(attempt))")
        if exploratory {
            lines.append("NOT A CAUSAL CLAIM — exploratory run, below the pair floor for a paired comparison.")
        }
        lines.append("Variable: \(experiment.variable)")
        lines.append("Question: \(experiment.question)")
        lines.append("Falsifier: \(experiment.falsifier)")
        lines.append("")

        lines.append("pair  control-suffix  treatment-suffix  delta")
        for result in pairs {
            let sign = result.delta >= 0 ? "+" : ""
            lines.append(
                "pair \(result.pair)  \(result.controlSuffix)  \(result.treatmentSuffix)  \(sign)\(result.delta)")
        }
        if let min = pairs.map(\.delta).min(), let max = pairs.map(\.delta).max() {
            lines.append("spread: min \(min)  max \(max)")
        }
        lines.append("")

        let chance = sameSignChance(pairCount: pairs.count)
        lines.append("Same-sign deltas by chance alone: 1 in \(chance), for \(pairs.count) pair(s).")
        lines.append("")

        if drops.isEmpty {
            lines.append("Dropped pairs: none.")
        } else {
            lines.append("Dropped pairs:")
            for drop in drops {
                switch drop {
                case .unusable(let arm, let reason):
                    lines.append("  arm \(arm): \(reason)")
                }
            }
        }
        lines.append("")

        if exploratory {
            lines.append("NOT A CAUSAL CLAIM — no verdict is drawn from an exploratory run.")
        }
        lines.append("VERDICT: \(verdict.rawValue)")

        return lines.joined(separator: "\n")
    }
}
