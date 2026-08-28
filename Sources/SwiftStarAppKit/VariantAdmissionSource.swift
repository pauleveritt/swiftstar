import Foundation

/// The single seam every `VariantGate.admit` call site uses for "how much
/// memory is available for this launch" (P25 Cycle 4a) and "what should the
/// refusal say if it isn't enough" (Cycle 4b). `VariantGate.admit` takes
/// plain `Int64` values — this is the one place that decides which live
/// system facts back them, so a future change again has one place to touch
/// instead of every call site independently.
///
/// Cycle 4b switched `availableBytes()` from `MemorySnapshot`'s free+inactive
/// pages to `MetalWorkingSet`'s wired-limit-aware ceiling — the denominator a
/// large GPU-resident model launch is actually bound by (P25 design doc,
/// "the actual blocker"). This is a **shared, cross-variant** change: every
/// variant now admits against a more permissive (and more accurate) ceiling,
/// not just DeepSeek V4 Flash.
public enum VariantAdmissionSource {
    /// The ceiling a launch's total resident bytes are compared against.
    public static func availableBytes() -> Int64 {
        MetalWorkingSet.effectiveLimitBytes()
    }

    /// The ceiling raising `iogpu.wired_limit_mb` could reach on this
    /// machine — passed to `VariantGate.admit` so a refusal that raising the
    /// limit would actually fix can say so, instead of suggesting the
    /// free-page advice that applied to the old denominator.
    public static func wiredLimitAdvisoryBytes() -> Int64 {
        MetalWorkingSet.ramAdvisoryCeilingBytes()
    }
}
