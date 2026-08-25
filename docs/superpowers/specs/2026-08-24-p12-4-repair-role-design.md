# SwiftStar P12.4 design: The repair role

**Date:** 2026-08-24
**Status:** accepted (brainstormed; each decision approved in-session).
**Phase:** P12 — Reliable agency, step P12.4.

This spec is the authority on *how* P12.4 is done. The P12 plan
([`2026-08-24-p12-reliable-agency.md`](../plans/2026-08-24-p12-reliable-agency.md))
stays settled; this fills its P12.4 stub.

## Problem

The harness (`swiftstar-agenttest`) has an implement loop and no repair loop:
it runs the three roadmap phases, grades once via the acceptance suite
(`test_acceptance.py`, 13 tests), records the exit code, and stops. Nothing
detects a failure and hands it back to the model.

P12.4 assembles the proven pipeline: hand-authored packets → nothink implement →
nothink repair on pytest failure. Implement is a known quantity (3/9 end-to-end,
diminishing returns — C15–C18). Repair is the next real gap, but its evidence is
thin: 3/3 correct minimal fixes measured through `repair.py` *outside* the
sandboxed harness, thinking never engaged, and a file picker that mis-picked a
non-broken file in three observed rounds. This spec designs the in-harness repair
loop that consumes that evidence's plumbing rather than `repair.py`'s.

## Gardenable facts (verified against the source)

- **The trigger gap is at grading, not validation.** Each implement phase already
  runs `validationCommand` (the vetted `import app` check) via
  `WorktreeDispatcher.runValidation`; the *acceptance* suite runs once, after
  `commitBack()`, inline in `main.swift`. Repair inserts a loop between "grade"
  and "record a failure."
- **`PacketRole.repair` already exists** in `HandoffPacket`; nothing dispatches
  it. `ThinkMode.off/.on/.bounded` and `SamplingPolicy` exist and are
  per-packet; `facts` render into `taskText` via `PhasePacketBuilder`.
- **The file-picker failure is self-inflicted.** `repair.py` narrowed to one file
  by traceback-substring match and showed the model only that — which is how it
  picked `templates/complaints.html` (innocent) for the misleading-locus bug. The
  revision-test ladder's L1 rung is "pytest failure + full file content," so a
  design that presents the whole writable surface has no picker to get wrong.
- **The typed contract is already the repair contract.** `writableFiles`,
  `validationCommand`, `selfTestCommand`, `redacts`, `facts`, `role`, `sampling`,
  and the pre-dispatch `HandoffPacketValidator` all exist; the validator already
  checks redaction on the *assembled* packet, not the authored fragment.
- **Repair needs no deliberation on the evidence available.** Thinking was never
  engaged in any of the five recorded repair runs; canonical fixes were produced
  at temp 0. The plan stub reads "nothink implement → nothink repair."
- **The two fixtures are the first valid L1 cells.** `misleading-locus` (traceback
  surfaces at rendering, defect in the handler) and `plausible-wrong-fix`
  (tempting 302, correct 303; pair with `AGENTTEST_REDACT=303`) are verified
  12/13 baselines against the real suite, each a minimal delta from
  `reference/app.py`.

## Decisions

- **D1 — Repair is post-grade recovery, not a phase.** The implement transaction
  ends at a candidate ref; acceptance grading is the boundary. A failed grade
  hands the candidate ref + grade output to repair. Repair is a bounded loop of
  *chained repair rounds*, each an ordinary `role: .repair` dispatch, re-graded
  after every round. No new phase kind, no change to the implement transaction's
  contract.

- **D2 — Full surface, no picker.** The repair packet presents the *complete
  current content* of every `writableFiles` entry plus the pytest failure output.
  The model localizes and edits. There is no host-side file selection, so the
  `repair.py` failure mode (traceback-substring match picking a non-broken file)
  cannot occur by construction. The fixtures measure whether the model edits the
  right file when shown everything and a failure that surfaces elsewhere — and,
  because a wrong edit re-fails grading, whether a wrong repair is detected as
  wrong.

- **D3 — Repair reuses `HandoffPacket`, unchanged.** No repair-specific packet
  type. The repair packet is built with `role: .repair`, `sampling: .off` by
  default (overridable via `AGENTTEST_REPAIR_THINK=1` → `.bounded` for the
  deferred bounded-thinking question), and task text composed as: pinned facts →
  repair directive (the pytest failure output + all file contents) → contract
  (`preamble` + `sharedContext`, redacted) → writable note. Same
  `validationCommand` (`import app`), same `selfTestCommand` (vetted pytest),
  same `writableFiles`, same `redacts`. One contract, two consumers.

- **D4 — Two rounds, then `.repairExhausted`.** Repair is bounded: up to 2
  rounds, each re-graded after a candidate. A wrong fix is detected by re-grading
  and becomes the next round's evidence. A round that yields a receipt
  (`noChanges` / `validationFailed` / `budgetExceeded` / `refusedTool`) is a
  failed round, counted against the bound. After the bound, the loop returns
  `.exhausted` carrying a new `Receipt.repairExhausted` case, so the run records
  *why* it stopped rather than silently reporting the last failed grade.

- **D5 — Fresh worktree per round, branched from the failed candidate ref.** Round
  N prepares a disposable worktree from `head` (the failed candidate ref, then the
  prior round's candidate ref) via `WorktreeDispatcher.prepare`, runs the turn,
  runs the import check, and `finalize`s to a new candidate ref. Each round is a
  clean, reverting, re-gradable step; no reuse of the graded worktree (which has
  `test_acceptance.py` dropped into it and is not a clean checkout).

- **D6 — Redaction gates authored content; machine evidence is exempt.** The
  validator's redaction check (e.g. `AGENTTEST_REDACT=303`) applies to authored
  content — spec, facts, notes, commands, paths — *not* to the pytest failure
  output or the file contents injected at repair time. The failure
  `assert 307 == 303` legitimately states 303; it is the L1 signal, not a leak.
  Therefore: validate the authored repair packet for redaction **first**, then
  append the failure output + file contents to `taskText`. The "check the
  assembled packet" doctrine still holds for authored content (that is where
  contamination lived); machine evidence is a distinct category, injected
  post-validation.

- **D7 — Acceptance-test isolation.** `test_acceptance.py` is written into the
  worktree only at grade time, after the repair turn ends — so the model never
  sees or runs it during a turn (it is not in `writableFiles` and not present).
  Same rule as the implement flow today.

- **D8 — Session-exhaustion guard carries into repair.** A repair turn ending
  `limit` / `contextFull` leaves the pooled worker session unusable; stop the
  whole run (no round 2), as `main.swift` already does for implement phases.

- **D9 — Placement: `RepairLoop` in SwiftStarAppKit, grading extracted.** Two new
  types, one extraction:
  - `GradeResult` (value type): `exit`, `output`, `passed`.
  - `AcceptanceGrader` (SwiftStarAppKit): the pytest run currently inline in
    `main.swift` — copy `test_acceptance.py` in, run
    `uv run --project <pyProject> pytest -q test_acceptance.py` with cwd = the
    worktree, return `GradeResult`. Shared by `main.swift` and `RepairLoop`.
  - `RepairLoop` (SwiftStarAppKit): the bounded orchestrator. Inputs: repo URL,
    failed candidate ref, failing `GradeResult`, acceptance-test source +
    pyProject, a `packetBuilder` closure, a `runPhase` closure. Returns
    `.passed(ref, grade)` or `.exhausted(lastGrade, .repairExhausted)`.
  - `Receipt.repairExhausted` (new case in SwiftStarKit).
  Division of labor: `packetBuilder` returns the **authored** packet (`role`,
  `sampling`, facts, directive, contract, writable note, `redacts`); `RepairLoop`
  validates that packet for redaction, reads the worktree's file contents, and
  appends [failure output + file contents] to `taskText` before dispatch (D6).
  `runPhase` is the pooled orchestrator's `orch.runPhase`. `RepairLoop` owns only
  the round/re-grade/bound/evidence-injection logic; everything model- and
  contract-specific stays harness-owned. This makes `RepairLoop` testable
  without a model load.

- **D10 — A fixture mode for deterministic verification.** `swiftstar-agenttest
  --fixture <misleading-locus|plausible-wrong-fix>` overlays `reference/*` +
  the fixture's buggy `app.py` into a fresh repo, skips the implement phases,
  grades (guaranteed 12/13), runs the *same* `RepairLoop`, and asserts 13/13.
  This is the primary test that the loop localizes and fixes; the live roadmap
  run (implement → grade → repair on failure) is the end-to-end 13/13 gate.

## Components

**SwiftStarKit** (pure): `GradeResult`; the `Receipt.repairExhausted` case. No
I/O, no git.

**SwiftStarAppKit** (IO/Process, no SwiftUI): `AcceptanceGrader` (the extracted
pytest run); `RepairLoop` (the bounded round/re-grade loop over
`WorktreeDispatcher.prepare`/`runValidation`/`finalize`/`discard`, driven through
the `packetBuilder`/`runPhase` closures).

**swiftstar-agenttest** (`main.swift`): the `packetBuilder` (which owns the
*authored* repair task-text composition — `writableFiles`, `facts`, `redacts`,
`sampling`, directive, contract, writable note), the `runPhase` closure
(`orch.runPhase`), the fixture seeding for `--fixture`, and the final outcome
recording (pass vs `.repairExhausted`).

## Data flow (one repair)

1. `main.swift`: implement phases → `commitBack()` → `AcceptanceGrader.grade(finalWorktree)`.
   Pass → done (13/13). Fail → `RepairLoop.run(...)` with the candidate ref and
   the failing `GradeResult`.
2. Round N (`head` = failed ref, then prior candidate ref):
   - `WorktreeDispatcher.prepare(packet, baseRef: head)`.
   - Read every `writableFiles` entry's current content from the worktree.
   - Build the repair packet via `packetBuilder`; validate the *authored* packet
     (redaction, structure); append failure output + file contents to `taskText`.
   - `runPhase(packet, worktree)`; `runValidation(import app)`; `finalize`.
   - Candidate → `AcceptanceGrader.grade(worktree)`: pass ⇒ `.passed(ref, grade)`;
     fail ⇒ head = new ref, evidence = new output, discard, next round.
   - Receipt ⇒ failed round, next round.
3. After the bound: `.exhausted(lastGrade, .repairExhausted)`.

## Testing

- **Model-free tier** (fast): `RepairLoop` driven by a fake `runPhase` closure
  that applies a scripted edit, against a `packetBuilder` returning a real
  packet — proves the round/re-grade/bound/`.repairExhausted` machinery without
  a model load. `GradeResult`/`AcceptanceGrader` against a real fixture tree.
- **Fixture tier** (`--fixture`): `misleading-locus` ⇒ must edit `app.py`, not
  `templates/complaints.html`; `plausible-wrong-fix` with `AGENTTEST_REDACT=303`
  ⇒ must land 303, not 302. Both must reach 13/13 through the loop.
- **Live tier** (`just capture`, never CI): the roadmap spec end-to-end —
  implement → grade → repair → 13/13 from packets.

## Concept budget

No new terms. The design leans on the existing **role**, **handoff packet**, and
**receipt** vocabulary; `repairExhausted` names a state, not a new concept.

## Out of scope

Implement-arm tuning (closed — D2 of the consolidation); `--think-budget` /
ds4 engine work (out of scope for P12.4); bounded-thinking validation for the
repair role (deferred to P12.6 — the `AGENTTEST_REPAIR_THINK` override exists so
it needs no code change later); harvesting-from-thinking as a repair safety net
(the model never sees the failure it must react to); any `repair.py`-style
bypass of the sandbox (the point is to run repair through the vetted
bash/worktree-dispatch machinery that already exists).
