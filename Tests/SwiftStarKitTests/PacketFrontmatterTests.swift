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

    /// `Int("01") == 1`, so a naive `Int(raw)` parse accepts a leading-zero
    /// literal that is not canonical YAML/JSON integer syntax. Silently
    /// accepting it means a typo like `packet: 01` parses as version 1
    /// instead of being caught as malformed.
    @Test func leadingZeroPacketVersionThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "packet: 1",
                                                                        with: "packet: 01"))
        }
    }

    /// Likewise `Int("+1") == 1` — an explicit leading `+` is not canonical
    /// integer syntax and must not be silently accepted as version 1.
    @Test func explicitPlusPacketVersionThrows() {
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(Self.sample.replacingOccurrences(of: "packet: 1",
                                                                        with: "packet: +1"))
        }
    }

    /// A trailing `# comment` on a scalar's line must not become part of the
    /// parsed value — that is silent corruption of the actual field.
    @Test func trailingCommentIsStrippedFromScalar() throws {
        let withComment = Self.sample.replacingOccurrences(
            of: "toolCalls: 30",
            with: "toolCalls: 30  # max tool calls per phase"
        )
        let packet = try PacketFrontmatter.parse(withComment)
        #expect(packet.toolCallBudget == 30)
    }

    /// A `#` that is part of a quoted scalar's actual content is not a
    /// comment and must survive.
    @Test func hashInsideQuotedScalarIsNotStrippedAsComment() throws {
        let withHash = Self.sample.replacingOccurrences(
            of: "command: \"pytest -q\"",
            with: "command: \"pytest -q -k 'not #slow'\""
        )
        let packet = try PacketFrontmatter.parse(withHash)
        #expect(packet.validationCommand == "pytest -q -k 'not #slow'")
    }

    /// An apostrophe inside a *plain* (unquoted) scalar is just a literal
    /// character — it does not open YAML single-quoting. The comment
    /// stripper must not mistake it for one and let a trailing `#` comment
    /// survive because it thinks it is "inside a quote" for the rest of the
    /// line.
    @Test func apostropheInPlainScalarDoesNotDefeatCommentStripping() throws {
        let withApostrophe = Self.sample.replacingOccurrences(
            of: "command: \"pytest -q\"",
            with: "command: don't stop  # slow"
        )
        let packet = try PacketFrontmatter.parse(withApostrophe)
        #expect(packet.validationCommand == "don't stop")
    }

    /// `command: |` is a YAML block scalar — the natural way to author a
    /// multi-line command. It must parse to the block's actual content, not
    /// the literal two-character string `"|"`.
    @Test func blockScalarCommandParsesToItsContent() throws {
        let withBlock = Self.sample.replacingOccurrences(
            of: "  command: \"pytest -q\"",
            with: """
              command: |
                set -e
                pytest -q
            """
        )
        let packet = try PacketFrontmatter.parse(withBlock)
        #expect(packet.validationCommand == "set -e\npytest -q")
    }

    /// A block scalar content line indented less than the block's own
    /// established indent (per the first content line), but still more than
    /// the parent key's indent, is a YAML syntax error — real YAML would
    /// reject it. Silently dedenting by `min(blockIndent, line.count)` would
    /// instead drop real leading characters from that line and corrupt the
    /// value. This parser's stated philosophy is to reject what it doesn't
    /// understand rather than guess, so this must throw.
    @Test func underIndentedBlockScalarContentThrows() {
        let underIndented = Self.sample.replacingOccurrences(
            of: "  command: \"pytest -q\"",
            with: """
              command: |
                set -e
               pytest -q
            """
        )
        #expect(throws: (any Error).self) {
            try PacketFrontmatter.parse(underIndented)
        }
    }

    /// A CRLF-terminated document is plausible input — this repo already
    /// models `LineEnding.crlf` for worktree files — not exotic, and must
    /// parse rather than throw the misleading `missingFrontmatter` (caused by
    /// `.whitespaces` not stripping `\r`, so the fence line `"---\r"` never
    /// compares equal to `"---"`).
    @Test func crlfDocumentParses() throws {
        let crlf = Self.sample.replacingOccurrences(of: "\n", with: "\r\n")
        let packet = try PacketFrontmatter.parse(crlf)
        #expect(packet.taskText == "Implement phase 2: the complaints board.")
        #expect(packet.writableFiles == ["app.py", "templates/complaints.html"])
        #expect(packet.validationCommand == "pytest -q")
    }
}
