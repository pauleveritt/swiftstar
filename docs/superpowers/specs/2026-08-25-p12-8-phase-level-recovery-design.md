# SwiftStar design: P12.8 — phase-level recovery

**Date:** 2026-08-25
**Status:** draft (brainstormed; awaiting review)
**Phase:** P12.8 — phase-level recovery (reopens P12's "recovery" charter)
**Branch:** `p15-host-controlled-action-mode` (at `ea3d7ca`); builds on the P15
text-contract build arm and P12.4's `RepairLoop`.
**Brief:** `docs/superpowers/plans/archive/P12.8-brief.md`

## Problem

A build phase (`swiftstar-agenttest/main.swift`, the phase loop) that fails its
`validationCommand` (the vetted import check) aborts the whole run before
`commitBack()`. Mechanism: `WorktreeTransaction.finalizePhase` →
`WorktreeDispatcher.finalize` → `WorktreeDispatch.verdict` step 3 maps a failed
validation to `.receipt(.validationFailed(exit:digest:))`, and the build loop's
`.receipt` arm returns `RunOutcome(.stopped)`.

`RepairLoop` exists and fixes exactly this defect class 4/4 live (one-line
content defects at a phase boundary: wrong import, wrong module, a mount path
outside the grant), but it is wired only after the *final* acceptance grade on
worker 2 — unreachable from a phase failure.

This is unfinished P12 scope, not new work: P12's charter was host-owned
"budgets, permissions, validation, **and recovery**"; P12.4 wired recovery only
at the acceptance boundary. Evidence (P15 verdict record): 5 of 6 build-run
failures were one-line content defects at a phase boundary.

## Scope (strict)

**In:**

- Replace the phase-abort with a single `RepairLoop` attempt, graded against the
  phase's own `validationCommand`.
- `WorktreeDispatcher.commitForRepair` — commit the failed phase's worktree to a
  throwaway ref (the `failedRef` `RepairLoop` branches from).
- `WorktreeTransaction.adoptRepairedPhase` — fold the repaired worktree back as
  the transaction's new `head`/`finalWorktree`.
- A phase-scoped repair packet (directive says "the import check failed," not
  "the acceptance suite failed").

**Out (deferred, named):**

- Retry-on-receipt (changing `RepairLoop`'s receipt-exit; see D2, D6).
- Worker-2 session reset between phase repairs (needs a pool-wire reset verb;
  see D6).
- Pool widening / worker rotation.
- Pass-rate guarantees (the verdict record's "3-of-9" discipline).

## Decisions

### D1 — Done-when: deterministic tier + one live confirmation (no rate)

The phase-repair path is wired, the coupled changes are unit/fixture-proven on
the fake tier (a scripted phase failure is repaired and the run continues), and
one live build-arm capture shows it firing. A pass-rate measurement is a
separate, later decision (the verdict record's n-survival lesson).

### D2 — One repair attempt per phase failure; `RepairLoop` unchanged

`validation.command` is mandatory (`HandoffPacketValidator`), so the import
check must stay the packet's `validationCommand`; a still-broken repair
therefore exits as `.receipt(.validationFailed)` — one attempt, for free. No
change to `RepairLoop`'s "exit on any receipt" rule.

Consistency with D4 (P12.4): the round bound of 2 is "a starting value, not a
derived one" (`2026-08-24-p12-4-repair-role-design.md:97-103`), and the fixture
tier was 6/6 on round 1 with round 2 never observed helping — so 1-for-validation
is the same unproven-bound caution applied where evidence is weaker, not an
inconsistency.

**Evidence asymmetry (recorded, not fixed here):** the grade path preserves full
evidence (`GradeResult.output` → `MachineEvidence`); the validation path hashes
it into the receipt. `runValidation` *captures* `output` (combined stdout+stderr,
`05a4fcc`), but `WorktreeDispatch.verdict` (`WorktreeDispatch.swift:78-79`) folds
it into `.receipt(.validationFailed(exit:digest:))`, which carries no output. A
future retry fix is therefore local — thread `validation.output` into `lastGrade`
at `RepairLoop`'s `finalize` call site, or widen the `Receipt.validationFailed`
case — not a change to `runValidation`/`ValidationResult`.

### D3 — `grade` is vestigial; always-pass

`finalize` returns `.candidate` only after the verdict's step-3 validation
passed, so by the time `RepairLoop` reaches `grade`, the gate has already passed.
Therefore:

- `grade: { _ in GradeResult(exit: 0, output: "") }` — trivial always-pass.
- The real gate is `validationCommand` (the import check, run inside `finalize`).
- `initialGrade` is the load-bearing evidence: `GradeResult(exit: validation.exit,
  output: validation.output)` — the import traceback that becomes
  `MachineEvidence.failureOutput`.

**Folding consequence:** because `grade` is vestigial, `.passed`'s retained
worktree is *the phase's committed result*, not a tree to grade further. The
transaction must adopt it as `head` (D4) — this inverts P12.4's
grade-then-discard lifecycle.

### D4 — Approach: commit-failed-phase → `RepairLoop` → adopt

Three pieces, two of them new and local:

1. `WorktreeDispatcher.commitForRepair(worktree:packet:in:) -> String` — extract
   `finalize`'s commit step (`git add -- <writableFiles>` + the porcelain-guarded
   `git commit` + `rev-parse HEAD`), made unconditional (no verdict). Returns the
   failed phase's commit as `failedRef`.
2. `RepairLoop.run(...)` unchanged, called with `failedRef`, `initialGrade` = the
   validation failure (D3), `runPhase` = worker 2, `grade` = always-pass.
3. `WorktreeTransaction.adoptRepairedPhase(failedWorktree:repairedWorktree:
   repairedRef:)` — discard the failed worktree, advance `head = resolve(repairedRef)`,
   `candidateRef = repairedRef`, `finalWorktree = repairedWorktree`.

Rejected: teaching `RepairLoop` to accept a live worktree base (git still needs a
commit-ish to branch from; drags P12.4's call site); repairing in place
(reimplements `MachineEvidence` + the text-contract harvest seam + the emission
follow-up — the P15 seams that took captures to get right).

### D5 — `commitForRepair` keeps the porcelain guard

The verdict checks validation (step 3) before noChanges (step 4), so a phase that
mutated nothing but inherited a broken tree returns `.validationFailed`, and the
commit step finds nothing staged. `commitDiff`'s existing `git status --porcelain`
guard (`WorktreeDispatcher.swift:200-209`, from `adc08c0`) already returns the
parent SHA in that case — which is correct: the failed state *is* the parent tree,
and repair against it is "write the missing files." The extraction must keep that
guard and its parent-SHA fallback; it must not add a "must have changes"
assertion, or it reintroduces the byte-identical-rewrite bug the guard was written
for.

### D6 — Worker 2 budget: accept the stop-guard; name the reset as follow-up

D8 sized worker 2 for two rounds of one repair ("round 2 starts ~10–12k, fits
32k"; `2026-08-24-p12-4-repair-role-design.md` D8). P12.8 changes the shape: up to
three phase repairs in one run, each dispatching to the same worker-2 session with
full-surface evidence. Three sequential repairs could approach ctx=32768.

Chosen: **accept the existing stop-guard and record the ceiling.** The
`limit`/`contextFull` guard already stops the run gracefully (D8's "stop the run"
is the backstop; `RepairLoop` throws `sessionExhausted`), and the one live
confirmation run will surface the ceiling with a graceful stop rather than a hang.
The deterministic tier proves the wiring and the stop-guard (a scripted exhausted
repair fires the guard), not the organic accumulation (a live-only property).

**Named follow-up:** reset worker 2's session between phase repairs.
`agent_worker_reset_to_sysprompt` exists engine-side (`ds4_agent.c:6429`) but is
reachable only from the interactive `/new` command; the pool wire (`PoolPrompt`)
carries no reset verb. So this is engine + protocol work, not a wiring tweak — its
own small phase, justified the moment a captured run shows worker 2 approaching
32k.

### D7 — Phase-scoped repair packet

The repair directive currently names "the acceptance suite failed against the code
written by a prior phase." A phase-level repair packet names "the import check
failed against the code written by this phase," same contract/`writableFiles`/
`redacts`, reuses the text-contract harvest seam and the two-turn emission
follow-up (`repairEmissionFollowUp`).

## Flow

In the build loop (`main.swift`), after harvest and before `finalizePhase`:

```
validation = runValidation(packet.validationCommand, in: wt.url)
if let validation, !validation.passed:
    failedRef = commitForRepair(wt, packet, repo)
    repair = RepairLoop.run(
        repo: repo, failedRef: failedRef,
        initialGrade: GradeResult(exit: validation.exit, output: validation.output),
        packetBuilder: phaseRepairPacket,
        runPhase: { orch.runPhase(worker: WorkerId(2), ...) },
        grade: { _ in GradeResult(exit: 0, output: "") },
        capture: ..., captureDir: ..., emissionFollowUp: repairEmissionFollowUp)
    switch repair:
    case .passed(repairedRef, _, repairedWT):
        txn.adoptRepairedPhase(failedWorktree: wt, repairedWorktree: repairedWT,
                               repairedRef: repairedRef)
        # continue to the next phase (skip finalizePhase — the repair already committed)
    case .exhausted(_, receipt):
        return RunOutcome(.stopped, note: "phase \(i+1) repair exhausted (\(receipt))", ...)
else:
    # existing finalizePhase path
```

## Error handling / edge cases

- **No-mutation phase failure** → `commitForRepair` returns the parent SHA (D5);
  repair is coherent ("write the missing files").
- **Repair exhausted** (`.exhausted`, incl. `.validationFailed` from the repair's
  own import) → the existing abort, with the receipt recorded (D2).
- **Worker 2 context exhaustion** → `sessionExhausted` → stop the run (existing
  guard; D6).

## Testing (done-when; D1)

- **Unit:** `commitForRepair` (incl. no-mutation → parent SHA), `adoptRepairedPhase`
  (advances head, discards the failed worktree), the `ValidationResult → GradeResult`
  conversion, the always-pass grade.
- **Fixture/fake tier:** a scripted phase validation failure routes through
  `RepairLoop` → phase-scoped grade → `adoptRepairedPhase` → the run continues and
  reaches acceptance; a scripted exhausted repair stops the run with the recorded
  receipt.
- **One live build-arm confirmation run** (a deliberately-failing phase, or
  observed): the path fires; worker 2's ctx_pos is watched for the D6 ceiling.

## Known limitations (carried forward)

- No retry on a repair that itself fails validation (D2/D6).
- No worker-2 reset between phase repairs (D6).
- Phase repair inherits the text-contract lenient-harvest blur (P15 verdict
  record, limitation 3).

## Gardenable facts (verified against source)

- `finalize` commits only in the `.candidate` branch (`WorktreeDispatcher.finalize`);
  a `.validationFailed` receipt leaves the phase's files only in the live worktree.
- `WorktreeDispatch.verdict` order: revision → budget → validation → noChanges →
  candidate (`WorktreeDispatch.swift` doc header + `:78-79`).
- `runValidation` captures combined stdout+stderr as `output` (`05a4fcc`); the
  receipt drops it (`WorktreeDispatch.swift:78-79`).
- `commitDiff` porcelain guard + parent-SHA fallback (`WorktreeDispatcher.swift:200-209`).
- `validation.command` is mandatory (`HandoffPacketValidator`).
- `PoolPrompt` carries only `{"t":"prompt","worker","s"}`; the engine's session
  reset is interactive `/new` only (`ds4_agent.c:17331-17337`).
