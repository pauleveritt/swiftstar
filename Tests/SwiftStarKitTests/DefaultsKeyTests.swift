import Testing
@testable import SwiftStarKit

struct DefaultsKeyTests {
    @Test func rawValuesMatchToday() {
        #expect(DefaultsKey.workspace.rawValue == "agentWorkspace")
        #expect(DefaultsKey.executable.rawValue == "engineExecutable")
        #expect(DefaultsKey.modelID.rawValue == "engineModelID")
        #expect(DefaultsKey.contextSize.rawValue == "engineContextSize")
        #expect(DefaultsKey.recentWorkspaces.rawValue == "recentWorkspaces")
        #expect(DefaultsKey.inspectorPresented.rawValue == "appShellInspectorPresented")
        #expect(DefaultsKey.transcriptFontSize.rawValue == "transcriptFontSize")
    }
}
