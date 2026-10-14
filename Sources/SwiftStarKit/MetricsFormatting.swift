import Foundation

/// Display formatting for engine metrics, shared by `InspectorView` and the
/// composer's bottom status bar — kept in one place so the two readings
/// never drift.
public enum MetricsFormatting {
    public static func rate(_ value: Double?, locale: Locale = .current) -> String {
        value.map { "\(oneDecimal($0, locale: locale)) tok/s" } ?? "—"
    }

    /// A GPU figure in GiB, as the engine's plan is (SU.6g, D2).
    public static func bytes(_ value: Int64?, locale: Locale = .current) -> String {
        value.map { gib(bytes: $0, locale: locale) } ?? "—"
    }

    public static func contextTooltip(used: Int, size: Int, locale: Locale = .current) -> String {
        let percent = (Double(used) / Double(size) * 100).formatted(.number.precision(.fractionLength(0)).locale(locale))
        return "Context window: \(number(used, locale: locale)) of \(number(size, locale: locale)) tokens (\(percent)% used)."
    }

    /// The GPU figures explained (SU.6g, D2): actual against the engine's
    /// plan for this model and context, and macOS's limit as context only.
    public static func gpuTooltip(allocated: Int64, planGiB: Double?, limit: Int64?, locale: Locale = .current) -> String {
        var text = "GPU memory: \(gib(bytes: allocated, locale: locale)) allocated"
        if let planGiB {
            text += ", of the \(gib(planGiB, locale: locale)) the engine planned for this model and context."
        } else {
            text += "."
        }
        if let limit {
            text += " macOS lets the GPU use up to \(gib(bytes: limit, locale: locale)) on this Mac."
        }
        return text
    }

    /// One of the status bar's two rates, bare: "189.8", or "—" before a
    /// measurement (SU.10).
    public static func rateNumber(_ value: Double?, locale: Locale = .current) -> String {
        value.map { oneDecimal($0, locale: locale) } ?? "—"
    }

    private static func oneDecimal(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }

    /// The widest number a status bar slot is sized for, so the rates hold
    /// still as digits come and go.
    public static let rateSlot = "8888.8"

    /// What the status bar's two numbers are.
    public static func ratesTooltip(prefill: Double?, generation: Double?) -> String {
        guard let prefill, let generation else {
            return "Prefill and generation, in tokens per second: averages over this session, once a turn has run."
        }
        return "Prefill \(rate(prefill)), generation \(rate(generation)): averages over this session."
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
    public static func duration(seconds: Double, locale: Locale = .current) -> String {
        let tenths = (seconds * 10).rounded() / 10
        let digits = tenths < 10 ? 1 : 0
        return tenths.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale)) + "s"
    }
}
