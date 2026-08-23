import Testing
import Foundation
@testable import SwiftStarKit

struct DispatchOutcomeTests {
    @Test func validationResultPassedIsZeroExit() {
        #expect(ValidationResult(exit: 0, digest: "sha256:ok").passed)
        #expect(!ValidationResult(exit: 1, digest: "sha256:no").passed)
        #expect(!ValidationResult(exit: 130, digest: "").passed)
    }

    @Test func candidateCarriesRefAndTurnOutcome() {
        let outcome = TurnOutcome(model: "m", build: "b", sampler: "s", task: "t",
                                   generatedTokens: 3, ctxUsed: 9, stopReason: .eos, toolCalls: [])
        let dispatch = DispatchOutcome.candidate(ref: "abc123", turnOutcome: outcome, baselines: [:])
        guard case .candidate(let ref, let carried, _) = dispatch else {
            Issue.record("expected candidate"); return
        }
        #expect(ref == "abc123")
        #expect(carried == outcome)
    }

    @Test func receiptRefusedToolNamesPath() {
        let r = Receipt.refusedTool("out/of/bounds.txt")
        guard case .refusedTool(let path) = r else {
            Issue.record("expected refusedTool"); return
        }
        #expect(path == "out/of/bounds.txt")
    }

    @Test func receiptBudgetExceededHasNoPayload() {
        #expect(Receipt.budgetExceeded == .budgetExceeded)
    }

    @Test func receiptValidationFailedCarriesExitAndDigest() {
        let r = Receipt.validationFailed(exit: 2, digest: "sha256:deadbeef")
        guard case .validationFailed(let exit, let digest) = r else {
            Issue.record("expected validationFailed"); return
        }
        #expect(exit == 2)
        #expect(digest == "sha256:deadbeef")
    }

    @Test func receiptNoChangesHasNoPayload() {
        #expect(Receipt.noChanges == .noChanges)
    }

    @Test func receiptsAreDistinct() {
        // Receipts must compare distinct so a caller can switch on the reason.
        #expect(Receipt.refusedTool("a") != .refusedTool("b"))
        #expect(Receipt.refusedTool("a") != .budgetExceeded)
        #expect(Receipt.budgetExceeded != .noChanges)
        #expect(Receipt.validationFailed(exit: 1, digest: "x") != .noChanges)
    }

    @Test func candidateAndReceiptAreDistinct() {
        let outcome = TurnOutcome(model: "m", build: "b", sampler: "s", task: "t",
                                   generatedTokens: 0, ctxUsed: 0, stopReason: .eos, toolCalls: [])
        let candidate = DispatchOutcome.candidate(ref: "", turnOutcome: outcome, baselines: [:])
        let receipt = DispatchOutcome.receipt(.noChanges)
        #expect(candidate != receipt)
    }
}
