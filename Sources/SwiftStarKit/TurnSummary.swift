import Foundation

/// The frozen per-turn summary attached to the assistant's reply bubble when
/// the turn ends: the turn's decode average, token count, and context usage.
/// The live Prompt/Decode readout stays in the status bar; this is the
/// historical record for one answer (the DS4 Control stats-line precedent).
public struct TurnSummary: Equatable, Sendable {
    public let promptTPS: Double
    public let decodeTPS: Double
    public let generatedTokens: Int
    public let ctxUsed: Int

    public init(promptTPS: Double, decodeTPS: Double, generatedTokens: Int, ctxUsed: Int) {
        self.promptTPS = promptTPS
        self.decodeTPS = decodeTPS
        self.generatedTokens = generatedTokens
        self.ctxUsed = ctxUsed
    }

    /// "Decode 47 tok/s · 512 tok · ctx 9,580" — the static line under the
    /// bubble, fixed once the turn completes. Never traps on a non-finite
    /// rate (a garbage wire value renders as a dash, not a crash).
    public var line: String {
        let rate = decodeTPS.isFinite ? Int(decodeTPS.rounded()) : 0
        return "Decode \(rate) tok/s · \(generatedTokens) tok · ctx \(ctxUsed.formatted())"
    }
}

/// A turn's decode work, accumulated from the wire's status stream.
///
/// The engine reports `gen_tps` as `generated / (now - t0)` for the *current
/// generation segment* (`ds4_agent.c:14914`) and resets both counters at every
/// prefill (`:15191`) — so a turn with tool rounds is several segments, not one.
/// Each segment's last sample gives that segment's tokens and, via its own rate,
/// the time the engine spent decoding them; summing both across segments yields
/// the turn's true decode total and decode time.
///
/// Deriving the average this way rather than from wire `ts` deltas is
/// deliberate. Wall time between statuses also contains prefill and host-tool
/// round trips — and the engine keeps reporting `generating` while it is blocked
/// on a tool result, so no state check can subtract them. Measured on a real
/// tool-heavy turn, a ts-delta average reads 7.3 tok/s where the engine's own
/// clock says 57. Using the engine's rate keeps the arithmetic on the only clock
/// that knows which time was decode.
public struct DecodeAccumulator: Equatable, Sendable {
    /// The last status sample of each generation segment, in order. One sample
    /// per segment is all the arithmetic needs: the engine's `gen_tps` is
    /// cumulative within the segment, so its final sample already summarizes it.
    private var segments: [StatusSnapshot] = []
    /// The segment still generating, if any.
    private var open: StatusSnapshot?
    /// The `ready` event's authoritative token count for the final segment.
    private var finalGenerated: Int?

    public init() {}

    /// Fold one status snapshot. Any non-`generating` state (prefill, idle)
    /// ends the open segment.
    public mutating func apply(_ snapshot: StatusSnapshot) {
        if snapshot.state == "generating" {
            open = snapshot
        } else if let open {
            segments.append(open)
            self.open = nil
        }
    }

    /// Close the turn with the `ready` event's token count, which supersedes the
    /// final segment's last status sample: samples are periodic, so the last one
    /// misses whatever that segment generated afterwards. It applies to the
    /// final segment ONLY — the engine resets its counter at every prefill, so
    /// `ready` alone undercounts a tool-heavy turn (measured on
    /// `fixtures/agent/tool-rounds.ndjson`: 298 reported against 714 generated).
    public mutating func finish(finalGenerated: Int?) {
        if let open {
            segments.append(open)
            self.open = nil
        }
        self.finalGenerated = finalGenerated
    }

    /// Tokens and decode seconds across every segment. The final segment takes
    /// the authoritative count when `finish` supplied one.
    private var total: (tokens: Int, seconds: Double) {
        var all = segments
        if let open { all.append(open) }
        var tokens = 0
        var seconds = 0.0
        for (index, segment) in all.enumerated() {
            guard segment.genTPS > 0, segment.genTPS.isFinite else { continue }
            let isFinal = index == all.count - 1
            let count = (isFinal ? finalGenerated : nil) ?? segment.generated
            guard count > 0 else { continue }
            tokens += count
            seconds += Double(count) / segment.genTPS
        }
        return (tokens, seconds)
    }

    /// Tokens the turn generated across all its segments — the engine's
    /// per-segment counter reset makes any single snapshot an undercount.
    public var generatedTokens: Int { total.tokens }

    /// The turn's decode average, or nil when no segment produced tokens (the
    /// caller then shows the engine's last reported rate rather than a
    /// fabricated average).
    public var tokensPerSecond: Double? {
        let total = self.total
        guard total.tokens > 0, total.seconds > 0 else { return nil }
        return Double(total.tokens) / total.seconds
    }
}
