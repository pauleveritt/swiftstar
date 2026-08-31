import Foundation

/// `AgentController.defaultSettings()`'s pure logic, extracted (item 5b, P22
/// cleanup) so it is unit-testable: `Sources/SwiftStar` has no test target,
/// so the resolution logic — engine dir, model (through `VariantResolver`),
/// context clamp, workspace, shell posture, and power-saving default — was
/// untestable in place. Takes
/// its implicit inputs explicitly (`UserDefaults`, the environment
/// dictionary, and the caller's resolved `projectRoot` — the one input that
/// isn't a parameter here because it depends on `Bundle.main`/the app's own
/// checkout-anchoring logic, which stays in `AgentController`).
///
/// A narrowly mechanical move: same defaulting behavior, same fallback model
/// path, same clamp — `AgentController.defaultSettings()` is now a thin
/// wrapper passing the real `UserDefaults.standard`/
/// `ProcessInfo.processInfo.environment`/its own `projectRoot()`.
public enum AgentDefaultSettings {
    /// The model used when nothing else resolves. Laguna S is the app's
    /// default but has no `Variant`, so its path is a literal — and an
    /// absolute one, in a developer's home directory, compiled into the
    /// binary. `SWIFTSTAR_DEFAULT_MODEL` overrides it; giving Laguna S a real
    /// `Variant` (P22) retires it.
    public static func defaultModelFallback(environment: [String: String]) -> URL {
        URL(fileURLWithPath: environment["SWIFTSTAR_DEFAULT_MODEL"]
            ?? "/Users/pauleveritt/models/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
    }

    /// The effective `selectedVariantID` for both model resolution (`resolve`,
    /// below) and pre-spawn admission (`AgentController.startAgent()`'s gate)
    /// — the stored choice, or Laguna S's id when nothing was ever configured
    /// (no variant, no legacy `modelPath`, no `SWIFTSTAR_MODEL` override). A
    /// single function so the two call sites can't disagree about which
    /// variant (if any) is in play — the failure mode that would otherwise let
    /// `resolve` pick Laguna S's file while the admission gate still saw "no
    /// variant selected" and skipped admission entirely.
    public static func effectiveSelectedVariantID(
        defaults: UserDefaults, environment: [String: String]
    ) -> String? {
        if let stored = defaults.string(forKey: "selectedVariantID"), !stored.isEmpty {
            return stored
        }
        let modelPath = defaults.string(forKey: "modelPath")
        let envModel = environment["SWIFTSTAR_MODEL"]
        guard (modelPath?.isEmpty ?? true), (envModel?.isEmpty ?? true) else { return nil }
        return VariantRegistry.lagunaS.id
    }

    /// The resolved launch settings (`AgentController.defaultSettings()`'s
    /// former body): engine dir (`UserDefaults` → `DS4_DIR` →
    /// `<cwd>/external/ds4`), model (through `VariantResolver.resolveModelFile`
    /// against `effectiveSelectedVariantID` — nothing-configured now resolves
    /// to Laguna S's variant, not the literal, with the hardcoded Laguna
    /// fallback only as the last resort), context size clamped to the resolved
    /// variant's declared range, workspace (`UserDefaults` → `projectRoot` →
    /// home), and the shell posture (`UserDefaults`, default deny).
    public static func resolve(
        defaults: UserDefaults, environment: [String: String], projectRoot: URL?
    ) -> AgentSettings {
        let engineDir: URL
        if let dir = defaults.string(forKey: "engineDir"), !dir.isEmpty {
            engineDir = URL(fileURLWithPath: dir)
        } else if let dir = environment["DS4_DIR"] {
            engineDir = URL(fileURLWithPath: dir)
        } else {
            engineDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("external/ds4")
        }
        // P13: resolve the model through the shared resolver, so a selected
        // variant takes precedence over the legacy path (M1), with the
        // hardcoded Laguna default only as the final fallback.
        let (modelPath, variant) = VariantResolver.resolveModelFile(
            selectedVariantID: effectiveSelectedVariantID(defaults: defaults, environment: environment),
            modelPath: defaults.string(forKey: "modelPath"),
            envModel: environment["SWIFTSTAR_MODEL"],
            fallback: defaultModelFallback(environment: environment)
        )
        // Clamp to the resolved variant's declared range. The app default
        // (51,200) is above Mellum's/Laguna XS's `maxContext` (40,960 /
        // 32,768) but exactly at Laguna S's (51,200 — capped there pending a
        // live measurement of the SSD-streaming budget above that point), so
        // the common case (no variant ever chosen, hence Laguna S by
        // default) clamps to a no-op; explicitly selecting Mellum or XS
        // still clamps as before.
        let requestedContext = defaults.object(forKey: "contextSize") as? Int ?? 51_200
        let contextSize = variant?.contract.memoryBudget.clampContext(requestedContext)
            ?? requestedContext
        let workspace: URL
        if let dir = defaults.string(forKey: "agentWorkspace"), !dir.isEmpty {
            workspace = URL(fileURLWithPath: dir)
        } else if let projectRoot {
            // During development the app is launched from the checkout; confine
            // the agent to the repo by default instead of the whole home dir.
            workspace = projectRoot
        } else {
            workspace = FileManager.default.homeDirectoryForCurrentUser
        }
        // D2: the app's default posture is deny — shell off until granted.
        let shellAllowed = defaults.bool(forKey: "agentShellAllowed")
        // Power savings is enabled by default. Read the object so an unset key
        // differs from an explicitly stored false.
        let powerSavingEnabled = defaults.object(forKey: "agentPowerSavingEnabled") as? Bool ?? true
        // P23: a standing guardrail against a runaway think loop. The
        // 2026-08-28 probe reproduced a turn that spent 15,873 of 16,384
        // tokens reasoning and never answered (the failure P20's closure
        // verdict also recorded). An ordinary round spends ~25 think tokens,
        // so 2,048 never fires normally. 0 disables the flag.
        let thinkBudget = defaults.object(forKey: "agentThinkBudget") as? Int ?? 2_048
        // P23 (D8): the per-worker context setting (default 8,192; 0 = inherit
        // the parent). Clamped to [4096, parent] at dispatch time so it can
        // never bypass admission.
        let workerContextSize = WorkerContextPolicy.resolve(defaults: defaults)
        return AgentSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            contextSize: contextSize,
            workspace: workspace,
            shellAllowed: shellAllowed,
            powerSavingEnabled: powerSavingEnabled,
            thinkBudget: thinkBudget,
            workerContextSize: workerContextSize,
            runtime: variant?.runtime
        )
    }
}
