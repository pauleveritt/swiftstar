import Foundation

/// P6's analyzer constants and pure arithmetic. Named, re-anchorable values,
/// following the same discipline as `DialLogic`'s thresholds: re-anchor against
/// fresh measurement before trusting far from where they were measured.
public enum DiagnosticsLogic {
    /// `ctx_used` ceiling for "early / small context" baseline samples.
    public static let baselineWindowTokens = 8_192
    /// Degradation ratio (baseline / current) bands. Critical is deliberately
    /// below the measured ~7x so a real problem is flagged long before it is
    /// catastrophic; the exact ratio still travels in the finding payload.
    public static let degradationWarningRatio = 2.0
    public static let degradationCriticalRatio = 3.5
    /// `cached / prompt` floor for "prefix cache healthy".
    public static let prefixCacheHealthyFraction = 0.5

    /// The session's own early prefill rate: the MEDIAN prefill_tps among
    /// statuses with `ctx_used <= baselineWindowTokens`. Median, not max — a
    /// single garbage outlier sample must not poison the baseline into a
    /// fabricated critical finding. Nil if none qualify.
    public static func baselineTPS(_ statuses: [StatusSnapshot]) -> Double? {
        let rates = statuses
            .filter { $0.prefillTPS > 0 && $0.ctxUsed <= baselineWindowTokens }
            .map(\.prefillTPS)
            .sorted()
        guard !rates.isEmpty else { return nil }
        return rates[rates.count / 2]
    }

    /// The current prefill rate: the last status with `prefill_tps > 0`.
    public static func currentTPS(_ statuses: [StatusSnapshot]) -> Double? {
        statuses.last(where: { $0.prefillTPS > 0 })?.prefillTPS
    }

    public static func degradationSeverity(ratio: Double) -> Severity {
        if ratio >= degradationCriticalRatio { return .critical }
        if ratio >= degradationWarningRatio { return .warning }
        return .healthy
    }

    public static func prefixCacheSeverity(hitFraction: Double) -> Severity {
        hitFraction >= prefixCacheHealthyFraction ? .healthy : .warning
    }
}
