import Foundation
import Testing
@testable import SwiftStarKit

struct DumbPacketBuilderTests {
    private let params: [ToolParam] = [
        ToolParam(name: "taskText", value: "fix the broken test"),
        ToolParam(name: "writableFiles", value: "a.swift, b.swift"),
        ToolParam(name: "validationCommand", value: "swift test"),
    ]

    @Test func dumbPacketIsMinimal() throws {
        let digest = RollingDigest()
        let packet = try #require(DispatchPacketBuilder.build(
            params: params, digest: digest, loaded: ["ROADMAP.md": "P11"],
            implementer: "laguna", dumb: true))
        // No pinned facts, no staged-read list, no adaptation instructions.
        #expect(!packet.taskText.contains("Context (reduced)"))
        #expect(!packet.taskText.contains("Staged files"))
        #expect(!packet.taskText.contains("Instructions"))
        // Just the objective + the writable constraint the machinery needs.
        #expect(packet.taskText.contains("Task: fix the broken test"))
        #expect(packet.taskText.contains("Writable files: a.swift, b.swift"))
    }

    @Test func dumbPacketKeepsIsolationAndVerdictMachinery() throws {
        let packet = try #require(DispatchPacketBuilder.build(
            params: params, digest: RollingDigest(), loaded: [:],
            implementer: "laguna", dumb: true))
        #expect(packet.writableFiles == ["a.swift", "b.swift"])
        #expect(packet.validationCommand == "swift test")
        #expect(packet.turnBudget == 100_000)
        #expect(packet.toolCallBudget == 64)
    }

    @Test func smartPacketStillCarriesTheHelp() throws {
        var digest = RollingDigest()
        digest = RollingDigestReducer.recordHostVerdict(
            digest, mutations: ["a.swift"], exitStatus: 0, validationRan: true)
        let packet = try #require(DispatchPacketBuilder.build(
            params: params, digest: digest, loaded: ["ROADMAP.md": "P11"],
            implementer: "laguna"))
        // The engineered packet's help markers — what the dumb mode strips.
        #expect(packet.taskText.contains("Context (reduced)"))
        #expect(packet.taskText.contains("Staged files"))
        #expect(packet.taskText.contains("Instructions"))
        #expect(packet.taskText.contains("Objective: fix the broken test"))
    }

    @Test func dumbTaskTextIsShorterThanSmart() throws {
        var digest = RollingDigest()
        digest = RollingDigestReducer.recordHostVerdict(
            digest, mutations: ["a.swift"], exitStatus: 0, validationRan: true)
        let dumb = try #require(DispatchPacketBuilder.build(
            params: params, digest: digest, loaded: ["ROADMAP.md": "P11"],
            implementer: "laguna", dumb: true))
        let smart = try #require(DispatchPacketBuilder.build(
            params: params, digest: digest, loaded: ["ROADMAP.md": "P11"],
            implementer: "laguna"))
        #expect(dumb.taskText.count < smart.taskText.count)
    }

    private static func textEvent(_ s: String) -> PoolWireEvent {
        var parser = PoolWireParser()
        _ = parser.feed(#"{"t":"hello","v":1,"caps":["text","tool","status","ts"],"ts":0}"#)
        return parser.feed(#"{"t":"text","s":"\(s)","worker":0,"ts":1}"#)!
    }
}
