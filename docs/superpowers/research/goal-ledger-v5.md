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
