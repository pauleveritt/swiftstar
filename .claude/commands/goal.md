---
description: >
  One self-pacing iteration toward the registered measurement goal. Refuses to
  record model results from runs that measured the harness. Designed to be
  driven by /loop with no interval; safe to re-enter cold.
argument-hint: "[new goal statement — omit to continue the registered goal]"
---

# /goal — one iteration of validity-gated measurement

You are one iteration of a loop. Do ONE unit of work, write it to the ledger,
commit, and stop. The loop's memory is the ledger, not your context.

> **v2, 2026-08-26.** v1 ran six iterations and produced two real harness fixes
> — and also let a miscoded check certify a headline result that was false. The
> rules below marked **[v2]** exist because a specific thing went wrong, and
> each says which. Read them as scar tissue, not ceremony.

## The goal, and what the goal is not

The registered goal lives at the top of the ledger:
`docs/superpowers/research/goal-ledger.md`. If the ledger does not exist,
create it with the goal from `$ARGUMENTS` (or, if empty, this default):

> **Goal: ≥10 valid Mellum cells** — pipeline runs whose outcome is
> attributable to the model under every validity invariant below — spanning
> ≥2 seeds and both path styles, with the model's pass/fail recorded either way.

The goal is a count of **valid measurements, not passes**. A clean run in which
Mellum fails every test is progress. A run in which Mellum "passes" but an
invariant is violated is zero progress. The model's pass fraction among valid
cells is reported in every entry and is never the goal.

If `ROADMAP.md`'s `## Now` no longer names P16, stop and tell the human — the
loop follows the roadmap's one-direction rule; it does not pick directions.

## Validity invariants (frozen)

A cell is **valid** only if every check passes. Each is a command over the
capture, never a judgment from memory. A failed check marks the cell
`blockedBy: harness (V<n>)` and **its numbers may not appear in any model
metric.** Each invariant names the exact artifact it reads — **[v2]** because
two of five checks read an adjacent artifact and both misfired.

- **V1 — rounds are cumulative.** Read: consecutive `repair-packet-N.json`
  `taskText`, gated on `repair-round-N.json`'s receipt being `validationFailed`.
  A round that ran and wrote must not be followed by a packet showing the
  identical missing-file set.
- **V2 — the failure surface was enumerable.** Read: **the dispatched
  `repair-packet-N.json` `taskText`** — what the model was shown. Not the grade
  recorded after the round ran. No packet may contain `Interrupted:` with
  `error during collection`.
- **V3 — no directive contradicted by its own packet.** Read:
  `repair-packet-N.json` `taskText`. A packet asserting "exactly one file is
  wrong" while its own evidence lists ≥2 missing writable files is invalid.
- **V4 — graded only on what was shown.** Read: every dispatched packet vs
  `verdict.json` reasons. **Currently UNAUDITABLE** — `main.swift:716` captures
  only `phases[0]`, so phase 2/3 briefs are absent from the capture. It reports
  UNAUDITABLE, which is **not** a pass.
- **V5 — every packet was delivered.** Read: `wire.ndjson`. No `exceeds
  context`, no `turnDidNotEnd`, no repair/build turn ending `limit`/`contextFull`.

Do not widen, narrow, or reinterpret this list mid-goal. A cell that dies in a
way no invariant covers is an **escalation**, not a new rule.

### The auditor is code, and code must be proven **[v2]**

`Tools/audit-goal-invariants.py` is the sole source of ledger cell-counts.

- **Never trust a check that has never fired.** Every check carries a fixture
  in `FIXTURES`: one known-bad cell it must FAIL and one known-good it must
  PASS. `--self-test` must pass before any number it produces enters the ledger.
  v1's `check_v2` and `check_v4` had neither fixture; both were broken, and
  `check_v4` could not fire under any input.
- **UNAUDITABLE is not a pass.** A check that cannot be evaluated from the
  captures says so. Any artifact an invariant references must be captured, or
  the invariant is UNAUDITABLE.
- Changing a check to match its frozen invariant's text is a **correction**,
  not a widening — but it retroactively invalidates every number that check
  produced. Say so in the ledger and re-run.

## One iteration

Read the ledger's last entry, then do exactly one of these, in priority order:

1. **Audit** (free). Any capture the ledger has not classified. Always the
   first iteration, and always re-run after an auditor correction.
2. **Fix** (no GPU). Fix the single invariant blocking the most cells. Land it
   with a test that fails before and passes after (`swift test` ~3s; then
   `SWIFTSTAR_INTEGRATION=1 swift test` ~30s). One invariant per iteration.
3. **Confirm** (GPU, ~1–2 min). If a fix landed last iteration, run ONE
   fixture-tier repair (`--fixture …`) before spending pipeline time.
4. **Probe** (GPU, ~15 min) **[v2]**. A fresh pipeline batch run to observe
   *shape* when invariants are known to still block. **No model numbers may be
   recorded from a probe** — only structural observations (which files were
   emitted, which directive was dispatched, where it died). v1's iteration 5
   was a probe that recorded model numbers, which is how a harness artifact
   became a "result."
5. **Measure** (GPU, ~15 min). Permitted only when **every invariant predicted
   to fire on the fresh cell's path has a landed, fixture-confirmed fix.**
   "No fresh captures exist yet" does not satisfy this — v1 read the gate that
   way and burned a GPU run that was structurally incapable of producing a
   valid cell. Before running: name which invariants the new cell will traverse
   and why each is now fixed. Then audit the new captures in the same iteration
   before writing any number down. Never the full matrix from inside the loop.

Before any GPU tier, check nothing else holds the engine (`ps aux` for
`llama|agenttest|caffeinate`). If held, record `deferred: engine busy` and fall
back to audit/fix work or stop.

## The ledger entry

Append one entry per iteration, then **commit that iteration alone** — **[v2]**,
so the loop's pacing is evidenced in git rather than four iterations landing in
one commit.

```
## <n> — <date> — <audit|fix|confirm|probe|measure>
did: <one sentence>
cells: valid=<k> blocked={V1:<a>, …} unauditable={V4:<n>} of <total>
model: <passes>/<valid> among valid cells (NOT the goal)
evidence: <commands run and the output lines the numbers came from>
next: <which action next, and why>
```

Rules for those lines:

- Every number must come from a command whose output is quoted. No number from
  memory, ever.
- **The `model:` line is computed from `repair-round-N.json` grade records —
  the last graded round — never from the harness's own summary fields [v2].**
  `acceptanceExit` and `verdict.json` are computed from the pre-repair tree when
  repair exhausts (`main.swift:981–983`), so they understate what the model
  produced. This rule alone would have prevented v1's worst error.
- Omit the `model:` line entirely on audit, fix, confirm, and probe iterations.
- **If a sentence in your entry contradicts a number in it, stop and resolve it
  before committing [v2].** v1's entry 5 wrote "V2 still fires" and
  `blocked={}` in the same entry; the number was wrong and nobody noticed.
- Corrections are **append-only** — a new entry that names what it retracts.
  Never silently edit a past entry's numbers.

## Stopping

**Goal met** — the count and spread are reached AND the final batch had zero
harness-blocked cells. Write a dated verdict record in
`docs/superpowers/research/` (the P15 record is the template), update
ROADMAP.md's `## Now`, tell the human, and tell them to stop the loop.

**Escalate — stop and say plainly why** — when any of:

- An invariant blocks cells in a batch run AFTER a fix for it landed.
- Two consecutive measure iterations add zero new valid cells.
- A cell fails in a way no invariant covers. Write up what you saw; do not add
  a rule and keep going.
- **An audit check is found to disagree with its frozen invariant's text
  [v2].** This is what actually went wrong in v1 and no rule forced anyone to
  notice it.
- **A fix needs a design decision with more than one defensible answer [v2]** —
  e.g. "on repair exhaustion, should the verdict grade the best tree repair
  reached, or the tree the run delivered?" That is the human's call, not the
  loop's.
- The ledger reaches 12 entries without meeting the goal.
- A default-tier test failure survives one fix attempt.

Escalation is a normal outcome, not a failure of the loop. What is a failure of
the loop: reporting progress whose evidence would not survive re-auditing.
