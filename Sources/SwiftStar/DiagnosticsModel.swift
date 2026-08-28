import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var findings: [Finding] = []
    private(set) var provenance: Provenance = .recorded
    /// The session is up but its capture has nothing to analyze yet (no turn has
    /// completed). Distinct from "analyzed, no findings" — without it an empty
    /// live read is indistinguishable from a clean bill of health.
    private(set) var awaitingCapture = false

    private let analyzer = DiagnosticsAnalyzer()
    private let phraser = DeterministicPhraser()

    /// Live: analyze the current session's own capture; the bundled fixture is
    /// only the pre-spawn placeholder. Re-run on every completed turn (MainView
    /// watches `completedTurns`) — a pid change alone fires while the wire is
    /// still empty and before the engine has opened its trace.
    func start(controller: AgentController) {
        if let input = Self.liveInput(from: controller), !input.events.isEmpty {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
            provenance = .live
            awaitingCapture = false
        } else if controller.isUp {
            findings = []
            provenance = .live
            awaitingCapture = true
        } else if let input = DiagnosticsFixture.load() {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
            provenance = .recorded
            awaitingCapture = false
        }
    }

    func phrase(_ finding: Finding) -> String {
        phraser.phrase(finding)
    }

    /// Parse the controller's live capture dir through the production parsers —
    /// the same shape `DiagnosticsFixture` produces for the bundled capture.
    /// The trace is optional: the engine only opens it after the model loads, so
    /// requiring it made every in-session read fail back to the fixture. Without
    /// it the compaction findings simply do not fire.
    private static func liveInput(from controller: AgentController) -> DiagnosticsFixture.Input? {
        guard let urls = controller.liveCaptureURLs,
              let wireText = try? String(contentsOf: urls.wire, encoding: .utf8) else {
            return nil
        }
        // The app always spawns a pool, so the wire is worker-tagged: keep the
        // orchestrator's own events or the findings describe a subagent.
        var wireParser = WireEventParser()
        var events: [WireEvent] = []
        for line in wireText.split(whereSeparator: \.isNewline) {
            guard PoolWireParser.worker(of: String(line)) == .orchestrator else { continue }
            if let e = wireParser.feed(String(line)) { events.append(e) }
        }
        // Lossy read: the engine's token-dump lines embed raw bytes, and a
        // truncated multibyte sequence (real occurrence in a live capture)
        // made the strict read return nil and drop every compaction finding.
        let trace = TraceParser.read(url: urls.trace)
        return DiagnosticsFixture.Input(events: events, trace: trace)
    }
}
