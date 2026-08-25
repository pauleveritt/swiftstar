import Foundation

/// The outcome of validating a `HandoffPacket`: either well-formed, or a list
/// of the reasons it is not. Deterministic and model-free — validating a packet
/// costs microseconds, where discovering the same defect by running an
/// implementer costs a model load and three phases.
public enum PacketValidation: Equatable, Sendable {
    case valid
    case invalid([String])
}

/// Mechanical validation of a `HandoffPacket` against the v1 schema.
///
/// **Validate the assembled packet, not the authored one.** `taskText` is built
/// up after authoring — `DispatchPacketBuilder` appends the digest and loaded
/// file contents through `ContextAssembly`, and the agenttest harness
/// concatenates the shared spec context. The contamination this gate exists to
/// catch lived in exactly that appended content, so validating a
/// frontmatter-parsed packet (whose `taskText` is only the markdown body) would
/// have missed it. Call this on the packet that is actually dispatched.
///
/// What the gate does **not** cover, and cannot:
/// - Restatement. The check is verbatim and case-sensitive, so a redacted fix
///   expressed in different words, different case, or split across lines passes.
/// - Files in the worktree. If the spec sits on disk where the worker can read
///   it, the packet's withholding is irrelevant.
///
/// It is a tripwire for the mistake that actually happened (pasting a fix into
/// content the packet claims to withhold), not a proof of ignorance.
public enum HandoffPacketValidator {
    public static func validate(_ packet: HandoffPacket) -> PacketValidation {
        var reasons: [String] = []

        // Every channel the worker actually sees is a channel a withheld string
        // can leak through, so all of them are checked, not just the task body.
        for secret in packet.redacts {
            if packet.taskText.contains(secret) {
                reasons.append("redacted string \"\(secret)\" appears in the task text")
            }
            for fact in packet.facts where fact.contains(secret) {
                reasons.append("redacted string \"\(secret)\" appears in a pinned fact")
            }
            if packet.validationCommand?.contains(secret) == true {
                reasons.append("redacted string \"\(secret)\" appears in the validation command")
            }
            if packet.selfTestCommand?.contains(secret) == true {
                reasons.append("redacted string \"\(secret)\" appears in the self-test command")
            }
            for path in packet.writableFiles where path.contains(secret) {
                reasons.append("redacted string \"\(secret)\" appears in writable path \"\(path)\"")
            }
        }

        if packet.taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reasons.append("task text is empty")
        }

        if packet.writableFiles.isEmpty {
            reasons.append("writableFiles is empty; the worker could not mutate anything")
        }

        if packet.toolCallBudget <= 0 {
            reasons.append("toolCallBudget must be greater than zero")
        }

        if packet.turnBudget <= 0 {
            reasons.append("turnBudget must be greater than zero")
        }

        if packet.sampling.maxTokens <= 0 {
            reasons.append("sampling.maxTokens must be greater than zero")
        }

        if packet.validationCommand?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            reasons.append("validation.command is required")
        }

        for path in packet.writableFiles {
            if path.hasPrefix("/") {
                reasons.append("writable path \"\(path)\" is absolute; paths are workspace-relative")
            }
            if path.split(separator: "/").contains("..") {
                reasons.append("writable path \"\(path)\" escapes the workspace with \"..\"")
            }
        }

        return reasons.isEmpty ? .valid : .invalid(reasons)
    }
}
