# Goal ledger v4 — P17 fixture-tier repair experiment

> **Answer the original question: is Mellum's multi-file repair failure a
> BUDGET limit, a FRAMING limit, or a DEPTH limit?**
>
> **Done when** every row of [`experiment-manifest.tsv`](experiment-manifest.tsv)
> (**24 cells** — 4 fixtures × 2 budgets × 3 seeds) has a recorded outcome,
> `harness-void` ≤ 4, and a dated verdict states the answer per arm with the
> numbers quoted.

Driven by [`.claude/commands/goal.md`](../../../.claude/commands/goal.md) v4.
Predecessors, both **closed records — no number from them enters this verdict**:
[`goal-ledger.md`](goal-ledger.md) (v1+v2, 13 iterations) and
[`goal-ledger-v3.md`](goal-ledger-v3.md) (v3, 8 iterations).

**Scope, stated up front and repeated in the verdict:** this measures repair
**in isolation from a pinned tree**, not repair in the pipeline. Pinning is what
makes the budget arm comparable at all — v2's budget comparison was worthless
because pipeline starting states were non-deterministic. The verdict must not
generalise to pipeline behaviour.

---

## 0 — 2026-08-26 — instrument (no GPU)

**did:** Built the multi-file fixture the 80-cell verdict named as the decisive
test on day one and that 21 iterations never built; generalised the fixture
runner to multi-file; pre-registered the 24-cell manifest.

**cells:** 0/24 recorded, 0 harness-void (quota 4), 0 disputed

**evidence:** baselines measured before any model touched them — the "red" for
the instrument:

```
=== plausible-wrong-fix   1 failed, 12 passed          FAILED test_post_complaint_redirects_to_complaints_board
=== depth-2               3 failed, 10 passed          FAILED test_home_html_element_declares_english_language
                                                       FAILED test_complaints_board_preserves_the_shared_layout
                                                       FAILED test_post_complaint_redirects_to_complaints_board
=== depth-3               4 failed,  9 passed          + FAILED test_complaint_model_contract_is_preserved
=== framing-2             1 error during collection    ModuleNotFoundError: No module named 'models'
```

**Design decisions, recorded because they shape every number that follows:**

- **"Depth" counts FILES THAT MUST CHANGE, not assertions.** depth-2 fails
  three assertions, not two: dropping `lang="en"` also trips
  `test_complaints_board_preserves_the_shared_layout`. Recorded rather than
  tuned away — forcing a 1:1 file:assertion mapping would have required a less
  natural defect.
- **The depth fixtures deliberately stay importable.** A defect in
  `models.complaints` aborts collection (`test_acceptance.py:26` reads it at
  module level) and *hides every other defect*. Building depth that way would
  have confounded depth with serialisation — the exact failure P16 exists to
  stop measuring.
- **framing-2 carries a stated confound.** It varies evidence-shape *and*
  defect-identity together (deleted `models.py` + an aliased import, vs
  depth-2's redirect + lang). A clean crossing was not achievable cheaply. Any
  framing claim must say this out loud.
- **24 cells, not "18–24".** Pre-registered means pinned. The framing arm gets
  its own fixture rather than displacing a depth level.

**Instrument changes:** `overlayTree` + `applyDeletions` in
`Sources/swiftstar-agenttest/main.swift` replace the hardcoded single-`app.py`
overlay (`copyItem` throws on an existing path, which is why the old tier
deleted `app.py` by hand first). A `.delete` manifest expresses defects that
consist of a file being *absent*. Single-file fixtures are unchanged — they are
the one-file case.

**next:** **run** — the depth arm at rounds=2, seeds {1,2,3}: 9 cells across
`plausible-wrong-fix`, `depth-2`, `depth-3`. Expect roughly 1–2 min/cell at
fixture tier. Row one is likely the first uncontested multi-file Mellum repair
number this project has produced.

## 1 — 2026-08-26 — run (rounds=2 half of the manifest)

**did:** Ran all 12 rounds=2 rows. **The depth arm is uninterpretable as run**,
for a reason the run itself made obvious: every multi-file fixture was
dispatched a directive asserting *"Exactly one file is wrong."*

**cells:** 12/24 recorded, 9 harness-void (quota 4 — see below), 1 disputed

**rows (raw outcomes, before reclassification):**

```
plausible-wrong-fix/2/1  pass  13/13
plausible-wrong-fix/2/2  pass  13/13
plausible-wrong-fix/2/3  pass  13/13
depth-2/2/1  fail  2 failed, 11 passed      depth-2/2/2  fail  4 failed, 9 passed
depth-2/2/3  fail  2 failed, 11 passed
depth-3/2/1  pass  13/13                    depth-3/2/2  contractNotFollowed
depth-3/2/3  pass  13/13
framing-2/2/1  fail  1 of 9 preconditions unmet.
framing-2/2/2  fail  1 of 9 preconditions unmet.
framing-2/2/3  fail  2 failed, 11 passed
```

**The anomaly that exposed it.** depth-3 is a strict superset of depth-2's
defects, yet raw depth-3 passed 2/3 while depth-2 passed 0/3. That cannot be a
depth effect. The dispatched packet says:

```
The acceptance suite failed against the code written by a prior phase. ...
Exactly one file is wrong.
```

`RepairContext.missingWritableFiles` counts files that are **absent**. The depth
fixtures' files are *present and broken*, so the count is 0 and `repairPacket`
takes its single-file branch. **The V3 fix from v2 only ever handled missing
files; broken files were never covered.**

The wire shows the model doing exactly what it was told, and the anomaly
dissolving:

```
depth-2/2/1   turn 2: headings=['app.py']   turn 4: headings=['app.py']   (twice, only app.py)
              both residual failures are the base.html defect it was never asked to fix
depth-3/2/1   turn 1: headings=['app.py', 'models.py', 'templates/base.html']  -> 13/13
```

depth-2's 0/3 measures **obedience to a false instruction**, not repair depth.
depth-3's passes measure the model *ignoring* the instruction. Neither is the
quantity this arm exists to measure.

**Reclassification, and why it is a correction rather than a re-run.** Every
row for a >1-file fixture is now `harness-void` with that cause and its raw
outcome preserved in the detail column. The three `plausible-wrong-fix` rows
**stand as recorded** — that fixture genuinely has exactly one wrong file, so
its directive was true and its **3/3 pass is a real number.** It also
reproduces P15's 4/4 baseline independently.

**On the quota:** 9 voids against a quota of 4. The quota is a **done-when
condition on the final recorded state**, and the policy table's rule for one
cause voiding ≥3 cells is exactly this situation: spend ONE iteration fixing
that cause, then re-run only the voided cells. The loop is following its own
policy, not breaching it. **No escalation.**

**Disputed (1).** `depth-3/2/2` returned `contractNotFollowed`. The model
diagnosed all three defects correctly in prose — `lang` attribute, naive
`timestamp`, `307 == 303` — then emitted numbered prose with unlabelled fences,
so nothing was harvested. Whether that is the model failing the format or the
parser being strict is genuinely ambiguous, so per the policy table it defaults
to **model** and carries `disputed`. Logged to `questions.md`.

### The claim I was about to make and did not **[v4 rule]**

I was about to report "depth-2: 0/3, depth-3: 2/3" as the first multi-file
Mellum repair numbers. They would have been the headline of this experiment and
they measure the directive, not the model — the third time in this project a
number about Mellum turned out to be a number about the harness. What stopped it
was the ordering anomaly (harder fixture passing more), not a re-reading.

**A design note I owe the record:** Fable's replan explicitly said to keep V3's
substance as a *runner assertion* — "the directive must match
`missingWritableFiles.count`, which `RepairContext` already carries". **I
dropped that when writing the v4 contract**, and this iteration is the cost.

**next:** **repair-the-apparatus** — make the repair directive's file-count
claim true for broken files, not just missing ones, and add the runner
assertion I omitted. Then re-run only the 9 voided cells.

## 2 — 2026-08-26 — repair + re-run (rounds=2, corrected directive)

**did:** Removed the false file-count claim from the repair directive, added the
runner assertion that should have been in v4 from the start, and re-ran all 12
rounds=2 cells. **Under a truthful directive the depth arm inverts completely.**

**cells:** 12/24 recorded, 1 harness-void (quota 4), 0 disputed

**rows:**

```
plausible-wrong-fix/2/1 pass 13/13   /2/2 pass 13/13   /2/3 pass 13/13
depth-2/2/1  pass 13/13   /2/2 pass 13/13   /2/3 harness-void: V5 stop_reason=limit
depth-3/2/1  pass 13/13   /2/2 pass 13/13   /2/3 pass 13/13
framing-2/2/1 fail 2 failed, 11 passed   /2/2 fail 1 of 9 preconditions unmet.
framing-2/2/3 fail 2 failed, 11 passed
```

**Depth arm, rounds=2: 1 file 3/3 · 2 files 2/3 (+1 void) · 3 files 3/3.**
Against the same fixtures under the false directive: 3/3 · 0/3 · 2-of-3-with-a-void.
**The directive was the entire depth signal.** Mellum repairs three coupled
files across three file types — Python, dataclass defaults, HTML attributes —
in a single turn, reliably, when it is not told that exactly one file is wrong.

**The fix.** `missingWritableFiles` counts files that are ABSENT, so a
present-but-broken file is invisible to it and the directive's single-file
branch fired for 0 missing / 3 broken. The claim is removed rather than
re-worded — the harness cannot know the count — and the directive now asks for
one heading-plus-block pair per file that needs changing.

**The runner assertion (Fable's, omitted by me in v4, restored here)** builds
the directive with 0, 1 and 3 missing files before any model loads and refuses
to start if the phrase appears. Proven by reintroducing the bad string:

```
swiftstar-agenttest: repair directive asserts "Exactly one file is wrong" with
0 missing writable files — the harness cannot know that.
```

**All 12 cells re-run, including the depth-1 3/3 that would have survived.**
Changing the directive changes what every cell was shown; keeping old rows
beside new ones would mix conditions inside one arm. Superseded rows are
archived in `experiment-results-superseded-directive.tsv` behind a header
saying no number in them enters the verdict.

### The framing arm is confounded more deeply than the fixture README says

Both framing-2 failures land on the same two assertions, and the arc matters:

```
round 1: exit 2  (still "1 of 9 preconditions unmet")
round 2: exit 1  FAILED test_complaint_model_contract_is_preserved
                 FAILED test_seed_complaint_count_is_preserved
```

The model **recreated the deleted `models.py`** and got it partly right —
missing the timezone-aware `timestamp` default and the 3–5 seed complaints. So
framing-2 is not "the same work presented differently": it asks the model to
**author a file from scratch whose required contents are only implied by the
suite**, where the depth fixtures ask it to **edit files it can see**. That is a
harder task of a different kind, and the README's stated confound understated
it. **A "framing is the limit" claim would be wrong.**

**And framing-2's budget expires exactly where its real work begins** — round 1
spent on the precondition, round 2 reaching the assertion surface, budget over.
That is the same pattern v2 saw in the pipeline. **Framing and budget are not
separable at rounds=2.** The rounds=5 half of the manifest is precisely the test
— and because the starting tree is pinned by a commit, it is a controlled
comparison, which v2's could never be.

### The claim I was about to make and did not **[v4 rule]**

"Depth is not the limit; framing is" — the numbers support the first half and
not the second. framing-2's 0/3 is currently indistinguishable between a framing
effect, a reconstruction-vs-editing effect, and a budget effect.

**Void:** `depth-2/2/3`, V5 `stop_reason=limit` — a runaway generation. Per the
policy table this is also a model-behaviour observation, recorded on the row.
1 of 12, inside quota.

**next:** **run** — the rounds=5 half (12 cells). It separates budget from the
other two explanations for framing-2 and tests whether depth-3's 3/3 is
budget-independent.

## 3 — 2026-08-26 — run (rounds=5) + verdict — **GOAL MET**

**did:** Ran the rounds=5 half. **Manifest complete: 24/24 recorded, 1
harness-void (quota 4), 0 disputed.** Wrote the verdict, updated ROADMAP,
opened the question queue.

**cells:** 24/24 recorded, 1 harness-void, 0 disputed — **all three done-when
conditions satisfied.**

**rows:**

```
plausible-wrong-fix/5/1 pass  /5/2 pass  /5/3 pass
depth-2/5/1 pass  /5/2 pass  /5/3 fail 2 failed, 11 passed
depth-3/5/1 pass  /5/2 fail 2 failed, 11 passed  /5/3 pass
framing-2/5/1 fail 1 of 9 preconditions unmet.
framing-2/5/2 fail 1 of 9 preconditions unmet.
framing-2/5/3 pass 13/13
```

**Pooled (both budgets):** 1 file **6/6** · 2 files **4/5** · 3 files **5/6** ·
author+edit **1/6**. Editing across depths 1→3: **15/17**.

**Budget:** editing 8/8 valid at rounds=2 vs 7/9 at rounds=5 — no effect, if
anything worse, inside noise at n=3. It mattered only where a precondition gate
had to be cleared first, and `framing-2`'s only pass shows the arc a 2-round
budget cannot express:

```
round 1 exit 2 | 1 of 9 preconditions unmet.
round 2 exit 1 | 2 failed, 11 passed
round 3 exit 0 | 13 passed          <- needed the third round
```

Its two failures never cleared the gate at all — `exit 2, 1 of 9 preconditions
unmet` on all five rounds. That is the stall the whack-a-mole brief described,
and it is specific to **authoring a deleted file**, not to depth or budget.

**Verdict:** [`2026-08-26-p17-repair-limit-verdict.md`](2026-08-26-p17-repair-limit-verdict.md).
Answer: predominantly a harness defect (the false directive); depth is not a
limit; budget has no measurable effect on editing; the residual difficulty is
authoring from an implied contract — stated with its confound rather than
claimed as "framing".

**The claim I was about to make and did not:** "budget doesn't matter." It
doesn't for editing, and it decided the single `framing-2` pass. The honest form
is conditional, and it is the form in the verdict.

**next:** **stop — goal met.** The loop ran 3 iterations, escalated zero times,
and answered the question. Remaining judgement calls are in
[`questions.md`](questions.md), answerable from kept captures at zero GPU cost.
