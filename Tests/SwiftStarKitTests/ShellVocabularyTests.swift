import Testing
@testable import SwiftStarKit

struct ShellVocabularyTests {
    @Test func idsAreUnique() {
        let ids = ShellVocabulary.regions.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyRegionHasNameAndRole() {
        for r in ShellVocabulary.regions {
            #expect(!r.name.isEmpty)
            #expect(!r.role.isEmpty)
        }
    }

    @Test func expectedShellRegionsArePresent() {
        let ids = Set(ShellVocabulary.regions.map(\.id))
        for expected in ["sidebar", "toolbar", "detail", "inspector", "composer",
                         "transcript", "toolCard", "statusBar", "ringGauge",
                         "modelMenu", "workspaceControl", "phaseBrowserRail"] {
            #expect(ids.contains(expected), "missing \(expected)")
        }
    }
}
