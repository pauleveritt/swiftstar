import Testing
import Foundation
@testable import SwiftStarKit

struct HandoffPacketValidatorTests {
    /// A packet that declares it withholds a string, then leaks that string in
    /// its own task text, is the contamination failure that silently turned an
    /// "L1" experiment cell into an L3 one. It must be caught mechanically.
    @Test func redactedStringInTaskTextIsRejected() {
        let packet = HandoffPacket(
            taskText: "Fix the import — RedirectResponse lives in fastapi.responses.",
            writableFiles: ["app.py"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            redacts: ["fastapi.responses"]
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result != .valid)
    }

    /// The 19:26 run burned six writes on absolute paths before self-correcting.
    /// A packet that names one is malformed, not merely unlucky.
    @Test func absoluteWritablePathIsRejected() {
        let packet = HandoffPacket(
            taskText: "Add the route.",
            writableFiles: ["/Users/pauleveritt/projects/app.py"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result != .valid)
    }

    /// A relative path can still escape the workspace. `writableFiles` is the
    /// grant the dispatcher revision-checks against, so traversal is a hole.
    @Test func traversingWritablePathIsRejected() {
        let packet = HandoffPacket(
            taskText: "Add the route.",
            writableFiles: ["../../etc/passwd"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result != .valid)
    }

    /// The positive case: a well-formed packet validates clean. Without this,
    /// a validator that rejected everything would pass every other test here.
    @Test func wellFormedPacketIsValid() {
        let packet = HandoffPacket(
            taskText: "Implement phase 2: the complaints board.",
            writableFiles: ["app.py", "templates/complaints.html"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            redacts: ["fastapi.responses"]
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result == .valid)
    }

    /// Pinning a fact that states a redacted answer is the contradiction worth
    /// catching: the near-miss bug's fix sat verbatim in the spec context while
    /// the cell claimed to withhold it.
    @Test func redactedStringInFactsIsRejected() {
        let packet = HandoffPacket(
            taskText: "Fix the failing contract test.",
            writableFiles: ["models.py"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            facts: ["timestamp uses field(default_factory=lambda: datetime.now(timezone.utc))"],
            redacts: ["default_factory"]
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result != .valid)
    }

    /// The validation command is part of the rendered packet the model sees,
    /// so it is another channel a withheld string can leak through.
    @Test func redactedStringInValidationCommandIsRejected() {
        let packet = HandoffPacket(
            taskText: "Fix the import.",
            writableFiles: ["app.py"],
            validationCommand: "python -c 'from fastapi.responses import RedirectResponse'",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            redacts: ["fastapi.responses"]
        )

        let result = HandoffPacketValidator.validate(packet)

        #expect(result != .valid)
    }

    /// The self-test command is the fourth channel the worker sees, and was the
    /// one the gate checked without any test proving it.
    @Test func redactedStringInSelfTestCommandIsRejected() {
        let packet = HandoffPacket(
            taskText: "Fix the import.",
            writableFiles: ["app.py"],
            validationCommand: "pytest -q",
            selfTestCommand: "python -c 'import fastapi.responses'",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            redacts: ["fastapi.responses"]
        )

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }

    /// A filename can carry the answer too — the manifest is rendered into the
    /// packet the worker reads.
    @Test func redactedStringInWritableFilesIsRejected() {
        let packet = HandoffPacket(
            taskText: "Add the board.",
            writableFiles: ["templates/complaints.html"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30,
            redacts: ["complaints"]
        )

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }

    @Test func zeroToolCallBudgetIsRejected() {
        let packet = HandoffPacket(
            taskText: "Add the route.",
            writableFiles: ["app.py"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 0
        )

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }

    /// A packet granting no writable files cannot produce a mutation, so it can
    /// only ever return the `noChanges` non-result.
    @Test func emptyWritableFilesIsRejected() {
        let packet = HandoffPacket(
            taskText: "Add the route.",
            writableFiles: [],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30
        )

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }

    /// `HandoffPacket` is persisted so a dispatch can be replayed. A packet
    /// written before `facts`/`redacts` existed must still decode, or adding
    /// the fields silently breaks every stored dispatch.
    @Test func packetPersistedBeforeNewFieldsStillDecodes() throws {
        let legacy = """
        {
          "taskText": "do the thing",
          "writableFiles": ["app.py"],
          "validationCommand": "pytest -q",
          "baselines": {},
          "turnBudget": 1,
          "toolCallBudget": 30
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HandoffPacket.self, from: legacy)

        #expect(decoded.taskText == "do the thing")
        #expect(decoded.facts == [])
        #expect(decoded.redacts == [])
    }

    @Test func emptyTaskTextIsRejected() {
        let packet = HandoffPacket(
            taskText: "   \n  ",
            writableFiles: ["app.py"],
            validationCommand: "pytest -q",
            baselines: [:],
            turnBudget: 1,
            toolCallBudget: 30
        )

        #expect(HandoffPacketValidator.validate(packet) != .valid)
    }
}
