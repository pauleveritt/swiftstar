import Testing
import Foundation
@testable import SwiftStarKit

struct EngineWireParserTests {
    private static func ready() -> EngineWireParser {
        var p = EngineWireParser()
        _ = p.parse(#"{"kind":"ready","protocol":1}"#)
        return p
    }

    private static func event(_ body: String) -> String {
        #"{"kind":"event","event":{"# + body + "}}"
    }

    // MARK: one line after `ready` → one exact event

    struct LineCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let line: String
        let expected: EngineEvent
    }

    private static func ev(_ body: String) -> String { #"{"kind":"event","event":{"# + body + "}}" }
    private static let relaunchArgv = ["tui", "--resume", "/s", "--source", "/r", "--ndjson"]

    // Payload sources: ds4-engine operator.py, tui_cli.py, ndjson_process.py,
    // operator_telemetry.py (cited per row where the old tests cited them).
    static let afterReadyCases: [LineCase] = [
        .init(testDescription: "unknownEventKindIsIgnored", line: ev(#""kind":"flux_capacitor""#), expected: .ignored),
        .init(testDescription: "sessionWithoutDFlash (SU.6b)", line: ev(#""kind":"session","model_id":"m","context_size":10"#),
              expected: .session(EngineSessionInfo(modelID: "m", contextSize: 10, dflash: nil))),
        .init(testDescription: "unavailableSnapshotIsIgnored",
              line: ev(#""kind":"checkpoint","snapshot":{"status":"unavailable"}"#), expected: .ignored),
        .init(testDescription: "nullSnapshotFieldsAreNil",
              line: ev(#""kind":"checkpoint","snapshot":{"eval_count":8,"sync_ms":null}"#),
              expected: .pause(PauseMetrics(prefillTokens: nil, prefillMs: nil, evalCount: 8, evalMs: nil))),
        .init(testDescription: "missingOptionalFieldsAreNil", line: ev(#""kind":"answer","text":"hi""#),
              expected: .answer(EngineAnswer(text: "hi", contextUsed: nil, contextSize: nil, durationMs: nil))),
        .init(testDescription: "answerKeepsOptionalReason (operator.py:312-322)",
              line: ev(#""kind":"answer","text":"","reason":"ran out of tokens","context_used":10,"context_size":100"#),
              expected: .answer(EngineAnswer(text: "", contextUsed: 10, contextSize: 100, durationMs: nil,
                                             reason: "ran out of tokens"))),
        .init(testDescription: "refusalBecomesRefused", line: ev(#""kind":"apply_refused","reason":"no changes""#),
              expected: .refused("no changes")),
        .init(testDescription: "refusedStillRefused (rewind_refused without relaunch)",
              line: ev(#""kind":"rewind_refused","reason":"no earlier prompt""#), expected: .refused("no earlier prompt")),
        .init(testDescription: "model_refused with relaunch (EN.1 minor)",
              line: ev(#""kind":"model_refused","reason":"switch","relaunch":["tui","--resume","/s","--source","/r","--ndjson"]"#),
              expected: .relaunch(EngineRelaunch(kind: .model, argv: relaunchArgv, reason: "switch"))),
        .init(testDescription: "resume_refused with relaunch (EN.1 minor)",
              line: ev(#""kind":"resume_refused","reason":"resume","relaunch":["tui","--resume","/s","--source","/r","--ndjson"]"#),
              expected: .relaunch(EngineRelaunch(kind: .resume, argv: relaunchArgv, reason: "resume"))),
        .init(testDescription: "apply_refused with relaunch stays refused",
              line: ev(#""kind":"apply_refused","reason":"no","relaunch":["tui","--ndjson"]"#), expected: .refused("no")),
        .init(testDescription: "helpBecomesNotice", line: ev(#""kind":"help","lines":["/help","/status"]"#),
              expected: .notice("/help\n/status")),
        .init(testDescription: "exportedNamesThePath", line: ev(#""kind":"exported","path":"/s/export.md""#),
              expected: .notice("Exported to /s/export.md")),
        .init(testDescription: "clearRendersSentence (operator.py:216)", line: ev(#""kind":"clear""#),
              expected: .notice("Conversation cleared")),
        .init(testDescription: "terminalDecodesOutcome (operator.py:384)",
              line: ev(#""kind":"terminal","outcome":"tool-limit","capture_path":"/x/capture","duration_ms":1234.5"#),
              expected: .turnEnded(outcome: "tool-limit")),
        .init(testDescription: "queuedTopLevelDecodes (ndjson_process.py:126)", line: #"{"kind":"queued","count":2}"#,
              expected: .queued(count: 2)),
        .init(testDescription: "steeringDecodesBothKinds (applied)",
              line: ev(#""kind":"steering_applied","text":"also do x""#), expected: .steering(applied: true)),
        .init(testDescription: "steeringDecodesBothKinds (unconfirmed)",
              line: ev(#""kind":"steering_unconfirmed","text":"also do x""#), expected: .steering(applied: false)),
        .init(testDescription: "mentionsAttachedIsNoticeMissingIsRefusal (attached; tui_cli.py:789-793)",
              line: ev(#""kind":"mentions","attached":["a.py","b.py"],"missing":[]"#), expected: .notice("Attached: a.py, b.py")),
        .init(testDescription: "mentionsAttachedIsNoticeMissingIsRefusal (missing)",
              line: ev(#""kind":"mentions","attached":[],"missing":["nope.py"]"#), expected: .refused("Not found: nope.py")),
        .init(testDescription: "mentionsAttachedIsNoticeMissingIsRefusal (empty)",
              line: ev(#""kind":"mentions","attached":[],"missing":[]"#), expected: .ignored),
        .init(testDescription: "compactionEventsRender (compacting; operator.py:181)", line: ev(#""kind":"compacting","focus":null"#),
              expected: .notice("Compacting…")),
        .init(testDescription: "compactionEventsRender (compacted; operator.py:185-190)",
              line: ev(#""kind":"compacted","text":"a long summary","tokens":812,"duration_ms":90.0"#),
              expected: .notice("Conversation compacted (812 tokens)")),
        .init(testDescription: "compactionEventsRender (failed; operator.py:199)",
              line: ev(#""kind":"compact_failed","reason":"summary too long","tokens":9,"duration_ms":1.0"#),
              expected: .refused("Not compacted: summary too long")),
        .init(testDescription: "telemetryErrorUsesErrorField (operator_telemetry.py:234)",
              line: ev(#""kind":"telemetry_error","error":"disk full""#), expected: .notice("Telemetry error: disk full")),
        .init(testDescription: "interruptedCarriesContext (operator.py:294-300)",
              line: ev(#""kind":"interrupted","capture_path":"/c","context_used":512,"context_size":20000,"duration_ms":5.0"#),
              expected: .interrupted(contextUsed: 512, contextSize: 20000)),
        .init(testDescription: "nativeEventsAreGenerating (start)", line: ev(#""kind":"native_start""#),
              expected: .generating(true)),
        .init(testDescription: "nativeEventsAreGenerating (end)", line: ev(#""kind":"native_end""#),
              expected: .generating(false)),
    ]

    @Test(arguments: afterReadyCases) func afterReady(_ c: LineCase) {
        var p = Self.ready()
        #expect(p.parse(c.line) == c.expected)
    }

    // MARK: the first line must be the handshake

    static let beforeReadyCases: [LineCase] = [
        .init(testDescription: "firstLineMustBeReady", line: #"{"kind":"input"}"#,
              expected: .protocolError("expected ready first, got input")),
        .init(testDescription: "protocolTwoIsRefused", line: #"{"kind":"ready","protocol":2}"#,
              expected: .protocolError("unsupported engine protocol 2; expected protocol 1")),
        .init(testDescription: "undecodableBeforeReadyIsFatal (not JSON)", line: "garbage",
              expected: .protocolError("not a JSON object: garbage")),
        .init(testDescription: "undecodableBeforeReadyIsFatal (no kind)", line: #"{"no":"kind"}"#,
              expected: .protocolError(#"line has no kind: {"no":"kind"}"#)),
    ]

    @Test(arguments: beforeReadyCases) func beforeReady(_ c: LineCase) {
        var p = EngineWireParser()
        #expect(p.parse(c.line) == c.expected)
    }

    @Test func toolRejectedFixtureDecodes() throws {
        let rejections = try Fixtures.events("tool-rejected.ndjson").compactMap { e -> EngineToolRejection? in
            if case .toolRejected(let r) = e { r } else { nil }
        }
        #expect(rejections == [EngineToolRejection(
            name: "list_files", reason: "unknown-tool", path: nil,
            text: "Tool error: unknown tool: list_files")])
    }

    @Test func rewindRefusedWithRelaunchDecodes() throws {
        let relaunches = try Fixtures.events("relaunch-rewind.ndjson").compactMap { e -> EngineRelaunch? in
            if case .relaunch(let r) = e { r } else { nil }
        }
        #expect(relaunches.count == 1)
        let r = try #require(relaunches.first)
        #expect(r.kind == .rewind)
        #expect(r.argv.first == "tui" && r.argv.last == "--ndjson")
        #expect(!r.argv.contains("--commit"))
    }

    @Test func resumedFixtureDecodes() throws {
        let resumed = try Fixtures.events("resumed.ndjson").compactMap { e -> EngineResumed? in
            if case .resumed(let r) = e { r } else { nil }
        }
        let r = try #require(resumed.first)
        #expect(r.turns.count == 1)
        #expect(r.rewoundTo == 1)
        #expect(r.turns.first?.answer == "2 + 2 equals 4.")
    }

    @Test func relaunchModelIdFromArgv() {
        let r = EngineRelaunch(kind: .model, argv: [
            "tui", "--resume", "/s", "--model-id", "qwen3.8-flash-next", "--new-conversation", "--ndjson"],
            reason: "")
        #expect(r.modelID == "qwen3.8-flash-next")
        #expect(EngineRelaunch(kind: .rewind, argv: ["tui", "--ndjson"], reason: "").modelID == nil)
    }

    @Test func toolReadFixtureDecodes() throws {
        let events = try Fixtures.events("tool-read.ndjson")
        let results = events.compactMap { e -> EngineToolResult? in
            if case .toolResult(let r) = e { return r } else { return nil }
        }
        #expect(results.count == 1)
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
        #expect(pauses.first?.capturePath?.contains("/sessions/") == true)  // SU.7a
        // SU.6b: the 27B's DFlash decision and its prefix-cache miss.
        let dflash = events.compactMap { e -> EngineDFlash? in
            if case .session(let s) = e { return s.dflash } else { return nil }
        }.first
        #expect(dflash?.on == true)
        #expect(dflash?.reason.hasPrefix("plan 19.27 GiB") == true)
        #expect(dflash?.drafter?.hasSuffix("dflash-Qwen3.8-27B-Q4_0.gguf") == true)
        let cache = events.compactMap { e -> EnginePrefixCache? in
            if case .prefixCache(let p) = e { return p } else { return nil }
        }
        #expect(cache.map(\.outcome) == ["miss"])
        #expect(cache.first?.tokens == 944)
        guard case .closed = events.last(where: { $0 != .ignored }) else {
            Issue.record("last non-ignored event is not closed"); return
        }
    }

    @Test func stopFixtureHasInterrupted() throws {
        #expect(try Fixtures.events("stop.ndjson").contains { if case .interrupted = $0 { true } else { false } })
    }

    @Test func errorFixtureHasError() throws {
        let events = try Fixtures.events("error.ndjson")
        #expect(events.contains { if case .error(let m) = $0 { m.contains("bogus") } else { false } })
    }

    @Test func statusReportIsOneReadableLine() {
        var p = EngineWireParser(locale: Locale(identifier: "en_US"))
        _ = p.parse(#"{"kind":"ready","protocol":1}"#)
        let e = p.parse(Self.event(
            #""kind":"status_report","model_id":"ds4-flash","context_used":1956,"context_size":65536,"gpu_allocated_bytes":10737418240,"gpu_budget_bytes":21474836480,"prompts":3,"where":null"#))
        guard case .notice(let t) = e else { Issue.record("expected notice"); return }
        #expect(!t.contains("\n"))
        #expect(t.contains("ds4-flash"))
        #expect(t.contains("1956 / 65536"))
        #expect(t.contains("10.0 GiB / 20.0 GiB"))
        #expect(t != "status_report")
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

}
