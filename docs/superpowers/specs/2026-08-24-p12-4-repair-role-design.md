# SwiftStar P12.4 design: The repair role

**Date:** 2026-08-24
**Status:** accepted (brainstormed; each decision approved in-session; adversarially
reviewed by Fable —
[`2026-08-24-p12-4-repair-role-fable-review.md`](../research/2026-08-24-p12-4-repair-role-fable-review.md);
findings F1–F11 folded in).
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
  wrong. `writableFiles` in this harness is one constant shared by every phase
  packet, so the repair surface is identical to every implement phase's — no
  per-phase narrowing exists to reconcile.

  **This makes the task strictly harder than the 3/3 evidence base, and the
  plan's "repair is proven" framing does not carry over.** The recorded 3/3 ran
  with the target file supplied directly — `repair.py`'s picker (and the
  localization problem it existed to solve) was bypassed, not merely working
  correctly. Full-surface repair asks the model to localize among six files
  *and* edit correctly, which is a materially different and harder task than
  anything measured. Treat P12.4 as testing an unproven capability, not
  assembling a proven one; the fixture tier should be expected to fail on the
  first attempt rather than read as a smoke test of known-good plumbing.

- **D3 — Repair reuses `HandoffPacket`, unchanged.** No repair-specific packet
  type. The repair packet is built with `role: .repair`, `sampling: .off` by
  default (overridable via `AGENTTEST_REPAIR_THINK=1` → `.bounded` for the
  deferred bounded-thinking question), and task text composed as: pinned facts →
  repair directive (which names the failure and points at the evidence appended
  at the end, per D6) → contract (`preamble` + `sharedContext`, redacted) →
  writable note. Same `validationCommand` (`import app`), same `selfTestCommand`
  (vetted pytest), same `writableFiles`, same `redacts`. One contract, two
  consumers.

- **D4 — Two candidate rounds, then `.repairExhausted`; a receipt ends the loop
  immediately.** *The bound of 2 is a starting value, not a derived one — no
  evidence sets it. The prior repair evidence was single-shot (one round, 3/3),
  so 1 would match the evidence and 2 buys one chance to act on a re-grade,
  which is the loop's whole premise. Cheap to revisit once the fixture tier
  reports how often round 2 helps: a round-2 rescue is a signal to raise it;
  round 2 never helping is a signal to drop to 1.* Repair is bounded: up to 2
  *candidate-producing* rounds, each re-graded. A wrong fix is detected by re-grading and becomes the next round's
  evidence. A round that yields a receipt (`noChanges` / `validationFailed` /
  `budgetExceeded` / `refusedTool`) produces no new candidate and no new
  evidence, so retrying it would replay the same dispatch — it terminates the
  loop immediately with `.exhausted(lastGrade, receipt)`. After two candidate
  rounds, the loop returns `.exhausted(lastGrade, .repairExhausted)`, so the run
  records *why* it stopped rather than silently reporting the last failed grade.

- **D5 — Fresh worktree per round, branched from the failed candidate ref.** The
  authored packet is built *first* (it is worktree-independent), then round N
  prepares a disposable worktree from `head` (the failed candidate ref, then the
  prior round's candidate ref) via `WorktreeDispatcher.prepare` — which needs the
  packet's `writableFiles` to read baselines, so this order is mandatory — then
  runs the turn, runs the import check, and `finalize`s to a new candidate ref.
  Each round is a clean, reverting, re-gradable step; no reuse of the graded
  worktree (which has `test_acceptance.py` dropped into it and is not a clean
  checkout).

- **D6 — Redaction gates authored content; machine evidence is a typed, exempt,
  bounded channel.** The validator's redaction check (e.g. `AGENTTEST_REDACT=303`)
  applies to authored content — spec, facts, notes, commands, paths — *not* to
  the pytest failure output or the file contents injected at repair time. The
  failure `assert 307 == 303` legitimately states 303; it is the L1 signal, not a
  leak. Therefore: validate the authored repair packet for redaction **first**,
  then append the failure output + file contents to `taskText` at the end, under
  a "Failure evidence (machine output)" header. The boundary is typed, not
  conventional: a `MachineEvidence` value is constructible **only** from a
  `GradeResult` plus worktree file reads (never from `packetBuilder` inputs), and
  the validator runs a **non-fatal audit** over the evidence for redact-hits,
  logging (not enforcing) — so "the fixture's answer is present in the failure
  output" is always visible rather than silently exempt. Evidence is **bounded**:
  pytest output is tail-capped to the last ~8 KB (the failure summary lives at the
  end; a failure assert can embed the full HTML response body), and each file's
  content is capped at a fixed per-file byte limit; both caps are recorded in the
  round record. The "check the assembled packet" doctrine still holds for
  authored content (that is where contamination lived); machine evidence is a
  distinct category, injected post-validation.

- **D7 — Acceptance-test isolation.** `test_acceptance.py` is written into the
  worktree only at grade time, after the repair turn ends — so the model never
  sees the file or runs the suite during a turn (it is not in `writableFiles` and
  not present). The failure output injected as evidence may quote the acceptance
  test's assertion lines; that is legitimate machine evidence, not a leak — the
  suite is non-gameable (not writable, not present in the worktree). The model's
  one in-loop verification path is the writable `tests/test_app.py`: it can write
  a regression test reproducing the failure and run it via the vetted self-test
  command. Host-side re-grade remains the only authority (doctrine). Same rule as
  the implement flow today.

- **D8 — Repair runs on a fresh worker session.** Implement phases accumulate on
  worker 1 (a phase-3 run has died at `ctx_pos=23301/32768`); full-surface repair
  on that same session would near-certainly exhaust it, and the old
  "stop on `limit`/`contextFull`" guard would only record the death. So the
  harness spawns `--subagent-pool 3` and dispatches repair rounds on worker 2
  (never used by implement): repair always starts from a clean session, and the
  fixture and live tiers then share the same session regime. Repair needs nothing
  from the implement session — evidence is re-injected per round by design. One
  extra session ≈ 8 GB (128 GB dev machine; the 55 GiB deployable figure was
  computed at ctx=100k, a separate concern). Both repair rounds share worker 2
  (round 2 starts ~10–12k, fits 32k). The `limit`/`contextFull` stop remains as a
  backstop: a repair turn that ends there leaves worker 2 unusable; stop the run.

- **D9 — Placement: `RepairLoop` in SwiftStarAppKit, grading extracted.** Two new
  types, one extraction:
  - `GradeResult` (value type): `exit`, `output`, `passed`.
  - `AcceptanceGrader` (SwiftStarAppKit): the pytest run currently inline in
    `main.swift` — copy `test_acceptance.py` in, run
    `uv run --project <pyProject> pytest -q test_acceptance.py` with cwd = the
    worktree, return `GradeResult`. Shared by `main.swift` and `RepairLoop`.
  - `RepairLoop` (SwiftStarAppKit): the bounded orchestrator. Inputs: repo URL,
    failed candidate ref, failing `GradeResult`, acceptance-test source +
    pyProject, a `packetBuilder` closure, a `runPhase` closure, a capture dir.
    Returns `.passed(ref, grade, worktree)` or `.exhausted(lastGrade:
    GradeResult?, receipt: Receipt)` — where `receipt` is the terminating round's
    receipt (D4) or `.repairExhausted` after two candidate rounds.
  - `Receipt.repairExhausted` (new case in SwiftStarKit).
  Division of labor: `packetBuilder` returns the **authored** packet (`role`,
  `sampling`, facts, directive, contract, writable note, `redacts`); `RepairLoop`
  validates that packet for redaction, reads the worktree's file contents, and
  appends the bounded `MachineEvidence` to `taskText` before dispatch (D6).
  `runPhase` is the pooled orchestrator's `orch.runPhase(worker: 2, ...)`.
  `RepairLoop` owns only the round/re-grade/bound/evidence-injection logic;
  everything model- and contract-specific stays harness-owned. **Per-round
  capture:** each round writes `repair-packet-N.json` (the assembled packet,
  evidence included), its verdict/receipt, the candidate ref, the grade
  exit + digest, and timings to the capture dir; run-config gains the repair
  fields (`repairThink`, round count). `.passed` retains the passing round's
  worktree as `finalWorktree` so `main.swift`'s code dump + DeepSeek grader run
  against the repaired tree. This makes `RepairLoop` testable without a model
  load.

- **D10 — A fixture mode for deterministic verification.** `swiftstar-agenttest
  --fixture <misleading-locus|plausible-wrong-fix>` overlays `reference/*` +
  the fixture's buggy `app.py` into a fresh repo, **commits the overlay as the
  failed candidate ref** (there is no implement phase to `commitBack()`, so the
  seed commit is what seeds repair's `head`), skips the implement phases,
  grades (guaranteed 12/13), runs the *same* `RepairLoop`, and asserts 13/13.
  What each fixture measures, stated precisely: `misleading-locus` measures
  localization — the repair must edit `app.py` (the handler), not
  `templates/complaints.html` (innocent), from a failure that surfaces at
  rendering. `plausible-wrong-fix` with `AGENTTEST_REDACT=303` measures
  *evidence-following over convention-recall*: the model must land 303 (read from
  the failure evidence) rather than pattern-match "redirect" to 302 — it does
  **not** claim diagnosis-from-a-redacted-contract, because the assert itself
  states the expected value. Because repair always runs on a fresh worker (D8),
  the fixture tier's session regime matches the live path; the one residual
  divergence is that live failures can be multi-test with large output (C16 run 3:
  7 failed), where fixtures are single-test — the D6 size cap covers that. The
  live roadmap run (implement → grade → repair on failure) is the end-to-end
  13/13 gate.

## Components

**SwiftStarKit** (pure): `GradeResult`; the `MachineEvidence` value type; the
`Receipt.repairExhausted` case. No I/O, no git.

**SwiftStarAppKit** (IO/Process, no SwiftUI): `AcceptanceGrader` (the extracted
pytest run); `RepairLoop` (the bounded round/re-grade loop over
`WorktreeDispatcher.prepare`/`runValidation`/`finalize`/`discard`, driven through
the `packetBuilder`/`runPhase` closures, with per-round capture); the pool spawn
widens to `--subagent-pool 3` (worker 2 reserved for repair).

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
   - Build the authored repair packet via `packetBuilder` (worktree-independent).
   - `WorktreeDispatcher.prepare(authoredPacket, baseRef: head)` (reads
     `writableFiles` baselines from the worktree).
   - Validate the authored packet (redaction, structure); read every
     `writableFiles` entry's current content from the worktree; build the bounded
     `MachineEvidence` and append it to `taskText` (D6); write
     `repair-packet-N.json`.
   - `runPhase(packet, worktree)` on worker 2; `runValidation(import app)`;
     `finalize`.
   - Candidate → `AcceptanceGrader.grade(worktree)`: pass ⇒ `.passed(ref, grade,
     worktree)`; fail ⇒ head = new ref, evidence = new output, discard, next round.
   - Receipt ⇒ `.exhausted(lastGrade, receipt)` immediately (D4).
3. After two candidate rounds: `.exhausted(lastGrade, .repairExhausted)`.

## Testing

- **Model-free tier** (fast): `RepairLoop` driven by a fake `runPhase` closure
  that applies a scripted edit, against a `packetBuilder` returning a real
  packet — proves the round/re-grade/bound/`.repairExhausted` machinery without
  a model load. `GradeResult`/`AcceptanceGrader` against a real fixture tree.
- **Fixture tier** (`--fixture`): `misleading-locus` ⇒ must edit `app.py`, not
  `templates/complaints.html`; `plausible-wrong-fix` with `AGENTTEST_REDACT=303`
  ⇒ must land 303, not 302 (evidence-following over convention-recall — D10).
  Both must reach 13/13 through the loop. Because repair runs on a fresh worker
  (D8), this tier exercises the same session regime as live; the residual
  difference (single-test vs multi-test failure output) is noted in D10.
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
bash/worktree-dispatch machinery that already exists). **Open-loop operation is
an evidence caveat, not a settled capability:** the 3/3 repair result ran with
unsandboxed bash, so whether the model can fix without reproducing the failure
in-loop is unexamined — P12.4 measures it rather than assuming it. A vetted
repro command is deliberately not added in v1 (it would either leak the oracle
or grow new machinery); the writable self-test (D7) is the model's only in-loop
verification.

## As-built deviations (added post-implementation, post-Fable-review)

Two places where the shipped code diverges from this spec's literal text —
both ruled correct during implementation review, neither previously written
back here:

- **D3's `AGENTTEST_REPAIR_THINK` override is inert, not deferred-but-neutral.**
  This spec originally claimed the override "exists so it needs no code
  change later" (P12.6). In practice, nothing at dispatch time reads
  `packet.sampling` — thinking is set once at engine-spawn time from
  `AGENTTEST_THINK`, a property of the whole pooled engine process, not
  per-dispatch. A final-review pass found that the repair packet's `think`
  field recorded `.bounded` under `AGENTTEST_REPAIR_THINK=1` while the
  engine actually ran `--nothink` — a capture-integrity lie, not a harmless
  no-op. The fix: `repairPacket`'s `think` now mirrors `AGENTTEST_THINK`
  (the same source the engine actually reads), same as `phasePacket`; the
  harness now warns on stderr if `AGENTTEST_REPAIR_THINK` is set, since it
  has zero effect. Full per-worker think override remains P12.6 scope — it
  needs new machinery (per-worker engine control, or a second engine),
  not just a code change to an existing field.
- **Repair cannot honor `AGENTTEST_PATH_STYLE=absolute`, and D5 forecloses it
  structurally.** D5 mandates the repair packet is built *before*
  `WorktreeDispatcher.prepare`, so no worktree URL exists yet to render an
  absolute root from — `repairPacket` always renders relative paths. An
  `AGENTTEST_PATH_STYLE=absolute` live run therefore implements with
  absolute paths and repairs with relative ones: an uncontrolled variable
  flip between the two phases of the same run. Not fixed — fixing it would
  mean relaxing D5's build-before-prepare ordering, which is out of scope
  for this note. Flagged here as a known limitation: don't combine
  `AGENTTEST_PATH_STYLE=absolute` with a repair-eligible run without
  accounting for this.

Separately, a post-smoke-test Fable review found the evidence-capping
approach (D6) needed hardening before the overnight run: `cappedContent`
was head-truncation only (a file over the cap silently lost its tail, where
live defects have historically concentrated) and a `writableFiles` entry
absent from the worktree was silently omitted from evidence with no marker.
Both fixed post-smoke-test: `cappedContent` now does middle-truncation
(keep head+tail, drop the middle, cap raised 4096→16384 bytes); a missing
file gets an explicit "(file does not exist in this worktree)" marker
instead of silent omission. `cappedFailureOutput` (pytest output) is
unchanged — tail-only truncation at 8192 bytes remains correct, since the
failure summary is at the end of pytest output.

## Parked minors from the build (mirrored 2026-08-25)

These came out of P12.4's task reviews and were consciously parked as
not-load-bearing. They lived only in that build's SDD ledger under
`.superpowers/`, which is gitignored — one `git clean` from gone — so they
are mirrored here, where the area's next toucher will find them. Two were
since fixed; the rest stand.

- **Fixed since:** a `writableFiles` entry absent from the worktree was
  silently omitted from evidence (now carries an explicit marker, plus a
  distinct one for present-but-not-UTF-8 files).
- **Worth revisiting when this area is next touched:** the batch summary
  carries no repair statistics at all — no rescue rate, and `repairNote` is
  printed only for `.stopped` runs — so "how often did repair actually save a
  run" must be reconstructed from `acceptance.txt` and round records rather
  than read off the summary. Redaction-audit hits go to stderr only, never
  into `RoundRecord`, so in a capture-only review they are invisible (this
  compounds with anything that reduces what a fixture run persists).
- **Cosmetic / low-risk, recorded for completeness:** `repairPacket` and
  `phasePacket` duplicate ~25 lines of contract scaffolding that could drift
  apart silently; the discard-by-provenance block has a dead branch (both
  arms call `txn.discardFinal()`); `.exhausted(lastGrade:)`'s payload is
  discarded at its only production call site, so a later round's partial
  progress is visible only in `repair-round-N.json`; the fixture tier
  dispatches on worker 1 while the live path uses worker 2 (functionally
  equivalent, both fresh, but D8/D10's prose implies they match);
  `acceptance.txt` is overwritten on repair success, losing the pre-repair
  grade that triggered repair; `1...maxCandidateRounds` traps if ever passed
  0 (unreachable today, but it is a public parameter); `pyProject` is
  interpolated unquoted into a `bash -c` string; and `PhasePacketBuilder`'s
  actual task-text order differs from D3's literal ordering — the *spec* text
  is what is inaccurate there, not the code.
- **Two unpinned behaviors** (correct today, no test holding them): that
  round 2's `RepairContext` carries round 1's grade and ref — D4's entire
  premise, currently proven only by a call-count assertion; and that evidence
  containing a redacted string does **not** block dispatch, which is the core
  D6 exemption. A regression in the second would pass every existing test and
  then break the `plausible-wrong-fix` fixture in a confusing, indirect way.
