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

    /// Average decode rate over a turn, from the wire's monotonic counters:
    /// generated-token delta over `ts` delta (`ts` is `CLOCK_MONOTONIC`
    /// microseconds since boot — `agent_buf_put_ts`; NOT nanoseconds as the
    /// pre-P21 code assumed, which read 1000x too slow). nil unless both
    /// snapshots exist, time advanced, and tokens advanced — the caller then
    /// falls back to the engine-reported rate instead of a fabricated average.
    public static func averageDecodeTPS(first: StatusSnapshot, last: StatusSnapshot) -> Double? {
        guard last.ts > first.ts, last.generated > first.generated else { return nil }
        let dt = Double(last.ts - first.ts) / 1_000_000.0
        let dgen = Double(last.generated - first.generated)
        guard dt > 0 else { return nil }
        return dgen / dt
    }

    /// The decode-average baseline for a turn: the first snapshot whose state
    /// is `generating`, held once captured. Excludes prefill — only decode
    /// belongs in a "Decode tok/s" — and must start at the turn's own counter
    /// (the engine resets `generated` per turn, so the previous turn's trailing
    /// status was a garbage baseline from turn 2 on). nil until a generating
    /// snapshot arrives.
    public static func baseline(for latest: StatusSnapshot, current: StatusSnapshot?) -> StatusSnapshot? {
        if let current { return current }
        return latest.state == "generating" ? latest : nil
    }

    /// "Decode 47 tok/s · 512 tok · ctx 9,580" — the static line under the
    /// bubble, fixed once the turn completes. Never traps on a non-finite
    /// rate (a garbage wire value renders as a dash, not a crash).
    public var line: String {
        let rate = decodeTPS.isFinite ? Int(decodeTPS.rounded()) : 0
        return "Decode \(rate) tok/s · \(generatedTokens) tok · ctx \(ctxUsed.formatted())"
    }
}
