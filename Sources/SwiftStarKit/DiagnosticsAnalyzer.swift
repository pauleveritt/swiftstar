import Foundation

/// The deterministic diagnostics engine. Consumes already-parsed wire + trace
/// events (it does not re-read files — the production parsers do that) and emits
/// typed findings. Every rule is a pure function of its inputs.
public struct DiagnosticsAnalyzer: Sendable {
    public init() {}

    public func analyze(events: [WireEvent], trace: [TraceEvent]) -> [Finding] {
        let statuses = statusSnapshots(events)
        let baseline = DiagnosticsLogic.baselineTPS(statuses)
        let current = DiagnosticsLogic.currentTPS(statuses)
        let ratio: Double? = {
            guard let baseline, let current, baseline > 0, current > 0 else { return nil }
            return baseline / current
        }()

        var findings: [Finding] = []

        // 1. Where you are in your context (absolute anchoring).
        if let last = statuses.last {
            findings.append(.contextPosition(
                ctxUsed: last.ctxUsed,
                ctxSize: last.ctxSize,
                severity: DialLogic.contextSeverity(ctxUsed: last.ctxUsed)
            ))
        }

        // 2. Current prefill throughput.
        if let current {
            findings.append(.prefillThroughput(currentTPS: current))
        }

        // 3. How far off this session's own baseline.
        if let baseline, let current, let ratio {
            let severity = DiagnosticsLogic.degradationSeverity(ratio: ratio)
            if severity != .healthy {
                findings.append(.baselineDrift(
                    baselineTPS: baseline, currentTPS: current, ratio: ratio, severity: severity))
            }
        }

        // 4. Prefix-cache health (most recent prefill sync).
        if let hit = latestCacheHitFraction(trace) {
            findings.append(.prefixCache(
                hitFraction: hit,
                severity: DiagnosticsLogic.prefixCacheSeverity(hitFraction: hit)))
        }

        // 5. Compactions observed.
        for event in trace {
            if case .compaction(_, let old, let new, _, let tail) = event {
                findings.append(.compactionObserved(
                    CompactionObserved(oldTokens: old, newTokens: new, tailTokens: tail)))
            }
        }

        // 6. Would compaction help (deep AND degraded).
        if let last = statuses.last, let ratio {
            let deep = last.ctxUsed >= DialLogic.contextWarningTokens
            let degraded = ratio >= DiagnosticsLogic.degradationWarningRatio
            if deep && degraded {
                let severity = DiagnosticsLogic.degradationSeverity(ratio: ratio)
                let verdict: CompactionVerdict
                if let hit = latestCacheHitFraction(trace) {
                    verdict = hit >= DiagnosticsLogic.prefixCacheHealthyFraction
                        ? .willNotFixRate(cacheHitFraction: hit)
                        : .mayRecoverCache(cacheHitFraction: hit)
                } else {
                    verdict = .unknown
                }
                findings.append(.compactionVerdict(verdict: verdict, severity: severity))
            }
        }

        return findings
    }

    private func statusSnapshots(_ events: [WireEvent]) -> [StatusSnapshot] {
        events.compactMap { event in
            if case .status(let s) = event { return s }
            return nil
        }
    }

    private func latestCacheHitFraction(_ trace: [TraceEvent]) -> Double? {
        let syncs: [(prompt: Int, cached: Int)] = trace.compactMap {
            if case .prefillSync(let prompt, let cached, _, _, _) = $0, prompt > 0 {
                return (prompt, cached)
            }
            return nil
        }
        guard let last = syncs.last else { return nil }
        return Double(last.cached) / Double(last.prompt)
    }
}
