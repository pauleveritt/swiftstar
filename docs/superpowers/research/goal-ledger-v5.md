# Goal ledger v5 — make repair rounds earn their cost

> **Primary:** `pass@3rounds − pass@1round` on **held-out**. Baseline ≈ 0.
> **Secondary:** stall rate (emission byte-identical to the previous round's).
> Baseline: 4 of 4 P17 failures were stalls.
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
