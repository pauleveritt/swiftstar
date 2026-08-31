# P23 — what the app's system prompt costs in thinking

**2026-08-28.** Measurement only, no production code. Task 7 of the
[P23 part-1 plan](../plans/archive/2026-08-28-p23-wire-level-control.md).

**Pre-registered scope, honoured:** this measures **think volume only**, n=1 per
arm, one task, one model, generation bounded at `-n 512`. **No task-success
claim is made or implied.**

## Why this was measured

Probe A (recorded in the [P23 research doc](./2026-08-28-p23-wire-control-research.md))
found that thinking is *prompt-induced, not flag-induced*: the same model at
`think=high` produced **zero** think output on a bare prompt and **80%** think
output when given a system prompt that explicitly demanded step-by-step
reasoning.

That raised a cheap, zero-engine-work possibility: if the app's own `-sys` text
drives think cost, trimming it is a lever that needs no wire patch at all. Part 2
should not be designed without knowing.

## The app's actual system prompt

Captured by calling the app's own code path
(`SuperpowersBootstrap.build(skillsDir:).indexPrompt + "\n\n" + DispatchPreferenceRule.text`),
with the skills dir resolving to the real default
(`~/.pi/agent/git/github.com/obra/superpowers/skills`, present on this machine —
14 skills):

| Component | Bytes | ≈ tokens |
|---|---:|---:|
| Superpowers bootstrap (skills index) | 2,390 | ~600 |
| `DispatchPreferenceRule` | 469 | ~117 |
| **Total `-sys`** | **2,861** | **~715** |

## Method

Four arms against the real engine (Laguna XS 2.1 RoutedQ3_K, pin `79b8590`,
ctx 16,384, `--think`, SSD streaming, `-n 512`). **Only the system-prompt
configuration varies.** The task is deliberately an ordinary request rather
than a reasoning puzzle, so that any thinking observed is attributable to the
prompt configuration rather than to the task:

> List three things you would check first when a Swift test fails.

## Result

| Arm | Think | Text | Think share | Wall |
|---|---:|---:|---:|---:|
| no system prompt | **0 chars / 0 ev** | 624 chars / 27 ev | 0.0% | 5 s |
| bootstrap only | **0 chars / 0 ev** | 663 chars / 27 ev | 0.0% | 5 s |
| bootstrap + dispatch rule (the app's real `-sys`) | **0 chars / 0 ev** | 591 chars / 25 ev | 0.0% | 6 s |
| the above **+ `--host-tools`** (tool schemas in the prompt) | **0 chars / 0 ev** | 735 chars / 31 ev | 0.0% | 6 s |

## Findings

1. **The app's system prompt does not induce thinking. Trimming `-sys` is not a
   think-cost lever — that possibility is closed.** The skills bootstrap, the
   dispatch-preference rule, and the tool-schema block all produce zero think
   output on an ordinary request.
2. **Probe A's 80%-think arm was driven by its system prompt's explicit demand
   for lengthy reasoning**, not by agent-style framing in general. The two
   results are consistent once that distinction is drawn, and the earlier
   research doc's phrasing ("thinking is prompt-induced") should be read
   narrowly: a prompt that *asks* for reasoning gets it; an agent prompt that
   merely describes tools and skills does not.
3. **The remaining explanation for production think cost is task complexity.**
   The 2026-08-27 capture recorded 757 think events with the same model and the
   same `-sys` — but across four turns of genuine multi-step exploration with
   118 tool calls. Think volume tracks the work, not the configuration.

## What this means for part 2

**It strengthens the case for per-turn control and removes the cheaper
alternative.** If think cost were a property of the prompt, it could be tuned
once, statically, with no wire change. It is not: it is a property of the task.
The only place to act on it is therefore *per turn* — which is exactly what
`/quick` and the `think` field on the prompt envelope are for.

It also sharpens what the think budget (shipped in part 1, task 6) is for: it
cannot reduce ordinary think cost, because ordinary turns do not think much. It
exists solely to bound the runaway case, which is how it is documented.

## Limits

n=1 per arm, one task, one model, one context size, `-n 512`. A single ordinary
request cannot rule out that some *other* class of prompt configuration induces
thinking. What it does establish is that the app's current `-sys` — the exact
bytes it ships today, with and without tool schemas — does not.
