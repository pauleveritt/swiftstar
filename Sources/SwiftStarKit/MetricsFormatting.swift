import Foundation

/// Display formatting for engine metrics, shared by `InspectorView` and the
/// composer's bottom status bar — kept in one place so the two readings
/// never drift.
public enum MetricsFormatting {
    public static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.1f tok/s", $0) } ?? "—"
    }

    public static func bytes(_ value: Int64?) -> String {
        value.map { $0.formatted(.byteCount(style: .memory)) } ?? "—"
    }

    public static func contextTooltip(used: Int, size: Int, locale: Locale = .current) -> String {
        let percent = Double(used) / Double(size) * 100
        return String(format: "Context window: %@ of %@ tokens (%.0f%% used).",
                      number(used, locale: locale), number(size, locale: locale), percent)
    }

    /// The status bar's text: rates and the composer's label while the session
    /// runs, else just the label (it carries the exit message once ended).
    public static func statusLine(phase: EngineSessionPhase, label: String, metrics: EngineMetricsState) -> String {
        guard phase == .running else { return label }
        return "Prefill avg \(rate(metrics.prefillTPS)) · Generation avg \(rate(metrics.generationTPS)) · \(label)"
    }

    /// A count with the locale's grouping ("8,192", "8.192").
    public static func number(_ n: Int, locale: Locale = .current) -> String {
        n.formatted(.number.locale(locale))
    }

    /// A size in GiB, one decimal, in the locale's notation.
    public static func gib(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " GiB"
    }

    public static func gib(bytes: Int64, locale: Locale = .current) -> String {
        gib(Double(bytes) / 1_073_741_824, locale: locale)
    }

    /// The Session card's prefix-cache line: "hit · 944 tokens in 20 ms",
    /// "miss · 944 tokens filled in 3.9s", or the engine's word and the count.
    public static func prefixCacheLine(_ p: EnginePrefixCache, locale: Locale = .current) -> String {
        let tokens = p.tokens.map { " · \(number($0, locale: locale)) tokens" } ?? ""
        switch p.outcome {
        case "hit":
            return "hit\(tokens)" + (p.loadMs.map { " in \(Int($0.rounded())) ms" } ?? "")
        case "miss":
            return "miss\(tokens)" + (p.fillMs.map { " filled in \(duration(seconds: $0 / 1000))" } ?? "")
        default:
            return "\(p.outcome)\(tokens)"
        }
    }

    /// One style for every duration: tenths under ten seconds, whole seconds
    /// from there ("1.8s", "75s").
    public static func duration(seconds: Double) -> String {
        let tenths = (seconds * 10).rounded() / 10
        return tenths < 10 ? String(format: "%.1fs", tenths) : String(format: "%.0fs", tenths)
    }
}
