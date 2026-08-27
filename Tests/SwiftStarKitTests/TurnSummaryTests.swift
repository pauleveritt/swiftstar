import Foundation
import Testing
@testable import SwiftStarKit

struct TurnSummaryTests {
    // MARK: DecodeAccumulator — decode work per generation segment, on the
    // engine's own clock (gen_tps = generated/(now-t0) for the CURRENT segment;
    // both counters reset at every prefill).

    private func status(_ state: String, generated: Int, genTPS: Double, ts: UInt64 = 0) -> StatusSnapshot {
        StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0, genTPS: genTPS,
                       ts: ts, generated: generated, state: state, power: 100, error: "")
    }

    @Test func accumulatesOneSegment() {
        var acc = DecodeAccumulator()
        acc.apply(status("prefill", generated: 0, genTPS: 0))
        acc.apply(status("generating", generated: 50, genTPS: 50))
        acc.apply(status("generating", generated: 100, genTPS: 50))
        // 100 tokens at the engine's reported 50 tok/s = 2s of decode.
        #expect(acc.generatedTokens == 100)
        #expect(acc.tokensPerSecond == 50)
    }

    @Test func sumsAcrossSegmentsSplitByPrefill() {
        // The tool-round shape: generate, re-prefill (counters reset), generate.
        // Both segments' tokens count, and neither the prefill nor any
        // tool-blocked wall time between them enters the rate.
        var acc = DecodeAccumulator()
        acc.apply(status("generating", generated: 100, genTPS: 50))   // 100 tok / 2s
        acc.apply(status("prefill", generated: 0, genTPS: 0))
        acc.apply(status("generating", generated: 200, genTPS: 100))  // 200 tok / 2s
        #expect(acc.generatedTokens == 300)
        #expect(acc.tokensPerSecond == 75)                            // 300 tok / 4s
    }

    @Test func ignoresWallClockBetweenSamples() {
        // The defect this design replaces: a Δts-based average charges prefill
        // and host-tool blocking to decode. Here ts jumps 60s between two
        // generating samples (the engine reports `generating` while blocked on a
        // tool result) — the rate must still be the engine's.
        var acc = DecodeAccumulator()
        acc.apply(status("generating", generated: 10, genTPS: 50, ts: 1_000_000))
        acc.apply(status("generating", generated: 100, genTPS: 50, ts: 61_000_000))
        #expect(acc.tokensPerSecond == 50)
    }

    @Test func finishUsesReadyCountForFinalSegment() {
        // Status samples are periodic, so a segment's last sample misses what it
        // generated afterwards; `ready.generated` is authoritative for the final
        // segment only (earlier ones are already closed).
        var acc = DecodeAccumulator()
        acc.apply(status("generating", generated: 100, genTPS: 50))
        acc.apply(status("prefill", generated: 0, genTPS: 0))
        acc.apply(status("generating", generated: 40, genTPS: 50))
        acc.finish(finalGenerated: 60)
        #expect(acc.generatedTokens == 160)      // 100 closed + 60 authoritative
        #expect(acc.tokensPerSecond == 50)
    }

    @Test func nilRateWithoutDecodeWork() {
        var acc = DecodeAccumulator()
        #expect(acc.tokensPerSecond == nil)
        acc.apply(status("prefill", generated: 0, genTPS: 0))
        #expect(acc.tokensPerSecond == nil)
        // A generating sample the engine could not rate yet contributes nothing.
        acc.apply(status("generating", generated: 5, genTPS: 0))
        #expect(acc.tokensPerSecond == nil)
        #expect(acc.generatedTokens == 0)
    }

    @Test func nonFiniteEngineRateIsRejected() {
        var acc = DecodeAccumulator()
        acc.apply(status("generating", generated: 10, genTPS: .infinity))
        #expect(acc.tokensPerSecond == nil)
    }

    @Test func lineDoesNotTrapOnNonFinite() {
        let s = TurnSummary(promptTPS: .infinity, decodeTPS: .infinity, generatedTokens: 10, ctxUsed: 100)
        #expect(s.line == "Decode 0 tok/s · 10 tok · ctx 100")
    }

    @Test func lineFormatIsFixed() {
        let s = TurnSummary(promptTPS: 1200, decodeTPS: 47.3, generatedTokens: 512, ctxUsed: 9_580)
        #expect(s.line == "Decode 47 tok/s · 512 tok · ctx 9,580")
    }

    private func fixture(_ name: String) throws -> [StatusSnapshot] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/\(name)")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var statuses: [StatusSnapshot] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = parser.feed(String(line)), case .status(let s) = e { statuses.append(s) }
        }
        return statuses
    }

    @Test func goldenReplayDecodeAveragesTrackEngineRates() throws {
        // End to end on a real chat session: each turn's accumulated average
        // must track the engine's own reported decode rate.
        let statuses = try fixture("golden.ndjson")
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
            var acc = DecodeAccumulator()
            for s in turn { acc.apply(s) }
            guard let avg = acc.tokensPerSecond else { continue }
            let rates = turn.filter { $0.genTPS > 0 }.map(\.genTPS)
            guard let engineRate = rates.last else { continue }
            #expect(abs(avg - engineRate) / engineRate < 0.05,
                    "turn avg \(avg) vs engine \(engineRate)")
            checked += 1
        }
        #expect(checked >= 2)
    }

    @Test func toolRoundTurnTracksEngineRate() throws {
        // The case the golden chat capture cannot show. This is one real turn
        // with host-tool round trips: 8 generation segments, the engine's
        // counter resetting at each re-prefill, and long stretches where it
        // reports `generating` while blocked on a tool result.
        //
        // Guards two independent regressions, both measured on this fixture:
        //   - a Δgenerated/Δts average over the turn reads 7.3 tok/s (it charges
        //     prefill and tool-blocked wall time to decode)
        //   - the terminal `ready.generated` alone reports 298 of 714 tokens
        let statuses = try fixture("tool-rounds.ndjson")
        var acc = DecodeAccumulator()
        for s in statuses { acc.apply(s) }
        acc.finish(finalGenerated: 298)  // the fixture's terminal ready

        #expect(acc.generatedTokens == 714)
        let avg = try #require(acc.tokensPerSecond)
        #expect(abs(avg - 56.9) < 0.5, "expected ~56.9 tok/s, got \(avg)")

        // The engine's own last-reported rate for the final segment; the turn
        // average sits near it, and nowhere near the wall-clock figure.
        let engineFinal = try #require(statuses.last(where: { $0.genTPS > 0 })?.genTPS)
        #expect(abs(avg - engineFinal) / engineFinal < 0.10)
        #expect(avg > 40, "a wall-clock average would read ~7 tok/s here")
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
