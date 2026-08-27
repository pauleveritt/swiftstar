import Foundation
import Testing
@testable import SwiftStarKit

struct TurnSummaryTests {
    // MARK: averageDecodeTPS — Δgenerated / Δts (ts is CLOCK_MONOTONIC ns)

    @Test func averageFromCounterDeltas() {
        let first = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                   ts: 0, generated: 0, state: "prefill")
        let last = StatusSnapshot(ctxUsed: 958, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                                  ts: 2_000_000_000, generated: 100, state: "idle")
        #expect(TurnSummary.averageDecodeTPS(first: first, last: last) == 50.0)
    }

    @Test func averageNilWithoutProgress() {
        let a = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                               ts: 1_000_000_000, generated: 10, state: "idle")
        // ts did not advance.
        #expect(TurnSummary.averageDecodeTPS(first: a, last: a) == nil)
        // tokens did not advance.
        let b = StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: 0,
                               ts: 2_000_000_000, generated: 10, state: "idle")
        #expect(TurnSummary.averageDecodeTPS(first: a, last: b) == nil)
    }

    @Test func lineFormatIsFixed() {
        let s = TurnSummary(promptTPS: 1200, decodeTPS: 47.3, generatedTokens: 512, ctxUsed: 9_580)
        #expect(s.line == "Decode 47 tok/s · 512 tok · ctx 9,580")
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
