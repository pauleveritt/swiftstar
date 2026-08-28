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

/// The pure switch decision (P22): admission × not-generating × settings-
/// changed. `admission` is nil for a custom/unverified model file — treated
/// like the fresh-launch path, which also skips the gate (Settings contract:
/// "a selected variant is verified before launch; a custom file is not").
public enum ModelSwitchEvaluator {
    /// Compares the fields `AgentDefaultSettings.resolve()` actually
    /// produces (model file, context size, runtime flags, engine dir,
    /// workspace, shell posture) rather than just the model file — a
    /// same-file switch that only changed contextSize or runtime flags
    /// (e.g. the P22 SSD-streaming config) must still apply, not be
    /// swallowed as a no-op. Deliberately excludes `tracePath`/
    /// `systemPrompt`/generation knobs: those are set on the running
    /// settings after `resolve()` returns (`startAgent()`), so a freshly
    /// resolved `targetSettings` never carries them and a full-struct
    /// comparison would report every switch as a change. The model file is
    /// compared with symlinks resolved so two spellings of one physical
    /// file (a `SWIFTSTAR_MODEL` override through a symlink vs. the
    /// registry's canonical path) don't register as a change.
    public static func decide(
        isGenerating: Bool,
        isConsulting: Bool,
        runningSettings: AgentSettings,
        targetSettings: AgentSettings,
        admission: VariantAdmission?
    ) -> ModelSwitchDecision {
        if isGenerating {
            return .refused("Model switching is refused while the agent is generating.")
        }
        if isConsulting {
            return .refused("Model switching is refused while a /chat consult is running.")
        }
        let unchanged =
            runningSettings.modelPath.resolvingSymlinksInPath()
                == targetSettings.modelPath.resolvingSymlinksInPath()
            && runningSettings.contextSize == targetSettings.contextSize
            && runningSettings.runtime == targetSettings.runtime
            && runningSettings.engineDir == targetSettings.engineDir
            && runningSettings.workspace == targetSettings.workspace
            && runningSettings.shellAllowed == targetSettings.shellAllowed
        if unchanged {
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
