# P12 — reliable agency: verdict record

*Written 2026-08-25, closing P12 at a waypoint. Covers the phase as it actually
ran: P12.0 through P12.8, across branches `p11-subagent-pool` (merged to `main`)
and the P12.8 work at `6ac5df7`..`cca02f2`. This record exists because every
other closed phase has one and P12 did not — a gap found by the same
2026-08-25 audit that found two false completion claims in the roadmap.*

***Revised 2026-08-25, same day, after P12.5 landed live.*** *The waypoint
verdict below named P12.5 as the reopen condition. It ran the same night, in
an autonomous session, with design and code both reviewed by Opus before
being trusted (see
[`2026-08-25-p12-5-model-authored-packets-design.md`](../specs/2026-08-25-p12-5-model-authored-packets-design.md)
for the full design, review, and result). The Verdict, Measured, What
shipped/did not, and Done-when sections below are updated in place rather
than left to visibly contradict this note — the original waypoint framing is
preserved in git history, not silently erased.*

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

**Reopen condition met the same day: all three roles have now run.**

The host-owned structure is real and works: typed packets, bounded tools,
worktree isolation, real validation, and recovery at both the acceptance
boundary (P12.4) and the phase boundary (P12.8). The **implement** and
**repair** roles ran against real grading, and — as of a same-day autonomous
follow-up session — so has **decompose**: a model-authored packet set
(`captures/agenttest/20260825-224119-roadmap`) matched a hand-authored
baseline's phase count, orphaned nothing from the spec, passed validation,
and drove the run to the same final result (a passing acceptance run).

So the phase's central structural claim — that a host can own the scaffolding
well enough for one small local model to fill three roles — is now
**evidenced for all three roles, each at small n.** This is not a reliability
claim (see Measured below — every figure in this record carries n=1 to n=9);
it is the structural claim the phase was chartered to test, and that claim now
has one real instance of each role rather than two.

**Reopen condition was P12.5; it is met.** The original waypoint verdict
(below, in spirit) named P12.5 as the condition — same pattern as P13's
verdict naming the condition that became P15. Unlike P15, this didn't need a
new sub-phase: P12.5 ran to a result the same day, in an autonomous session,
its design and code reviewed by Opus at each checkpoint before being trusted.

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
| Decompose role, structural | **1/1** — phase count matched baseline, nothing orphaned, every packet validated | `captures/agenttest/20260825-224119-roadmap` vs `-223848-roadmap` baseline |
| Build arm + real repair, live, non-fixture, unseeded | **2/2** — 12/13→13/13 and 11/13→13/13, each in one repair round | `20260825-224119-roadmap` (see P12.5 design doc's "Result"); `20260825-225503-roadmap-user-story` (hard spec, host decompose, `AGENTTEST_TEXT_CONTRACT=1`) |

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
- **P12.5** — the decompose role: a model-authored packet, built and
  dispatched on its own pool worker, exempt from `HandoffPacketValidator` by
  construction (it makes no mutations), with a one-shot emission follow-up
  for the reason-then-stop failure mode P15 already had to solve once. Live
  at n=1: matched a hand-authored baseline's phase count and drove the run to
  the same final result. See the design doc's "Result" section for the full
  accounting, including what it does *not* establish (acceptance
  equivalence, at n=1).

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
- **P12.4's live end-to-end tier still hasn't run at any real n.** The
  overnight n=15–20/arm validation was started and stopped early by explicit
  decision. A real (non-fixture) implement failure feeding real repair
  through to 13/13 **has now been observed twice** — both live, both
  unseeded, both byproducts of other work rather than a dedicated batch:
  once inside the P12.5 model-decompose comparison (`20260825-224119-
  roadmap`, easy spec, 12/13→13/13) and once during a P12.8 confirmation
  attempt (`20260825-225503-roadmap-user-story`, hard spec, host decompose,
  text-contract on, 11/13→13/13). That is n=2, not a rate — two different
  configs, two different failure contents, both repaired in one round. The
  planned n=15–20/arm run is still not done.
- **P12.7: 2 of 5 pieces shipped the same night** (trace-channel capture,
  Σprompt/Σcached/Σsuffix — live-confirmed, `captures/agenttest/20260825-
  232102-roadmap`: 38014/33828/4186, a real nonzero split). Still missing:
  `DumbImplementer`, stateful tokens (deliberately deferred — no single
  "final ctx_used" obviously exists across a pooled multi-worker run),
  warm-started timing, the `docs/cool_things/` write-up, and the redone
  Claude Code L3 comparison.
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
| P12.4 | Partial — fixture tier fully met; the "three phases, 13/13, from packets" line has now been exercised end-to-end with a real implement failure feeding repair **twice** (2026-08-25, live, unseeded, n=2), as byproducts of other work rather than a dedicated validation batch. Still no rate. |
| P12.5 | **Yes**, on the structural disjunct (2026-08-25, live, n=1). Acceptance-equivalence deliberately left uncharacterized — see the design doc's "Result." |
| P12.6 | Second disjunct only. No run has shown a role completing *with* bounded thinking; every self-describing capture records `think=nothink`. |
| P12.7 | Partial — pieces 1-2 of 5 shipped and live-confirmed (2026-08-25); `DumbImplementer`, stateful tokens, warm-started timing, and the write-up remain. |
| P12.8 | Deterministic tier yes; live confirmation no. |

## Known limitations — carried forward, not fixed here

All are filed in ROADMAP's Backlog as of `e0f892c`; listed here so this record
stands alone:

- ~~`RepairLoop` exits on every receipt, including `validationFailed` — no
  second attempt with a new traceback.~~ **FIXED (2026-08-25, `953d05a`)** —
  `validationFailed` now retries with fresh evidence, within the existing
  round budget; every other receipt still exits immediately by design. P12.8's
  own live phase-boundary confirmation is a separate, still-open item: three
  live attempts the same night (`captures/agenttest/20260825-214309-`,
  `-215349-`, `-220104-roadmap-user-story`) all passed 13/13 clean on the
  first try, so phase-level repair specifically has not fired again since
  the one failed attempt recorded in the "Now" section — not because the fix
  doesn't work, but because no phase has failed validation in any attempt
  since.
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

**A structural phase that delivered its structure, and — as of the same-day
P12.5 follow-up — has now exercised every role it was chartered to test.**
The host-side machinery P12 set out to build exists, is tested at the unit
and fixture level, is in use, and has now run all three roles (decompose,
implement, repair) at least once against real grading with no fallback path
papering over a failure. What P12 still does not have is the live,
end-to-end, *repeated* measurement that would let anyone state a reliability
figure for the assembled pipeline — every number in this record is n=1 to
n=9, and P12.5's own acceptance-equivalence question is explicitly left
uncharacterized rather than answered on one pair.

The honest summary for a future reader: **trust P12's mechanisms, not P12's
numbers — and now trust that all three mechanisms have actually been used,
not just two of three.** The mechanisms are reviewed and tested. The numbers
are small-n, and the phase's own strongest finding is that tuning did not
move them.
