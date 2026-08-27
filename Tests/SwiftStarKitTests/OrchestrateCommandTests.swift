import Foundation
import Testing
@testable import SwiftStarKit

struct OrchestrateCommandTests {
    @Test func extractsFollowingText() throws {
        let r = try #require(OrchestrateCommand.parse("/orchestrate fix the broken test"))
        #expect(r.task == "fix the broken test")
        #expect(r.writableFiles == [])
    }

    @Test func caseInsensitiveAndFlexibleWhitespace() throws {
        let r = try #require(OrchestrateCommand.parse("  /Orchestrate   run swift test  "))
        #expect(r.task == "run swift test")
    }

    @Test func bareCommandYieldsEmptyTask() throws {
        #expect(try #require(OrchestrateCommand.parse("/orchestrate")).task == "")
        #expect(try #require(OrchestrateCommand.parse("/orchestrate   ")).task == "")
    }

    @Test func nonCommandsAreNil() {
        #expect(OrchestrateCommand.parse("orchestrate fix") == nil)          // no slash
        #expect(OrchestrateCommand.parse("/orchestratefix") == nil)          // glued token
        #expect(OrchestrateCommand.parse("hello /orchestrate x") == nil)     // not at the start
        #expect(OrchestrateCommand.parse("") == nil)
    }

    @Test func filesFlagPopulatesWritableSet() throws {
        let r = try #require(OrchestrateCommand.parse(
            "/orchestrate fix the bug --files Sources/A.swift, Tests/B.swift"))
        #expect(r.task == "fix the bug")
        #expect(r.writableFiles == ["Sources/A.swift", "Tests/B.swift"])
    }

    @Test func filesFlagToleratesMessyWhitespace() throws {
        let r = try #require(OrchestrateCommand.parse(
            "/orchestrate  edit the doc  --files   a.swift , b.swift "))
        #expect(r.task == "edit the doc")
        #expect(r.writableFiles == ["a.swift", "b.swift"])
    }

    @Test func filesFlagWithoutTask() throws {
        let r = try #require(OrchestrateCommand.parse("/orchestrate --files a.swift"))
        #expect(r.task == "")
        #expect(r.writableFiles == ["a.swift"])
    }
}
