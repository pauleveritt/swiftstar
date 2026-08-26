# /goal — retired 2026-08-26

There is no active `/goal` loop. **Do not restart one from this file.**

## History, for context if you land here

- **v1 + v2** (13 iterations) — pipeline-tier repair-harness validity. Closed
  without meeting its goal. Record:
  [`docs/superpowers/research/goal-ledger.md`](../../docs/superpowers/research/goal-ledger.md).
- **v3** (8 iterations) — apparatus-trustworthiness, replacing v2's goal after
  it was shown unreachable in principle. Closed the same way. Record:
  [`docs/superpowers/research/goal-ledger-v3.md`](../../docs/superpowers/research/goal-ledger-v3.md).
- **v4** (3 iterations, 0 escalations) — a pre-registered fixture-tier
  experiment. **Met its goal.** Verdict:
  [`docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md`](../../docs/superpowers/research/2026-08-26-p17-repair-limit-verdict.md).
  This is the answer to the project's original question and remains valid.
- **v5** (3 iterations, escalated) — an attempt to optimise the repair loop
  itself (make extra rounds earn their cost). **Retired, not concluded**: the
  dev screen it built could not resolve an effect from engine sampling noise at
  the sample size used, and by the time that surfaced, project direction had
  already moved past the question. Retirement record:
  [`docs/superpowers/research/superseded/goal-ledger-v5.md`](../../docs/superpowers/research/superseded/goal-ledger-v5.md)
  (see the **RETIRED** entry at the bottom). All artifacts, including the
  interventions it tried, are archived in
  [`docs/superpowers/research/superseded/`](../../docs/superpowers/research/superseded/).

**None of this is "Mellum cannot repair."** P17 measured Mellum at 15/17 on
editing tasks — a genuine, bounded-editor result. What's retired is narrower:
that the pipeline/fixture-tier apparatus built across v1–v5 could answer
follow-on questions about round budgets and feedback policy at the resolution
tried.

## Current direction

See `ROADMAP.md` `## Now`: a small, deliberately narrow one-shot benchmark
(working name `mellum-fixture`), separate from `swiftstar-agenttest`, that
answers "what can this Mellum configuration do on explicit, pinned repair
tasks" — one attempt, a flat requirement-by-requirement oracle instead of a
collection-gated pytest run, no repair rounds and no self-modifying
optimisation loop. If and when that produces a design worth iterating on
autonomously, a new `/goal` contract should be written **from scratch** against
that instrument — not by reviving this file.
