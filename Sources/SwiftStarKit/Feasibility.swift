import Foundation

public struct FeasibilityReason: Equatable, Sendable {
    public let message: String
    public let deficitBytes: Int64
    public let availableBytes: Int64
    public let plannedBytes: Int64
}

public enum FeasibilityVerdict: Equatable, Sendable {
    case feasible
    case infeasible(FeasibilityReason)
}

/// Arithmetic on the engine's own startup memory plan. Never a percentage
/// heuristic: the engine's planned_bytes is the number that matters, and the
/// message is computed from it. A person can act on the result.
public enum Feasibility {
    /// The engine's `planned_bytes` under-reports on Laguna: `laguna_graph_alloc`
    /// reserves ~6.1 GiB of per-session GPU scratch that the estimator omits
    /// (the estimator computes single-row scratch; the committed `golden.ndjson`
    /// `ready` carries `scratch_bytes: 784752` while the same session's stderr
    /// reports `scratch 5862.21 MiB`). Until the estimator is fixed upstream,
    /// the correction is a documented constant (ROADMAP P3 dependency bullet,
    /// research note `2026-08-22-p11-engine-constraints-and-corrections.md`).
    private static let lagunaScratchUnderreportBytes: Int64 = 6_549_825_126  // ~6.1 GiB

    public static func check(
        plannedBytes: Int64,
        availableBytes: Int64,
        modelName: String
    ) -> FeasibilityVerdict {
        guard plannedBytes >= 0, availableBytes >= 0 else { return .feasible }
        // Apply the Laguna correction so a launch clearing the gate by less
        // than ~6.1 GiB is refused instead of admitted and then exceeding the
        // plan. The correction is a constant, not a re-derived mirror.
        let effective = plannedBytes
            + (modelName.lowercased().contains("laguna") ? lagunaScratchUnderreportBytes : 0)
        guard effective > availableBytes else { return .feasible }
        let deficit = effective - availableBytes
        let message = """
        "\(modelName)" needs \(gib(effective)) GiB of RAM but only \
        \(gib(availableBytes)) GiB is available (short \(gib(deficit)) GiB). \
        Close memory-heavy apps, or pick a smaller quant and check again.
        """
        return .infeasible(FeasibilityReason(
            message: message,
            deficitBytes: deficit,
            availableBytes: availableBytes,
            plannedBytes: effective
        ))
    }

    private static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}
