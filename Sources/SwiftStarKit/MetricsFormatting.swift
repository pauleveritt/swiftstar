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

    /// One style for every duration: tenths under ten seconds, whole seconds
    /// from there ("1.8s", "75s").
    public static func duration(seconds: Double) -> String {
        let tenths = (seconds * 10).rounded() / 10
        return tenths < 10 ? String(format: "%.1fs", tenths) : String(format: "%.0fs", tenths)
    }
}
