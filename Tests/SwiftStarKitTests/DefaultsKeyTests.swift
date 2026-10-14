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
        // SU.9, D4: a new key, so a saved old default doesn't hold the size at 16.
        #expect(DefaultsKey.transcriptFontSize.rawValue == "fontSize")
        #expect(DefaultsKey.lastSessionDirectory.rawValue == "lastSessionDirectory")
        #expect(DefaultsKey.sidebarVisible.rawValue == "sidebarVisible")
    }
}
