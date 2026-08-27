import Foundation

/// The infeasibility payload a variant gate (or any admission path) carries:
/// what the launch needs, what is available, and the shortfall. A person can
/// act on the message. `Feasibility.check` (the pre-`VariantGate` arithmetic
/// and its Laguna-scratch correction) was removed 2026-08-27 — `VariantGate`
/// owns admission now, and this is just its reason type.
public struct FeasibilityReason: Equatable, Sendable {
    public let message: String
    public let deficitBytes: Int64
    public let availableBytes: Int64
    public let plannedBytes: Int64

    public init(message: String, deficitBytes: Int64, availableBytes: Int64, plannedBytes: Int64) {
        self.message = message
        self.deficitBytes = deficitBytes
        self.availableBytes = availableBytes
        self.plannedBytes = plannedBytes
    }
}
