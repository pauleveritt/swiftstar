import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var findings: [Finding] = []
    private(set) var isReplayingCapture = false

    private let analyzer = DiagnosticsAnalyzer()
    private let phraser = DeterministicPhraser()

    /// Idempotent: computed once from the bundled capture. Live wiring is P7.
    func start() {
        guard findings.isEmpty else { return }
        isReplayingCapture = true
        if let input = DiagnosticsFixture.load() {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
        }
        isReplayingCapture = false
    }

    func phrase(_ finding: Finding) -> String {
        phraser.phrase(finding)
    }
}
