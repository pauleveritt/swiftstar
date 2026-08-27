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
    /// nanoseconds on macOS). nil unless both snapshots exist, time advanced,
    /// and tokens advanced — the caller then falls back to the engine-reported
    /// rate instead of showing a fabricated average.
    public static func averageDecodeTPS(first: StatusSnapshot, last: StatusSnapshot) -> Double? {
        guard last.ts > first.ts, last.generated > first.generated else { return nil }
        let dt = Double(last.ts - first.ts) / 1_000_000_000.0
        let dgen = Double(last.generated - first.generated)
        guard dt > 0 else { return nil }
        return dgen / dt
    }

    /// "Decode 47 tok/s · 512 tok · ctx 9,580" — the static line under the
    /// bubble, fixed once the turn completes.
    public var line: String {
        "Decode \(Int(decodeTPS.rounded())) tok/s · \(generatedTokens) tok · ctx \(ctxUsed.formatted())"
    }
}
