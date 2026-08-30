import Foundation
import Testing
@testable import SwiftStarKit

struct ToolCardEnrichmentTests {
    private func event(_ phase: AgentToolPhase, idx: Int = 0, name: String? = nil,
                       paramKind: String? = nil, paramName: String? = nil, value: String? = nil,
                       status: String? = nil, calls: Int? = nil) -> AgentEvent {
        .tool(AgentToolEvent(phase: phase, idx: idx, name: name, paramKind: paramKind,
                             paramName: paramName, value: value, status: status, calls: calls))
    }

    private func openCard(_ t: inout AgentTranscript, name: String) {
        t.apply(event(.start))
        t.apply(event(.tool, name: name))
    }

    @Test func paramKindSurvivesIntoToolParam() {
        var t = AgentTranscript()
        openCard(&t, name: "write")
        t.apply(event(.paramBegin, paramKind: "content", paramName: "content"))
        #expect(t.rows == [.tool(ToolCard(
            name: "write",
            params: [ToolParam(name: "content", value: "", kind: "content")]))])
    }

    @Test func pathParamPopulatesCardPathAtEnd() {
        var t = AgentTranscript()
        openCard(&t, name: "read")
        t.apply(event(.paramBegin, paramKind: "path", paramName: "path"))
        t.apply(event(.paramValue, value: "seed.txt"))
        t.apply(event(.paramEnd))
        t.apply(event(.finish, status: nil, calls: 1))
        guard case .tool(let card)? = t.rows.last else {
            Issue.record("expected a tool card"); return
        }
        #expect(card.path == "seed.txt")
        #expect(card.params == [ToolParam(name: "path", value: "seed.txt", kind: "path")])
    }

    @Test func finishMarksCardFinished() {
        var t = AgentTranscript()
        openCard(&t, name: "bash")
        t.apply(event(.finish, status: nil, calls: 1))
        guard case .tool(let card)? = t.rows.last else {
            Issue.record("expected a tool card"); return
        }
        #expect(card.finished)
        // An interrupted finish (status set) is still finished — the block closed.
        var u = AgentTranscript()
        openCard(&u, name: "bash")
        u.apply(event(.finish, status: "[tool call interrupted]\n", calls: 1))
        guard case .tool(let card2)? = u.rows.last else {
            Issue.record("expected a tool card"); return
        }
        #expect(card2.finished)
        #expect(card2.status == "[tool call interrupted]\n")
    }

    @Test func userRowAppends() {
        var t = AgentTranscript()
        t.appendUser("hello")
        guard case .user("hello", let stats) = t.rows[0] else {
            Issue.record("expected a user row"); return
        }
        #expect(stats?.characterCount == 5)
        // A subsequent content row is a separate row, not coalesced into the user row.
        t.apply(.text("reply"))
        #expect(t.rows.count == 2)
        #expect(t.rows[1] == .content("reply", summary: nil))
    }
}
