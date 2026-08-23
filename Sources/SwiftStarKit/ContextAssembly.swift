import Foundation

/// The packet-maker (D5): `deterministic-load → rolling digest → adaptation →
/// packet`. This type is the **pure** half — it maps the assembled inputs
/// (objective, digest, staged reads, the adaptation text) into the packet's
/// prepared `taskText`. The deterministic adaptation (D7) is a pure template;
/// the deferred model-trip form is `adaptationPrompt` (not run in P11).
public enum ContextAssembly {
    /// The deterministic v1 adaptation (D7): size the brief to the implementer
    /// without a model trip. A small-capability implementer (mellum/afm) gets a
    /// finer, single-file-steps brief; a large one (laguna) gets a coarse,
    /// general brief. Pure — the deferred no-think model trip (`adaptationPrompt`)
    /// would replace this once the gate justifies it.
    public static func deterministicAdaptation(objective: String, digest: RollingDigest,
                                               loaded: [String: String], implementer: String) -> String {
        let isSmall = implementer.lowercased().contains("mellum")
            || implementer.lowercased().contains("afm")
        let reads = loaded.keys.sorted().joined(separator: ", ")
        if isSmall {
            return "Work in small, single-file steps, one at a time. Staged files: \(reads). Objective: \(objective)"
        }
        return "Objective: \(objective). Staged files: \(reads). Work as you see fit."
    }

    /// The deferred no-think prompt for the model-trip form of D7 (NOT run in
    /// P11 — out of scope with the RLM tier). Kept so the contract is complete
    /// when that trip lands.
    public static func adaptationPrompt(objective: String, digest: RollingDigest,
                                        loaded: [String: String], implementer: String) -> String {
        let reads = loaded.keys.sorted().joined(separator: ", ")
        return """
        Objective: \(objective)

        Available reduced context (host ledger — already stripped of tool noise):
        \(digest.summary())

        Staged files: \(reads)

        Write the minimal worker brief for the implementer model \(implementer):
        - filter this context to only what bears on the objective;
        - if \(implementer) is small-capability, split the task into smaller, more
          detailed chunks; if large-capability, keep it coarse and general.
        Output only the brief.
        """
    }

    /// Assemble the packet's prepared `taskText` from its inputs (D5). The
    /// objective leads; the digest and staged reads follow; the adaptation is
    /// the final, objective-scoped instruction. Deterministic and pure.
    public static func assemble(objective: String, digest: RollingDigest,
                                loaded: [String: String], adaptation: String) -> String {
        var parts: [String] = ["Task: \(objective)"]
        let d = digest.summary()
        if !d.isEmpty { parts.append("Context (reduced):\n\(d)") }
        if !loaded.isEmpty {
            parts.append("Staged files: \(loaded.keys.sorted().joined(separator: ", "))")
        }
        if !adaptation.isEmpty { parts.append("Instructions:\n\(adaptation)") }
        return parts.joined(separator: "\n\n")
    }
}
