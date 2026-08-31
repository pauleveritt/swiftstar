# P12.8 — Phase-level Recovery Implementation Plan

> **Status (2026-08-25): all four tasks implemented and committed** —
> `6ac5df7` (`commitForRepair`), `84b9fa1` (`adoptRepairedPhase`), `a438634`
> (`PhaseRepair`), `de46f4f` (build-loop wiring), `cca02f2` (capture-namespace
> review fix). Every step below is ticked to match; they were left unchecked
> after the work landed and were corrected in a later audit pass.
>
> **Still owed: the live confirmation run** described under "Post-plan
> verification" at the end of this file. It is not a checkbox and is *not*
> satisfied. One attempt was made
> (`captures/agenttest/20260825-203706-roadmap-user-story`): phase 1 failed
> validation, the repair attempt itself returned `validationFailed`, and
> `RepairLoop` exited on that receipt by design (D4), so the run never reached
> acceptance. Lifting that receipt-exit limitation is filed in ROADMAP's
> Backlog and is the likely prerequisite for a confirming run.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair a build phase that fails its `validationCommand` (vetted import check) with one `RepairLoop` attempt instead of aborting the run before `commitBack()`.

**Architecture:** On a phase validation failure, commit the failed phase's worktree to a throwaway ref (`commitForRepair`), run `RepairLoop` once against the phase's own import check (grade = always-pass, since `finalize` only returns `.candidate` after validation already passed), and fold the repaired worktree back as the transaction's new head (`adoptRepairedPhase`). `RepairLoop` itself is unchanged.

**Tech Stack:** Swift 6, Swift Testing (`@Test`), git worktrees, `WorktreeDispatcher`/`WorktreeTransaction`/`RepairLoop` (SwiftStarAppKit).

**Spec:** `docs/superpowers/specs/2026-08-25-p12-8-phase-level-recovery-design.md` — the plan argues from its decisions D1–D7; executors read both.

## Global Constraints

- Branch `p12-8-phase-level-recovery`, worktree `.worktrees/p12-8-phase-level-recovery`.
- Fast tier: `swift test` (SwiftStarKitTests only; no model, no network, no subprocess).
- Integration tier: `SWIFTSTAR_INTEGRATION=1 swift test` (a.k.a. `just integration`) — real processes, git I/O, fake engines.
- One repair attempt per phase failure; do NOT change `RepairLoop`'s receipt-exit behavior (D2).
- `grade` in the phase-level call is a trivial always-pass: `{ _ in GradeResult(exit: 0, output: "") }` (D3).
- `commitForRepair` keeps `commitDiff`'s `git status --porcelain` guard and parent-SHA fallback — no "must have changes" assertion (D5).
- Worker 2 budget: accept the existing `limit`/`contextFull` stop-guard; do NOT add a session reset (D6).
- Every task commits separately; run the failing test before the fix.

---

### Task 1: `WorktreeDispatcher.commitForRepair`

**Files:**
- Modify: `Sources/SwiftStarAppKit/WorktreeDispatcher.swift` (add one public method near `finalize`)
- Test: `Tests/SwiftStarIntegrationTests/WorktreeDispatcherTests.swift` (append two tests)

**Interfaces:**
- Consumes: existing private `commitDiff(in:writableFiles:)` (`WorktreeDispatcher.swift:181-210`).
- Produces: `public static func commitForRepair(_ worktree: Worktree, packet: HandoffPacket, in repo: URL) throws -> String` — returns the commit SHA (or the parent SHA when nothing is staged). Later tasks call it to produce a `failedRef`.

- [x] **Step 1: Write the failing tests**

Append to `WorktreeDispatcherTests` (inside the existing struct, which already has `makeFixtureRepo()` and `git(_:_:)` helpers):

```swift
    // MARK: - commitForRepair (P12.8): commit failed phase work unconditionally

    @Test func commitForRepairCommitsFailedPhaseWork() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packet = HandoffPacket(
            taskText: "edit a.txt", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }
        try "broken\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)

        let ref = try WorktreeDispatcher.commitForRepair(worktree, packet: packet, in: repo)
        #expect(ref.count == 40, "commitForRepair must return a 40-char commit SHA")
        let show = try git(repo, ["show", "--stat", "--name-only", ref])
        #expect(show.contains("a.txt"), "the failed phase's mutation must be committed")
    }

    @Test func commitForRepairReturnsParentShaWhenNothingStaged() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let head = try git(repo, ["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let packet = HandoffPacket(
            taskText: "no-op", writableFiles: ["a.txt"], validationCommand: nil,
            baselines: [:], turnBudget: 10_000, toolCallBudget: 16)
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }

        let ref = try WorktreeDispatcher.commitForRepair(worktree, packet: packet, in: repo)
        #expect(ref == head,
                "no staged changes must return the parent SHA (the failed state is the parent tree), not an empty commit")
    }
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeDispatcherTests`
Expected: both new tests FAIL — `value of type 'WorktreeDispatcher' has no member 'commitForRepair'`.

- [x] **Step 3: Implement**

In `WorktreeDispatcher`, after `finalize` (before `discard`), add:

```swift
    /// Commit the worktree's diff unconditionally (no verdict) and return the
    /// commit SHA — or the parent SHA when nothing is staged (D5). P12.8 uses
    /// this to turn a phase that failed validation into a `failedRef` that
    /// `RepairLoop` can branch from; a no-mutation failure returns the parent
    /// tree, which *is* the failed state to repair.
    public static func commitForRepair(_ worktree: Worktree, packet: HandoffPacket,
                                       in repo: URL) throws -> String {
        try commitDiff(in: worktree.url, writableFiles: packet.writableFiles)
    }
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeDispatcherTests`
Expected: PASS (both new tests, plus the existing `WorktreeDispatcherTests`).

- [x] **Step 5: Commit**

```bash
git add Sources/SwiftStarAppKit/WorktreeDispatcher.swift Tests/SwiftStarIntegrationTests/WorktreeDispatcherTests.swift
git commit -m "P12.8: add WorktreeDispatcher.commitForRepair (commit failed phase for repair)"
```

---

### Task 2: `WorktreeTransaction.adoptRepairedPhase`

**Files:**
- Modify: `Sources/SwiftStarAppKit/WorktreeTransaction.swift`
- Test: `Tests/SwiftStarIntegrationTests/WorktreeTransactionTests.swift` (append one test)

**Interfaces:**
- Consumes: `WorktreeDispatcher.resolve(ref:in:)`, `WorktreeDispatcher.discard(_:in:)` (both existing).
- Produces: `public func adoptRepairedPhase(failedWorktree: WorktreeDispatcher.Worktree, repairedWorktree: WorktreeDispatcher.Worktree, repairedRef: String) throws` — discards the failed worktree, tracks the repaired worktree, and advances `head`/`candidateRef`/`finalWorktree`.

- [x] **Step 1: Write the failing test**

Append to `WorktreeTransactionTests` (struct already has `makeFixtureRepo()`, `git(_:_:)`, `packet(_:task:)`, `outcome(mutations:)`):

```swift
    @Test func adoptRepairedPhaseAdvancesHeadAndDiscardsFailedWorktree() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let txn = WorktreeTransaction(repo: repo)

        // Phase 1 candidate.
        let p1 = packet(["a.txt"], task: "phase 1")
        let wt1 = try txn.preparePhase(packet: p1)
        try "one\n".write(to: wt1.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        _ = try txn.finalizePhase(wt1, packet: p1, turnOutcome: outcome(mutations: ["a.txt"]), validation: nil)

        // Phase 2 fails validation; its work is committed for repair.
        let p2 = packet(["b.txt"], task: "phase 2")
        let wt2 = try txn.preparePhase(packet: p2)
        try "broken\n".write(to: wt2.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let failedRef = try WorktreeDispatcher.commitForRepair(wt2, packet: p2, in: repo)

        // A repair worktree branched from the failed phase's commit.
        let repairedWT = try WorktreeDispatcher.prepare(packet: p2, in: repo, baseRef: failedRef)
        try "fixed\n".write(to: repairedWT.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        guard case .candidate(let repairedRef, _, _) = try WorktreeDispatcher.finalize(
            repairedWT, packet: p2, turnOutcome: outcome(mutations: ["b.txt"]), validation: nil, in: repo) else {
            Issue.record("repair must finalize to a candidate"); return
        }

        try txn.adoptRepairedPhase(failedWorktree: wt2, repairedWorktree: repairedWT, repairedRef: repairedRef)

        #expect(txn.candidateRef == repairedRef)
        #expect(txn.head == (try git(repo, ["rev-parse", repairedRef])
            .trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(txn.finalWorktree?.url == repairedWT.url)
        #expect(!FileManager.default.fileExists(atPath: wt2.url.path),
                "the failed worktree must be discarded by adoptRepairedPhase")

        // Phase 3 branches from the repaired head and must see the repaired file.
        let p3 = packet(["c.txt"], task: "phase 3")
        let wt3 = try txn.preparePhase(packet: p3)
        #expect(try String(contentsOf: wt3.url.appendingPathComponent("b.txt"), encoding: .utf8) == "fixed\n",
                "phase 3's checkout must contain the repaired phase 2 work")
        _ = try txn.finalizePhase(wt3, packet: p3, turnOutcome: outcome(mutations: ["c.txt"]), validation: nil)

        guard let finalRef = txn.commitBack() else { Issue.record("commitBack must return the final ref"); return }
        #expect(finalRef.hasPrefix("refs/swiftstar/candidates/"))
        // The repaired worktree, superseded by phase 3, must not leak.
        #expect(!FileManager.default.fileExists(atPath: repairedWT.url.path),
                "the repaired worktree must be discarded once superseded")

        txn.discardFinal()
    }
```

- [x] **Step 2: Run the test to verify it fails**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeTransactionTests`
Expected: the new test FAILS — `value of type 'WorktreeTransaction' has no member 'adoptRepairedPhase'`.

- [x] **Step 3: Implement**

In `WorktreeTransaction`, after `finalizePhase` (before `commitBack`), add:

```swift
    /// P12.8 (D4): fold a repaired phase back into the transaction. The failed
    /// phase's worktree is discarded; the repaired worktree is tracked so
    /// `commitBack` discards it when a later phase supersedes it (it must never
    /// leak as a finalWorktree that is not in `worktrees`).
    public func adoptRepairedPhase(
        failedWorktree: WorktreeDispatcher.Worktree,
        repairedWorktree: WorktreeDispatcher.Worktree,
        repairedRef: String
    ) throws {
        worktrees.removeAll { $0.url == failedWorktree.url }
        WorktreeDispatcher.discard(failedWorktree, in: repo)
        worktrees.append(repairedWorktree)
        head = try WorktreeDispatcher.resolve(ref: repairedRef, in: repo)
        candidateRef = repairedRef
        finalWorktree = repairedWorktree
    }
```

- [x] **Step 4: Run the test to verify it passes**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeTransactionTests`
Expected: PASS (new test plus the existing three `WorktreeTransactionTests`).

- [x] **Step 5: Commit**

```bash
git add Sources/SwiftStarAppKit/WorktreeTransaction.swift Tests/SwiftStarIntegrationTests/WorktreeTransactionTests.swift
git commit -m "P12.8: add WorktreeTransaction.adoptRepairedPhase (fold repaired phase back)"
```

---

### Task 3: `PhaseRepair` orchestration

**Files:**
- Create: `Sources/SwiftStarAppKit/PhaseRepair.swift`
- Test: `Tests/SwiftStarIntegrationTests/PhaseRepairTests.swift` (new file)

**Interfaces:**
- Consumes: `WorktreeDispatcher.commitForRepair` (Task 1), `RepairLoop.run` (existing), `GradeResult`, `ValidationResult`, `Receipt`, `RepairContext`, `HandoffPacket`.
- Produces: `enum PhaseRepair` with `Outcome` (`.repaired(ref:worktree:)` / `.exhausted(receipt:)`) and `static func run(repo:failedWorktree:packet:validation:packetBuilder:runPhase:capture:captureDir:emissionFollowUp:) throws -> Outcome`. Task 4 calls it; it throws `RepairLoopError.sessionExhausted` upward.

- [x] **Step 1: Write the failing tests**

Create `Tests/SwiftStarIntegrationTests/PhaseRepairTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit
@testable import SwiftStarAppKit

/// P12.8 (D4): PhaseRepair turns a validation-failed phase into a repaired
/// result — commitForRepair + RepairLoop.run (grade = always-pass) — with a
/// fake runPhase so no model is involved. Env-guarded (integration tier).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct PhaseRepairTests {

    private func makeFixtureRepo() throws -> URL {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase-repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ a: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path] + a
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["config", "user.email", "t@t"]); git(["config", "user.name", "t"])
        try "seed\n".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        git(["add", "a.txt"]); git(["commit", "-q", "-m", "seed"])
        return repo
    }

    @Test func repairsAValidationFailedPhaseWhenTheFakeTurnFixesIt() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packet = HandoffPacket(
            taskText: "fix a.txt", writableFiles: ["a.txt"], validationCommand: "true",
            baselines: [:], turnBudget: 100, toolCallBudget: 5,
            textContract: true, role: .repair, sampling: SamplingPolicy())
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }
        try "broken\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)

        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { _, _, _ in
            // Text-contract turn: a labeled block the host harvests and writes.
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.text = "#a.txt\n```\nfixed\n\n```\n"
            return o
        }
        let packetBuilder: (RepairContext) throws -> HandoffPacket = { _ in packet }

        let result = try PhaseRepair.run(
            repo: repo, failedWorktree: worktree, packet: packet,
            validation: ValidationResult(exit: 1, digest: "sha256:x", output: "ImportError"),
            packetBuilder: packetBuilder, runPhase: runPhase)

        guard case .repaired(let ref, let repairedWT) = result else {
            Issue.record("expected .repaired, got \(result)"); return
        }
        defer { WorktreeDispatcher.discard(repairedWT, in: repo) }
        #expect(try String(contentsOf: repairedWT.url.appendingPathComponent("a.txt"),
                           encoding: .utf8) == "fixed\n")
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
    }

    @Test func exhaustsWhenTheRepairTurnStillFailsValidation() throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        let packet = HandoffPacket(
            taskText: "fix a.txt", writableFiles: ["a.txt"], validationCommand: "false",
            baselines: [:], turnBudget: 100, toolCallBudget: 5)
        let worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        defer { WorktreeDispatcher.discard(worktree, in: repo) }
        try "broken\n".write(to: worktree.url.appendingPathComponent("a.txt"),
                             atomically: true, encoding: .utf8)

        let runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome = { _, _, _ in
            // Mutated, but the content still fails validation.
            var o = TurnOutcome(model: "fake", build: "b", sampler: "s", task: "t",
                                generatedTokens: 10, ctxUsed: 10, stopReason: .eos, toolCalls: [])
            o.mutations = ["a.txt"]
            return o
        }
        let packetBuilder: (RepairContext) throws -> HandoffPacket = { _ in packet }

        let result = try PhaseRepair.run(
            repo: repo, failedWorktree: worktree, packet: packet,
            validation: ValidationResult(exit: 1, digest: "sha256:x", output: "ImportError"),
            packetBuilder: packetBuilder, runPhase: runPhase)

        guard case .exhausted(let receipt) = result else {
            Issue.record("expected .exhausted, got \(result)"); return
        }
        guard case .validationFailed = receipt else {
            Issue.record("expected validationFailed receipt, got \(receipt)"); return
        }
    }
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter PhaseRepairTests`
Expected: both FAIL — `cannot find 'PhaseRepair' in scope`.

- [x] **Step 3: Implement**

Create `Sources/SwiftStarAppKit/PhaseRepair.swift`:

```swift
import Foundation
import SwiftStarKit

/// P12.8 (D4): repair a phase that failed its `validationCommand`. Commits the
/// failed phase's work to a throwaway ref and runs `RepairLoop` once against the
/// phase's own import check. The `grade` closure is a trivial always-pass (D3):
/// `finalize` returns `.candidate` only after validation already passed, so the
/// import check is the real gate and `grade` cannot meaningfully fail. Throws
/// `RepairLoopError.sessionExhausted` upward for the caller to map to a stop.
public enum PhaseRepair {

    public enum Outcome: Sendable {
        case repaired(ref: String, worktree: WorktreeDispatcher.Worktree)
        case exhausted(receipt: Receipt)
    }

    public static func run(
        repo: URL,
        failedWorktree: WorktreeDispatcher.Worktree,
        packet: HandoffPacket,
        validation: ValidationResult,
        packetBuilder: (RepairContext) throws -> HandoffPacket,
        runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome,
        capture: FileHandle? = nil,
        captureDir: URL? = nil,
        emissionFollowUp: String? = nil
    ) throws -> Outcome {
        let failedRef = try WorktreeDispatcher.commitForRepair(failedWorktree, packet: packet, in: repo)
        let result = try RepairLoop.run(
            repo: repo,
            failedRef: failedRef,
            initialGrade: GradeResult(exit: validation.exit, output: validation.output),
            packetBuilder: packetBuilder,
            runPhase: runPhase,
            grade: { _ in GradeResult(exit: 0, output: "") },
            capture: capture,
            captureDir: captureDir,
            emissionFollowUp: emissionFollowUp)
        switch result {
        case .passed(let ref, _, let wt):
            return .repaired(ref: ref, worktree: wt)
        case .exhausted(_, let receipt):
            return .exhausted(receipt: receipt)
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter PhaseRepairTests`
Expected: PASS (both).

- [x] **Step 5: Commit**

```bash
git add Sources/SwiftStarAppKit/PhaseRepair.swift Tests/SwiftStarIntegrationTests/PhaseRepairTests.swift
git commit -m "P12.8: add PhaseRepair (commit failed phase + one RepairLoop attempt)"
```

---

### Task 4: phase-scoped repair packet + wire the build loop

**Files:**
- Modify: `Sources/swiftstar-agenttest/main.swift` (two changes: parameterize `repairPacket`; wire `PhaseRepair` into the phase loop)

**Interfaces:**
- Consumes: `PhaseRepair.run` (Task 3), `WorktreeTransaction.adoptRepairedPhase` (Task 2), `WorkerId(2)`, `orch.runPhase`, `repairEmissionFollowUp` (all existing in `main.swift`).
- Produces: `repairPacket(_:phaseScoped:)` and the phase-loop routing; no new types.

- [x] **Step 1: Parameterize `repairPacket`**

In `main.swift`, change the signature and directive of `repairPacket`:

```swift
func repairPacket(_ ctx: RepairContext, phaseScoped: Bool = false) -> HandoffPacket {
```

Replace the `directive` array with a `phaseScoped`-conditional (phase text first):

```swift
    let directive = (phaseScoped ? [
        "The import check failed against the code written by this phase. The",
        "failure output and the current file contents are appended below under",
        "\"Failure evidence (machine output)\".",
        "Exactly one file is wrong. First, in a few sentences, work out what the",
        "failure output tells you and what the corrected line must be. Then emit",
        "the heading line for that file followed by one fenced code block holding",
        "that file's complete corrected contents. The heading line and its fenced",
        "block must be the LAST thing in your response — end with the closing",
        "fence and write nothing after it.",
        "Do not emit a diff or a partial snippet, and do not reproduce the current",
        "broken file: emit the corrected file exactly once. The host applies the",
        "file you return exactly as written and re-runs the import check itself.",
        "Do not rewrite working files and do not add new files or routes.",
    ] : [
        "The acceptance suite failed against the code written by a prior phase. The",
        "failure output and the current file contents are appended below under",
        "\"Failure evidence (machine output)\".",
        "Exactly one file is wrong. First, in a few sentences, work out what the",
        "failure output tells you and what the corrected line must be. Then emit",
        "the heading line for that file followed by one fenced code block holding",
        "that file's complete corrected contents. The heading line and its fenced",
        "block must be the LAST thing in your response — end with the closing",
        "fence and write nothing after it.",
        "Do not emit a diff or a partial snippet, and do not reproduce the current",
        "broken file: emit the corrected file exactly once. The host applies the",
        "file you return exactly as written and re-runs the suite itself.",
        "Do not rewrite working files and do not add new files or routes.",
    ]).joined(separator: " ")
```

In the same function's `writableNote`, make the host-runs line phase-conditional — replace:

```swift
        "Do not run any command. After you return the file, the host runs the",
        "import check and the acceptance suite itself and re-grades the result.",
```

with:

```swift
        "Do not run any command. After you return the file, the host runs the",
        phaseScoped
            ? "import check itself and re-validates the result."
            : "import check and the acceptance suite itself and re-grades the result.",
```

Update the existing acceptance-repair call site (it passed `repairPacket` as a bare function reference, which no longer type-checks):

```swift
                packetBuilder: repairPacket,
```
becomes:
```swift
                packetBuilder: { repairPacket($0) },
```

- [x] **Step 2: Wire the phase loop**

In the build phase loop, replace the validation-failure block (the `if let validation, !validation.passed { ... }` that prints and persists, around the `runValidation` call before `txn.finalizePhase`) with:

```swift
        let validation = try WorktreeDispatcher.runValidation(packet.validationCommand, in: wt.url)
        if let validation, !validation.passed {
            print("[agenttest]   phase \(i + 1): import check failed (exit \(validation.exit)) — repairing")
            if !validation.output.isEmpty {
                print(validation.output)
                try? "phase \(i + 1) validation exit=\(validation.exit)\n\n\(validation.output)"
                    .write(to: captureDir.appendingPathComponent("validation-phase\(i + 1).txt"),
                           atomically: true, encoding: .utf8)
            }
            do {
                let repair = try PhaseRepair.run(
                    repo: repoURL,
                    failedWorktree: wt,
                    packet: packet,
                    validation: validation,
                    packetBuilder: { repairPacket($0, phaseScoped: true) },
                    runPhase: { pkt, tree, cap in
                        try orch.runPhase(worker: WorkerId(2), packet: pkt, worktree: tree, capture: cap)
                    },
                    capture: captureHandle,
                    captureDir: captureDir,
                    emissionFollowUp: repairEmissionFollowUp)
                switch repair {
                case .repaired(let repairedRef, let repairedWT):
                    try txn.adoptRepairedPhase(failedWorktree: wt,
                                               repairedWorktree: repairedWT,
                                               repairedRef: repairedRef)
                    print("[agenttest]   phase \(i + 1): repaired \(repairedRef)")
                    continue
                case .exhausted(let receipt):
                    return RunOutcome(finish: .stopped,
                                      note: "phase \(i + 1) repair exhausted (\(receipt))",
                                      acceptanceExit: nil, verdict: nil, report: nil,
                                      elapsed: Int(Date().timeIntervalSince(runStart)))
                }
            } catch RepairLoopError.sessionExhausted(let reason) {
                return RunOutcome(finish: .stopped,
                                  note: "phase \(i + 1) repair session exhausted (\(reason.rawValue))",
                                  acceptanceExit: nil, verdict: nil, report: nil,
                                  elapsed: Int(Date().timeIntervalSince(runStart)))
            }
        }
```

The `txn.finalizePhase(...)` call and its `switch` remain untouched immediately after this block (they now only run when validation passed or is nil).

- [x] **Step 3: Build**

Run: `swift build` (in the worktree; first run is a cold build)
Expected: SUCCESS. (This compiles the executable wiring; the routing logic itself is proven by Task 3's fake-tier test, and the end-to-end path by the live confirmation.)

- [x] **Step 4: Run the full integration tier**

Run: `SWIFTSTAR_INTEGRATION=1 swift test`
Expected: PASS — all suites, including the three new ones from Tasks 1–3, plus the existing `RepairLoopSeamTests`/`WorktreeTransactionTests`/`WorktreeDispatcherTests`.

- [x] **Step 5: Commit**

```bash
git add Sources/swiftstar-agenttest/main.swift
git commit -m "P12.8: wire phase-level repair into the build loop"
```

---

## Post-plan verification (D1 done-when)

- **Deterministic tier** is satisfied by Tasks 1–3 (unit + fake-tier: `commitForRepair`, `adoptRepairedPhase`, `PhaseRepair` with a scripted failure).
- **One live confirmation run** (not part of the automated tier): run the build arm — `AGENTTEST_TEXT_CONTRACT=1 swift run swiftstar-agenttest --spec roadmap-user-story` (text-contract is where the P15 phase-boundary defects were observed) — and confirm the capture shows `phase N: repaired <ref>` and the run continues to acceptance. Phase failures are stochastic (≈2/3 of runs), so this may take a couple of attempts; watch worker 2's `ctx_pos` for the D6 ceiling.
