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
        facts: [String] = [],
        redacts: [String] = [],
        sampling: SamplingPolicy = SamplingPolicy(),
        role: PacketRole = .implement
    ) -> HandoffPacket {
        HandoffPacket(
            taskText: [phaseText, writableNote, preamble, sharedContext].joined(separator: "\n\n"),
            writableFiles: writableFiles,
            validationCommand: validationCommand,
            selfTestCommand: selfTestCommand,
            baselines: [:],
            turnBudget: 100_000,
            toolCallBudget: toolCallBudget,
            facts: facts,
            redacts: redacts,
            role: role,
            sampling: sampling
        )
    }
}
