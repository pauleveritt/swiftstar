import Testing
import Foundation
@testable import SwiftStarKit

struct WorktreeDispatchTests {
    /// A clean `TurnOutcome` with the given tool-call count and generated tokens.
    private func outcome(toolCalls: Int = 0, generated: Int = 0) -> TurnOutcome {
        let calls = (0..<toolCalls).map { _ in
            ToolCallOutcome(name: "tool", transitions: [.emitted])
        }
        return TurnOutcome(model: "m", build: "b", sampler: "s", task: "t",
                           generatedTokens: generated, ctxUsed: 10,
                           stopReason: .eos, toolCalls: calls)
    }

    /// A packet with the given writable files, validation command, and budgets.
    private func packet(writable: [String] = ["a.txt"], validation: String? = nil,
                        turnBudget: Int = 10_000, toolCallBudget: Int = 16,
                        baselines: [String: FileBaseline] = [:]) -> HandoffPacket {
        HandoffPacket(taskText: "t", writableFiles: writable, validationCommand: validation,
                      baselines: baselines, turnBudget: turnBudget, toolCallBudget: toolCallBudget)
    }

    // MARK: - the happy path: allowed mutations yield a candidate

    @Test func allowedMutationsYieldCandidate() {
        let p = packet(writable: ["a.txt", "b.txt"])
        let oc = outcome(toolCalls: 1, generated: 5)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt", "b.txt"],
                                               turnOutcome: oc, validation: nil)
        guard case .candidate(let ref, let carried, _) = result else {
            Issue.record("expected candidate"); return
        }
        // The pure verdict leaves the ref empty; the app-layer dispatcher
        // fills it after committing the worktree (see D3).
        #expect(ref == "")
        #expect(carried == oc)
    }

    @Test func candidateCarriesTheTurnOutcomeEvidence() {
        let oc = outcome(toolCalls: 2, generated: 42)
        let p = packet(writable: ["a.txt"])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: oc, validation: nil)
        guard case .candidate(_, let carried, _) = result else {
            Issue.record("expected candidate"); return
        }
        #expect(carried == oc)
        #expect(carried.toolCalls.count == 2)
        #expect(carried.generatedTokens == 42)
    }

    @Test func pureVerdictLeavesBaselinesEmptyForTheAppLayerToFill() {
        // The pure verdict cannot read the worktree (no I/O), so it leaves the
        // candidate's baselines empty — a sentinel the app-layer dispatcher
        // fills from the worktree reads (mirroring the empty `ref` sentinel).
        // Carrying real baselines is the app layer's job (see the integration
        // test `candidateCarriesBaselinesForWritableFiles`).
        let oc = outcome(toolCalls: 1, generated: 5)
        let p = packet(writable: ["a.txt"],
                       baselines: ["a.txt": FileBaseline(sha256: "ignored", lineEnding: .lf, mode: 0o644)])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: oc, validation: nil)
        guard case .candidate(_, _, let baselines) = result else {
            Issue.record("expected candidate"); return
        }
        #expect(baselines.isEmpty, "the pure verdict must leave baselines empty")
    }

    // MARK: - revision check: a mutation outside writableFiles is refused

    @Test func mutationOutsideWritableFilesIsRefused() {
        let p = packet(writable: ["a.txt"])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt", "outside.txt"],
                                               turnOutcome: outcome(), validation: nil)
        guard case .receipt(.refusedTool(let path)) = result else {
            Issue.record("expected refusedTool"); return
        }
        #expect(path == "outside.txt")
    }

    @Test func refusedToolNamesFirstOffendingPath() {
        let p = packet(writable: ["a.txt"])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["bad1.txt", "bad2.txt"],
                                               turnOutcome: outcome(), validation: nil)
        guard case .receipt(.refusedTool(let path)) = result else {
            Issue.record("expected refusedTool"); return
        }
        #expect(path == "bad1.txt")
    }

    @Test func refusedToolTakesPrecedenceOverBudgetAndNoChanges() {
        // An out-of-bounds mutation is a contract violation; it is reported
        // even when the turn also blew the budget or made no in-bounds changes.
        let p = packet(writable: ["a.txt"], turnBudget: 1, toolCallBudget: 1)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["outside.txt"],
                                               turnOutcome: outcome(toolCalls: 9, generated: 999),
                                               validation: nil)
        #expect(result == .receipt(.refusedTool("outside.txt")))
    }

    // MARK: - budget: tool-call count or turn tokens over the caps

    /// The turn-budget gate reads `generatedTokens`, which until 2026-08-30 was
    /// the wire's FINAL generation segment rather than the turn's total — so a
    /// subagent that blew its budget across tool rounds was admitted as long as
    /// its closing segment was small. Measured on
    /// `captures/live/20260830-180004`: 1,422 reported against 6,034 generated.
    /// This is the end-to-end proof, built through the real builder rather than
    /// from a hand-made outcome.
    @Test func turnBudgetCountsEverySegmentNotJustTheLast() {
        func status(_ state: String, generated: Int) -> AgentEvent {
            .status(StatusSnapshot(ctxUsed: 0, ctxSize: 51_200, prefillTPS: 0, genTPS: 20,
                                   ts: 0, generated: generated, state: state))
        }
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        for segment in [400, 400, 400] {              // 1,200 across three rounds
            b.apply(status("generating", generated: segment))
            b.apply(status("prefill", generated: 0))
        }
        b.apply(status("generating", generated: 10))
        b.apply(.ready(plannedBytes: nil, stopReason: "eos", generated: 50, ctxUsed: 900))
        let oc = b.finish()

        #expect(oc.generatedTokens == 1_250)   // 400*3 + 50
        #expect(oc.finalSegmentTokens == 50)   // what the gate used to see

        let p = packet(turnBudget: 1_000)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: oc, validation: nil)
        #expect(result == .receipt(.budgetExceeded))
    }

    @Test func toolCallBudgetExceeded() {
        let p = packet(toolCallBudget: 2)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 3),
                                               validation: nil)
        #expect(result == .receipt(.budgetExceeded))
    }

    @Test func turnTokenBudgetExceeded() {
        let p = packet(turnBudget: 100)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 1, generated: 101),
                                               validation: nil)
        #expect(result == .receipt(.budgetExceeded))
    }

    @Test func budgetAtLimitIsNotExceeded() {
        // At the limit (==, not >) the turn is still a candidate.
        let p = packet(turnBudget: 100, toolCallBudget: 2)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 2, generated: 100),
                                               validation: nil)
        if case .receipt = result {
            Issue.record("expected candidate at the limit, not a receipt")
        }
    }

    // MARK: - validation: a non-passing result yields a receipt with exit+digest

    @Test func validationFailedYieldsReceiptWithExitAndDigest() {
        let p = packet(writable: ["a.txt"], validation: "swift test")
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 1, generated: 5),
                                               validation: ValidationResult(exit: 1, digest: "sha256:fail"))
        guard case .receipt(.validationFailed(let exit, let digest)) = result else {
            Issue.record("expected validationFailed"); return
        }
        #expect(exit == 1)
        #expect(digest == "sha256:fail")
    }

    @Test func validationPassedYieldsCandidate() {
        let p = packet(writable: ["a.txt"], validation: "swift test")
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 1, generated: 5),
                                               validation: ValidationResult(exit: 0, digest: "sha256:ok"))
        if case .receipt = result {
            Issue.record("expected candidate when validation passed")
        }
    }

    @Test func noValidationNeededYieldsCandidateWhenValidationIsNil() {
        // No validation command, no validation result: the turn is a candidate
        // if it mutated allowed files within budget.
        let p = packet(writable: ["a.txt"], validation: nil)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 1, generated: 5),
                                               validation: nil)
        if case .receipt = result {
            Issue.record("expected candidate when no validation was required")
        }
    }

    // MARK: - no changes: nothing mutated -> nothing to commit

    @Test func noMutationsYieldNoChanges() {
        let p = packet(writable: ["a.txt"])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: [],
                                               turnOutcome: outcome(), validation: nil)
        #expect(result == .receipt(.noChanges))
    }

    @Test func noChangesWhenValidationNotRequired() {
        // No mutations and no validation -> noChanges (nothing to commit).
        let p = packet(writable: ["a.txt"], validation: nil)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: [],
                                               turnOutcome: outcome(), validation: nil)
        #expect(result == .receipt(.noChanges))
    }

    @Test func validationFailedBeatsNoChanges() {
        // Validation ran and failed even though nothing was mutated: the
        // failing validation is the reason, reported with its exit+digest.
        let p = packet(writable: ["a.txt"], validation: "swift test")
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: [],
                                               turnOutcome: outcome(),
                                               validation: ValidationResult(exit: 2, digest: "sha256:boom"))
        guard case .receipt(.validationFailed(let exit, _)) = result else {
            Issue.record("expected validationFailed"); return
        }
        #expect(exit == 2)
    }

    // MARK: - baselines ride on the packet, not the verdict

    @Test func packetBaselinesAreOpaqueToTheVerdict() {
        // The verdict does not consult baselines (they are for the parent's
        // drift check, D1); a candidate is returned regardless of baseline
        // contents as long as the mutations are within writableFiles.
        let p = packet(writable: ["a.txt"],
                       baselines: ["a.txt": FileBaseline(sha256: "old", lineEnding: .lf, mode: 0o644)])
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: ["a.txt"],
                                               turnOutcome: outcome(toolCalls: 1, generated: 5),
                                               validation: nil)
        if case .receipt = result {
            Issue.record("expected candidate; baselines must not affect the verdict")
        }
    }

    // MARK: - relativize (D4): the host executor records absolute paths; the
    // verdict compares worktree-relative forms against `writableFiles`.

    @Test func relativizeStripsTheWorktreePrefix() {
        let wt = URL(fileURLWithPath: "/tmp/swiftstar-wt-XYZ")
        var oc = outcome(toolCalls: 1, generated: 5)
        oc.mutations = ["/tmp/swiftstar-wt-XYZ/a.txt", "/tmp/swiftstar-wt-XYZ/sub/b.txt"]
        let rel = WorktreeDispatch.relativize(outcome: oc, worktree: wt)
        #expect(rel.mutations == ["a.txt", "sub/b.txt"])
    }

    @Test func relativizeKeepsAlreadyRelativePaths() {
        // A path without the worktree prefix (already relative, or an escape
        // the grant already refused) is kept unchanged — idempotent for the
        // integration tier's scripted relative mutations.
        let wt = URL(fileURLWithPath: "/tmp/swiftstar-wt-XYZ")
        var oc = outcome(toolCalls: 1, generated: 5)
        oc.mutations = ["a.txt", "sub/b.txt"]
        let rel = WorktreeDispatch.relativize(outcome: oc, worktree: wt)
        #expect(rel.mutations == ["a.txt", "sub/b.txt"])
    }

    @Test func relativizeKeepsNonWorktreeAbsolutePaths() {
        // An absolute path outside the worktree (an escape) is kept as-is so
        // the verdict's revision check refuses it (the host should have, but
        // the verdict is the backstop).
        let wt = URL(fileURLWithPath: "/tmp/swiftstar-wt-XYZ")
        var oc = outcome(toolCalls: 1, generated: 5)
        oc.mutations = ["/etc/passwd"]
        let rel = WorktreeDispatch.relativize(outcome: oc, worktree: wt)
        #expect(rel.mutations == ["/etc/passwd"])
    }

    @Test func relativizeFeedsTheVerdictRelativeMutations() {
        // End-to-end: the host records an absolute in-contract mutation;
        // relativize + verdict yields a candidate (the relative form matches
        // writableFiles).
        let wt = URL(fileURLWithPath: "/tmp/swiftstar-wt-XYZ")
        let p = packet(writable: ["a.txt"])
        var oc = outcome(toolCalls: 1, generated: 5)
        oc.mutations = ["/tmp/swiftstar-wt-XYZ/a.txt"]
        let rel = WorktreeDispatch.relativize(outcome: oc, worktree: wt)
        let result = WorktreeDispatch.verdict(packet: p, allowedMutations: rel.mutations,
                                               turnOutcome: rel, validation: nil)
        guard case .candidate = result else {
            Issue.record("expected candidate after relativizing an in-contract mutation"); return
        }
    }
}
