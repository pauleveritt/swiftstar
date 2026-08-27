import Foundation

public enum Severity: Equatable, Hashable, Sendable {
    case healthy
    case warning
    case critical

    /// Deterministic label for phrasing (Kit, not view, concern).
    public var label: String {
        switch self {
        case .healthy: return "healthy"
        case .warning: return "warning"
        case .critical: return "critical"
        }
    }
}

/// One live machine sample from the OS collectors. `residentBytes` is nil when
/// no engine pid is supplied (per-process); the other three are system-wide.
public struct MachineSnapshot: Equatable, Sendable {
    public var residentBytes: Int64?
    public var watts: Double
    public var gpuUtilization: Double
    public var cpuUtilization: Double

    public init(residentBytes: Int64?, watts: Double, gpuUtilization: Double, cpuUtilization: Double) {
        self.residentBytes = residentBytes
        self.watts = watts
        self.gpuUtilization = gpuUtilization
        self.cpuUtilization = cpuUtilization
    }
}

/// The harvest's widget learnings, as pure functions. Color mapping is a view
/// concern — views map `Severity` to a color; Kit never does.
public enum DialLogic {
    // Re-anchored for the app's 51,200-token default context (P21 forward):
    // warning at ~half, critical at ~73% — critical must be REACHABLE at 50k
    // (the previous 37.5k/75k anchors were derived from a 150k setting, so
    // critical never fired). Absolute-token curve (learning #1), not a fraction.
    public static let contextWarningTokens = 25_000
    public static let contextCriticalTokens = 37_500
    public static let memoryWarningFraction = 0.70
    public static let memoryCriticalFraction = 0.90
    /// Generic percent thresholds for the engine's own throttle percent
    /// (`StatusSnapshot.power`) — a different quantity from watts, so it does
    /// not reuse `wattsMax`/memory's fraction thresholds.
    public static let throttleWarningPercent = 50.0
    public static let throttleCriticalPercent = 80.0

    /// Absolute context anchoring (learning #1): curve-shaped on tokens, never
    /// a fraction of ctx_size.
    public static func contextSeverity(ctxUsed: Int) -> Severity {
        if ctxUsed >= contextCriticalTokens { return .critical }
        if ctxUsed >= contextWarningTokens { return .warning }
        return .healthy
    }

    /// Generic memory thresholds (learning #5) — deliberately not the context
    /// curve.
    public static func memorySeverity(residentBytes: Int64, plannedBytes: Int64) -> Severity {
        guard plannedBytes > 0, residentBytes >= 0 else { return .healthy }
        let fraction = Double(residentBytes) / Double(plannedBytes)
        if fraction >= memoryCriticalFraction { return .critical }
        if fraction >= memoryWarningFraction { return .warning }
        return .healthy
    }

    /// The engine's own throttle percent (0-100), NOT `MachineSnapshot.watts`
    /// severity — a distinct quantity from a distinct source (the wire, not
    /// `IOReportPower`).
    public static func throttleSeverity(percent: Double) -> Severity {
        if percent >= throttleCriticalPercent { return .critical }
        if percent >= throttleWarningPercent { return .warning }
        return .healthy
    }

    /// Fixed-width field (learning #2): pad so value changes don't shift the
    /// surrounding line.
    public static func fixedWidth(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    /// Private-API hardware reads can return garbage; the surface never shows
    /// it. NaN, ±∞, negatives → 0; watts is additionally upper-clamped (a
    /// garbage IOReport delta must not render as 9.2e18 W); clean values pass
    /// through.
    public static func sanitize(_ raw: MachineSnapshot) -> MachineSnapshot {
        func finite(_ v: Double) -> Bool { v.isFinite && v >= 0 }
        return MachineSnapshot(
            residentBytes: raw.residentBytes.map { $0 < 0 ? 0 : $0 },
            watts: finite(raw.watts) ? Swift.min(raw.watts, wattsMax) : 0,
            gpuUtilization: finite(raw.gpuUtilization) ? raw.gpuUtilization : 0,
            cpuUtilization: finite(raw.cpuUtilization) ? raw.cpuUtilization : 0
        )
    }

    /// Upper bound for a plausible watts reading — a Mac draws single-digit
    /// hundreds, so this only catches IOReport garbage.
    public static let wattsMax: Double = 10_000
}
