# P10 verification record (2026-08-22)

Durable record for Phase P10 ("Isolation"). Executed on branch `p10-isolation`,
spec-driven per [`docs/sdd.md`](../../sdd.md).
Spec: [`docs/superpowers/specs/2026-08-22-p10-isolation-design.md`](../specs/2026-08-22-p10-isolation-design.md).
Plan: [`docs/superpowers/plans/2026-08-22-p10-isolation.md`](../plans/2026-08-22-p10-isolation.md).

## Test evidence

- **Fast tier** (`just test`): **288 tests in 38 suites passed**, 0 failures
  (0.298 s). The integration-gated suites are skipped — no model, no network, no
  subprocess (tripwire-guarded). New P10 fast suites: `HandoffPacketTests` (6 —
  `LineEnding`'s three cases, `FileBaseline` round-trips, the mixed-line-ending
  survival, `HandoffPacket` round-trips with and without a validation command,
  the octal-literal mode round-trip), `DispatchOutcomeTests` (8 — the candidate
  carries the ref + the `TurnOutcome`; each `Receipt` case names its reason or
  carries its payload; the candidate/receipt cases are distinct), `WorktreeDispatchTests`
  (19 — the pure `request → verdict` mapping: allowed mutations → candidate
  carrying the evidence; a mutation outside `writableFiles` → `.refusedTool`
  naming the first offending path; `refusedTool` precedence over budget and
  noChanges; turn/tool-call budgets exceeded but `==` is still a candidate;
  validation failed → `.validationFailed(exit:digest:)`; validation nil/passed
  → candidate; no mutations → `.noChanges`; `validationFailed` beats
  `noChanges`; baselines opaque to the verdict; the four `relativize`
  invariants — strip the worktree prefix, keep already-relative, keep
  non-worktree absolute, feed the verdict relative mutations). Extended suites:
  `ToolCallbackResponderTests` (+8 — `consent` refuses `write`/`edit` outside
  `writableFiles`, allows them inside and nested, leaves the read aids
  (`read`/`more`/`list`/`search`) unaffected, ignores the set when `nil`;
  `respond` refuses an out-of-contract write **without executing** and records
  no mutation, executes an in-contract write and records it, and a refusal
  returns `ok:false` without executing).
- **Integration tier** (`just integration`): **288 tests in 38 suites passed**,
  0 failures (3.402 s) — the gated suites now run. New P10 integration:
  `WorktreeDispatcherTests` (8 — `@Suite(.enabled(if: SWIFTSTAR_INTEGRATION == "1"))`,
  against a real fixture repo): `candidateCommitsAllowedMutation` (an allowed
  write → a candidate ref that resolves via `git rev-parse` and shows the file
  in `git show --stat`), `candidateCommitResolvesFromOutsideTheWorktree` (the
  ref still resolves after the worktree is removed — the commit object
  survives), `mutationOutsideWritableFilesYieldsReceipt` (`.refusedTool("outside.txt")`),
  `validationFailedYieldsReceiptWithExitAndDigest` (`validationCommand:"false"`
  → `.validationFailed` with `exit != 0`), `validationPassedYieldsCandidate`
  (`validationCommand:"true"` → candidate), `noMutationsYieldNoChangesReceipt`,
  `baselineReadFromWorktreeDiffersAfterChange` (baseline `mode == 0o644`,
  `lineEnding == .lf`; after a content edit `sha256` differs and `mode` does
  not), `baselineClassifiesCrlfLineEnding`. `FakeHostToolsIntegrationTests`
  (5, unchanged from P9) still green.
- **Engine tier** (`make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`):
  **`ds4-agent tests: ok`** (exit 0). P10 adds **no engine patch** (D5: no new
  wire; the dispatch reuses P9's `--host-tools` spawn), so the suite is
  re-verified green at the unchanged submodule SHA rather than re-exercised by a
  new regression — `ds4_agent_test` is the proof the reused `--host-tools` /
  `--workspace` / `--shell` surface still holds.
- **Live tier**: none. D5 reads "the dispatch uses the existing agent spawn"
  as the in-process, single-attempt, full-context case; a live end-to-end
  dispatch (a real model + a real `ds4-agent` over the wire) is out of scope for
  the tiered oracles — the app target has no test target, and the pure pieces
  the dispatch routes through (`ToolCallbackResponder.consent`/`respond`,
  `WorktreeDispatch.verdict`/`relativize`) are fast-tier-tested while the
  `WorktreeDispatcher` lifecycle is integration-tested with a scripted
  `attempt` closure.

## Round-trip evidence

The P9 `FakeHostToolsIntegrationTests` round trip (the fake agent ↔ fake app
`tool_request`/`tool_result` exchange) is unchanged and still green — P10 does
not touch the wire. The new round-trip-equivalent is the integration-tier
`WorktreeDispatcherTests`: a real `git worktree add`, a scripted `attempt`
closure (the injection point production fills with the agent spawn), a real
`git commit` of the diff, and a real `git rev-parse` of the candidate ref after
the worktree is removed. The candidate ref resolves as a commit (binding rule
6, the evidence floor); a changed file differs from its baseline; each refusal
case yields a typed `Receipt`. The dispatch is asserted by naming the fixture
repo and the `attempt` closure, not by hand-authoring the commit.

## Shown-fail records (binding rule 2)

Every new test was shown to fail before its implementation passed (binding rule
2: in a compiled language, "fail" = the target does not compile or the
assertion fails). Representative pins:

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| the pure verdict refuses an out-of-set mutation (T1) | accept a mutation outside `writableFiles` as a candidate | `mutationOutsideWritableFilesIsRefused` / `refusedToolNamesFirstOffendingPath` fail | yes |
| `refusedTool` precedence over budget and `noChanges` (T1) | check budget/noChanges first | `refusedToolTakesPrecedenceOverBudgetAndNoChanges` fails | yes |
| the candidate carries the `TurnOutcome` evidence (T1/D4) | return `.candidate` without the turn outcome | `candidateCarriesTheTurnOutcomeEvidence` fails | yes |
| the host refuses an out-of-contract write **without executing** (T3/D2) | execute then refuse, or record the mutation | `respondRefusesOutContractWriteAndDoesNotExecute` / `respondRefuseReturnsOkFalseAndDoesNotExecute` fail | yes |
| `relativize` strips the worktree prefix before the verdict (T3/D4) | feed the verdict absolute paths | `relativizeStripsTheWorktreePrefix` / `relativizeFeedsTheVerdictRelativeMutations` fail | yes |
| the candidate ref resolves as a commit after worktree removal (T2/rule 6) | delete the commit object with the worktree | `candidateCommitResolvesFromOutsideTheWorktree` fails (`git rev-parse` a missing object) | yes |
| a failed validation yields `.validationFailed` with exit + digest (T2) | return a candidate on validation failure | `validationFailedYieldsReceiptWithExitAndDigest` fails | yes |

## Real findings / design rulings during P10

1. **`.validationRan: Bool` was not a fifth `Receipt` case.** The plan/dispatch
   list a fifth receipt entry `.validationRan: Bool`, which is not valid Swift
   enum-case syntax (cases use parens for associated values; a colon denotes a
   property), and design D3 enumerates exactly four receipt reasons ("refused
   tool, budget exceeded, validation failed with exit status + digest, no
   changes"). D4 states `validationRan` rides on the P9 `TurnOutcome`, which
   `.candidate` carries as evidence. Read as a stray reference to the existing
   `TurnOutcome.validationRan` field — no fifth case added. (Task 1 ruling;
   carried through the close.)
2. **Two revision checks, by design (D2).** The host-side refusal
   (`ToolCallbackResponder.consent` with `writableFiles` set) is the production
   confinement: an out-of-set `write`/`edit` is refused, **not executed, not
   recorded**, so it never lands in the worktree. The pure verdict's
   `.refusedTool` is the **backstop** — it fires when an out-of-set mutation is
   *in* `allowedMutations` (a symlink escape the pure grant missed, or the
   integration test's scripted relative mutation). A dispatched attempt where
   the agent's out-of-set writes are all refused and it then writes in-set yields
   a **candidate**; one where it mutates nothing yields `.noChanges`. This is D3
   ("a turn that ends without a revision-check violation").
3. **Absolute vs relative mutations.** The P9 host executor records absolute
   paths (the confined `resolvedPath` under the worktree), but
   `packet.writableFiles` is worktree-relative, so the pure verdict's revision
   check compares apples-to-apples only after a strip. `WorktreeDispatch.relativize`
   bridges this in the dispatched attempt's finished `TurnOutcome` (pure,
   fast-tier-tested, idempotent for the integration tier's scripted relative
   mutations). Production (via the responder) produces absolute, which
   `relativize` strips; the integration tier scripts relative, which
   `relativize` keeps unchanged.
4. **`dispatch` takes an `attempt` closure.** The plan's headline signature is
   `dispatch(packet:in repo:)`; the integration tier needs an injection point
   for the "scripted attempt" (a write into the worktree the dispatcher itself
   creates and removes in one call), and a two-parameter call cannot both create
   the worktree and host the external attempt. The closure is that point:
   production spawns the agent at `--workspace <worktree>` and returns the P9
   `TurnOutcome`; a test is a scripted write. The pure verdict consumes that
   `TurnOutcome` (D4) — the packet's success is never inferred from prose.
5. **The throwaway branch is deleted in `defer`; the commit object survives.**
   The parent reviews the ref (a commit SHA), not the worktree — `git rev-parse
   <sha>` resolves a dangling commit, so deleting the branch keeps the ref
   reviewable while not leaving worktrees/branches piled up across dispatches.
   Worktree removal is `--force` to tolerate an unclean tree on a receipt path.
6. **App target untested.** `AgentController.dispatchAttempt` + `DispatchView` +
   the ephemeral wire drain are app-target code gated only by `swift build` (the
   app target has no test target). The pure pieces they route through are
   tier-tested; the `WorktreeDispatcher` lifecycle is integration-tested with a
   scripted `attempt` closure. A live end-to-end dispatch (real model + real
   agent) is out of scope for the tiered oracles.

## Concept budget

**handoff packet**, **candidate ref**, **receipt**, and **revision check** are
now defined (see ROADMAP). The seed terms **handoff packet** and **candidate ref**
are retired from the seed list (defined here, not deferred to P11). **patch set**,
**shipped integration**, and **variant** remain seed terms.

## Scope compliance

P10 shipped what the spec's Components section lists and nothing the Out-of-scope
section defers. In: `HandoffPacket` + `FileBaseline` + budget types; the pure
`WorktreeDispatch.verdict` (revision check → budget → validation → noChanges →
candidate); `DispatchOutcome` (candidate ref / receipt) + `Receipt`; the
`ToolCallbackResponder` revision check (`writableFiles` membership, refuse without
executing); `WorktreeDispatch.relativize`; `WorktreeDispatcher.dispatch`
(worktree create/remove, baseline read, validation parent-side, commit the
candidate, the ref resolves after removal); `AgentController.dispatchAttempt`
(host mode, shell off, the P9 responder revision-checking, `relativize` before the
verdict) + the minimal Dispatch tab. Out, and deliberately deferred: the subagent
pool / parallelism / specialized one-command workers (P11); the routing axes
(backlog); merging the candidate (the parent reviews the ref; merge is a human
act); `recall`/session browser (backlog); a live end-to-end dispatch with a real
model (out of scope for the tiered oracles). No new wire; the dispatch reuses
P9's `--host-tools` spawn.
