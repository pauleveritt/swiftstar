import Foundation

/// Assembles one agenttest phase's `HandoffPacket`.
///
/// Extracted from the harness so the assembly order is testable: `taskText` is
/// the phase spec *plus* the writable note, preamble, and shared spec context
/// appended after it. That appended content is where packet contamination has
/// actually occurred, so the packet this returns — not the authored fragment —
/// is what `HandoffPacketValidator` must be given.
public enum PhasePacketBuilder {
    public static func build(
        phaseText: String,
        writableNote: String,
        preamble: String,
        sharedContext: String,
        writableFiles: [String],
        validationCommand: String,
        selfTestCommand: String,
        toolCallBudget: Int,
        textContract: Bool = false,
        turnBudget: Int = 100_000,
        facts: [String] = [],
        redacts: [String] = [],
        sampling: SamplingPolicy = SamplingPolicy(),
        role: PacketRole = .implement
    ) -> HandoffPacket {
        // Facts must be rendered, not merely stored: the orchestrator sends only
        // `taskText` to the worker, so a fact left in the struct field is a no-op.
        // They lead, because their whole purpose is to pre-empt deliberation the
        // phase text would otherwise trigger.
        let factBlock = facts.isEmpty ? nil : ([
            "Pinned facts — these are settled; do not re-derive them:",
        ] + facts.map { "- \($0)" }).joined(separator: "\n")

        return HandoffPacket(
            taskText: ([factBlock, phaseText, writableNote, preamble, sharedContext]
                        .compactMap { $0 }).joined(separator: "\n\n"),
            writableFiles: writableFiles,
            validationCommand: validationCommand,
            selfTestCommand: selfTestCommand,
            baselines: [:],
            turnBudget: turnBudget,
            toolCallBudget: toolCallBudget,
            textContract: textContract,
            facts: facts,
            redacts: redacts,
            role: role,
            sampling: sampling
        )
    }
}
