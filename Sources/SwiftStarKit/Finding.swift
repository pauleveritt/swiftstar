import Foundation

/// One compaction's rebuild facts, from a trace `compacted` line.
public struct CompactionObserved: Equatable, Hashable, Sendable {
    public let oldTokens: Int
    public let newTokens: Int
    public let tailTokens: Int
    public init(oldTokens: Int, newTokens: Int, tailTokens: Int) {
        self.oldTokens = oldTokens
        self.newTokens = newTokens
        self.tailTokens = tailTokens
    }
}

/// The deterministic answer to "would compaction help". The whole point is to
/// tell apart "size is the cause, cache is fine" from "cache is broken, rebuild
/// it" — the measurement says the former is what actually happens.
public enum CompactionVerdict: Equatable, Hashable, Sendable {
    case willNotFixRate(cacheHitFraction: Double)
    case mayRecoverCache(cacheHitFraction: Double)
    case unknown
}

/// A machine-computed diagnostic finding. Strongly typed so tests assert on
/// values, never on rendered prose (binding rule 3). `DeterministicPhraser`
/// turns one of these into a sentence; a model phraser can replace it later.
public enum Finding: Equatable, Hashable, Sendable {
    case contextPosition(ctxUsed: Int, ctxSize: Int, severity: Severity)
    case prefillThroughput(currentTPS: Double)
    case baselineDrift(baselineTPS: Double, currentTPS: Double, ratio: Double, severity: Severity)
    case prefixCache(hitFraction: Double, severity: Severity)
    case compactionObserved(CompactionObserved)
    case compactionVerdict(verdict: CompactionVerdict, severity: Severity)
}

/// Renders a `Finding` to a sentence built only from the finding's own numbers.
/// This is the shipped renderer; a model phraser implements the same shape later.
public struct DeterministicPhraser: Sendable {
    public init() {}

    public func phrase(_ finding: Finding) -> String {
        switch finding {
        case .contextPosition(let ctxUsed, let ctxSize, let severity):
            return "Context is at \(ctxUsed) of \(ctxSize) tokens (\(severity.label))."
        case .prefillThroughput(let tps):
            return "Current prefill throughput is \(Self.rate(tps)) tok/s."
        case .baselineDrift(let baseline, let current, let ratio, let severity):
            return "Prefill is \(Self.rate(current)) tok/s — \(Self.ratio(ratio))× slower than this session's own baseline of \(Self.rate(baseline)) tok/s at small context (\(severity.label))."
        case .prefixCache(let hit, let severity):
            return "Prefix cache is \(Self.percent(hit)) hit (\(severity.label))."
        case .compactionObserved(let c):
            return "Compaction rebuilt context from \(c.oldTokens) to \(c.newTokens) tokens (tail \(c.tailTokens))."
        case .compactionVerdict(let verdict, let severity):
            switch verdict {
            case .willNotFixRate(let hit):
                return "Compaction will not fix this — the prefix cache is already healthy (\(Self.percent(hit)) hit); the slowdown is context size (\(severity.label))."
            case .mayRecoverCache(let hit):
                return "Compaction may help — the prefix cache is missing (\(Self.percent(hit)) hit); a rebuild could recover it (\(severity.label))."
            case .unknown:
                return "Whether compaction would help is unknown — no prefix-cache data in the trace (\(severity.label))."
            }
        }
    }

    static func rate(_ v: Double) -> String { String(format: "%.0f", v) }
    static func ratio(_ v: Double) -> String { String(format: "%.1f", v) }
    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}
