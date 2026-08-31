# P11 addendum — the canonical agent test: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A headless harness (`swiftstar-agenttest`) that runs a task decomposed into phases, each phase a subagent in a chained-worktree transaction, captures per-subagent + whole telemetry, and grades the result (deterministic acceptance suite + a DeepSeek "looks good vs spec" verdict). This is the project's canonical agent test.

**Architecture:** `WorktreeTransaction` (AppKit: chained worktrees, one commit-back) + `PoolOrchestrator` (AppKit: the headless orchestrator loop extracted from `AgentController`) + a new `swiftstar-agenttest` executable that drives them, plus committed AgentClinic fixtures. Kit is unchanged.

**Tech Stack:** Swift 6.3, SwiftPM; git CLI; `uv run pytest` for the acceptance suite; OpenRouter (`deepseek`) for the grader.

**Spec:** `docs/superpowers/specs/2026-08-23-p11-agenttest-addendum-design.md`

## Global Constraints

- Fast tier: pure Kit only (tripwire-guarded). Worktree/git/process are integration tier.
- Binding rule 2 (shown-fail), rule 3 (no source-text assertions), rule 6 (evidence floor: the acceptance suite rejects the broken fixture and accepts the reference).
- D3: phase N's worktree is branched from phase N-1's commit, not HEAD; one commit-back.
- D4: code folds forward via the checkout, context via the packet (v1 stubs the context).
- D6: grading has two legs — `uv run pytest` (deterministic) and a DeepSeek read (agent-judged); neither fabricates a pass.
- D8: n=1 first.

## File Structure

- AppKit: `WorktreeTransaction.swift` (new), `PoolOrchestrator.swift` (new); `WorktreeDispatcher.swift` (add `baseRef` to `prepare`, add `resolve`). Integration tests `WorktreeTransactionTests`, `PoolOrchestratorTests`.
- Harness: `Sources/swiftstar-agenttest/main.swift` (new executable target in `Package.swift`).
- Fixtures: `fixtures/agenttest/` (the two specs + acceptance contract + reference/broken).

---

### Task 1: WorktreeTransaction — chained worktrees, one commit-back

**Files:**
- Modify: `Sources/SwiftStarAppKit/WorktreeDispatcher.swift` (add `baseRef` to `prepare`, add `resolve(ref:in:)`).
- Create: `Sources/SwiftStarAppKit/WorktreeTransaction.swift`
- Test: `Tests/SwiftStarIntegrationTests/WorktreeTransactionTests.swift`

**Interfaces:**
- Consumes: `WorktreeDispatcher.prepare`/`finalize`/`discard`, `HandoffPacket`, `TurnOutcome`, `ValidationResult`.
- Produces: `WorktreeDispatcher.prepare(packet:in:baseRef:) -> Worktree`; `WorktreeDispatcher.resolve(ref:in:) throws -> String`; `WorktreeTransaction` (`preparePhase(packet:) -> Worktree`, `finalizePhase(worktree:packet:turnOutcome:validation:) -> DispatchOutcome`, `commitBack() -> String?`, `abort()`).

- [ ] **Step 1: Write the failing integration test.** A fixture repo with two files; phase 1 writes `a.txt`, phase 2 (branched from phase 1's commit) sees `a.txt`'s changed content and writes `b.txt`; `commitBack` returns a ref that resolves to a commit containing **both** files' changes; the caller's tree is untouched; after `commitBack`, the intermediate worktrees are gone.

```swift
@Test func phasesChainAndCommitBack() throws {
    let repo = try makeFixtureRepo()   // seed commit with a.txt = "seed\n"
    defer { try? FileManager.default.removeItem(at: repo) }
    let txn = WorktreeTransaction(repo: repo)

    let p1 = HandoffPacket(taskText: "phase 1", writableFiles: ["a.txt"],
                           validationCommand: nil, baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    let wt1 = try txn.preparePhase(packet: p1)
    try "one\n".write(to: wt1.url.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    let o1 = try txn.finalizePhase(wt1, packet: p1,
                                   turnOutcome: outcome(mutations: ["a.txt"]), validation: nil)
    guard case .candidate = o1 else { Issue.record("phase 1 must be a candidate"); return }

    let p2 = HandoffPacket(taskText: "phase 2", writableFiles: ["b.txt"],
                           validationCommand: nil, baselines: [:], turnBudget: 1000, toolCallBudget: 8)
    let wt2 = try txn.preparePhase(packet: p2)
    // Phase 2's checkout already contains phase 1's committed change to a.txt.
    #expect(try String(contentsOf: wt2.url.appendingPathComponent("a.txt"), encoding: .utf8) == "one\n")
    try "two\n".write(to: wt2.url.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
    _ = try txn.finalizePhase(wt2, packet: p2,
                              turnOutcome: outcome(mutations: ["b.txt"]), validation: nil)

    guard let ref = txn.commitBack() else { Issue.record("commitBack must return the final ref"); return }
    #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
    // The final worktree is retained for grading (the acceptance suite runs here).
    let gradeWT = try #require(txn.finalWorktree)
    #expect(FileManager.default.fileExists(atPath: gradeWT.url.appendingPathComponent("b.txt").path))
    let show = try git(repo, ["show", "--stat", "--name-only", ref])
    #expect(show.contains("a.txt"))
    #expect(show.contains("b.txt"))
    #expect(try String(contentsOf: repo.appendingPathComponent("a.txt"), encoding: .utf8) == "seed\n")
    txn.discardFinal()
    #expect(!FileManager.default.fileExists(atPath: gradeWT.url.path))
}
```

- [ ] **Step 2: Run it, confirm RED** (`SWIFTSTAR_INTEGRATION=1 swift test --filter WorktreeTransactionTests`).

- [ ] **Step 3: Implement.** In `WorktreeDispatcher`, add `baseRef: String? = nil` to `prepare` (when set, `git worktree add -b <branch> <path> <baseRef>`) and add `resolve(ref:in:) -> String` (`git rev-parse <ref>`). Create `WorktreeTransaction`:

```swift
public final class WorktreeTransaction {
    private let repo: URL
    private var worktrees: [WorktreeDispatcher.Worktree] = []
    public private(set) var head = "HEAD"
    public private(set) var candidateRef: String?
    /// The worktree of the last *candidate* phase — retained for grading.
    public private(set) var finalWorktree: WorktreeDispatcher.Worktree?

    public init(repo: URL) { self.repo = repo }

    public func preparePhase(packet: HandoffPacket) throws -> WorktreeDispatcher.Worktree {
        let wt = try WorktreeDispatcher.prepare(packet: packet, in: repo, baseRef: head)
        worktrees.append(wt)
        return wt
    }

    public func finalizePhase(_ worktree: WorktreeDispatcher.Worktree, packet: HandoffPacket,
                              turnOutcome: TurnOutcome,
                              validation: ValidationResult?) throws -> DispatchOutcome {
        let outcome = try WorktreeDispatcher.finalize(
            worktree, packet: packet, turnOutcome: turnOutcome, validation: validation, in: repo)
        switch outcome {
        case .candidate(let ref, _, _):
            head = try WorktreeDispatcher.resolve(ref: ref, in: repo)
            candidateRef = ref
            finalWorktree = worktree
        case .receipt:
            break  // no head advance; the transaction stops
        }
        return outcome
    }

    /// Return the final candidate ref, discarding every intermediate worktree but
    /// KEEPING `finalWorktree` for grading (the caller grades there, then calls
    /// `discardFinal`). Returns nil when no phase produced a candidate.
    public func commitBack() -> String? {
        for wt in worktrees where wt.url != finalWorktree?.url {
            WorktreeDispatcher.discard(wt, in: repo)
        }
        worktrees = finalWorktree.map { [$0] } ?? []
        return candidateRef
    }

    public func discardFinal() {
        if let f = finalWorktree { WorktreeDispatcher.discard(f, in: repo) }
        worktrees.removeAll()
        finalWorktree = nil
    }

    public func abort() {
        discardFinal()
        head = "HEAD"
        candidateRef = nil
    }
}
```

- [ ] **Step 4: Run, confirm GREEN.**

- [ ] **Step 5: Commit** `P11 agenttest: WorktreeTransaction (chained worktrees + commit-back)`.

---

### Task 2: PoolOrchestrator — the headless orchestrator loop

**Files:**
- Create: `Sources/SwiftStarAppKit/PoolOrchestrator.swift`
- Test: `Tests/SwiftStarIntegrationTests/PoolOrchestratorTests.swift`

**Interfaces:**
- Consumes: `AgentCommand`, `PoolWireParser`, `PoolPrompt`, `ToolCallbackResponder`, `TurnOutcomeBuilder`, `WorktreeDispatch`, `SubprocessRunner`.
- Produces: `PoolOrchestrator` (`init(settings:) throws` spawns `ds4-agent --subagent-pool 2` — one worker slot, v1, reused across phases; `runPhase(worker:packet:worktree:) throws -> TurnOutcome` — send `PoolPrompt`, drain worker-N events, answer tool requests, relativize + return; `stop()`).

- [ ] **Step 1: Write the failing integration test.** Against the fake pool engine (`pool.ndjson` + `--subagent-pool 2` argv): `runPhase(worker: 1, …)` returns a `TurnOutcome` whose `stopReason` is `.eos` and whose mutations are the worker's.

- [ ] **Step 2: Run, confirm RED.**

- [ ] **Step 3: Implement.** `runPhase` is the P10 `runDispatchedTurn` shape, but it drives **worker N of the pooled engine** rather than spawning a fresh process: write `PoolPrompt(worker:text:).encode()`, drain `worker`-tagged events, answer `.toolRequest` via `ToolCallbackResponder.respond(workspace: worktree, shellAllowed: false, writableFiles: packet.writableFiles)`, and on the worker's turn-end `.ready`, `WorktreeDispatch.relativize` the `TurnOutcome` against `worktree` and return it. A wall-clock deadline + `Task.isCancelled` guard mirror P10's dispatch-turn timeout.

- [ ] **Step 4: Run, confirm GREEN.**

- [ ] **Step 5: Commit** `P11 agenttest: PoolOrchestrator (headless orchestrator loop)`.

---

### Task 3: The AgentClinic fixtures (committed)

**Files:**
- Create: `fixtures/agenttest/roadmap.md` (the full 3-phase imperative spec), `fixtures/agenttest/roadmap-user-story.md` (the user-story variant), `fixtures/agenttest/mission.md`, `fixtures/agenttest/tech-stack.md`, `fixtures/agenttest/acceptance/test_acceptance.py`, `fixtures/agenttest/reference/`, `fixtures/agenttest/broken/`.

- [ ] **Step 1: Recover the full roadmap.** The committed `local-ai-pi` `examples/agentclinic/specs/roadmap.md` has only Phase 1; Phases 2 (complaints board) and 3 (add complaint) live in git history (`8af05f8`, `a5ef1e1`). Recover them, or author them from `mission.md` + `tech-stack.md` (Complaint `dataclass`: `agent_name`/`text`/`timestamp`, in-memory list; `/complaints` read route; `/complaints` add form). Do the same for the user-story variant.

- [ ] **Step 2: Copy the acceptance contract + reference/broken** fixtures, adapting any imports to the committed layout.

- [ ] **Step 3: Evidence floor.** Run the acceptance suite against `reference/` (passes) and `broken/` (rejects) in a throwaway checkout, recording the commands. A single `uv run pytest` command must be the deterministic grade.

- [ ] **Step 4: Commit** `P11 agenttest: AgentClinic fixtures (3-phase roadmap + user-story + acceptance)`.

---

### Task 4: The harness executable (`swiftstar-agenttest`)

**Files:**
- Modify: `Package.swift` (add `.executableTarget(name: "swiftstar-agenttest", dependencies: ["SwiftStarKit", "SwiftStarAppKit"])`).
- Create: `Sources/swiftstar-agenttest/main.swift`

**Interfaces:**
- Consumes: `WorktreeTransaction`, `PoolOrchestrator`, `HandoffPacket`, `DispatchPacketBuilder`, `RollingDigest`.
- Produces: a report to stdout — per-phase telemetry (turns, tokens, tool calls, mutations, ref/receipt), the whole-run summary, the acceptance result, and the paths to the generated code + spec for the grader.

- [ ] **Step 1: The decomposition** (pure, in `main.swift` or a Kit helper): split a roadmap on `## Phase` headers; the `## Environment` section (plus `mission.md`/`tech-stack.md`) is shared context prepended to every packet.

- [ ] **Step 2: The run loop.** Begin `WorktreeTransaction`; for each phase, `preparePhase` → build the packet (`DispatchPacketBuilder`-style: phase section + shared context + prior ref, `validationCommand: nil` in v1 — the worker codes blind) → `runPhase` → `finalizePhase` → record telemetry. **On a phase receipt, stop the transaction** (no partial chain) and record the failure.

- [ ] **Step 3: Grading.** Run `uv run pytest` in `txn.finalWorktree` (deterministic) — this is the only validation in v1; the packet's `validationCommand` is nil and the worker codes blind. Write the generated code + the full rubric (spec + `mission.md` + `tech-stack.md`) to a report dir for the grader.

- [ ] **Step 3a: The grader component** (a small pure parser + a live OpenRouter call): the pinned prompt (rubric + `git diff HEAD..<candidate>` + "return JSON `{\"verdict\":\"good\"|\"bad\",\"reasons\":[…]}`"), model `deepseek/deepseek-chat`, a timeout + one retry, and on failure record `verdict: "error"` — never fabricate a pass. A unit test parses canned good/bad/error responses.

- [ ] **Step 4: Build + `swift build`; commit** `P11 agenttest: swiftstar-agenttest executable`.

---

### Task 5: The live run + close

**Files:**
- Modify: `docs/superpowers/research/2026-08-23-p11-agenttest-verification-record.md` (new).

- [ ] **Step 1: Run the harness** on the **easy** and **hard** specs, n=1, against the real engine and weights (`SWIFTSTAR_MODEL`, `DS4_DIR`), headless.

- [ ] **Step 2: Grade.** Run the DeepSeek pass (Step 3a's component) over each result: the structured verdict + reasons, or `verdict: "error"` on a failed call. Do not claim a pass the acceptance suite did not give.

- [ ] **Step 3: Record.** Write the verification record: per-phase + whole telemetry, acceptance result, DeepSeek verdict, exact commands. State plainly what n=1 does and does not establish.

- [ ] **Step 4: Commit** `P11 agenttest: live run (easy/hard, n=1) + verification record`.

---

## Self-review

**Spec coverage:** D1→Task 2,4 (harness orchestrates; model implements); D2→Task 3 (two specs, one contract); D3→Task 1; D4→Task 4 (v1-stubbed context); D5→Task 4 (report); D6→Tasks 4,5 (both legs); D7→Task 2 (extraction); D8→Task 5 (n=1); D9→ out of scope, but the harness's `runPhase` + `WorktreeTransaction` are the seams a future specialist-role subagent plugs into.

**Placeholder scan:** no TBD/TODO; Phase 2/3 recovery is pinned to specific commits or to `mission.md`+`tech-stack.md`.

**Type consistency:** `WorktreeTransaction` (Task 1) is consumed by Task 4; `PoolOrchestrator` (Task 2) by Task 4; the packet shape is P11's `HandoffPacket` throughout.

**Known deviation, stated:** the DeepSeek grader is a live-tier model call (OpenRouter), so it is part of the harness's live run, never CI.
