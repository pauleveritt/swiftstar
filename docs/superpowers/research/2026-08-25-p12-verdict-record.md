# P12 — reliable agency: verdict record

*Written 2026-08-25, closing P12 at a waypoint. Covers the phase as it actually
ran: P12.0 through P12.8, across branches `p11-subagent-pool` (merged to `main`)
and the P12.8 work at `6ac5df7`..`cca02f2`. This record exists because every
other closed phase has one and P12 did not — a gap found by the same
2026-08-25 audit that found two false completion claims in the roadmap.*

## The question P12 asked

Reframed 2026-08-24 from "More models" after an overnight investigation found
the blocker was model *agency*, not model *variety*: a local model that
demonstrably writes correct code still fails to reliably **act**, and most of
those failures traced to host-side contract or prompt shape rather than to the
model. The phase's charter:

> One model, **three roles** — decompose, implement, repair — with the host
> owning phase boundaries, budgets, permissions, validation, and recovery, and
> the model supplying judgment and code. Success measured by files written and
> a passing acceptance suite; never by tool calls, never by a model's own
> report.

## Verdict

**Closed at a waypoint, not complete. Two of the three roles were tested.**

The host-owned structure is real and works: typed packets, bounded tools,
worktree isolation, real validation, and recovery at both the acceptance
boundary (P12.4) and the phase boundary (P12.8). The **implement** and
**repair** roles ran against real grading. The **decompose** role never ran at
all — `PacketRole.decompose` remains an unexercised enum case, and the
`decompose` function in the harness is a host-side string splitter over `##
Phase` headers, not a model role. P12.5, the sub-phase that would have tested
it, has no commits and no captures.

So the phase's central structural claim — that a host can own the scaffolding
well enough for one small local model to fill three roles — is **two-thirds
evidenced and one-third untested**, and the untested third is the one the plan
itself called "the one untested link."

**Reopen condition: P12.5.** Same pattern as P13's verdict naming the condition
that became P15.

## Measured

Numbers here are quoted with their sample size attached, per this project's own
rule. None is a reliability figure.

| Result | Value | Source |
|---|---|---|
| Build arm, end-to-end, hard spec | **3/9** (3/6 among runs surviving `budgetExceeded`) | C15–C18, three identical-config batches |
| Repair, fixture tier | **3/3 × 2 fixtures**, all round-1 passes | P12.4 smoke, 2026-08-25 |
| Repair, P15 text-contract arm | **4/4 at 13/13** | P15 verdict record |
| Build arm, P15 text-contract | 3/9 at 13/13 with 0 tool calls | P15 verdict record |
| Basic spec (`roadmap`), single run | 13/13, 20 tool calls, 95s | `captures/agenttest/20260825-073352-roadmap` |
| Hard spec, single confirmation run | 13/13 on first grade, repair never fired | `captures/agenttest/20260825-072342-roadmap-user-story` |

**The headline, so nobody re-derives it:** tuning the implement arm across three
identical-config batches advanced mechanism understanding substantially and the
pass rate not at all. That is the finding that should govern how much further
tuning is worth.

What the batch-to-batch spread actually looks like on an unchanged config:
0/2 → 2/2 → 1/2. Any single batch quoted alone misleads, in either direction.

## What shipped

- **P12.1** — validator/parser hardening (packet schema version, `maxTokens`,
  required `validationCommand`, CRLF normalization, `|` block scalars, trailing
  comments, plus four follow-up fixes: under-indent rejection, apostrophe
  handling, chomping-indicator rejection, non-canonical version literals).
  `thinkBudget` and path presentation wired as real levers.
- **P12.2** — Mellum loadable: submodule pinned to the merged
  mellum-think-budget line; `VariantGate`/`VariantVerifier`; admission
  contract enforced before any engine work.
- **P12.3 (Laguna arm)** — prompt-shape ablation at n=3 against real grading.
  Absolute path presentation is a real lever; a pinned working-directory fact
  removed a specific reasoning loop.
- **P12.4** — the repair role: `RepairLoop`, `AcceptanceGrader`,
  `MachineEvidence`, `Receipt.repairExhausted`, `--fixture` mode. Fixture tier
  verified against the real model.
- **P12.6 (second disjunct)** — the next failure mode named and classified:
  *completes-and-is-wrong* (up to 7 assertion failures with clean imports),
  not the predicted shallow exploration.
- **P12.8** — phase-level recovery: `commitForRepair`, `adoptRepairedPhase`,
  `PhaseRepair`, build-loop wiring. Deterministic tier green.

## What did not ship, stated plainly

- **P12.0's source-of-truth document was never written**, and no superseded-doc
  banners were ever applied. `2026-08-24-overnight-consolidation.md` still
  stands as self-described unmerged staging. Partially remedied on the same day
  as this record — see `2026-08-25-local-model-agency.md`, which is a
  reduced-scope index, not the full merge P12.0 specified.
- **P12.3's Mellum arm never ran**, and the Mellum revision re-run under the
  absolute-path shape never happened. The corpus still carries a
  "Mellum cannot revise" claim that the phase marked *at risk* and never
  resolved. P13's Mellum data cannot substitute: 0 tool calls in every cell
  means nothing was written, so nothing was graded.
- **P12.4's live end-to-end tier never ran.** The overnight n=15–20/arm
  validation was started and stopped early by explicit decision. Repair
  evidence is fixture-tier only; a real implement failure feeding real repair
  through to 13/13 has not been observed.
- **P12.5 never ran at all.** See Verdict.
- **P12.7 shipped plan text only** — no `DumbImplementer`, no trace-channel
  capture, no Σprompt/Σcached/Σsuffix metrics, no warm-started timing, no
  `docs/cool_things/` write-up.
- **P12.8's live confirmation was attempted and not achieved.** See below.

## The P12.8 confirmation attempt

One live attempt, `captures/agenttest/20260825-203706-roadmap-user-story`:
phase 1 failed its import check with
`StaticFiles.__init__() got an unexpected keyword argument`, the repair
attempt returned `validationFailed`, and the run never reached acceptance.

Two things worth separating:

1. **The single repair round is by design, not a malfunction.** `RepairLoop`
   returns `.exhausted` on *any* receipt (D4) — the receipt path discards the
   worktree and never advances `head`/`lastGrade`, so a retry would replay a
   byte-identical dispatch. That reasoning is sound as originally written. It
   is a limitation to be lifted, not a bug that misfired.
2. **The triggering defect is exactly the class repair exists for** — a
   one-line content error with a clean traceback, the same class P15 measured
   repair fixing 4/4. That the wiring fired and reached repair at all is the
   part P12.8 proved; that repair then produced a still-broken candidate and
   got no second look at the *new* traceback is the part that is now filed.

Lifting the receipt-exit limitation is cheaper than when first recorded:
`ValidationResult` already carries `output` (`05a4fcc`), so threading it into
`lastGrade` at the `finalize` call site is local to `RepairLoop`.

## Corrections folded in

- An earlier ROADMAP entry credited P12.0 with consolidating three overlapping
  research records into one source of truth, and P12.7 with correcting the
  metrics the measurement gate reports against. **Both claims were false** and
  were corrected 2026-08-25 (`e0f892c`).
- The P12 plan header, dated "2026-08-24 evening" and never revised, asserted
  four things that had since become false (status, validator hardening owed,
  repair never run in-harness, import gate never fired live). Corrected
  (`ae1453d`).
- P12.6 was initially scored NOT STARTED by the audit on the grounds that no
  commits reference it. Its done-when is a *disjunction* that never required
  commits, and the second branch was met. Corrected before this record was
  written.
- A claimed `TurnOutcomeBuilder.generated` accumulation bug — asserted in
  P12.7's plan, in commit `1400171`'s message, and in a session's analysis —
  **was retracted** after checking the wire and the engine source: `.ready`
  fires once per turn, not per tool round, and a later `ready` repeats the
  value for reconnect recovery, so accumulating would double-count. The code
  was correct. Recorded rather than deleted.

## Done-when audit

P12's own criteria, honestly scored:

| Sub-phase | Done-when met? |
|---|---|
| P12.0 | No — source-of-truth doc absent; banners absent. Only the per-capture `run-config.json` clause was met. Partially remedied 2026-08-25. |
| P12.1 | Partially. Hardening landed. But sampling remains *descriptive* (env → packet), not *prescriptive* (packet → engine); the harness's own comment documents this. Path presentation is wired. |
| P12.2 | Yes. |
| P12.3 | Half — Laguna arm only. |
| P12.4 | No — fixture tier only; the "three phases, 13/13, from packets" line was never exercised end-to-end with a real implement failure feeding repair. |
| P12.5 | Not started. |
| P12.6 | Second disjunct only. No run has shown a role completing *with* bounded thinking; every self-describing capture records `think=nothink`. |
| P12.7 | Not started (plan text only). |
| P12.8 | Deterministic tier yes; live confirmation no. |

## Known limitations — carried forward, not fixed here

All are filed in ROADMAP's Backlog as of `e0f892c`; listed here so this record
stands alone:

- `RepairLoop` exits on every receipt, including `validationFailed` — no second
  attempt with a new traceback. Now observed live.
- Worker-2 session-context ceiling across multiple phase repairs (D8 sized it
  for two rounds of one repair; P12.8 allows up to three repairs per run).
- `AGENTTEST_REPAIR_THINK` is inert; bounded thinking for the repair role is
  unvalidated.
- Repair cannot honor `AGENTTEST_PATH_STYLE=absolute` — D5's build-before-
  prepare ordering forecloses it, so an absolute-path run flips presentation
  mid-run in the arm where presentation is a known lever.
- Two P15 harvest limitations (repeated-heading abort can drop a late file;
  first-occurrence-wins discards a self-corrected re-emission).
- P12.4's parked minors M1–M12 and two unpinned behaviors, mirrored into that
  phase's design doc out of gitignored scratch.

## Repo-state footnote: the second P12.4 implementation

Branch `p12-4-repair-role` (worktree `.worktrees/p12-4-repair-role`, 9 commits,
**unmerged and deliberately kept**) is a second, independently-built
implementation of the same P12.4 plan. It was discovered mid-build: two agents
had implemented the same design in parallel, unaware of each other. It branched
*before* the design's second review round landed, so it does not carry those
three findings — but it independently arrived at a better evidence-capping
approach (middle-truncation, 16 KB cap), which the merged line then adopted
after a Fable review flagged the same gap.

Kept, not merged or deleted, by explicit decision. Recorded here because an
unexplained 9-commit branch is exactly the kind of thing a future reader
would waste time reconstructing.

## Result class

**A structural phase that delivered its structure and under-delivered its
evidence.** The host-side machinery P12 set out to build exists, is tested at
the unit and fixture level, and is in use. What P12 does not have is the live,
end-to-end, repeated measurement that would let anyone state a reliability
figure for the assembled pipeline — and it closed with its own central role
untested.

The honest summary for a future reader: **trust P12's mechanisms, not P12's
numbers.** The mechanisms are reviewed and tested. The numbers are small-n,
and the phase's own strongest finding is that tuning did not move them.
