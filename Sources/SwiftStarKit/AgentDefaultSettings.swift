import Foundation

/// `AgentController.defaultSettings()`'s pure logic, extracted (item 5b, P22
/// cleanup) so it is unit-testable: `Sources/SwiftStar` has no test target,
/// so the resolution logic — engine dir, model (through `VariantResolver`),
/// context clamp, workspace, shell posture — was untestable in place. Takes
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
            ?? "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
    }

    /// The resolved launch settings (`AgentController.defaultSettings()`'s
    /// former body, verbatim in behavior): engine dir (`UserDefaults` →
    /// `DS4_DIR` → `<cwd>/external/ds4`), model (through
    /// `VariantResolver.resolveModelFile`, the hardcoded Laguna fallback
    /// last), context size clamped to the resolved variant's declared range
    /// (unselected — Laguna S, which has no `Variant` — keeps the requested
    /// size), workspace (`UserDefaults` → `projectRoot` → home), and the
    /// shell posture (`UserDefaults`, default deny).
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
            selectedVariantID: defaults.string(forKey: "selectedVariantID"),
            modelPath: defaults.string(forKey: "modelPath"),
            envModel: environment["SWIFTSTAR_MODEL"],
            fallback: defaultModelFallback(environment: environment)
        )
        // Clamp to the resolved variant's declared range. The app default
        // (51,200) is above every variant's `maxContext` — 40,960 for Mellum,
        // 32,768 for Laguna XS — so without this, selecting a variant and
        // pressing Start could only ever fail: the gate would refuse a context
        // the variant never declared. Unselected (Laguna S, which has no
        // Variant) keeps the requested size.
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
        return AgentSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            contextSize: contextSize,
            workspace: workspace,
            shellAllowed: shellAllowed,
            runtime: variant?.runtime
        )
    }
}
