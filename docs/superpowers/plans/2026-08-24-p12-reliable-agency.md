# P12 — Reliable agency

**Status:** planned, not started. Written 2026-08-24, replacing the earlier
"P12 — More models" framing.

**Direction.** One model, three roles, host-owned structure. The host owns phase
boundaries, budgets, permissions, validation, and recovery; the model supplies
judgment and code. Success is measured by **files written and a passing
acceptance suite** — never by tool calls, and never by a model's own report.

## Why the phase changed

P12 was "Laguna XS 2.1 and/or Mellum 2.1 as first-class variants." An overnight
investigation across three parallel sessions
([consolidation](../research/2026-08-24-overnight-consolidation.md), Sections
A–D) established that variety is not the blocker. The blocker is that a local
model which demonstrably writes correct code still fails to reliably *act*, and
most of those failures traced to host-side contract or prompt shape rather than
to the model:

- A decomposition inventing a file outside the writable grant; six writes burned
  on absolute paths; ~31k reasoning tokens spent deriving an unstated data-model
  contract. All contract defects, all now mechanically preventable.
- "Model scored zero tool calls" turned out to describe a *prompt shape*, not a
  model — swapping relative deliverable paths for absolute ones took Mellum from
  0 calls to 4-of-4 files in a clean one-variable ablation (B8).
- An experiment cell that claimed to withhold a bug's fix while shipping it
  verbatim in its own spec context — an invalid measurement nobody caught by
  reading.

Adding a second variant to a harness with those properties would produce more
uninterpretable results, faster. **P13 inherits the variant work**, once there
is something that can evaluate a variant.

## What is already true (do not re-derive)

- **The deployable configuration exists and is replicated.** Laguna S Q2_K at
  49.59 GiB planned — inside the 55 GiB target natively, no SSD streaming and
  none of its ~42–48% penalty — completes the full three-phase hard spec 13/13
  with thinking disabled, replicated 3–4×. Q4_K_M does not fit (68.21 GiB).
- **Repair works.** Given a real pytest failure and a broken file, correct
  minimal fixes 3/3, verified 13/13 against the real suite.
- **The typed packet contract is built and landed** (`6b68619`): facts,
  redaction gate, role/sampling, frontmatter parser, validator, and pre-dispatch
  validation in the agenttest harness.
- **`--think-budget` is built** (ds4 `1f9a4c5`, branch `laguna-think-budget`):
  a per-round thinking ceiling with forced `</think>`. Unwired, unvalidated.

## Concept budget

Three new terms, each earning its place by naming something the design needs:

- **role** — decompose / implement / repair. Roles differ by *bounding policy*
  (how much deliberation is useful, how expensive failure is), not by persona
  text. This is what makes per-role sampling meaningful rather than prompt
  decoration.
- **think budget** — a per-assistant-round ceiling on reasoning tokens, distinct
  from the round's total generation cap. Needed because `--nothink` and
  unbounded thinking are the only two settings that exist today, and neither is
  right for every role.
- **path presentation** — how a packet renders its manifest in task text,
  separate from the grant it authorizes. Needed because these were conflated,
  and the conflation hid a variable that flips agency (B8/D6).

`handoff packet` and `candidate ref` are already defined (P10). **`variant`
remains a seed term and moves to P13** with the work that needs it.

## Sequence

Ordered so each step's failure is cheap and diagnostic. Steps marked *(no model
runs)* cost nothing but time.

### P12.0 — Consolidation gate *(no model runs)*

Nothing below is trustworthy until this lands.

1. Write `docs/superpowers/research/2026-08-24-local-model-agency.md` — the
   single source of truth: what each model can and cannot do as *measured*, the
   deployable configuration, the architecture doctrine, and the measurement
   rules.
2. Banner the eleven superseded research docs (Clusters 1–3 of A7); retire the
   consolidation document itself the same day it merges.
3. Apply the five measurement fixes (D3): stop citing grader verdicts, persist
   acceptance evidence in captures, make captures self-describing, pin the
   grading environment, tag results with a spec version.

**Done when:** one document answers "what do we know", every superseded doc
points at it, and a capture can tell you which model and config produced it.

### P12.1 — Wire what exists *(no model runs)*

`thinkBudget` through `AgentSettings`/`AgentCommand`; `HandoffPacket.sampling`
actually driving worker argv instead of being write-only; **path presentation**
added to the packet schema, separate from the grant.

**Done when:** a packet can express its own sampling policy and path
presentation, and the harness passes both to the engine.

### P12.2 — Prompt-shape ablation

The cheapest high-information experiment available, and it gates P12.5.
Relative vs absolute path presentation × thinking on/off, n=3, **graded by the
real acceptance suite** — B8's runs were self-graded, which carries little
weight (C2).

This bears on three things at once: whether "Laguna 0/3 with thinking" is a
mechanism failure or a prompt artifact (the harness told every one of those runs
"never absolute paths"), whether Mellum's initiation finding replicates, and
whether `--think-budget` is solving a real problem.

**Done when:** the initiation effect is replicated or refuted at n=3 against
real grading, for both models.

### P12.3 — The proven pipeline, end to end

Hand-authored packets → nothink implement → nothink repair on pytest failure.
Every component is already replicated; this is assembly.

**Done when:** three phases, files written, 13/13 — from packets, not a
hand-driven harness.

### P12.4 — Model-authored packets

The one untested link. Decompose → schema validation (microseconds, fails
closed) → P12.3's proven chain. If decompose is bad, branch: use another model
for decompose only.

**Done when:** a model-authored packet passes validation and drives P12.3 to the
same result as a hand-authored one — or the gap is characterized.

### P12.5 — Bounded thinking, only where evidence demands it

Validate `--think-budget` live, for the roles P12.2–P12.4 show actually need
reasoning. **Expect it to expose the next failure** — shallow exploration, no
writes — rather than cure everything; the 20k run already showed transition
without productive action.

**Done when:** a role that needs reasoning completes with bounded thinking, or
the next failure mode is named and classified.

## Explicit non-goals

- **More quantization hunting.** Same failure signature at Q2_K and Q4_K_M; only
  the odds move, and Q4 exceeds the memory target. A matched Q4 control returns
  only *after* steering is tested (D2).
- **Footprint work.** Closed as a track: down stays Q8_0, no K-quant can reach a
  896-wide contiguous dimension (B1).
- **Harvest-from-thinking as a primary lever.** Fallback only — it cannot serve
  repair, since the model never sees the failure it must react to.

## Carried debt, tracked here so it is not lost

- **`ds4.c:36895` admission contract** — release-blocking silent-corruption
  class, independent of everything above. Should land regardless of P12.
- **Q4_K expert-major prefill** — the 0.21× penalty; the only engine item a user
  would feel.
- **Subagent-pool cross-worker coalescing** — already spun off as a task.
- **Landing `swiftstar-integration-mellum` (`cde6438`)** and bumping the
  submodule pin — the only step between here and Mellum being *loadable*, worth
  doing independent of whether Mellum is ever an agent.

## Mellum

**Reopened, pending replication** (D6) — not parked. B8 falsified the premise it
was parked on. Its re-entry is P12.2, alongside Laguna, since the ablation is
the same experiment for both models. What P12 does *not* do is treat Mellum as a
variant; that is P13.
