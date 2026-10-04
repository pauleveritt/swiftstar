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

    public static func contextTooltip(used: Int, size: Int) -> String {
        let percent = Double(used) / Double(size) * 100
        return String(format: "Context window: %@ of %@ tokens (%.0f%% used).",
                      used.formatted(), size.formatted(), percent)
    }
}
