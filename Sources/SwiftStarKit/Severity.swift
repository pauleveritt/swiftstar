import Foundation

/// Health level of a gauge. Views map it to a color; this file never does.
public enum Severity: Equatable, Hashable, Sendable {
    case healthy
    case warning
    case critical

    /// Context fill as a fraction of the window: warning at half, critical at
    /// three quarters. Integer arithmetic keeps the thresholds exact at any
    /// window size; an unknown or empty window reads healthy.
    public static func ofContext(used: Int?, size: Int?) -> Severity {
        guard let used, let size, size > 0 else { return .healthy }
        if used * 4 >= size * 3 { return .critical }
        if used * 2 >= size { return .warning }
        return .healthy
    }
}
