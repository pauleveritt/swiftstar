import Testing
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
}
