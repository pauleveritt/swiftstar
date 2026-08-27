import Testing
import Foundation
@testable import SwiftStarKit

struct DispatchReceiptTests {
    @Test func candidateInjectionNamesRef() {
        let r = DispatchReceipt(worker: WorkerId(2), ref: "refs/swiftstar/candidates/abc", reason: nil, summary: "3 files changed")
        #expect(r.injectionPrompt().contains("candidate ref refs/swiftstar/candidates/abc"))
        #expect(r.injectionPrompt().contains("Worker 2"))
    }
    @Test func refusalInjectionNamesReason() {
        let r = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: "budgetExceeded", summary: "turn budget exceeded")
        #expect(r.injectionPrompt().contains("refused"))
        #expect(r.injectionPrompt().contains("budgetExceeded"))
    }
    @Test func candidateWithoutRefIsNotRefused() {
        // A candidate whose worktree commit is pending (ref nil) must NOT be
        // reported as a refusal.
        let r = DispatchReceipt(worker: WorkerId(2), ref: nil, reason: nil, summary: "3 mutations")
        #expect(!r.injectionPrompt().contains("refused"))
        #expect(r.injectionPrompt().contains("candidate"))
    }
    @Test func consultAnswerWinsOverTheVerdictInInjection() {
        // A consult worker runs read-only, so its verdict is ALWAYS a refusal.
        // If the direct send is refused (the user started a turn mid-consult)
        // the receipt stays pending and folds back through this path — it must
        // deliver the answer, not "Worker 1 refused: noChanges", which describes
        // the contract rather than what the worker said.
        let r = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: "noChanges",
                                summary: "noChanges", answerText: "the answer text")
        #expect(r.injectionPrompt().contains("the answer text"))
        #expect(!r.injectionPrompt().contains("refused"))
    }

    @Test func emptyAnswerFallsBackToTheVerdict() {
        let r = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: "noChanges",
                                summary: "noChanges", answerText: "")
        #expect(r.injectionPrompt().contains("refused"))
    }

    @Test func answerTextDefaultsNilAndRoundTrips() throws {
        let r = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: nil, summary: "done")
        #expect(r.answerText == nil)
        let withAnswer = DispatchReceipt(worker: WorkerId(1), ref: nil, reason: nil, summary: "done", answerText: "the answer")
        #expect(withAnswer.answerText == "the answer")
        let json = try JSONEncoder().encode(withAnswer)
        let decoded = try JSONDecoder().decode(DispatchReceipt.self, from: json)
        #expect(decoded.answerText == "the answer")
        // An absent answerText (an older receipt) decodes as nil.
        let old = "{\"worker\":1,\"executor\":\"fullContext\",\"summary\":\"done\"}"
        let oldDecoded = try JSONDecoder().decode(DispatchReceipt.self, from: Data(old.utf8))
        #expect(oldDecoded.answerText == nil)
    }
}
