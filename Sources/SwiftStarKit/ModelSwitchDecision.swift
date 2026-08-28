import Foundation

/// The result of the model-switch decision (P22).
public enum ModelSwitchDecision: Equatable, Sendable {
    /// Stop the current session and re-spawn with the target model.
    case apply
    /// The target resolves to the model already running — nothing to do.
    case noChange
    /// Refuse the switch; the current session is untouched.
    case refused(String)
}

/// The pure switch decision (P22): admission × not-generating × model-changed.
/// `admission` is nil for a custom/unverified model file — treated like the
/// fresh-launch path, which also skips the gate (Settings contract: "a
/// selected variant is verified before launch; a custom file is not").
public enum ModelSwitchEvaluator {
    public static func decide(
        isGenerating: Bool,
        runningModelFile: URL,
        targetModelFile: URL,
        admission: VariantAdmission?
    ) -> ModelSwitchDecision {
        if isGenerating {
            return .refused("Model switching is refused while the agent is generating.")
        }
        if runningModelFile.standardizedFileURL == targetModelFile.standardizedFileURL {
            return .noChange
        }
        switch admission {
        case nil, .admitted:
            return .apply
        case .contractMismatch(let mismatches):
            return .refused(mismatches.map(\.message).joined(separator: "\n"))
        case .infeasible(let reason):
            return .refused(reason.message)
        }
    }
}
