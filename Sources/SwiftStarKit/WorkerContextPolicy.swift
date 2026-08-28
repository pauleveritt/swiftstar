import Foundation

/// The per-worker context size for pool workers (P23, D8). The measured speed
/// leg: a 4k worker needs ~1.5 GB of scratch where a full-ctx worker needs
/// ~6.15 GB, and prefill cost tracks ctx (4.2× ceiling, P11). The app clamps
/// through the same arithmetic the parent uses, so a worker context can never
/// bypass admission.
public enum WorkerContextPolicy {
    /// The default worker context. 8,192 halves scratch (~3.1 GB vs ~6.15 GB)
    /// while leaving a worker room to hold a bounded packet; scratch savings
    /// begin only below 16,384 (`rows = min(ctx, 16384)` on Laguna).
    public static let defaultContext = 8192
    /// The floor below which the engine's own minimums apply and the scratch
    /// curve stops helping (D8: clamped [4,096, parent]).
    public static let minContext = 4096

    /// Clamp a requested worker context into `[minContext, parentContext]`.
    /// `requested <= 0` inherits the parent. The parent cap is applied last
    /// and therefore wins even when it is below `minContext` — exceeding the
    /// parent is the case that would bypass admission, so it is the binding
    /// constraint.
    public static func clamp(requested: Int, parentContext: Int) -> Int {
        let effective = requested > 0 ? requested : parentContext
        return Swift.min(Swift.max(effective, minContext), parentContext)
    }

    /// The configured worker context (UserDefaults `workerContextSize`,
    /// default 8,192; 0 = inherit the parent). The pure resolve, so
    /// `AgentDefaultSettings` and the tests agree on one rule.
    public static func resolve(defaults: UserDefaults) -> Int {
        defaults.object(forKey: "workerContextSize") as? Int ?? defaultContext
    }
}
