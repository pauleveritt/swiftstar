import Testing
import Foundation
@testable import SwiftStarAppKit
@testable import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FixtureReplayTests {
    @Test func bundledFixtureMatchesRepoFixture() throws {
        guard let bundled = Bundle.module.url(forResource: "golden", withExtension: "ndjson") else {
            Issue.record("bundled golden.ndjson missing")
            return
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent/golden.ndjson")
        #expect(try Data(contentsOf: bundled) == Data(contentsOf: repo))
    }

    /// `golden.trace` is the same kind of manually-synced duplicate as
    /// `golden.ndjson` (a symlink was tried and rejected — SwiftPM's
    /// resource-copy step preserves it rather than dereferencing it, so it
    /// dangles once relocated into the `.build` bundle; see
    /// `fixtures/agent/provenance.md`) but the sibling test above only ever
    /// checked the `.ndjson` half, so a recapture could update one copy of
    /// `.trace` and not the other with nothing catching it.
    @Test func bundledTraceFixtureMatchesRepoFixture() throws {
        guard let bundled = Bundle.module.url(forResource: "golden", withExtension: "trace") else {
            Issue.record("bundled golden.trace missing")
            return
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarIntegrationTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent/golden.trace")
        #expect(try Data(contentsOf: bundled) == Data(contentsOf: repo))
    }

    @Test func replayYieldsStatusAndReadyThroughReducer() async {
        var parser = WireEventParser()
        let reducer = MetricsReducer()
        var state = MetricsState()
        var sawStatus = false, sawBudget = false
        for await line in FixtureReplay.lines(cadenceNanoseconds: 1_000) {
            if let event = parser.feed(line) {
                reducer.reduce(&state, event)
                if case .status = event { sawStatus = true }
                if case .ready(let p) = event, p != nil { sawBudget = true }
            }
        }
        #expect(sawStatus)
        #expect(sawBudget)
        #expect(state.ctxUsed != nil)
        // P23 golden recapture: this value moved from 49_943_965_040 to
        // 56_090_149_896. Traced to commit 0e13e14 ("Enable chunked Laguna
        // XS prefill", 2026-07-27, upstream laguna-s2.1 work unrelated to
        // P23) — it fixed the Laguna prefill-graph scratch estimator, which
        // previously reported a near-zero "one-token scratch" regardless of
        // the actual prefill chunk width. KV bytes and model bytes are
        // byte-identical to the old fixture; only the (previously
        // under-reported) scratch/buffers component changed. golden.ndjson
        // simply predates this fix and was never recaptured until now — not
        // a P23 config mismatch.
        #expect(state.memoryBudgetPlannedBytes == 56_090_149_896)
    }

    /// P23: the think-override fixture's hello advertises the cap, and each
    /// of its three turns (bare text; `think:"none"`; `think:"high"`) answers
    /// its own distinct question — provable only if the N=1 JSON-envelope
    /// path extracted `s` correctly rather than feeding the whole line to the
    /// model as literal text (the defect `44b70b5`'s N=1 fix retires).
    ///
    /// This fixture's `think:"high"` turn does not actually produce visible
    /// `{"t":"think"}` events — see `think-override.provenance.md`: thinking
    /// is prompt-induced (probe A), and this capture uses no system prompt,
    /// matching every other committed fixture's bare-CLI shape. Asserting
    /// think-event presence here would pin a false claim about this specific
    /// capture, so this test does not attempt it.
    @Test func thinkOverrideFixtureAdvertisesCapAndEachTurnAnswersItsOwnQuestion() throws {
        let fixture = try FakeAgentHarness.fixture("think-override.ndjson")
        let lines = try String(contentsOf: fixture, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var parser = AgentWireParser()
        var sawOverrideCap = false
        var turnTexts: [String] = [""]
        for line in lines {
            guard let event = parser.feed(line) else { continue }
            switch event {
            case .hello(_, let caps):
                sawOverrideCap = caps.contains("think_override")
            case .text(let s):
                turnTexts[turnTexts.count - 1] += s
            case .ready(_, let stopReason, _, _) where stopReason != nil:
                turnTexts.append("")
            default:
                break
            }
        }
        #expect(sawOverrideCap, "the fixture's hello must advertise think_override")
        #expect(turnTexts.count == 4, "expected 3 completed turns (plus the trailing empty accumulator)")
        #expect(turnTexts[0].contains("KV cache") || turnTexts[0].contains("Key-Value"),
            "turn 1 (bare prompt) should answer the KV-cache question")
        #expect(turnTexts[1].contains("2") && turnTexts[1].contains("3") && turnTexts[1].contains("5"),
            "turn 2 (think:none) should list prime numbers, not echo the envelope")
        #expect(turnTexts[2].contains("256"),
            "turn 3 (think:high) should answer 2^8, not echo the envelope")
    }
}
