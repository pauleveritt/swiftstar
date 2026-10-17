import Foundation
import Testing
@testable import SwiftStarKit

/// EN.2: the kinds ds4-engine added to the wire after `5451cd7d`. Until the
/// recordings at `a84b79bd` land (Task 6), the payloads follow the engine's
/// own tests and code at `a84b79bd`, cited per line.
struct EngineStartupEventsTests {
    private static let locale = Locale(identifier: "en_US")

    private static func parse(_ body: String) -> EngineEvent {
        var p = EngineWireParser()
        _ = p.parse(#"{"kind":"ready","protocol":1}"#)
        return p.parse(#"{"kind":"event","event":{"# + body + "}}")
    }

    // tests/test_baseline.py:136-141.
    static let baseline = #""kind":"baseline","commit":"HEAD","resolved":"5cc0836aa1","source_head":"5cc0836aa1","at_source_head":true,"excluded":[{"path":"app.py","change":"untracked","code":"??","staged":false}],"excluded_count":1,"summary":"The model works on a clean copy of commit 5cc0836; 1 uncommitted file in your checkout is not included: app.py.""#
    // operator.py:760-765.
    static let candidateReady = #""kind":"candidate_ready","created_ms":812.5,"waited_ms":40.0,"overlapped":true"#
    // candidate_env.py:151-248; the summary's wording is illustrative.
    static let envSync = #""kind":"env_sync","command":["uv","sync"],"outcome":"ok","duration_ms":2300.0,"summary":"Synced the candidate's environment (uv sync, 2.3 s).""#
    // project_instructions.py:116-131.
    static let instructions = #""kind":"project_instructions","file":"AGENTS.md","sha256":"ab","bytes":3000,"lines":40,"tokens":1000,"cut":false,"given_bytes":3000,"given_lines":40,"given_tokens":1000,"cap_tokens":2000,"token_estimate":"1 token per 3 bytes","uncommitted":[],"summary":"Loaded AGENTS.md (40 lines, about 1,000 tokens).""#
    // session_receipt.py:122.
    static let indexPrimed = #""kind":"index_primed","since_start_ms":3336.0"#

    @Test func startupKindsDecode() {
        #expect(Self.parse(Self.baseline) == .startup(
            .baseline(commit: "5cc0836aa1", excludedCount: 1),
            summary: "The model works on a clean copy of commit 5cc0836; 1 uncommitted file in your checkout is not included: app.py."))
        #expect(Self.parse(Self.candidateReady) == .startup(.candidateReady(createdMs: 812.5, waitedMs: 40), summary: nil))
        #expect(Self.parse(Self.envSync) == .startup(
            .envSync(outcome: "ok", durationMs: 2300), summary: "Synced the candidate's environment (uv sync, 2.3 s)."))
        #expect(Self.parse(Self.instructions) == .startup(
            .projectInstructions(file: "AGENTS.md", tokens: 1000, cut: false),
            summary: "Loaded AGENTS.md (40 lines, about 1,000 tokens)."))
        #expect(Self.parse(Self.indexPrimed) == .startup(.indexPrimed(sinceStartMs: 3336), summary: nil))
    }

    @Test func summariesBecomeRowsAndNullOnesDont() {
        var t = EngineTranscript()
        t.apply(Self.parse(Self.baseline))
        // tests/test_baseline.py:81-95: a clean checkout sends `summary: null`.
        t.apply(Self.parse(#""kind":"baseline","resolved":"5cc0836aa1","excluded_count":0,"summary":null"#))
        t.apply(Self.parse(Self.candidateReady))
        #expect(t.rows == [.system(
            "The model works on a clean copy of commit 5cc0836; 1 uncommitted file in your checkout is not included: app.py.")])
    }

    @Test func startupFoldsIntoMetrics() {
        var m = EngineMetricsState()
        for line in [Self.baseline, Self.candidateReady, Self.envSync, Self.instructions, Self.indexPrimed] {
            EngineMetricsReducer.reduce(&m, Self.parse(line))
        }
        #expect(m.startup == EngineStartupInfo(
            commit: "5cc0836aa1", excludedCount: 1, candidateCreatedMs: 812.5, candidateWaitedMs: 40,
            envSyncOutcome: "ok", envSyncMs: 2300, instructionsFile: "AGENTS.md", instructionsTokens: 1000,
            instructionsCut: false, indexPrimedMs: 3336))
        #expect(MetricsFormatting.startupRows(m.startup, locale: Self.locale).map { "\($0.0): \($0.1)" } == [
            "Commit: 5cc0836 · 1 uncommitted file left out",
            "Candidate: ready in 813 ms (waited 40 ms)",
            "Environment: ok in 2.3s",
            "Instructions: AGENTS.md · 1,000 tokens",
            "Index primed: 3.3s",
        ])
        EngineMetricsReducer.reduce(&m, .session(EngineSessionInfo(modelID: "m", contextSize: 1)))
        #expect(m.startup == EngineStartupInfo())
    }

    // tests/test_resume_conversation.py:244-250; `loaded` and `failed` per
    // driver.rs:469-500.
    @Test(arguments: [
        (#""kind":"conversation_state","method":"run_until_pause","outcome":"loaded","bytes":365000000,"load_ms":1200.0,"error":null"#,
         "Saved conversation state loaded · 0.3 GiB in 1.2s"),
        (#""kind":"conversation_state","method":"run_until_pause","outcome":"failed","bytes":5,"load_ms":3.0,"error":"bad magic""#,
         "Saved conversation state not loaded: failed (bad magic)"),
        (#""kind":"conversation_state","method":"run_until_pause","outcome":"absent","bytes":null,"load_ms":null,"error":null"#,
         "Saved conversation state not loaded: absent"),
        (#""kind":"conversation_state","method":"run_until_pause","outcome":"unsupported","bytes":5,"load_ms":0.1,"error":null"#,
         "Saved conversation state not loaded: unsupported"),
    ]) func conversationStateLines(_ body: String, _ line: String) throws {
        guard case .conversationState(let state) = Self.parse(body) else {
            Issue.record("not a conversation state: \(Self.parse(body))"); return
        }
        #expect(MetricsFormatting.conversationStateLine(state, locale: Self.locale) == line)
        #expect(MetricsFormatting.conversationStateLine(state, subject: false, locale: Self.locale)
                == String(line.dropFirst("Saved conversation state ".count)))
        var t = EngineTranscript()
        t.apply(.conversationState(state))
        #expect(t.rows == [.system(line)])
        var m = EngineMetricsState()
        EngineMetricsReducer.reduce(&m, .conversationState(state))
        #expect(m.conversationState == state)
    }

    // prefix_cache.rs:75-86, bindings.rs:1616-1619.
    @Test(arguments: [
        (#""kind":"prefix_cache","outcome":"miss","prefix_tokens":944,"load_ms":null,"fill_ms":1729.4,"changed":["model","shaders"],"entry_fill_ms":null"#,
         "miss · 944 tokens filled in 1.7s · changed: model, shaders"),
        (#""kind":"prefix_cache","outcome":"miss","prefix_tokens":944,"load_ms":null,"fill_ms":1729.4,"changed":[],"entry_fill_ms":null"#,
         "miss · 944 tokens filled in 1.7s · its entry did not load"),
        (#""kind":"prefix_cache","outcome":"miss","prefix_tokens":944,"load_ms":null,"fill_ms":1729.4,"changed":null"#,
         "miss · 944 tokens filled in 1.7s"),
        (#""kind":"prefix_cache","outcome":"hit","prefix_tokens":944,"load_ms":20.0,"fill_ms":null,"changed":null,"entry_fill_ms":1729.4"#,
         "hit · 944 tokens in 20 ms (filled in 1.7s)"),
    ]) func prefixLineSaysWhatChanged(_ body: String, _ line: String) throws {
        guard case .prefixCache(let p) = Self.parse(body) else { Issue.record("not a prefix cache"); return }
        #expect(MetricsFormatting.prefixCacheLine(p, locale: Self.locale) == line)
    }

    // tui_cli.py:141; tests/test_tui_analyze.py:101.
    @Test func analysisBecomesAFencedReport() {
        let event = Self.parse(#""kind":"analysis","lines":["session  x · m","rates    prefill 440 tok/s"]"#)
        #expect(event == .analysis(["session  x · m", "rates    prefill 440 tok/s"]))
        var t = EngineTranscript()
        t.apply(event)
        #expect(t.rows == [.report("```\nsession  x · m\nrates    prefill 440 tok/s\n```")])
    }
}

/// EN.2, D5: the `git` and `test` tools (ds4-engine SC.1), whose calls carry
/// no path on the wire (`operator.py:385-393`).
struct GitAndTestCardTests {
    private static func card(_ op: String, preview: String? = nil) -> EngineToolCard {
        let tool = EngineTool(op: op, path: "")
        return EngineToolCard(
            tool: tool, ok: true, durationMs: 2300,
            result: preview.map { EngineToolResult(tool: tool, preview: $0, truncated: false) })
    }

    @Test func gitAndTestIcons() {
        #expect(Self.card("git").icon == "arrow.triangle.branch")
        #expect(Self.card("test").icon == "checkmark.seal")
        #expect(Self.card("git").headerText == "git")
    }

    @Test func gitResultIsDiff() {
        #expect(Self.card("git").resultLanguage == "diff")
        let read = EngineToolCard(tool: EngineTool(op: "read", path: "a.py"))
        #expect(read.resultLanguage == "python")
    }

    // test_tool.py:113-126.
    @Test func testCardShowsPytestLine() {
        let card = Self.card("test", preview: "[pytest with the project's .venv: exit 0 in 2.3 s]\n5 passed")
        #expect(card.metadataLine == "succeeded · 2.3s · pytest with the project's .venv: exit 0 in 2.3 s")
        #expect(Self.card("test", preview: "no bracket line").metadataLine == "succeeded · 2.3s")
    }
}
