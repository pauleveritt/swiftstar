import Testing
import Foundation
@testable import SwiftStarKit

struct HandoffPacketTests {
    @Test func lineEndingHasThreeCases() {
        #expect(LineEnding.allCases == [.lf, .crlf, .mixed])
    }

    @Test func fileBaselineRoundTrips() throws {
        let baseline = FileBaseline(sha256: "abc123", lineEnding: .lf, mode: 0o644)
        let data = try JSONEncoder().encode(baseline)
        let decoded = try JSONDecoder().decode(FileBaseline.self, from: data)
        #expect(decoded == baseline)
    }

    @Test func mixedLineEndingSurvivesRoundTrip() throws {
        let baseline = FileBaseline(sha256: "x", lineEnding: .mixed, mode: 0o755)
        let data = try JSONEncoder().encode(baseline)
        let decoded = try JSONDecoder().decode(FileBaseline.self, from: data)
        #expect(decoded == baseline)
        #expect(decoded.lineEnding == .mixed)
        #expect(decoded.mode == 0o755)
    }

    @Test func handoffPacketRoundTrips() throws {
        let packet = HandoffPacket(
            taskText: "do the thing",
            writableFiles: ["src/a.swift", "tests/a.swift"],
            validationCommand: "swift test",
            baselines: [
                "src/a.swift": FileBaseline(sha256: "sha-a", lineEnding: .lf, mode: 0o644),
                "tests/a.swift": FileBaseline(sha256: "sha-b", lineEnding: .crlf, mode: 0o644),
            ],
            turnBudget: 4096,
            toolCallBudget: 12
        )
        let data = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(HandoffPacket.self, from: data)
        #expect(decoded == packet)
        #expect(decoded.validationCommand == "swift test")
        #expect(decoded.baselines["src/a.swift"]?.sha256 == "sha-a")
        #expect(decoded.baselines["tests/a.swift"]?.lineEnding == .crlf)
    }

    @Test func handoffPacketRoundTripsWithoutValidationCommand() throws {
        let packet = HandoffPacket(
            taskText: "t",
            writableFiles: ["a.txt"],
            validationCommand: nil,
            baselines: ["a.txt": FileBaseline(sha256: "s", lineEnding: .mixed, mode: 0o600)],
            turnBudget: 1000,
            toolCallBudget: 5
        )
        let data = try JSONEncoder().encode(packet)
        let decoded = try JSONDecoder().decode(HandoffPacket.self, from: data)
        #expect(decoded == packet)
        #expect(decoded.validationCommand == nil)
    }

    @Test func modeRoundTripsThroughOctalLiteral() throws {
        // Unix mode bits round-trip exactly; 0o755 == 493.
        let baseline = FileBaseline(sha256: "h", lineEnding: .lf, mode: 0o755)
        let data = try JSONEncoder().encode(baseline)
        let decoded = try JSONDecoder().decode(FileBaseline.self, from: data)
        #expect(decoded.mode == 0o755)
        #expect(decoded.mode == 493)
    }
}
