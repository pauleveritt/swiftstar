---
description: >
  One self-pacing iteration toward the registered measurement goal. Refuses to
  record model results from runs that measured the harness. Designed to be
  driven by /loop with no interval; safe to re-enter cold.
argument-hint: "[new goal statement — omit to continue the registered goal]"
---

# /goal — one iteration of validity-gated measurement

You are one iteration of a loop. Do ONE unit of work, write it to the ledger,
and stop. The loop's memory is the ledger, not your context.

## The goal, and what the goal is not

The registered goal lives at the top of the ledger:
`docs/superpowers/research/goal-ledger.md`. If the ledger does not exist,
create it with the goal from `$ARGUMENTS` (or, if empty, this default, which is
P12.3's open arm):

> **Goal: ≥10 valid Mellum cells** — pipeline runs whose outcome is
> attributable to the model under every validity invariant below — spanning
> ≥2 seeds and both path styles, with the model's pass/fail recorded either way.

The goal is a count of **valid measurements, not passes**. A clean run in which
Mellum fails every test is progress. A run in which Mellum "passes" but an
invariant is violated is zero progress. The model's pass fraction among valid
cells is reported in every entry and is never the goal. This is the lesson paid
for twice (P15: "the old 1/4 was measuring the parser, not the model"; the
2026-08-26 overnight matrix: 0/40 measured the harness — see
`docs/superpowers/research/2026-08-26-overnight-80-cell-verdict.md`).

If ROADMAP.md's `## Now` no longer points at this goal, stop and tell the
human — the loop follows the roadmap's one-direction rule; it does not pick
directions.

## Validity invariants (frozen)

A cell counts as **valid** only if every check passes. Each check is a command
over the capture, never a judgment from memory. A failed check marks the cell
`blockedBy: harness (V<n>)` and its number may not appear in any model metric.

- **V1 — rounds are cumulative.** No repair round's packet may say
  `(file does not exist in this worktree)` for a path an earlier round of the
  same loop wrote. Check: compare each `repair-packet-N.json` evidence block
  against round N-1's emissions/mutations.
- **V2 — the failure surface was enumerable.** No round's evidence may contain
  `Interrupted:` with `error during collection` — a grader that can only name
  one error has not shown the model its task.
- **V3 — no directive contradicted by its own packet.** A packet asserting
  "Exactly one file is wrong" while its evidence lists ≥2 missing or failing
  writable files is invalid.
- **V4 — graded only on what was shown.** Every reason in `verdict.json` must
  trace to requirement text present in some packet this run dispatched (grep
  the phrase across `packet.json` / `repair-packet-*.json`). Name the packet,
  or mark V4.
- **V5 — every packet was delivered.** The wire must show no
  `exceeds context`, no `turnDidNotEnd`, and no repair/build turn ending
  `stop_reason` `limit`/`contextFull`. A packet assembled but never prefilled
  is not a measurement (cell 20260826-055741: the one packet all night that
  carried real failing assertions died at 37,180 tokens against a 32,768
  context).

Do not widen, narrow, or reinterpret this list mid-goal. A cell that dies in a
way no invariant covers is an **escalation**, not a new rule.

## One iteration

Read the ledger's last entry, then do exactly one of these, in priority order:

1. **Audit (free, no GPU).** If any captures exist that the ledger has not
   classified, run the invariant checks over them and record
   valid / blockedBy(V<n>) per cell. This is always the first iteration.
2. **Fix (no GPU).** If the latest audit shows harness-blocked cells, fix the
   single invariant that blocked the most cells. Land the change with a test
   that fails before and passes after (`swift test`, 3.3s; then
   `SWIFTSTAR_INTEGRATION=1 swift test`, ~32s, 536 tests). One invariant per
   iteration.
3. **Confirm (GPU, ~1–2 min).** If a fix landed last iteration, run ONE
   fixture-tier repair (`swiftstar-agenttest --fixture …`, 22–72s/round) to see
   the fix live before spending pipeline time.
4. **Measure (GPU, ~15 min).** Only when the latest audit shows zero
   harness-blocked cells among fresh captures: run a batch of ≤5 pipeline
   cells (~2.7 min/cell), varying seed/path style per the goal. Then audit the
   new captures in the same iteration before writing any number down. Never
   run the full matrix from inside the loop.

Before any GPU tier: check nothing else holds the engine lock (the overnight
scripts use the same lock). If held, record `measurement deferred: lock held`
and fall back to audit/fix work or stop.

## The ledger entry

Append one entry per iteration to `docs/superpowers/research/goal-ledger.md`:

```
## <n> — <date> — <audit|fix|confirm|measure>
did: <one sentence>
cells: valid=<k> blocked={V1:<a>, V2:<b>, …} of <total classified>
model: <passes>/<valid> among valid cells (NOT the goal)
evidence: <the command(s) run and the line(s) of output the numbers came from>
next: <which of the four actions the next iteration should take, and why>
```

Every number must come from a command whose output is quoted in `evidence`.
No number from memory, ever.

## Stopping

**Goal met** — the valid-cell count and spread in the goal statement are
reached AND the final batch had zero harness-blocked cells. Then: write a
dated verdict record in `docs/superpowers/research/` (the P15 record is the
template), update ROADMAP.md's `## Now`, tell the human, and tell them to stop
the /loop.

**Escalate — stop the loop and say plainly why** — when any of:

- An invariant blocks cells in a batch run AFTER a fix for that same invariant
  landed. The fix didn't fix; a human should look before more GPU is spent.
- Two consecutive measure iterations add zero new valid cells.
- A cell fails in a way no invariant covers. Write up what you saw; do not
  add a rule and keep going.
- The ledger reaches 12 entries without meeting the goal.
- A default-tier test failure survives one fix attempt.

Escalation is a normal outcome, not a failure of the loop. What is a failure
of the loop: reporting progress whose evidence would not survive the audit in
step 1.
