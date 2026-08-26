# P12 — Reliable agency

**Status:** closed at a waypoint 2026-08-25 — two of three roles tested.
**Reopen condition: P12.5 (model-authored packets), which never ran.** Written
2026-08-24, replacing the earlier "P12 — More models" framing.

**Status as of 2026-08-25 (supersedes the 2026-08-24 evening progress note
below, which was never revised and had gone stale on four counts).** What
shipped: P12.1 (including the validator/parser hardening the old note lists as
owed); P12.2; P12.3's Laguna arm; P12.4 (fixture tier 3/3 ×2 — repair *has* now
run in-harness, and the import gate *has* fired live); P12.6's second disjunct
(the next failure mode named and classified — see that section); P12.8
(phase-level recovery, code landed, live confirmation still owed). What did
not: P12.0's source-of-truth document and superseded-doc banners; P12.3's
Mellum arm and the Mellum revision re-run; P12.4's live end-to-end tier;
**P12.5 entirely**; P12.7 beyond plan text. Full accounting in ROADMAP's Prior
work entry for P12.

**Progress as of 2026-08-24 evening — HISTORICAL, superseded by the status
above.** Several steps ran out of the plan's order, driven by findings rather
than sequence. Landed:

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

**~~Still true and unchanged~~ — all three of these are now false** (kept for
the historical record, corrected 2026-08-25): repair has since run in-harness
(P12.4's fixture tier, 3/3 ×2); the import gate has since fired live (5 of 6
failing P15 build runs); and the `--think-budget` branch was merged with the
Mellum integration branch in P12.2 — the submodule pins that merge today.

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

**Status (2026-08-25): implementation done, in-harness repair now exists and
is smoke-verified; the "done when" line above is not yet met at scale.**

- Design ([`2026-08-24-p12-4-repair-role-design.md`](../specs/2026-08-24-p12-4-repair-role-design.md),
  D1-D10) and plan ([`2026-08-24-p12-4-repair-role.md`](../plans/2026-08-24-p12-4-repair-role.md))
  are accepted, twice Fable-reviewed at the design stage.
- All 7 implementation tasks landed on `p11-subagent-pool`
  (`GradeResult`/`Receipt.repairExhausted` → `MachineEvidence` → `AcceptanceGrader`
  → `RepairLoop` → 3-worker pool + `repairPacket` → wired into `runOnce` →
  `--fixture` mode), each task-reviewed, plus a final whole-branch review and
  two rounds of fixes, plus a Fable review of the actual code + smoke results
  and one more fix round. Full record, every finding and ruling, in
  [`.superpowers/sdd/2026-08-24-p12-4-repair-role/progress.md`](../../../.superpowers/sdd/2026-08-24-p12-4-repair-role/progress.md)
  (git-ignored — lives only in this working tree, read it before resuming).
- **Fixture tier confirmed working against the real model**: `--fixture
  misleading-locus` and `--fixture plausible-wrong-fix` both 3/3 (all
  round-1 passes) against Laguna S 2.1 Q2_K. This proves the repair loop's
  plumbing and both D6/D10 measurements (localization; evidence-following
  over convention-recall) — it does **not** prove repair works at live
  difficulty (single-failing-test fixtures on a 6-file, ~4.5KB surface).
- **The "done when" line (three phases, 13/13, from packets) has never been
  exercised end-to-end with a real implement failure feeding real repair.**
  One single confirmation run (`--spec roadmap-user-story`, nothink,
  no `--batch`) was in flight as of this note — check
  `captures/agenttest/` for the most recent `roadmap-user-story` capture to
  see how it landed before doing anything else.
- **The planned overnight validation (n=15-20/arm: nothink-implement+repair,
  and think-budget-implement+repair replicating C15/C17/C18's exact config
  — `AGENTTEST_THINK=1 AGENTTEST_THINK_BUDGET=2048 AGENTTEST_PATH_STYLE=absolute`
  — both on `roadmap-user-story`) was started, then stopped early per
  explicit user request** (it was launched at a time that stopped being
  "overnight" partway through) **and has not run.** This is the next real
  gate on P12.4 — see the ledger's "Overnight live-tier run" section for the
  exact configs and the chunking rationale (5×`--batch 3` per arm, not one
  `--batch 15`, so a broken run can be caught before it burns hours).
- Known, deliberately-not-fixed limitations (documented in the design spec's
  new "As-built deviations" section): `AGENTTEST_REPAIR_THINK` is inert
  (warns on stderr); repair cannot honor `AGENTTEST_PATH_STYLE=absolute`
  (D5 forces relative paths) — so Arm B's repair rounds render relative
  paths even though its implement phases use absolute ones. Not a bug to
  fix; a known confound to interpret around.
- A **second, independently-built implementation of this same plan** exists
  in a sibling worktree (`.worktrees/p12-4-repair-role`, branch
  `p12-4-repair-role`) — branched before this design's second review round
  landed, has its own review history, and independently arrived at a better
  evidence-capping approach (middle-truncation, 16KB cap) that this branch
  adopted after a Fable review flagged the same gap. User explicitly chose
  to continue on `p11-subagent-pool`; the sibling worktree was left
  untouched, not reconciled or merged.

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

**Status (2026-08-25): met by the second disjunct, not the first.** A
2026-08-25 audit initially scored this NOT STARTED on the grounds that no
commits reference P12.6 — but the criterion is a disjunction, and it never
required commits. The second branch was satisfied: validating `--think-budget`
(verified at the token level in C15–C18) named and classified the next failure
mode as *completes-and-is-wrong* — up to 7 assertion failures with clean
imports — rather than the predicted shallow exploration. **The first branch
was not**: no run has demonstrated a role that needs reasoning completing
*with* bounded thinking, and every self-describing capture records
`think=nothink, thinkBudget=0`. Bounded thinking for the repair role
specifically remains unvalidated and is filed in ROADMAP's Backlog alongside
the inert `AGENTTEST_REPAIR_THINK` override.

### P12.7 — Honest cross-system comparison

**Added 2026-08-25**, after a session's ad-hoc comparison against a Claude
Code course exercise turned out to have measured the wrong metric (single
final `ctx_used` — a live session position — compared against a stateless
architecture's cumulative resend total) and needed a Fable correction to
catch. This phase builds the comparison properly instead of re-deriving it
by hand next time. **Revised 2026-08-25 (same day)** after a second,
deeper-diving agent found the first correction's own replacement metric was
still wrong, plus a real accumulation bug — see items 2 and 2a below.

Five pieces:

1. **Trace-channel capture in `swiftstar-agenttest`.** The harness currently
   captures only `wire.ndjson`; the `--trace` channel (already parsed
   elsewhere by `TraceParser`, built for P6) carries the `prefill sync done
   … cached=X suffix=Y` lines needed to compute real cumulative context.
   Wire it into this harness's capture the way `swiftstar-drive` already
   does.
2. **Three separate metrics from that trace data, not one.** The first
   draft of this plan proposed summing `suffix` alone as "cumulative
   context processed" — wrong: `suffix` measures fresh prefill *compute*,
   not the API-style "total input tokens" a system like Claude Code
   reports (which includes cache-read tokens — per OpenAI's own prompt-
   caching docs, cached tokens stay counted in total input tokens, tracked
   separately, billed at a reduced rate, even though their KV state avoids
   repeated computation). Capture and report all three, per run:
   - **Σprompt** — total tokens presented to the model each round, summed
     across every round. Only this one is plausibly comparable to a
     Claude-style "context processed" figure.
   - **Σcached** — the portion of Σprompt served from KV without
     recomputation.
   - **Σsuffix** — the portion that was freshly prefilled (Σprompt − Σcached).
   - **Stateful tokens** — `Σprompt − final ctx_used`: tokens that were
     logically part of the session but never needed *reprocessing* thanks
     to the persistent KV session — i.e. what a stateless-per-call
     architecture would have paid for again that this architecture didn't.
     Structurally undefined for a stateless system (no persistent session
     to diff against) — reports as N/A in that column, not zero.
   2a. ~~**Fix a real bug while wiring this: `generated` is last-value-wins,
   not accumulated.**~~ **RETRACTED 2026-08-25 — there is no bug here; this
   item was wrong and the code is correct as written.** The claim assumed
   `.ready` fires once per tool-calling round carrying a per-round count, so
   that `TurnOutcomeBuilder`'s `self.generated = generated` would keep only
   the last round. Checked against evidence before changing anything, and the
   premise is false on both sides:
   - **Wire:** in `captures/agenttest/20260824-171135-roadmap-user-story-run3/wire.ndjson`,
     worker 1 emits dozens of tool blocks before its *first* `ready`. The other
     `ready` events in that file belong to separate `runPhase` calls (context
     resets between them), i.e. separate turns and separate builders — not
     extra rounds of one turn.
   - **Engine:** `external/ds4/ds4_agent.c` writes `w->last_turn_generated`
     only on a turn-ending return (interrupt/EOS/limit/context-full), never
     when the tool-round loop continues. Its own doc comment notes that a
     later `ready` *repeats* the last turn's outcome for reconnect recovery —
     so `+=` would double-count on replay. Last-value-wins is required, and is
     symmetric with `ctxUsed`.
   - **Consumers agree:** `PoolOrchestrator` breaks its read loop on the first
     `.ready`; `AgentTestAnalyzer` closes its phase accumulator there.

   Recorded rather than silently deleted because the false claim reached a
   commit message (`1400171`) and a session's analysis before being caught.
   *Left open by this retraction:* whether the engine's own
   `last_turn_generated` represents a whole turn or only its final tool round
   is a separate question this check did not settle — worth one look if
   per-turn token figures ever become load-bearing.
3. **`DumbImplementer`** — a naive, flag-gated packet-builder mode that
   sends a minimal "here's the spec, build it" packet instead of
   `phasePacket`'s engineered prompt (no pinned facts, no "don't re-explore"
   rule, no terse writable-note discipline), still dispatched through
   `PoolOrchestrator` — isolating how much of Laguna's context economy is
   architectural (the persistent session, `ToolResultCondenser`'s 8000-
   *byte* cap) versus prompt engineering specific to this harness. Note:
   the SHA-256 read-cache (`PoolOrchestrator.readCache`) is **not** part of
   that architectural floor the way the design doc previously implied — it
   is cleared at the start of every `runPhase` call (`readCache.removeAll()`),
   so it helps only *within* a phase's own tool-calling rounds, not across
   the whole multi-phase run.
4. **Warm-started timing.** `runOnce`'s wall-clock/context counters
   currently start before the engine attaches to Metal and loads weights —
   conflating one-time engine-boot cost with task performance. Attach, run
   one throwaway warm-up prompt, then start every counter this harness
   reports from that point. One number, not two.

DeepSeek grading (`DeepSeekGrader`, already working via `OPENROUTER_API_KEY`/
`~/.pi/agent/auth.json`) needs no new work — it already grades whatever
lands in `writableFiles`; `DumbImplementer` runs go through the same
`runOnce` grading step.

**Done when:** a `DumbImplementer` run against `roadmap`/`roadmap-user-story`
reports Σprompt/Σcached/Σsuffix and stateful-tokens alongside the existing
(now-fixed, truly-accumulated) generated-token count, warm-started timing
is in place, and the comparison against Claude Code's L3 config is redone
with Σprompt as the comparable figure — written up in `docs/cool_things/`
alongside the persistent-session-vs-stateless-API finding that motivated
this phase, stated as a hypothesis pending that real measurement, not a
result, until the trace capture actually lands.

**Status (2026-08-25): NOT STARTED — plan text only.** Both P12.7 commits
(`082329d`, `1400171`) touch this file and nothing else. There is no
`DumbImplementer` in `Sources/`, no trace-channel capture, no
Σprompt/Σcached/Σsuffix, no warm-started timing, and `docs/cool_things/` does
not exist. An earlier ROADMAP entry credited P12.7 with having "corrected the
cross-system metric definitions the measurement gate reports against" — true
only of the definitions *in this document*, not of anything the harness
measures; that claim has been corrected. Item 2a's alleged
`TurnOutcomeBuilder` accumulation bug has been **retracted** — it was checked
against the wire and the engine source and the existing code is correct; see
that item.

### P12.8 — Phase-level recovery

**Added 2026-08-25** (after P12 was first closed), reopening P12 for the half
of its own "recovery" charter that P12.4 left unwired: P12.4 recovers at the
end-of-run acceptance boundary, but a build phase failing its import check
aborts the run before `commitBack()`, so the repair loop was never reachable
for the failure class that actually stopped 5 of 6 failing P15 build runs.

Design: [`2026-08-25-p12-8-phase-level-recovery-design.md`](../specs/2026-08-25-p12-8-phase-level-recovery-design.md).
Plan: [`2026-08-25-p12-8-phase-level-recovery-plan.md`](2026-08-25-p12-8-phase-level-recovery-plan.md).

**Status: code landed, live confirmation owed.** `commitForRepair`,
`adoptRepairedPhase`, `PhaseRepair`, and the build-loop wiring are committed
(`6ac5df7`, `84b9fa1`, `a438634`, `de46f4f`, `cca02f2`) and the deterministic
tier passes. The one live attempt
(`captures/agenttest/20260825-203706-roadmap-user-story`) did **not** reach
acceptance: phase 1 failed validation on a trivially repairable content defect,
the repair itself returned `validationFailed`, and `RepairLoop` exited on that
receipt **by design** (D4 — any receipt ends the loop; this is a limitation to
be lifted, not a malfunction). No verdict record written.

**Done when:** a live run shows `phase N: repaired <ref>` and continues to
acceptance, and that run is recorded.

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
