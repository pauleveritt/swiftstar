import Foundation

/// P11 (D5): the pure mapping from a `dispatch` tool call's params to a
/// `HandoffPacket` with a *prepared* taskText — the packet-maker's last mile.
/// The orchestrator model supplies the objective (`taskText`) and the exact
/// writable files; the host enriches it through `ContextAssembly`
/// (deterministic-load already happened upstream, `loaded` carries the staged
/// read names; the digest is the rolling reduced form; the adaptation is the
/// deterministic v1 sizing). Returns nil when the call is not a well-formed
/// dispatch (no taskText, or no writable files) — the responder's consent check
/// already refused that shape, so this is the backstop.
public enum DispatchPacketBuilder {
    public static func build(
        params: [ToolParam],
        digest: RollingDigest,
        loaded: [String: String],
        implementer: String,
        turnBudget: Int = 100_000,
        toolCallBudget: Int = 64
    ) -> HandoffPacket? {
        guard let objective = params.first(where: { $0.name == "taskText" })?.value,
              !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let writableFiles = (params.first(where: { $0.name == "writableFiles" })?.value ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !writableFiles.isEmpty else { return nil }
        let rawValidation = params.first(where: { $0.name == "validationCommand" })?.value ?? ""
        let validationCommand = rawValidation.isEmpty ? nil : rawValidation

        let adaptation = ContextAssembly.deterministicAdaptation(
            objective: objective, digest: digest, loaded: loaded, implementer: implementer)
        let prepared = ContextAssembly.assemble(
            objective: objective, digest: digest, loaded: loaded, adaptation: adaptation)

        return HandoffPacket(
            taskText: prepared,
            writableFiles: writableFiles,
            validationCommand: validationCommand,
            baselines: [:],
            turnBudget: turnBudget,
            toolCallBudget: toolCallBudget)
    }
}
