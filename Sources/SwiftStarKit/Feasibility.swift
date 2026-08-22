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
    public static func check(
        plannedBytes: Int64,
        availableBytes: Int64,
        modelName: String
    ) -> FeasibilityVerdict {
        guard plannedBytes > availableBytes else { return .feasible }
        let deficit = plannedBytes - availableBytes
        let message = """
        "\(modelName)" needs \(gib(plannedBytes)) GiB of RAM but only \
        \(gib(availableBytes)) GiB is available (short \(gib(deficit)) GiB). \
        Close memory-heavy apps, or pick a smaller quant and check again.
        """
        return .infeasible(FeasibilityReason(
            message: message,
            deficitBytes: deficit,
            availableBytes: availableBytes,
            plannedBytes: plannedBytes
        ))
    }

    private static func gib(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }
}
