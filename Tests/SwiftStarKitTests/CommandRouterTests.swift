import Testing
@testable import SwiftStarKit

struct CommandRouterTests {
    @Test func barePromptIsNotACommand() {
        #expect(CommandRouter.parse("just a question") == nil)
    }

    @Test func chatParses() {
        #expect(CommandRouter.parse("/chat explain the bug") == .chat(task: "explain the bug"))
    }

    @Test func chatIsReadOnly() {
        // The current /orchestrate (read-only worker) becomes /chat; it has no --files.
        #expect(CommandRouter.parse("/chat") == .chat(task: ""))
    }

    @Test func orchestrateParsesFilesFlag() {
        #expect(CommandRouter.parse("/orchestrate build it --files a.swift,b.swift")
                == .orchestrate(task: "build it", writableFiles: ["a.swift", "b.swift"]))
    }

    @Test func commandMustBeWholeToken() {
        #expect(CommandRouter.parse("/chatfoo") == nil)
    }
}
