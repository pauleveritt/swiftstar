# Goal ledger v5 — make repair rounds earn their cost

> **Primary:** `pass@3rounds − pass@1round` on **held-out**. Baseline ≈ 0.
> **Secondary:** stall rate — a round whose *dispatched packet* is byte-identical
> to the previous round's. **Measured at rounds=5**, where the phenomenon exists:
> P17 8/26 = 31%. At rounds=3 it is 0/6. (Corrected in entry 1; the original
> "emission byte-identical / 4 of 4 failures" wording was a broken metric.)
>
> **Done when EITHER** held-out gain ≥ +0.25 with stall < 10% (it works),
> **OR** three consecutive interventions fail to move dev gain — verdict
> *"multi-round repair does not work for this model"*, and the recommendation
> is to delete the multi-round loop rather than tune it.

Driven by [`.claude/commands/goal.md`](../../../.claude/commands/goal.md) v5.
Split: [`fixture-split.tsv`](fixture-split.tsv). Predecessors, closed records:
[v1+v2](goal-ledger.md), [v3](goal-ledger-v3.md), [v4](goal-ledger-v4.md).
P17's answer: [verdict](2026-08-26-p17-repair-limit-verdict.md).

---

## 0 — 2026-08-26 — adoption (no GPU)

**did:** Fixed two live defects in the instrument this goal optimises, then
registered the split and the bounded search space.

**Plan-vs-implemented diff [v5 rule, the one v4 lacked]:**

| review item | status |
|---|---|
| separate information from capability (acceptance source in evidence) | **kept** — search-space item 2 |
| second authoring fixture pair | **modified** — deferred to the stress step, which generates adversarial fixtures on demand rather than pre-building a guess |
| stall detection | **kept** — search-space item 4, and promoted to the secondary metric |
| fix residual directive count claim | **kept** — landed below |
| resume pipeline / P16 | **dropped** — it inherits the `missingCount` defect class and its only argument is ecological validity, which is worth invoking after the fixture-tier story settles |
| Laguna contrast | **dropped for now** — only well-posed once we know the gap is capability and not information; a 6-cell rider after search-space item 2 |

**Fix 1 — the same defect in a smaller font.** `main.swift:280` asserted an
EXACT count from `missingWritableFiles`, which sees only *absent* files: 2
missing + 1 present-but-broken claimed "2 are wrong" when 3 were. Dormant in
P17 (no fixture has ≥2 missing) and live the moment pipeline work resumes.
Now a lower bound, and the runner assertion checks the new claim rather than
grepping the old string. Proven to fire:

```
swiftstar-agenttest: repair directive names a file count that is not stated as a
lower bound (3 missing) — `missingWritableFiles` cannot see a file that is
present and broken.
```

**Fix 2 — v4's `limit` contradiction.** Its policy table said a `limit` stop
counts as a model observation; its validity section said the same wire is
harness-void. The loop silently followed the second. v5 resolves it in favour
of counting: a runaway is model behaviour and, under this goal, a stall variant
— the very thing being measured.

**The split, and why `plausible-wrong-fix` is a guard not a metric:** it scored
6/6 at every budget in P17, so it can detect a regression but never an
improvement. Counting it would inflate every marginal-gain number.

**next:** **intervene** — search-space item 1, per-round sampling variation. It
attacks the byte-identical replay directly, is nearly free, and if it does not
move the needle then items 2–5 are all more expensive ways of asking the same
question.

## 0a — 2026-08-26 — amendment (no GPU, before the first intervention landed)

Two amendments to a contract written hours ago. Both are recorded here because
the contract requires a reason for any change to the search space, and because
the second is an error of mine that the loop would otherwise have paid for.

**Amendment 1 — forced. Rounds can differ only by prompt.** `PoolPrompt`
(`Sources/SwiftStarKit/PoolPrompt.swift:13`) encodes exactly
`{"t":"prompt","worker":N,"s":...}`, and the engine's `--seed` is a
process-level argv flag (`AgentCommand.swift:99`). There is no per-prompt seed,
so every round of a run re-seeds identically. **Search-space item 1, per-round
sampling variation, is not implementable** without engine or protocol work.

That gives a sharper statement of the defect than the contract opened with:
**the repair loop is a deterministic map and a stall is a fixed point of it.**
Round N+1's prompt is a function of the tree and grade after round N; if the
model's output does not change the grade, the next prompt is identical and so is
the next output — forever. The byte-identical runs in the P17 captures are not
the model grinding against a hard problem, they are `f(x) = x`.

Item 1 is therefore **repurposed as the control**: prompt variation carrying no
new information (a round marker). If variation alone lifts the metric the fix is
cheap; if it does not, the gain must come from *information*, and one cheap run
has isolated that. The policy table's row claiming non-determinism becomes "the
mechanism" under item 1 was stale on arrival and is corrected.

**Amendment 2 — my error. The threshold was unresolvable by the measurement.**
Dev is 2 fixtures × 3 seeds = **6 cells per budget**. A +0.25 marginal-gain bar
on 6 cells is a two-cell swing, well inside chance. I wrote that threshold
without checking it against the sample size, and the loop would most likely have
declared a false win at iteration 2 or 3 — the checkpoint would have caught it,
but only after burning the iterations.

Amended to **screen then confirm**: dev at n=3 is a directional screen,
promotion requires a **≥2-cell dev gain**, and the done-when threshold is
evaluated **only** on a held-out confirmation at **n=5**. This also keeps the
GPU budget honest — 15 twelve-cell screens is ~4.5 h, and confirming at n=5 only
for candidates that survive the screen stays inside the 6-hour ceiling.

**next:** unchanged — **intervene** with item 1 (now the control), once the
baseline `pass@1`/`pass@3` measurement completes.

## 1 — 2026-08-26 — baseline (dev, rounds ∈ {1,3}) — **premise corrected**

**did:** Measured `pass@1` and `pass@3` on dev — numbers that had never been
taken; P17 only ran rounds 2 and 5. Then found my stall metric was wrong, fixed
it, and the corrected figure **refutes this goal's founding claim.**

**intervention:** none — baseline.

**dev:** pass@1 **2/6** · pass@3 **3/6** · gain **+0.17** (+1 cell) · stall **0%**

```
depth-2/1   pass pass fail        depth-2/3   pass pass pass
framing-2/1 fail fail fail        framing-2/3 fail fail fail
```

### The metric was broken, and I nearly reported 0% as a finding

First version compared consecutive **wire turns**. Each round emits **two**
turns — the answer plus an `emissionFollowUp` — so it was comparing answers to
follow-ups. In `20260826-161902` turns 2 and 6 share a hash while no adjacent
pair does; the counter read 19 "transitions" across 12 cells where only 6 round
boundaries exist.

Rewritten against `repair-packet-N.json`, which maps 1:1 to rounds. **Round N+1
is a stall iff its dispatched packet is byte-identical to round N's** — the
packet is a deterministic function of the previous tree and grade, and the
engine re-seeds identically per prompt, so an identical packet *guarantees* an
identical emission. That is the fixed point, stated as something checkable.

### The correction: stalls are a LATE phenomenon, not a structural one

```
dev at rounds=3 :  0/6  = 0%
P17 at rounds=5 :  8/26 = 31%   — and every stalled round is round 3, 4 or 5
                                  depth-2/5/3 rounds 3,4,5
                                  depth-3/5/2 rounds 4,5
                                  framing-2/5/1 round 5 · framing-2/5/2 round 4
```

**No stall ever occurs at round 2.** This contract opened by asserting that the
loop feeds round N+1 the same prompt as round N and therefore "rounds cannot
differ". **That is wrong.** Rounds 1–3 genuinely differ — the model changes the
tree, the evidence changes, the prompt changes. The loop *converges*, and only
then replays. So v4's budget null was not guaranteed by construction after all;
the +1 cell from rounds 1→3 here is real (if small, and inside the ≥2-cell noise
floor I set for promotion).

**Consequences, applied rather than noted:**

1. **The problem is not "rounds cannot differ", it is "the loop converges to a
   WRONG fixed point after ~3 rounds."** Still worth attacking, and the primary
   metric is unaffected: `pass@3` is 3/6, so half the dev cells fail with three
   rounds to work in.
2. **Stall rate must be measured at rounds=5, not rounds=3** — at 3 there are no
   stalls to improve on, so the secondary metric had no headroom and would have
   read "already at target" for the rest of the run.
3. Search-space item 4 (stall detection) is now aimed at a real, quantified
   target: 31% of rounds at budget 5.

### The claim I was about to make and did not **[v5 rule]**

"Stall rate 0% — the loop already has no fixed points." That was a broken
metric measured at a budget where the phenomenon does not occur. Twice now in
this goal's short life the premise has needed correcting before any GPU was
spent on optimising against it — which is the loop working, not failing.

**next:** **intervene** with search-space item **2** (acceptance-suite source in
the evidence), not item 1. `framing-2` is 0/6 across both budgets and its
failures are provably guesses at a contract no packet contains; item 2 targets
that directly. The control (item 1) is only needed to attribute a win, so it
runs *after* a win, not before one.

## 2 — 2026-08-26 — intervene (item 2: acceptance-suite source) — **REVERTED**

**did:** Put the acceptance suite's own source in the repair evidence
(`AGENTTEST_SHOW_SPEC=1`, off by default). **The metric improved and the system
got worse.** Reverted, and the promotion rule that would have accepted it is
amended.

**intervention:** item 2 — **reverted**.

**dev:**

| | baseline | int 2 |
|---|---|---|
| `pass@1` | **2/6** | **0/5 valid (+1 void)** |
| `pass@3` | 3/6 | 3/6 |
| marginal gain | +0.17 | **+0.50** |
| `framing-2` pooled | 0/6 | 1/6 |
| stall @rounds=3 | 0% | **29%** (2/7) |

**evidence:** the spec verifiably reached the model — packets went ~10K → 19–21K
bytes and contained the exact assertion it had been guessing at:

```
contains acceptance suite: True     contains the tz assertion: True
```

### Why this is a revert despite passing the promotion bar

Marginal gain rose by +2 cells, which my own rule said to promote on. But it
rose **entirely because `pass@1` collapsed** from 2/6 to 0/6 while `pass@3`
stayed flat at 3/6. Absolute capability did not improve; one-round capability
got worse. **`pass@3 − pass@1` is trivially maximised by degrading round 1**,
and I wrote a promotion rule that rewards exactly that. Amended: promotion now
requires `pass@3` to improve by ≥2 cells *and* gain not to fall. **That is the
second metric flaw this goal has produced in two iterations** — the first was
measuring stalls at a budget where they do not occur.

### The information-starvation hypothesis is not supported

Fable's reading, and mine, was that `framing-2`'s failures were the model
guessing at a contract no packet contained. Handed that contract verbatim it
went **0/6 → 1/6** — one cell, below the noise floor — and its failures still
read `1 of 9 preconditions unmet`, meaning it never even exported a `complaints`
attribute. The tz-aware default and the seed count it previously got wrong were
never the binding constraint.

What the spec *did* change is behaviour, for the worse. With it visible the
model stopped doing targeted repair and began rewriting the whole app —
capture `165330` rounds 2 and 3 each emit **six headings and 12 fenced blocks**
(`app.py`, `models.py`, all three templates, and the test file) where the
baseline emitted one or two files. Stall rate went 0% → 29% at rounds=3: the
two long rewrites are near-identical to each other, so a 5.2K-char full rewrite
is now the fixed point instead of a targeted patch.

**Honest denominator note:** int2's `pass@1` had one `harness-void`
(`contractNotFollowed`, capture `162516`), so it is 0 of 5 valid, not 0 of 6.
Also logged: the runner classifies `contractNotFollowed` as `harness-void`,
while the v5 policy table says ambiguous attribution defaults to **model** with
a `disputed` flag. Runner and policy disagree; queued rather than silently
reconciled mid-run.

### The claim I was about to make and did not **[v5 rule]**

"Intervention 2 improved marginal gain by +0.33 — promote it." True by the rule
as written, and wrong: it would have shipped a loop that is worse at one round,
no better at three, and 29% stalled instead of 0%.

**next:** **intervene** with item **4** (stall detection), not the control. The
control tests whether prompt variation alone helps; this run just showed that
adding information *hurts* by triggering whole-app rewrites, so the promising
direction is constraining what a round may do, not enriching what it sees.
Failure count toward the negative done-when: **1 of 3.**

## 2a — 2026-08-26 — correction (no GPU) — review found a rigged next step

**did:** A light external review checked the two iterations and found the
planned next intervention would have been **uninformative by construction**.
Landed three corrections; no numbers change except a denominator, which is now
single.

**1. Intervention 4 was the wrong next step, by this loop's own iteration-1
finding.** Item 4 (stall detection) triggers when round N's tree equals round
N−1's. **Baseline stall at rounds=3 is 0/6** — entry 1's headline correction.
The dev screen runs rounds ∈ {1,3}. So screening item 4 there is *mechanically
guaranteed* to show nothing, and would have banked failure 2-of-3 toward the
negative verdict on a foregone conclusion — a rigged step toward "delete the
loop." int2's 29% does not rescue it: int2 was reverted, so the configuration
being improved is the 0%-stall baseline. The same reasoning disqualifies item 1,
the control: variation-with-no-information only matters where replays exist,
i.e. rounds ≥ 4.

**A screening pre-check is now in the contract**, because all three defects this
goal has produced are one species — *a measurement defined where it has no
headroom or no resolution*: the +0.25 bar on 6 cells (unresolvable), stall rate
at rounds=3 (phenomenon absent), gain maximisable by degrading `pass@1`. Before
any GPU, answer in the ledger: **(a)** can this intervention's mechanism fire at
the budget I am screening at? **(b)** can the promotion gate resolve the effect
size I expect?

**2. Runner and policy reconciled.** The runner called a round ending
`contractNotFollowed` a `harness-void`; the policy table says ambiguous
model-vs-harness attribution defaults to **model** with `disputed`. The runner
now follows the contract it implements. Re-classified `depth-2/1/1` in int2:

```
  was: harness-void | no graded round recorded
  now: fail         | contractNotFollowed (disputed: model per policy)
```

Denominators are single. **Nothing material moves** — int2 was 0/5-valid, is now
0/6; gain is +0.50 either way and the revert stands.

**3. Stale ledger header fixed** — it still described the broken
"emission byte-identical / 4 of 4 P17 failures were stalls" metric that entry 1
replaced. The header is what a skim reads.

**Where the loop stands, honestly.** The negative verdict is now the **modal**
outcome: `framing-2` fails `pass@3` at `1 of 9 preconditions unmet` — never
exporting a `complaints` attribute — *with the full spec in hand*. That reads as
a capability floor, not a loop defect. A ≥2-cell `pass@3` gain needs `framing-2`
to go 0/3 → 2/3, and nothing observed suggests any listed intervention does
that. The contract already declared that ending acceptable and actionable
("delete rather than tune"). **The one way to reach it dishonestly is to spend
the remaining two failure counts on interventions the screen cannot detect** —
which is exactly what the corrected plan avoids.

**next:** **intervene** with item **3** (feed forward the delta: what the
previous round changed and which tests still fail). Pre-check: **(a)** its
mechanism fires at rounds=3 — rounds genuinely differ there, so a delta exists
to feed; **(b)** it targets `framing-2`'s 0/3, the only dev headroom, so a
≥2-cell effect is resolvable. int2 failed by adding *untargeted* information
that licensed whole-app rewrites; item 3 adds *targeted* information, which is
the constraint entry 2 concluded was missing. Failure count: **1 of 3.**

## 3 — 2026-08-26 — intervene (item 3: feed-forward delta) — **NOT counted as a failure**

**did:** Fed each round what the previous round wrote and what still failed.
The mechanism landed correctly. **The result is that the dev screen cannot
resolve any intervention, and this iteration proves it with byte-identical
inputs.** Recorded as an apparatus finding, *not* as failure 2 of 3.

**intervention:** item 3 — outcome **indeterminate** (see below).

**pre-check (as the contract now requires):** (a) mechanism fires at rounds=3 —
**verified, 4/4 round-2 packets carried the block**; (b) gate resolves the
expected effect — **this is what turned out to be false.**

```
## What your previous attempt already did

You rewrote: app.py.
After applying that, these still fail:
- FAILED test_acceptance.py::test_home_html_element_declares_english_language
- FAILED test_acceptance.py::test_complaints_board_preserves_the_shared_layout
```

**dev:**

| | pass@1 | pass@3 | gain |
|---|---|---|---|
| baseline | 2/6 | 3/6 | +0.17 |
| int2 (reverted) | 0/6 | 3/6 | +0.50 |
| int3 | 0/6 | 3/6 | +0.50 |

### The finding: the screen's noise floor equals its promotion threshold

The delta block only exists from round 2, so **every rounds=1 cell should be
identical to baseline.** Their packets are:

```
depth-2   seed1  packet 3ff2f7f944d4 vs 3ff2f7f944d4  SAME   pass -> fail
depth-2   seed2  packet 3ff2f7f944d4 vs 3ff2f7f944d4  SAME   pass -> fail
depth-2   seed3  packet 3ff2f7f944d4 vs 3ff2f7f944d4  SAME   fail -> stalled-runaway
framing-2 seed1/2/3                                   SAME   fail -> fail
```

**Byte-identical prompts, same seeds, opposite outcomes.** `depth-2` at rounds=1
swung 2/3 → 0/3 on inputs that did not change by one byte. That is the engine
non-determinism documented in v3 iteration 6, now demonstrated at the *outcome*
level: **a 2-cell swing arises from noise alone, and my promotion gate is ≥2
cells.** The screen is exactly at its own noise floor and cannot distinguish a
real effect from a re-run.

So `pass@3` being flat at 3/6 across baseline, int2 and int3 licenses **no**
conclusion about item 3. Counting it as failure 2-of-3 would bank a failure on a
measurement that cannot measure — the precise dishonesty the review warned about
one iteration ago, in a new costume. **Failure count stays at 1 of 3.**

**Also reconciled:** the runner called a `limit` stop `harness-void` while the
policy table says record `stalled-runaway` and **count it as a failure**. Same
bug class as iteration 2a's `contractNotFollowed` mismatch — the runner
disagreeing with the contract it implements. Fixed; two int3 rows re-classified;
denominators are single throughout the table above.

### The claim I was about to make and did not **[v5 rule]**

"Intervention 3 failed — `pass@3` flat, failure 2 of 3." Wrong twice over: the
rounds=1 collapse it appears to have caused happened on inputs identical to
baseline, and the screen cannot resolve ±2 cells anyway.

### What this costs, and the fix I am not making unilaterally

Binary pass/fail discards almost all the signal each cell produces. `depth-2`
fails **3** assertions at baseline; a round that fixes 2 of 3 scores identically
to one that fixes 0. A graded score — failing-assertion count, or passed/13 —
would have far more resolution per cell at exactly the same GPU cost, and would
likely lift the screen above its noise floor without raising `n`.

**That changes the loop's primary metric mid-run, so it is escalated rather than
adopted quietly.** Every other correction in this ledger has been an
implementation fix; this one redefines what is being optimised.

**next:** **escalated** — the human decides between (i) regrade on a continuous
score and re-run the three existing configurations from their kept captures
where possible, (ii) raise `n` to 7+ and accept ~45 min per screen, or
(iii) take the negative verdict now on the grounds that no listed intervention
has moved `pass@3` off 3/6 in three runs. Failure count: **1 of 3.**
