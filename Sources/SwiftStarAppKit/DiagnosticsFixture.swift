import Foundation
import SwiftStarKit

/// Loads the bundled `golden` capture (wire + trace) and runs it through the
/// production parsers. The pre-spawn placeholder for the Diagnostics tab
/// (P21: once a session is live, `DiagnosticsModel` analyzes the session's own
/// capture instead — same relationship Metrics' `FixtureReplay` has to its
/// live source).
///
/// The bundled `golden.{ndjson,trace}` are unsynced-by-construction copies of
/// `fixtures/agent/golden.{ndjson,trace}` — see `FixtureReplay`'s doc comment
/// for why (a symlink was tried and does not survive SwiftPM's resource copy)
/// and update both on every recapture.
public struct DiagnosticsFixture: Sendable {
    public struct Input: Equatable, Sendable {
        public var events: [WireEvent]
        public var trace: [TraceEvent]
        public init(events: [WireEvent], trace: [TraceEvent]) {
            self.events = events
            self.trace = trace
        }
    }

    public static func load() -> Input? {
        guard let wireURL = Bundle.module.url(forResource: "golden", withExtension: "ndjson"),
              let traceURL = Bundle.module.url(forResource: "golden", withExtension: "trace"),
              let wireText = try? String(contentsOf: wireURL, encoding: .utf8),
              let traceText = try? String(contentsOf: traceURL, encoding: .utf8) else {
            return nil
        }

        var wireParser = WireEventParser()
        var events: [WireEvent] = []
        for line in wireText.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = wireParser.feed(s) { events.append(e) }
        }

        var traceParser = TraceParser()
        var trace: [TraceEvent] = []
        for line in traceText.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = traceParser.feed(s) { trace.append(e) }
        }

        return Input(events: events, trace: trace)
    }
}
