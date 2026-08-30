import Testing
@testable import SwiftStarKit

struct ToolRefusalTrackerTests {
    private func refusal(_ text: String = "refused") -> ToolCallbackResponse {
        ToolCallbackResponse(idx: 2, ok: false, s: text)
    }

    @Test func thirdIdenticalRefusalGetsHintAndLaterCountsContinue() {
        var tracker = ToolRefusalTracker()
        let params = [ToolParam(name: "path", value: "missing.py")]

        #expect(!tracker.apply(refusal(), name: "read", params: params).s.contains("hint:"))
        #expect(!tracker.apply(refusal(), name: "read", params: params).s.contains("hint:"))
        #expect(tracker.apply(refusal(), name: "read", params: params).s.contains("3 times"))
        #expect(tracker.apply(refusal(), name: "read", params: params).s.contains("4 times"))
    }

    @Test func successfulCallResetsTheStreak() {
        var tracker = ToolRefusalTracker()
        let params = [ToolParam(name: "path", value: "missing.py")]

        _ = tracker.apply(refusal(), name: "read", params: params)
        _ = tracker.apply(refusal(), name: "read", params: params)
        _ = tracker.apply(
            ToolCallbackResponse(idx: 2, ok: true, s: "read"),
            name: "read", params: params)
        #expect(!tracker.apply(refusal(), name: "read", params: params).s.contains("hint:"))
    }

    @Test func differentRefusalStartsANewStreak() {
        var tracker = ToolRefusalTracker()
        let first = [ToolParam(name: "path", value: "a.py")]
        let second = [ToolParam(name: "path", value: "b.py")]

        _ = tracker.apply(refusal(), name: "read", params: first)
        _ = tracker.apply(refusal(), name: "read", params: first)
        #expect(!tracker.apply(refusal(), name: "read", params: second).s.contains("hint:"))
    }
}
