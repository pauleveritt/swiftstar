# P12 — Reliable agency

**Status:** in progress. Written 2026-08-24, replacing the earlier "P12 — More
models" framing.

**Progress as of 2026-08-24 evening** — several steps ran out of the plan's
order, driven by findings rather than sequence. Landed:

- **P12.1 is done.** `thinkBudget` wiring (`066f28d`), path presentation
  (`4535dcd`), facts actually rendered into the prompt (`aad4eb0` — they were
  stored but never sent), plus the commit-level `noChanges` fix (`adc08c0`) and
  the mandatory import check (`2172454`). Validator/parser hardening is **not**
  done and is still owed.
- **P12.3 ran for Laguna** (C13–C18): path presentation is a real lever, the
  `--think-budget` engine feature works and is verified at the token level, and
  a pinned working-directory fact removed a specific reasoning loop. Mellum's
  arm has **not** run — it needs P12.2.
- **P12.6 effectively ran early**, since validating `--think-budget` was the only
  way to test the termination fix. Its prediction — that a forced transition
  would expose the next failure rather than cure everything — held, but the next
  failure was not the one predicted: it is *completes-and-is-wrong* (up to 7
  assertion failures with clean imports), not shallow exploration.

**The headline number, so nobody re-derives it:** across three identical-config
batches, **3/9 end-to-end** (3/6 among runs that survived `budgetExceeded`).
Tuning the implement arm across those batches advanced mechanism understanding
substantially and the pass rate not at all. See C15–C18 in the consolidation
doc.

**Still true and unchanged:** repair has never run in-harness; the import gate is
verified in isolation but has never fired live; the `--think-budget` submodule
branch is not merged with the Mellum integration branch (P12.2).

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

**Also harden the validation gate, because P12.5 depends on it failing closed.**
The landed validator and parser have known gaps (C5 items 7–8): no `packet`
version rule (`packet: 99` is accepted), `sampling.maxTokens` and
`validation.command` unchecked, and a silent-misparse class in the parser —
`command: |` block scalars yield the literal string `"|"`, trailing `# comment`
is retained inside scalars, and a CRLF document throws a misleading
`missingFrontmatter`. These are tolerable while packets are hand-authored and
disqualifying once a *model* authors them: a block scalar is the natural way to
write a multi-line command, and today it mis-parses silently rather than
refusing.

**Done when:** a packet can express its own sampling policy and path
presentation, the harness passes both to the engine, and every gap above either
validates or fails closed.

### P12.2 — Make Mellum loadable

**P12.3 cannot run without this, and nothing else sequences it.** Mellum is not
reachable from the current submodule pin: `cde6438` is not even an object in
`external/ds4` — it exists only in the separate
`~/projects/ds4/.claude/worktrees/swiftstar-integration-mellum` worktree. Land
that line, reconcile it with `laguna-think-budget` (`1f9a4c5`, which carries
`--think-budget`; the two have diverged from `8784fe6`), and bump the submodule
pin.

Couple the **`ds4.c` admission-contract fix** to this step rather than leaving it
free-floating in carried debt: the defect is real (verified — the Mellum decode
contract infers layout from `ffn_gate_exps` alone and never inspects down, so a
non-Q8_0 down silently runs the Q8_0 batch kernel over foreign bytes) but it
exists *only* in mellum-branch code, so it cannot bite until this branch lands
and must not ship with it.

**Done when:** the app can load Mellum from the pinned submodule, and the
admission contract refuses unsupported quant × path combinations loudly.

### P12.3 — Prompt-shape ablation

The cheapest high-information experiment available, and it gates P12.6.
Relative vs absolute path presentation × thinking on/off, n=3, **graded by the
real acceptance suite** — B8's runs were self-graded, which carries little
weight (C2).

This bears on three things at once: whether "Laguna 0/3 with thinking" is a
mechanism failure or a prompt artifact (the harness told every one of those runs
"never absolute paths"), whether Mellum's initiation finding replicates, and
whether `--think-budget` is solving a real problem.

**Also re-run the Mellum revision test under the absolute-path shape.** D6
records "Mellum cannot revise" as *at risk*, not settled: B8 observed Mellum
entering a genuine write → pytest → diagnose → fix loop and correctly reading a
stray `</head>` from failure output. That must be resolved here, or P12.0's
source-of-truth document will record a measured limit the corpus marks unsettled.

**Done when:** the initiation effect is replicated or refuted at n=3 against
real grading for both models, **and** Mellum's revision capability is settled
under the shape that triggers its initiation.

### P12.4 — The proven pipeline, end to end

Hand-authored packets → nothink implement → nothink repair on pytest failure.
Every component is already replicated; this is assembly.

**One honest caveat:** repair's 3/3 was measured through `repair.py`'s
fence-parsing *outside* the sandboxed packet harness — C1 records that the
revision experiments "bypassed all of it." In-harness, packet-driven repair has
never run. That is normal for an assembly step, and it is why P12.4 can still
surprise despite every part being individually replicated.

**Done when:** three phases, files written, 13/13 — from packets, not a
hand-driven harness.

### P12.5 — Model-authored packets

The one untested link. Decompose → schema validation (microseconds, fails
closed) → P12.4's proven chain. If decompose is bad, branch: use another model
for decompose only.

**Done when:** a model-authored packet passes validation and drives P12.4 to the
same result as a hand-authored one — or the gap is characterized.

### P12.6 — Bounded thinking, only where evidence demands it

Validate `--think-budget` live, for the roles P12.3–P12.5 show actually need
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
  896-wide contiguous dimension (B1). **One exception B5 explicitly kept**: the
  all-28-layer Q4_K gate/up build *with* imatrix (9.33 → 8.59 GiB) is untested —
  same format already validated on 22 of 28 layers, so it is far lower risk than
  any new format. Worth one KLD run before it is adopted or discarded; it is not
  a reason to reopen the track.
- **Harvest-from-thinking as a primary lever.** Fallback only — it cannot serve
  repair, since the model never sees the failure it must react to. **Note the
  fallback is not usable today**: `ThinkHarvest` is landed but unwired, and
  mechanical harvest misassigned files in 2 of 3 real runs because the model's
  block-labelling is a per-run stylistic choice (C9). If P12.6's expected failure
  (transition without writes) occurs, this is not a safety net yet — making it
  one means pinning the label format as a packet directive and wiring
  harvest-on-`noChanges`, both currently unowned.

## Carried debt, tracked here so it is not lost

- **`ds4.c:36895` admission contract** — release-blocking silent-corruption
  class, independent of everything above. Should land regardless of P12.
- **Q4_K expert-major prefill** — the 0.21× penalty; the only engine item a user
  would feel.
- **Subagent-pool cross-worker coalescing** — already spun off as a task.
- **Landing `swiftstar-integration-mellum` (`cde6438`)** and bumping the
  submodule pin — **now sequenced as P12.2**, not free-floating, because P12.3
  depends on it.
- **`--prefill-chunk` is accepted and ignored** (B5.4) — reaches only the
  estimator, so it silently alters diagnostics and nothing else. Wire it or
  refuse it. Note the `DS4_MELLUM_PREFILL_CHUNK` env var *does* work; only the
  CLI flag is inert.
- **The layer-0 oracle fails on Q4_K** (B5.6) — needs an *independent* Q4_K
  reference (llama.cpp's layer-0 output on the same artifact) and explicitly must
  **not** be "fixed" by raising the threshold.
- **Per-layer prefill eligibility** (B5.3, "piece 3a") — ~1.17–1.20× for the six
  pure-Q8_0 layers. Cheap *if* paths can mix within one prefill pass; verify that
  before costing it, and do not sequence it before Q4_K prefill's measurement or
  neither result is attributable.
- **Two small Mellum leftovers from A5**: the `SettingsView` modelPath preset
  (A5.2), and the decision on the drafted-but-unsent Mellum-team report (A5.6 —
  a user decision, not an engineering task).

## Mellum

**Reopened, pending replication** (D6) — not parked. B8 falsified the premise it
was parked on. Its re-entry is P12.2, alongside Laguna, since the ablation is
the same experiment for both models. What P12 does *not* do is treat Mellum as a
variant; that is P13.
