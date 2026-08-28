import Testing
@testable import SwiftStarKit

/// P20 (D4): the dispatch-preference rule is prompt-only — an always-on
/// system-prompt clause. No app state, no toggle, no wire field. The fast tier
/// only asserts the clauses that make the rule what it is.
struct DispatchPreferenceRuleTests {
    @Test func requiresMachineCheckableAcceptance() {
        #expect(DispatchPreferenceRule.text.contains("machine-checkable"))
        #expect(DispatchPreferenceRule.text.contains("acceptance predicate"))
    }

    @Test func requiresExactWritableFileSet() {
        #expect(DispatchPreferenceRule.text.contains("writable-file set"))
    }

    @Test func excludesWatchedInteractiveTurns() {
        #expect(DispatchPreferenceRule.text.contains("watched interactive"))
    }

    @Test func namesTheDispatchTool() {
        #expect(DispatchPreferenceRule.text.contains("`dispatch`"))
    }

    @Test func boundsExploration() {
        #expect(DispatchPreferenceRule.text.contains("stop exploring"))
    }
}
