# /goal — one iteration of a search, not a measurement

You are one iteration of a loop that **searches for a repair-loop design that
works**, keeps what beats the baseline, reverts what doesn't, and validates
against data it never tuned on. It runs to completion without stopping for the
human. Do one unit of work, write it to the ledger, commit, and continue.

> **v5, 2026-08-26.** v4 answered its question in 3 iterations with zero
> escalations, after v1–v3 spent 21 iterations answering nothing. But v4's
> success was partly the question getting easier — fixture tier removed most of
> the apparatus surface. v4's text is in git at `cb29b45`.
>
> Every previous version **measured**. This one **optimises**, because the most
> useful thing v4 found was not a fact about the model but a defect in the
> machinery, and that is something this project controls.

## What v4 found that this goal exists to fix

The repair loop feeds round N+1 **the same prompt and the same evidence** as
round N. With near-deterministic decoding the second round is a re-run of the
first. Verified in the captures — emissions byte-identical across rounds:

```
142316-framing-2   turns 4,5,6  all 35a1272040  (2522 chars each)
142723-framing-2   turns 3,4,5,6 all a2f66634d5 (2446 chars each)
141608-depth-3     turns 5,6    both 82c6d4ddc8
```

All four of v4's failures were stalls of this shape. So **"extra rounds don't
help" was guaranteed by construction, not measured** — v4's budget null is
partly an artefact, and its ledger's reading of it as task structure was wrong.
A multi-round repair loop whose rounds cannot differ is not a repair loop; it is
one attempt billed several times.

## The goal

> **Make additional repair rounds earn their cost.**
>
> **Primary — marginal round gain:** `pass@3rounds − pass@1round` on the
> **held-out** fixture set. Baseline today ≈ 0.
> **Secondary — stall rate:** fraction of rounds whose emission is byte-identical
> to the previous round's. Baseline today: 4 of 4 failures were stalls.
>
> **Done when EITHER:**
> - held-out marginal gain **≥ +0.25** with stall rate **< 10%** — the loop
>   found something that works; write the verdict; **or**
> - **three consecutive interventions fail to move dev marginal gain** — the
>   verdict is *"multi-round repair does not work for this model"*, the loop
>   says so plainly and stops.

**Both endings are results.** The negative one is worth having and cheap to
reach; if it lands, the recommendation is to delete the multi-round loop rather
than tune it. A goal only one of whose outcomes counts as success is how v3
ran 8 iterations against a target its own iteration 6 had disproved.

## The fixture split — pre-registered, and the load-bearing rule

**Dev (iterate freely):** `depth-2`, `framing-2`
**Held-out (checkpoints only, NEVER during iteration):** `depth-3`, `framing-2-edit`
**Guards (both sets, sanity only — no metric contribution):**
`plausible-wrong-fix`, `misleading-locus`

Registered in `docs/superpowers/research/fixture-split.tsv`.

The metric fixtures are the four with **headroom** — fixtures that sometimes
fail at one round. `plausible-wrong-fix` is 6/6 at every budget, so it can only
detect a regression, never an improvement; treating it as a metric fixture would
inflate every number. It is a guard.

**Touching held-out outside a checkpoint invalidates the run.** Without this the
loop will tune the prompt into the fixtures and call it progress — the failure
mode a search loop has and a measurement loop does not.

## The search space — pre-registered and bounded

An unbounded space is how v1–v3 became whack-a-mole. One intervention per
iteration, from this list. Adding to it requires saying why in the ledger.

1. **Per-round sampling variation** — a different seed each round. Attacks the
   byte-identical replay directly, and is nearly free.
2. **Include the acceptance-suite source in the evidence.** Legitimate at fixture
   tier: the grader's file *is* the spec. **0 of 91 v4 packets contained it**, so
   the model was authoring against a contract it could not read. Tests whether
   v4's "authoring limit" is really information starvation.
3. **Feed forward the delta** — what the previous round changed, and which tests
   still fail after it.
4. **Stall detection** — if round N's tree equals round N−1's, abandon and
   re-prompt with variation rather than replaying.
5. **Per-file targeting** when the failure output implicates specific files.

## One iteration

1. **intervene** — implement ONE item, run the dev set at rounds ∈ {1, 3},
   compute marginal gain and stall rate.
2. **keep or revert** — keep only if dev marginal gain beats current best by
   more than noise; otherwise revert. **Log both outcomes.** A failed
   intervention is data, not a wasted iteration.
3. **checkpoint** (every 3rd iteration) — run held-out at rounds ∈ {1, 3}. If
   dev gains do not transfer, that is **overfitting**: say so, revert to the
   last config that transferred, and note which intervention did not survive.
4. **stress** (at each checkpoint) — build one adversarial fixture aimed at the
   *current best* config, in a defect class it has not seen. If the config
   survives, it generalises; if not, that fixture joins **dev** (never held-out).
5. **verdict** — a done-when condition fired.

Before any GPU tier check nothing else holds the engine (`ps aux` for
`llama|agenttest|ds4-agent`); if held, record `deferred: engine busy`.

## Policy — the loop decides, and records

| situation | what the loop does, without asking |
|---|---|
| an intervention makes things worse | revert, log the number, move to the next item |
| a harness defect voids a cell | record `harness-void: <cause>`, continue |
| one cause voids ≥3 cells | one iteration fixing that cause, then re-run only voided cells |
| model-vs-harness attribution ambiguous | default **model**, flag `disputed` |
| **runaway generation / `limit` stop** | **record `stalled-runaway`; the cell counts as a failure, not a void** |
| run-to-run non-determinism | a measured variable; with intervention 1 it becomes the *mechanism*, not noise |

**The `limit` ruling is a correction.** v4 shipped a contradiction — its policy
table said a `limit` stop counts, its validity section said the same wire is
harness-void — and the loop silently followed the second. Resolved here in
favour of counting it: a runaway is model behaviour, and under this goal it is a
*stall variant*, which is the thing being measured.

Anything else that would once have escalated goes to
`docs/superpowers/research/questions.md` with the default taken. Captures are
kept, so an answer can flip flagged cells retroactively at zero GPU cost.

**Budgets:** 15 iterations, ~6 GPU-hours. Hitting a ceiling produces the verdict
from what completed, with `n` stated honestly.

## The ledger

`docs/superpowers/research/goal-ledger-v5.md`, one entry per iteration, commit
that iteration alone.

```
## <n> — <date> — <intervene|checkpoint|verdict>
did: <one sentence>
intervention: <which search-space item, and kept or reverted>
dev:      pass@1 <a>/<n>  pass@3 <b>/<n>  gain <+x.xx>  stall <y%>
held-out: (checkpoints only) pass@1 <a>/<n>  pass@3 <b>/<n>  gain <+x.xx>
evidence: <commands run and the output lines the numbers came from>
next: <which action, and why>
```

Rules kept because they earned their place:

- Every number comes from a command whose output is quoted. None from memory.
- **Record the claim you were about to make and did not.** Highest-yield rule in
  this file: it caught three false headlines in v3 and one in v4.
- **Digest inequality is not evidence of change**; diff the artifacts. And its
  converse, learned this session: **digest equality IS evidence of a stall** —
  check it before describing a model as "grinding".
- **Nested fixtures must respect their ordering.** `depth-3` ⊃ `depth-2`, so
  depth-3 passing *more* is impossible and means the instrument is lying. This
  is what exposed v4's directive defect. Assert it at every checkpoint.
- **[v5] At adoption, diff the plan against what was implemented** — kept /
  dropped / modified, with a reason for anything dropped. v4 silently dropped a
  recommended runner assertion and paid a full 12-cell run for it.
- Corrections are append-only: a new entry naming what it retracts.

## Stopping — the complete list

1. **Either done-when fires** → write the verdict, update ROADMAP, tell the human.
2. **A held-out regression survives one revert** — the loop can no longer tell
   improvement from overfitting.
3. **A budget ceiling is hit** → partial verdict.
4. **ROADMAP `## Now` stops naming this goal** — direction is the human's.

Nothing else stops the loop.

What is still a failure of the loop: reporting progress whose evidence would not
survive re-auditing — or reporting a dev gain as a result without a held-out
checkpoint behind it.
