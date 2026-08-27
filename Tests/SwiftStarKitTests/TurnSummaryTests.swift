import Foundation
import Testing
@testable import SwiftStarKit

struct TurnSummaryTests {
    // MARK: averageDecodeTPS — Δgenerated / Δts (ts is CLOCK_MONOTONIC µs, per
    // the engine's agent_buf_put_ts — NOT ns as the pre-P21 code assumed)

    @Test func averageFromCounterDeltas() {
        let first = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                   ts: 0, generated: 0, state: "generating")
        let last = StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                  ts: 2_000_000, generated: 100, state: "idle")
        #expect(TurnSummary.averageDecodeTPS(first: first, last: last) == 50.0)
    }

    @Test func averageNilWithoutProgress() {
        let a = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                               ts: 1_000_000, generated: 10, state: "idle")
        // ts did not advance.
        #expect(TurnSummary.averageDecodeTPS(first: a, last: a) == nil)
        // tokens did not advance.
        let b = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                               ts: 2_000_000, generated: 10, state: "idle")
        #expect(TurnSummary.averageDecodeTPS(first: a, last: b) == nil)
    }

    @Test func baselineCapturesFirstGeneratingAndHolds() {
        let prefill = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                     ts: 1, generated: 0, state: "prefill")
        #expect(TurnSummary.baseline(for: prefill, current: nil) == nil)
        let gen1 = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                  ts: 2, generated: 0, state: "generating")
        let baseline = TurnSummary.baseline(for: gen1, current: nil)
        #expect(baseline == gen1)
        let gen2 = StatusSnapshot(ctxUsed: 500, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                  ts: 3, generated: 10, state: "generating")
        #expect(TurnSummary.baseline(for: gen2, current: baseline) == gen1)  // held, not advanced
    }

    @Test func lineDoesNotTrapOnNonFinite() {
        let s = TurnSummary(promptTPS: .infinity, decodeTPS: .infinity, generatedTokens: 10, ctxUsed: 100)
        #expect(s.line == "Decode 0 tok/s · 10 tok · ctx 100")
    }

    @Test func lineFormatIsFixed() {
        let s = TurnSummary(promptTPS: 1200, decodeTPS: 47.3, generatedTokens: 512, ctxUsed: 9_580)
        #expect(s.line == "Decode 47 tok/s · 512 tok · ctx 9,580")
    }

    @Test func goldenReplayDecodeAveragesTrackEngineRates() throws {
        // The whole point of the decode average, end-to-end: replay the golden
        // session's status stream and check the Δ/Δ average per turn tracks the
        // engine's own reported decode rate. Fails for all three pre-P21
        // reasons — wrong ts unit, wrong (previous-turn) baseline, prefill
        // included — and passes only with the µs unit + the first-generating
        // baseline (prefill excluded).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/golden.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var statuses: [StatusSnapshot] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = parser.feed(String(line)), case .status(let s) = e { statuses.append(s) }
        }
        // Segment into turns: idle ends a turn; prefill/generating begin one.
        var turns: [[StatusSnapshot]] = []
        var current: [StatusSnapshot] = []
        for s in statuses {
            if s.state == "idle", !current.isEmpty {
                current.append(s)
                turns.append(current)
                current = []
            } else if s.state != "idle" {
                current.append(s)
            }
        }
        #expect(turns.count >= 2)
        var checked = 0
        for turn in turns {
            var baseline: StatusSnapshot?
            for s in turn { baseline = TurnSummary.baseline(for: s, current: baseline) }
            guard let b = baseline, let last = turn.last,
                  let avg = TurnSummary.averageDecodeTPS(first: b, last: last) else { continue }
            let gen = turn.filter { $0.genTPS > 0 }.map(\.genTPS)
            guard !gen.isEmpty else { continue }
            let engineRate = gen.reduce(0, +) / Double(gen.count)
            #expect(abs(avg - engineRate) / engineRate < 0.05,
                    "turn avg \(avg) vs engine \(engineRate)")
            checked += 1
        }
        #expect(checked >= 2)
    }

    // MARK: transcript attach

    @Test func summaryAttachesToTrailingContentRow() {
        var t = AgentTranscript()
        t.apply(.text("answer"))
        let summary = TurnSummary(promptTPS: 0, decodeTPS: 40, generatedTokens: 100, ctxUsed: 500)
        t.attachSummary(summary)
        #expect(t.rows == [.content("answer", summary: summary)])
    }

    @Test func attachIsNoOpWhenTrailingRowIsNotContent() {
        var t = AgentTranscript()
        t.apply(.text("answer"))
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil,
                                     paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil,
                                     paramName: nil, value: nil, status: nil, calls: nil)))
        // A turn that ended with a tool card has no trailing prose bubble: the
        // summary must not wander up to an earlier turn's content row.
        let summary = TurnSummary(promptTPS: 0, decodeTPS: 40, generatedTokens: 100, ctxUsed: 500)
        t.attachSummary(summary)
        #expect(t.rows == [
            .content("answer", summary: nil),
            .tool(ToolCard(name: "read", params: [], output: nil, status: nil)),
        ])
    }

    @Test func attachIsNoOpOnEmptyTranscript() {
        var t = AgentTranscript()
        t.attachSummary(TurnSummary(promptTPS: 0, decodeTPS: 40, generatedTokens: 100, ctxUsed: 500))
        #expect(t.rows.isEmpty)
    }

    @Test func coalescingPreservesAttachedSummary() {
        var t = AgentTranscript()
        t.apply(.text("answer"))
        let summary = TurnSummary(promptTPS: 0, decodeTPS: 40, generatedTokens: 100, ctxUsed: 500)
        t.attachSummary(summary)
        // A late delta (e.g. a trailing tool-narration chunk) must not drop it.
        t.apply(.text("!"))
        #expect(t.rows == [.content("answer!", summary: summary)])
    }
}
