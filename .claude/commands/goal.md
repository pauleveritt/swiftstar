# /goal — one iteration of validity-gated measurement

You are one iteration of a loop. Do ONE unit of work, write it to the ledger,
commit, and stop. The loop's memory is the ledger, not your context.

> **v3, 2026-08-26.** v2 ran thirteen iterations. It landed five real harness
> fixes and produced **four** valid cells against a goal of ten — and every
> batch it ran surfaced a new blocking defect, at a rate that never declined.
> Two cells failed in ways no invariant covered, and one audit check was found
> to disagree with the invariant it claimed to enforce. Rules marked **[v3]**
> exist because of a specific v2 failure and say which. Rules marked **[v2]**
> earned their place earlier and are kept. Read them as scar tissue.
>
> v2's text is in git at `070e0f4`.

## The goal, and why it changed **[v3]**

The registered goal lives at the top of the ledger:
`docs/superpowers/research/goal-ledger-v3.md`.

> **Goal: an apparatus that can attribute a failure.** Done when ONE batch of
> ≥8 Mellum cells satisfies all four:
>
> **(a)** zero cells fail in a way no invariant covers;
> **(b)** every invariant is auditable — V4 included;
> **(c)** two runs at the same seed produce byte-identical dispatched packets;
> **(d)** every check has fired on a known-bad drawn from *that* batch, not
> only a frozen fixture.

**Why this replaced "≥10 valid Mellum cells."** That count silently presumed
the invariant set was complete. It was not: two cells died in ways no invariant
covered, so the count was measuring an unknown, and one headline computed from
it had to be retracted (v2 entry 7). Counting cells through an apparatus that
keeps being wrong does not accumulate knowledge.

**P16's own done-when is unchanged** — ≥10 valid Mellum cells, spanning ≥2
seeds and both path styles. This goal is a *prerequisite stage* of it, not a
replacement. When this goal is met, the cell count resumes against an apparatus
that has passed its own audit.

If `ROADMAP.md`'s `## Now` no longer names P16, stop and tell the human — the
loop follows the roadmap's one-direction rule; it does not pick directions.

## Standing rulings **[v3]**

These were escalated in v2 and decided by the human. They are settled; do not
re-litigate them, and do not silently extend them either.

1. **Harvest.** **Prose between a heading and its fence does not beat the
   fence.** When a heading is followed by anything other than a fence, and a
   fence appears before the next allowlisted heading, the fenced block is the
   content and the commentary is not. Landed v3 iteration 2.

   **The zero-fence clause is WITHDRAWN** (v3 iteration 3). It was ruled first
   and then refuted: three of the four frozen harvest fixtures
   (`repeated.txt`, `unfenced-a.txt`, `unfenced-b.txt`) are zero-fence
   emissions carrying real code, and `unfenced-a.txt` opens `#app.py` followed
   immediately by `from fastapi import FastAPI`. "Zero fences means a plan, not
   code" is false. **Lenient harvest of an unfenced body stays.**

   Consequence to hold in view, not to fix silently: a model that emits
   headings and a *plan* under each (capture `20260826-112536`) still has its
   prose harvested as file content. Under this ruling that is the model failing
   the contract, not the harness misreading it — but the run records it as
   `validationFailed` rather than `contractNotFollowed`, which mislabels the
   failure class. Reclassifying it is measurement semantics; do not.

   **Explicitly rejected:** filtering harvested bodies by whether they parse as
   the target language. Refusing to harvest Python that does not compile would
   suppress exactly what we are trying to measure — Mellum writing broken code.
   A harvest filter that hides model errors is the same class of mistake as the
   inverted cap: the apparatus deciding what counts before the measurement
   happens.

2. **Autonomy is drawn by subject matter, not by risk.** v2's escalations were
   correct and valuable; stopping too often was never the failure mode.
   Certifying results from checks it had never proven was.

   - **The loop decides** implementation: how to fix a defect, what to test,
     how to structure a check, what to name things.
   - **The loop escalates** anything that changes *measurement semantics*:
     what counts as valid, what the model is shown, or what a number means.

   Under this rule the loop fixes a broken check itself, and still escalates a
   change to what the check is checking.

3. **Reproducibility is a defect, not a fact of life.** A fixed seed that does
   not produce a fixed prompt is a broken control. See V7.

## Validity invariants (frozen for this goal)

A cell is **valid** only if every check passes. Each is a command over the
capture, never a judgment from memory. A failed check marks the cell
`blockedBy: harness (V<n>)` and **its numbers may not appear in any model
metric.** Each invariant names the exact artifact it reads — **[v2]** because
two of five checks read an adjacent artifact and both misfired.

- **V1 — rounds are cumulative.** Read: consecutive `repair-packet-N.json`
  `taskText`, gated on `repair-round-N.json`'s receipt being `validationFailed`.
  A round that ran **and wrote** must not be followed by a packet showing the
  identical missing-file set.
  **[v3] The check must establish that the round WROTE the missing file, not
  merely that it ran.** v2's check gated only on the receipt, so a round that
  ran and legitimately did not emit the missing file was reported as a
  discarded write. That false positive is the named reason this rule exists;
  any V1 count produced by the old check on a multi-round capture is void.
- **V2 — the failure surface was enumerable.** Read: **the dispatched
  `repair-packet-N.json` `taskText`** — what the model was shown. Not the grade
  recorded after the round ran. No packet may contain `Interrupted:` with
  `error during collection`.
- **V3 — no directive contradicted by its own packet.** Read:
  `repair-packet-N.json` `taskText`. A packet asserting "exactly one file is
  wrong" while its own evidence lists ≥2 missing writable files is invalid.
- **V4 — graded only on what was shown.** Read: every dispatched packet vs
  `verdict.json` reasons. **Was UNAUDITABLE through all of v2** —
  `main.swift:716` captures only `phases[0]`. **[v3] Making V4 auditable is
  done-when (b) and is in scope for this goal.** Until it is, it reports
  UNAUDITABLE, which is **not** a pass.
- **V5 — every packet was delivered.** Read: `wire.ndjson`. No `exceeds
  context`, no `turnDidNotEnd`, no repair/build turn ending `limit`/`contextFull`.
  **[v3] Note the open question, do not resolve it silently:** v2 confirmed the
  `exceeds context` clause fixed, then blocked a cell on the `limit` clause —
  a runaway 8192-token generation with two-thirds of the context unused. Whether
  that is a harness bound or a model property is a measurement-semantics
  question and therefore escalates.
- **V6 — no file content was harvested in place of code the model fenced.
  [v3, amended iteration 3]** Read: `wire.ndjson` turn text plus the resulting
  packet evidence. No heading may have had a fenced block discarded in favour
  of commentary. In capture `20260826-104811` all six headings went that way —
  the model emitted correct fenced code six times, the harness kept its prose
  and skipped the fences, `app.py` became English, and every later round
  repaired the model's own commentary.
  **The original zero-fence clause is withdrawn** — see standing ruling 1. It
  would have marked P15's correct zero-fence harvests invalid, and the check
  could not tell commentary from code.
- **V7 — the run was reproducible. [v3]** Read: dispatched packets of two runs
  at the same seed. They must be byte-identical. v2's packets embedded the
  per-round temp-worktree UUID inside tracebacks, so a fixed seed produced a
  different prompt and a different outcome — one batch pair diverged into
  "repaired" vs "failed" on identical config. This also defeats prompt-prefix
  caching and injects an absolute host path into runs whose purpose is a
  relative-vs-absolute arm.

A cell that dies in a way no invariant covers is an **escalation**, not a new
rule. Under this goal it is also a direct failure of done-when (a).

### The auditor is code, and code must be proven **[v2, strengthened v3]**

`Tools/audit-goal-invariants.py` is the sole source of ledger cell-counts.

- **Never trust a check that has never fired.** Every check carries a fixture
  in `FIXTURES`: one known-bad it must FAIL and one known-good it must PASS.
  `--self-test` must pass before any number it produces enters the ledger.
- **[v3] A frozen fixture is necessary and not sufficient — done-when (d).**
  `check_v1` passed its frozen fixtures for the whole of v2 and was still
  wrong, because the fixture was a 2-round capture and the defect only appears
  at round 3+. Every check must also fire on a known-bad drawn from the
  **current** batch. A check with no current-batch known-bad is reported as
  unexercised, not as passing.
- **UNAUDITABLE is not a pass.** Any artifact an invariant references must be
  captured, or the invariant is UNAUDITABLE.
- **[v3] Digest inequality is not evidence of change.** Two receipts differing
  only by an ephemeral path are the same result. Before concluding "the tree
  changed," diff the artifacts.
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
   **[v3] If the test passes on arrival, say so and call it a regression guard
   — not a red-then-green proof.** v2 shipped one of each and the distinction
   matters when the ledger is read back.
3. **Confirm** (GPU, ~1–2 min). If a fix landed last iteration, run ONE
   fixture-tier repair (`--fixture …`) before spending pipeline time.
4. **Probe** (GPU, ~15 min) **[v2]**. A fresh pipeline batch to observe *shape*
   when invariants are known to still block. **No model numbers may be recorded
   from a probe** — only structural observations.
5. **Measure** (GPU, ~15–45 min). Permitted only when **every invariant
   predicted to fire on the fresh cell's path has a landed, fixture-confirmed
   fix.** "No fresh captures exist yet" does not satisfy this. Before running:
   name which invariants the new cell will traverse and why each is now fixed.
   Then audit the new captures in the same iteration before writing any number
   down. Never the full matrix from inside the loop.

**[v3] Budget note.** Rounds are cumulative since v2's V1 fix, so a bad round's
damage persists into every later round. A larger round budget may therefore
compound damage rather than allow recovery. v2 could not test this because V7
was broken. Once V7 holds, this is worth one controlled experiment — and
changing the budget is an implementation choice the loop may make, while
*interpreting* a budget-driven difference as a model result is measurement
semantics and escalates.

Before any GPU tier, check nothing else holds the engine (`ps aux` for
`llama|agenttest|caffeinate`). If held, record `deferred: engine busy` and fall
back to audit/fix work or stop.

## The ledger entry

Append one entry per iteration, then **commit that iteration alone** — **[v2]**,
so the loop's pacing is evidenced in git.

```
## <n> — <date> — <audit|fix|confirm|probe|measure>
did: <one sentence>
cells: valid=<k> blocked={V1:<a>, …} unauditable={V4:<n>} of <total>
done-when: a=<y/n> b=<y/n> c=<y/n> d=<y/n>
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
  produced.
- Omit the `model:` line entirely on audit, fix, confirm, and probe iterations,
  and whenever no acceptance round ran.
- **[v3] The `done-when:` line is mandatory on every entry.** v2's goal was a
  single number and drifted out of view for iterations at a time.
- **If a sentence in your entry contradicts a number in it, stop and resolve it
  before committing [v2].**
- **[v3] Record the claim you were about to make and did not.** v2's most
  useful ledger lines were the near-misses — a headline about "the first
  assertion-bearing packet" that a scan of all 146 packets refuted, and a
  "the tree changed each round" inference that a one-line diff killed. Both
  would have entered the record as facts.
- Corrections are **append-only** — a new entry that names what it retracts.

## Stopping

**Goal met** — all four done-when clauses hold in a single batch. Write a dated
verdict record in `docs/superpowers/research/`, update ROADMAP.md's `## Now` to
resume P16's cell count, tell the human, and tell them to stop the loop.

**Escalate — stop and say plainly why** — when any of:

- An invariant blocks cells in a batch run AFTER a fix for it landed.
- Two consecutive measure iterations add zero new valid cells.
- A cell fails in a way no invariant covers.
- **An audit check is found to disagree with its frozen invariant's text [v2].**
- **A decision touches measurement semantics [v3]** — what counts as valid,
  what the model is shown, or what a number means. Implementation decisions do
  not escalate; make them and record the alternative you rejected.
- The ledger reaches 12 entries without meeting the goal.
- A default-tier test failure survives one fix attempt.

Escalation is a normal outcome, not a failure of the loop. What is a failure of
the loop: reporting progress whose evidence would not survive re-auditing.
