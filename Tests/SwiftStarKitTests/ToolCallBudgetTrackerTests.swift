import Testing
@testable import SwiftStarKit

struct ToolCallBudgetTrackerTests {
    @Test func zeroBudgetRefusesTheFirstRequest() {
        var tracker = ToolCallBudgetTracker(budget: 0)

        let admitted = tracker.admit()
        #expect(!admitted)
        #expect(tracker.callsSeen == 1)
    }

    @Test func requestAtTheBudgetIsAdmitted() {
        var tracker = ToolCallBudgetTracker(budget: 2)

        let first = tracker.admit()
        let second = tracker.admit()
        #expect(first)
        #expect(second)
        #expect(tracker.callsSeen == 2)
    }

    @Test func requestsAfterTheBudgetRemainRefused() {
        var tracker = ToolCallBudgetTracker(budget: 1)

        let first = tracker.admit()
        let second = tracker.admit()
        let third = tracker.admit()
        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(tracker.callsSeen == 3)
    }
}
