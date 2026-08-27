import Foundation
import Testing
@testable import SwiftStarKit

struct OrchestrateCommandTests {
    @Test func extractsFollowingText() {
        #expect(OrchestrateCommand.parse("/orchestrate fix the broken test") == "fix the broken test")
    }

    @Test func caseInsensitiveAndFlexibleWhitespace() {
        #expect(OrchestrateCommand.parse("  /Orchestrate   run swift test  ") == "run swift test")
    }

    @Test func bareCommandYieldsEmptyTask() {
        #expect(OrchestrateCommand.parse("/orchestrate") == "")
        #expect(OrchestrateCommand.parse("/orchestrate   ") == "")
    }

    @Test func nonCommandsAreNil() {
        #expect(OrchestrateCommand.parse("orchestrate fix") == nil)          // no slash
        #expect(OrchestrateCommand.parse("/orchestratefix") == nil)          // glued token
        #expect(OrchestrateCommand.parse("hello /orchestrate x") == nil)     // not at the start
        #expect(OrchestrateCommand.parse("") == nil)
    }
}
