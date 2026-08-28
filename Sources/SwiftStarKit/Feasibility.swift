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
    /// The RAM-based ceiling raising `iogpu.wired_limit_mb` could reach, when
    /// the caller supplied one (P25 Cycle 4b's Metal-working-set admission
    /// path). nil for a caller using the legacy free+inactive-pages
    /// denominator, which has no GPU wired-limit remedy to offer — this is
    /// the machine-readable form of what `message` says in prose, so a UI
    /// wanting a copyable command or a "Raise the limit" button doesn't have
    /// to parse the string (Fable review, 2026-08-28).
    public let wiredLimitAdvisoryBytes: Int64?

    public init(
        message: String, deficitBytes: Int64, availableBytes: Int64, plannedBytes: Int64,
        wiredLimitAdvisoryBytes: Int64? = nil
    ) {
        self.message = message
        self.deficitBytes = deficitBytes
        self.availableBytes = availableBytes
        self.plannedBytes = plannedBytes
        self.wiredLimitAdvisoryBytes = wiredLimitAdvisoryBytes
    }

    /// The single fact a "Raise the limit" UI action needs: the exact value
    /// to set `iogpu.wired_limit_mb` to, in bytes — non-nil only when an
    /// advisory was supplied AND raising it would actually admit this
    /// launch. Covers both cases a caller must not conflate into "show the
    /// button": no GPU-wired-limit context at all (legacy denominator,
    /// `wiredLimitAdvisoryBytes` nil), and a genuinely undersized machine
    /// where raising the limit wouldn't be enough (advisory present but
    /// below `plannedBytes`) — both read as nil here.
    public var wiredLimitFixBytes: Int64? {
        Self.wiredLimitFix(plannedBytes: plannedBytes, advisory: wiredLimitAdvisoryBytes)
    }

    /// Shared with `VariantGate`'s message construction so the prose and this
    /// machine-readable fact can never disagree about whether raising the
    /// limit would help — one formula, not two independently maintained ones.
    static func wiredLimitFix(plannedBytes: Int64, advisory: Int64?) -> Int64? {
        guard let advisory, plannedBytes <= advisory else { return nil }
        return advisory
    }
}
