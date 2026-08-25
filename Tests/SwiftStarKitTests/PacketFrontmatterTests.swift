import Testing
import Foundation
@testable import SwiftStarKit

struct PacketFrontmatterTests {
    /// The authorable form: YAML frontmatter for the declared fields, the task
    /// as the markdown body. `baselines` are absent by design — they are read
    /// from the worktree at dispatch, never authored.
    static let sample = """
    ---
    packet: 1
    role: implement
    workspace:
      paths: workspace-relative
      writable:
        - app.py
        - templates/complaints.html
    budget:
      toolCalls: 30
      turns: 2
      maxTokens: 4096
    sampling:
      think: off
      temp: 0.7
    validation:
      command: "pytest -q"
    facts:
      - "The list lives in models.py."
    redacts:
      - "fastapi.responses"
    ---

    Implement phase 2: the complaints board.
    """

    @Test func parsesWritableFilesFromFrontmatter() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.writableFiles == ["app.py", "templates/complaints.html"])
    }

    @Test func parsesTaskTextFromMarkdownBody() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.taskText == "Implement phase 2: the complaints board.")
    }

    @Test func parsesFactsAndRedacts() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.facts == ["The list lives in models.py."])
        #expect(packet.redacts == ["fastapi.responses"])
    }

    @Test func parsesBudgets() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.toolCallBudget == 30)
        #expect(packet.turnBudget == 2)
    }

    @Test func parsesValidationCommandStrippingQuotes() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.validationCommand == "pytest -q")
    }

    /// The sampling policy is per-role config, not a global switch. Making it a
    /// packet field is what lets `think` differ between decompose and implement
    /// instead of being one process-wide flag.
    @Test func parsesSamplingPolicy() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.sampling.think == .off)
        #expect(packet.sampling.maxTokens == 4096)
        #expect(packet.sampling.temperature == 0.7)
    }

    @Test func parsesRole() throws {
        let packet = try PacketFrontmatter.parse(Self.sample)
        #expect(packet.role == .implement)
    }

    /// Thinking defaults to bounded, not off: a packet that forgets to say
    /// should not silently inherit the amputation.
    @Test func absentSamplingDefaultsToBounded() throws {
        let minimal = """
        ---
        packet: 1
        role: repair
        workspace:
          writable:
            - app.py
        budget:
          toolCalls: 30
          turns: 2
        validation:
          command: "pytest -q"
        ---

        Fix it.
        """
        let packet = try PacketFrontmatter.parse(minimal)
        #expect(packet.sampling.think == .bounded)
    }

    /// A document with no frontmatter fence is not a packet. Failing loudly
    /// beats silently treating the whole file as task text.
    @Test func documentWithoutFrontmatterThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse("just a task, no frontmatter")
        }
    }

    /// `think: false` is YAML-boolean muscle memory, and silently defaulting it
    /// to `.bounded` would change an experiment's sampling with no error — the
    /// exact class of silent misconfiguration this schema exists to prevent.
    @Test func unknownThinkModeThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "think: off",
                                                                        with: "think: false"))
        }
    }

    @Test func unknownRoleThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "role: implement",
                                                                        with: "role: implment"))
        }
    }

    /// An unparseable budget currently falls back to a default that passes
    /// validation, so the typo never surfaces.
    @Test func unparseableBudgetThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "turns: 2",
                                                                        with: "turns: x"))
        }
    }

    /// `packet: 99` must not be silently accepted — an unknown schema version
    /// means the parser cannot know the fields it is reading mean what it
    /// thinks they mean.
    @Test func unknownPacketVersionThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "packet: 1",
                                                                        with: "packet: 99"))
        }
    }

    /// A packet missing the version field entirely is just as unknown as one
    /// declaring an unsupported version.
    @Test func missingPacketVersionThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "packet: 1\n",
                                                                        with: ""))
        }
    }
}
