import Testing
import Foundation
@testable import SwiftStarKit

/// `EvalReport` (task 5, eval-cli): deltas, spread, and an outcome-named
/// verdict — never a headline ratio. A ratio is exactly the shape that made
/// a `--power 70` vs `100` throttle read as an engine speedup.
struct EvalReportTests {
    private static func experiment(pairs: Int = 5) -> EvalExperiment {
        EvalExperiment(
            name: "power-throttle-probe",
            question: "Does power change decode throughput?",
            falsifier: "If the effect is small across all pairs, the claim is falsified.",
            variable: "power", pairs: pairs, mode: .bare,
            promptFile: "prompts/throttle.md", captureSelection: "latest",
            arms: [
                Arm(id: "control", overrides: [:]),
                Arm(id: "treatment", overrides: [:]),
            ],
            common: [:])
    }

    /// Deltas engineered so the naive ratio (Σtreatment / Σcontrol) is 2.2 —
    /// exactly the figure `neverPrintsARatio` checks never appears formatted.
    private static func fivePairs() -> [PairResult] {
        [
            PairResult(pair: 1, controlSuffix: 100, treatmentSuffix: 220, delta: 120),
            PairResult(pair: 2, controlSuffix: 100, treatmentSuffix: 220, delta: 120),
            PairResult(pair: 3, controlSuffix: 100, treatmentSuffix: 220, delta: 120),
            PairResult(pair: 4, controlSuffix: 100, treatmentSuffix: 220, delta: 120),
            PairResult(pair: 5, controlSuffix: 100, treatmentSuffix: 220, delta: 120),
        ]
    }

    @Test func reportsEveryPairAndTheSpread() {
        let report = EvalReport.render(
            Self.experiment(), pairs: Self.fivePairs(), drops: [],
            verdict: .claimSurvives, attempt: 1, exploratory: false)
        for pair in 1...5 {
            #expect(report.contains("pair \(pair) "))
        }
        #expect(report.contains("spread: min 120  max 120"))
    }

    @Test func neverPrintsARatio() {
        let report = EvalReport.render(
            Self.experiment(), pairs: Self.fivePairs(), drops: [],
            verdict: .claimSurvives, attempt: 1, exploratory: false)
        // The naive ratio here is 220/100 == 2.2 — a "2.2x" or a percentage
        // figure must not appear anywhere in the rendered report.
        let ratioPattern = try! NSRegularExpression(pattern: #"\d+\.\d+x|\d+%"#, options: .caseInsensitive)
        let range = NSRange(report.startIndex..<report.endIndex, in: report)
        #expect(ratioPattern.firstMatch(in: report, range: range) == nil)
    }

    @Test func statesTheChanceOfAllSameSign() {
        let report = EvalReport.render(
            Self.experiment(), pairs: Self.fivePairs(), drops: [],
            verdict: .claimSurvives, attempt: 1, exploratory: false)
        // n=5 pairs: 1 / 2^(5-1) == 1 in 16.
        #expect(report.contains("1 in 16"))
    }

    @Test func namesEveryDroppedPair() {
        let drops: [PairDrop] = [.unusable(arm: "control", reason: "wire records no work")]
        let report = EvalReport.render(
            Self.experiment(), pairs: [], drops: drops,
            verdict: .unrecorded, attempt: 1, exploratory: false)
        #expect(report.contains("control"))
        #expect(report.contains("wire records no work"))
    }

    @Test func unrecordedVerdictExitsNonZero() {
        #expect(EvalReport.exitCode(for: .unrecorded) == 2)
        let report = EvalReport.render(
            Self.experiment(), pairs: [], drops: [],
            verdict: .unrecorded, attempt: 1, exploratory: false)
        #expect(report.contains("VERDICT: unrecorded"))
    }

    @Test func recordedVerdictExitsZero() {
        #expect(EvalReport.exitCode(for: .claimSurvives) == 0)
    }

    @Test func attemptNumberIsPrinted() {
        let report = EvalReport.render(
            Self.experiment(), pairs: Self.fivePairs(), drops: [],
            verdict: .claimSurvives, attempt: 3, exploratory: false)
        #expect(report.contains("attempt 3"))
    }

    @Test func exploratoryStampsEveryClaim() {
        let report = EvalReport.render(
            Self.experiment(pairs: 1), pairs: [PairResult(pair: 1, controlSuffix: 10, treatmentSuffix: 15, delta: 5)],
            drops: [], verdict: .unrecorded, attempt: 1, exploratory: true)
        #expect(report.contains("NOT A CAUSAL CLAIM"))
    }
}
