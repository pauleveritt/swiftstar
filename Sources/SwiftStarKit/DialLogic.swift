import Foundation

public enum Severity: Equatable, Sendable {
    case healthy
    case warning
    case critical
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
    // Provisional, absolute-anchored at the measured 150,000 everyday setting
    // (telemetry-findings: ~7x degradation at ~92,500 ctx). Re-anchor before
    // trusting on other hardware — keep these as named constants for that.
    public static let contextWarningTokens = 37_500
    public static let contextCriticalTokens = 75_000
    public static let memoryWarningFraction = 0.70
    public static let memoryCriticalFraction = 0.90

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

    /// Fixed-width field (learning #2): pad so value changes don't shift the
    /// surrounding line.
    public static func fixedWidth(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return String(repeating: " ", count: width - text.count) + text
    }

    /// Private-API hardware reads can return garbage; the surface never shows
    /// it. Negative -> 0, NaN -> 0, clean values pass through.
    public static func sanitize(_ raw: MachineSnapshot) -> MachineSnapshot {
        func clamp(_ v: Double) -> Double { v.isNaN || v < 0 ? 0 : v }
        let resident: Int64?
        if let r = raw.residentBytes, r < 0 { resident = 0 } else { resident = raw.residentBytes }
        return MachineSnapshot(
            residentBytes: resident,
            watts: clamp(raw.watts),
            gpuUtilization: clamp(raw.gpuUtilization),
            cpuUtilization: clamp(raw.cpuUtilization)
        )
    }
}
