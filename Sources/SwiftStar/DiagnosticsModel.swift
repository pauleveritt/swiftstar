import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

@MainActor
@Observable
final class DiagnosticsModel {
    private(set) var findings: [Finding] = []
    private(set) var provenance: Provenance = .recorded

    private let analyzer = DiagnosticsAnalyzer()
    private let phraser = DeterministicPhraser()

    /// Live: analyze the current session's capture (wire + trace) when one
    /// exists; the bundled fixture is only the pre-spawn placeholder. Re-run
    /// when the session changes (MainView re-calls on pid change).
    func start(controller: AgentController) {
        if let input = Self.liveInput(from: controller) {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
            provenance = .live
        } else if let input = DiagnosticsFixture.load() {
            findings = analyzer.analyze(events: input.events, trace: input.trace)
            provenance = .recorded
        }
    }

    func phrase(_ finding: Finding) -> String {
        phraser.phrase(finding)
    }

    /// Parse the controller's live capture dir (wire.ndjson + agent.trace)
    /// through the production parsers — the same shape `DiagnosticsFixture`
    /// produces for the bundled golden capture.
    private static func liveInput(from controller: AgentController) -> DiagnosticsFixture.Input? {
        guard let urls = controller.liveCaptureURLs,
              let wireText = try? String(contentsOf: urls.wire, encoding: .utf8),
              let traceText = try? String(contentsOf: urls.trace, encoding: .utf8) else {
            return nil
        }
        var wireParser = WireEventParser()
        var events: [WireEvent] = []
        for line in wireText.split(whereSeparator: \.isNewline) {
            if let e = wireParser.feed(String(line)) { events.append(e) }
        }
        var traceParser = TraceParser()
        var trace: [TraceEvent] = []
        for line in traceText.split(whereSeparator: \.isNewline) {
            if let e = traceParser.feed(String(line)) { trace.append(e) }
        }
        return DiagnosticsFixture.Input(events: events, trace: trace)
    }
}
