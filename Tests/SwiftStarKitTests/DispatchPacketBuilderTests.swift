import Testing
@testable import SwiftStarKit

struct DispatchPacketBuilderTests {
    @Test func buildsPacketFromDispatchParams() {
        let params = [ToolParam(name: "taskText", value: "fix a.swift"),
                      ToolParam(name: "writableFiles", value: "a.swift, b.swift")]
        let p = DispatchPacketBuilder.build(
            params: params, digest: RollingDigest(), loaded: ["ROADMAP.md": "P11"], implementer: "laguna")
        #expect(p != nil)
        #expect(p?.writableFiles == ["a.swift", "b.swift"])
        #expect(p?.taskText.contains("fix a.swift") == true)
        #expect(p?.taskText.contains("ROADMAP.md") == true)   // staged read named, D5
    }
    @Test func refusesWithoutTaskText() {
        #expect(DispatchPacketBuilder.build(params: [], digest: RollingDigest(), loaded: [:], implementer: "laguna") == nil)
    }
    @Test func refusesWithoutWritableFiles() {
        let params = [ToolParam(name: "taskText", value: "x")]
        #expect(DispatchPacketBuilder.build(params: params, digest: RollingDigest(), loaded: [:], implementer: "laguna") == nil)
    }
    @Test func validationCommandIsOptional() {
        let params = [ToolParam(name: "taskText", value: "x"),
                      ToolParam(name: "writableFiles", value: "a.swift")]
        let p = DispatchPacketBuilder.build(params: params, digest: RollingDigest(), loaded: [:], implementer: "mellum")
        #expect(p?.validationCommand == nil)
        #expect(p?.taskText.contains("one at a time") == true)  // small-capability adaptation, D7
    }
}
