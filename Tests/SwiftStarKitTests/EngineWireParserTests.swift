import Testing
import Foundation
@testable import SwiftStarKit

struct EngineWireParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/engine")
    }

    private static func events(fromFixture name: String) throws -> [EngineEvent] {
        let text = try String(contentsOf: fixturesRoot.appendingPathComponent(name), encoding: .utf8)
        var parser = EngineWireParser()
        return text.split(whereSeparator: \.isNewline).map { parser.parse(String($0)) }
    }

    private static func ready() -> EngineWireParser {
        var p = EngineWireParser()
        _ = p.parse(#"{"kind":"ready","protocol":1}"#)
        return p
    }

    private static func event(_ body: String) -> String {
        #"{"kind":"event","event":{"# + body + "}}"
    }

    @Test func firstLineMustBeReady() {
        var p = EngineWireParser()
        guard case .protocolError(let m) = p.parse(#"{"kind":"input"}"#) else {
            Issue.record("expected protocolError"); return
        }
        #expect(m.contains("input"))
    }

    @Test func protocolTwoIsRefused() {
        var p = EngineWireParser()
        guard case .protocolError(let m) = p.parse(#"{"kind":"ready","protocol":2}"#) else {
            Issue.record("expected protocolError"); return
        }
        #expect(m.contains("protocol 2"))
    }

    @Test func unknownEventKindIsIgnored() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"flux_capacitor""#)) == .ignored)
    }

    @Test func toolReadFixtureDecodes() throws {
        let events = try Self.events(fromFixture: "tool-read.ndjson")
        let results = events.compactMap { e -> EngineToolResult? in
            if case .toolResult(let r) = e { return r } else { return nil }
        }
        #expect(results.count == 2)
        for r in results {
            #expect(r.tool.op == "read")
            #expect(r.tool.path == "Package.swift")
            #expect(!r.preview.isEmpty)
        }
        let answers = events.compactMap { e -> EngineAnswer? in
            if case .answer(let a) = e { return a } else { return nil }
        }
        #expect(answers.count == 1)
        #expect((answers.first?.contextUsed ?? 0) > 0)
        let pauses = events.compactMap { e -> PauseMetrics? in
            if case .pause(let m) = e { return m } else { return nil }
        }
        #expect(!pauses.isEmpty)
        #expect(pauses.allSatisfy { $0.evalCount > 0 })
        guard case .closed = events.last(where: { $0 != .ignored }) else {
            Issue.record("last non-ignored event is not closed"); return
        }
    }

    @Test func stopFixtureHasInterrupted() throws {
        #expect(try Self.events(fromFixture: "stop.ndjson").contains { if case .interrupted = $0 { true } else { false } })
    }

    @Test func errorFixtureHasError() throws {
        let events = try Self.events(fromFixture: "error.ndjson")
        #expect(events.contains { if case .error(let m) = $0 { m.contains("bogus") } else { false } })
    }

    @Test func unavailableSnapshotIsIgnored() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"checkpoint","snapshot":{"status":"unavailable"}"#)) == .ignored)
    }

    @Test func nullSnapshotFieldsAreNil() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"checkpoint","snapshot":{"eval_count":8,"sync_ms":null}"#))
        guard case .pause(let m) = e else { Issue.record("expected pause"); return }
        #expect(m.evalCount == 8)
        #expect(m.prefillMs == nil)
        #expect(m.prefillTokens == nil)
    }

    @Test func missingOptionalFieldsAreNil() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"answer","text":"hi""#))
        #expect(e == .answer(EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil)))
    }

    @Test func refusalBecomesRefused() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"apply_refused","reason":"no changes""#)) == .refused("no changes"))
    }

    @Test func helpBecomesNotice() {
        var p = Self.ready()
        let e = p.parse(Self.event(#""kind":"help","lines":["/help","/status"]"#))
        guard case .notice(let t) = e else { Issue.record("expected notice"); return }
        #expect(!t.isEmpty)
        #expect(t.contains("/status"))
    }

    @Test func exportedNamesThePath() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"exported","path":"/s/export.md""#)) == .notice("Exported to /s/export.md"))
    }

    @Test func statusReportIsOneReadableLine() {
        var p = Self.ready()
        let e = p.parse(Self.event(
            #""kind":"status_report","model_id":"ds4-flash","context_used":1956,"context_size":65536,"gpu_allocated_bytes":10737418240,"gpu_budget_bytes":21474836480,"prompts":3,"where":null"#))
        guard case .notice(let t) = e else { Issue.record("expected notice"); return }
        #expect(!t.contains("\n"))
        #expect(t.contains("ds4-flash"))
        #expect(t.contains("1956 / 65536"))
        #expect(t.contains("10.0 GiB / 20.0 GiB"))
        #expect(t != "status_report")
    }

    // Payload: operator.py:216 `emit("clear")` — no fields but the envelope.
    @Test func clearRendersSentence() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"clear""#)) == .notice("Conversation cleared"))
    }

    // Payload: operator.py:384 `emit("terminal", outcome=, capture_path=, duration_ms=)`.
    @Test func terminalDecodesOutcome() {
        var p = Self.ready()
        let line = Self.event(#""kind":"terminal","outcome":"tool-limit","capture_path":"/x/capture","duration_ms":1234.5"#)
        #expect(p.parse(line) == .turnEnded(outcome: "tool-limit"))
    }

    // Payload: ndjson_process.py:126 `{"kind": "queued", "count": len(self.pending)}` (top level).
    @Test func queuedTopLevelDecodes() {
        var p = Self.ready()
        #expect(p.parse(#"{"kind":"queued","count":2}"#) == .queued(count: 2))
    }

    // Payload: operator.py:283-289 `emit("steering_applied" | "steering_unconfirmed", text=...)`.
    @Test func steeringDecodesBothKinds() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"steering_applied","text":"also do x""#))
            == .steering(applied: true, text: "also do x"))
        #expect(p.parse(Self.event(#""kind":"steering_unconfirmed","text":"also do x""#))
            == .steering(applied: false, text: "also do x"))
    }

    // Payload: tui_cli.py:789-793 `observer.emit("mentions", attached=[...], missing=[...])`.
    @Test func mentionsAttachedIsNoticeMissingIsRefusal() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"mentions","attached":["a.py","b.py"],"missing":[]"#))
            == .notice("Attached: a.py, b.py"))
        #expect(p.parse(Self.event(#""kind":"mentions","attached":[],"missing":["nope.py"]"#))
            == .refused("Not found: nope.py"))
        #expect(p.parse(Self.event(#""kind":"mentions","attached":[],"missing":[]"#)) == .ignored)
    }

    // Payloads: operator.py:181 `emit("compacting", focus=...)`; :185-190 `emit("compacted",
    // text=, tokens=, duration_ms=)`; :199 `emit("compact_failed", reason=, tokens=, duration_ms=)`.
    @Test func compactionEventsRender() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"compacting","focus":null"#)) == .notice("Compacting…"))
        #expect(p.parse(Self.event(#""kind":"compacted","text":"a long summary","tokens":812,"duration_ms":90.0"#))
            == .notice("Conversation compacted (812 tokens)"))
        #expect(p.parse(Self.event(#""kind":"compact_failed","reason":"summary too long","tokens":9,"duration_ms":1.0"#))
            == .refused("Not compacted: summary too long"))
    }

    // Payload: operator_telemetry.py:234 `{**event, "kind": "telemetry_error", "error": error}`.
    @Test func telemetryErrorUsesErrorField() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"telemetry_error","error":"disk full""#))
            == .notice("Telemetry error: disk full"))
    }

    // Payload: operator.py:312-322 `emit("answer", text=, **reason, ...)`; reason only for laguna-xs-chat.
    @Test func answerKeepsOptionalReason() {
        var p = Self.ready()
        guard case .answer(let a) = p.parse(Self.event(#""kind":"answer","text":"","reason":"ran out of tokens","context_used":10,"context_size":100"#)) else {
            Issue.record("expected answer"); return
        }
        #expect(a.reason == "ran out of tokens")
        guard case .answer(let b) = p.parse(Self.event(#""kind":"answer","text":"hi""#)) else {
            Issue.record("expected answer"); return
        }
        #expect(b.reason == nil)
    }

    // Payload: operator.py:294-300 `emit("interrupted", capture_path=, context_used=, context_size=, duration_ms=)`.
    @Test func interruptedCarriesContext() {
        var p = Self.ready()
        let line = Self.event(#""kind":"interrupted","capture_path":"/c","context_used":512,"context_size":20000,"duration_ms":5.0"#)
        #expect(p.parse(line) == .interrupted(contextUsed: 512, contextSize: 20000))
    }

    @Test func undecodableAfterReadyIsNotice() {
        var p = Self.ready()
        #expect(p.parse("garbage") == .notice("Engine output: garbage"))
        #expect(p.parse(#"{"no":"kind"}"#) == .notice(#"Engine output: {"no":"kind"}"#))
        guard case .notice(let n) = p.parse(String(repeating: "x", count: 500)) else {
            Issue.record("expected notice"); return
        }
        #expect(n == "Engine output: " + String(repeating: "x", count: 200))
        // The session continues: a later good line still decodes.
        #expect(p.parse(#"{"kind":"input"}"#) == .awaitingInput)
    }

    @Test func undecodableBeforeReadyIsFatal() {
        var p = EngineWireParser()
        guard case .protocolError = p.parse("garbage") else {
            Issue.record("expected protocolError"); return
        }
        var q = EngineWireParser()
        guard case .protocolError = q.parse(#"{"no":"kind"}"#) else {
            Issue.record("expected protocolError"); return
        }
    }

    @Test func nativeEventsAreGenerating() {
        var p = Self.ready()
        #expect(p.parse(Self.event(#""kind":"native_start""#)) == .generating(true))
        #expect(p.parse(Self.event(#""kind":"native_end""#)) == .generating(false))
    }
}
