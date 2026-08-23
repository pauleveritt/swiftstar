# SwiftStar P11 addendum: the canonical agent test

**Date:** 2026-08-23
**Status:** accepted (brainstormed; each decision approved).
**Phase:** P11 addendum — the headless agent test that exercises the subagent
machinery end-to-end and becomes the project's canonical agent test.

This spec is the authority on *how* the addendum is done. `BRIEF.md`/`ROADMAP.md`
and the P11 spec stay settled; this is the test harness P11's machinery was built
to serve.

## Problem

P11 built the subagent machinery — the `dispatch` host-tool, the pool, the
`HandoffPacket`, the rolling digest / context assembly, the worktree dispatcher.
But no single thing exercises the *whole* path: a task decomposed into phases,
each phase run by a separate subagent in its own worktree, the prior phase's
result folded forward with care into the next, telemetry captured per-subagent
and as-a-whole, and the final result graded. This addendum builds that test,
headless, and makes it the canonical agent test for the project — the substrate
the later roadmap items (specialized tool subagents, RLM sub-queries, the
out-of-band context the rolling digest already is) plug into.

## Gardenable facts (verified against the source)

- **The task already exists, transplanted from the prior project.**
  `~/projects/pauleveritt/local-ai-pi/examples/agentclinic/` holds the AgentClinic
  task: `specs/roadmap.md` (the detailed, imperative spec — names FastAPI, the
  exact files, the exact tagline), `specs/roadmap-user-story.md` (the same
  milestone written as user-facing outcomes — no framework, no file names),
  `specs/mission.md`, `specs/tech-stack.md`, and `phase-1/` with the
  `acceptance/test_acceptance.py` contract plus `reference/` (known-good) and
  `broken/` (known-broken) fixtures. The acceptance contract asserts user-visible
  behavior and exact literals, and deliberately does *not* assert file layout.
- **The lessons are recorded.** `docs/evals/slm-struggles.md` names them: the
  **wrong framework** (the suite drives ASGI; the model wrote WSGI/Flask), the
  **261-turn `ls -R` loop**, **stale-anchor edits**, and **"facts work, rules of
  conduct do not."** `docs/superpowers/research/2026-08-04-phase5-cycle4-user-story-arms.md`
  records the two-arm zero: the imperative spec triggers building (but the wrong
  thing), the user-story spec triggers *no agency* (16/16 declined to start), and
  the two levers that move the floor — supplying the technology stack, and an
  imperative/orchestrator framing. The user-story spec currently omits the
  framework, which is the wrong-framework hazard un-applied.
- **The machinery exists.** P11 shipped `WorkerId`/`PoolWireParser`/`PoolPrompt`/
  `DispatchReceipt`, `PoolScheduler` (bounded free-list), `RollingDigest`,
  `ContextAssembly`, `DispatchPacketBuilder`, the `dispatch` host-tool, and
  `WorktreeDispatcher` (`prepare`/`finalize`/`discard`). The engine hosts N
  sessions (`--subagent-pool`), serialized by a pool mutex.
- **The app target is the one gap.** The orchestrator loop (dispatch → queue →
  worker turn → receipt → fold) lives in `AgentController` (the SwiftUI target,
  no test target). The headless harness must extract that loop.

## Decisions

- **D1 — Harness is the orchestrator (v1); the model is the implementer.** The
  harness decomposes the task into phases deterministically and drives each phase
  as a subagent; the model runs *only* as each phase's implementer (worker N).
  There is no model-driven "implement the whole thing" in v1 — that is the growth
  path, exercised later.

- **D2 — Two task specs, one acceptance contract.** The test runs the **easy**
  spec (`roadmap.md`, imperative) and the **hard** spec (`roadmap-user-story.md`,
  user-story) against the *same* `phase-1` acceptance contract. The hard spec's
  missing framework is a deliberate hazard the grader will surface.

- **D3 — Worktree transaction: chained worktrees, one commit-back.** A
  "transaction" is a multi-phase effort ending in one candidate ref. `prepare`
  gains a **base ref**: phase N's worktree is branched from phase N-1's commit,
  not `HEAD`. The transaction retains the chain of intermediate worktrees until
  the final phase commits; the last commit is the candidate ref; then all
  intermediates are discarded.

- **D4 — Fold-forward: two channels.** The *code* travels forward through the
  checkout (phase N's worktree already contains phases 1..N-1's committed code);
  the *context* travels through the packet (a curated "only what's needed"
  summary of what prior phases decided and what phase N must respect). v1 stubs
  the context with the phase's roadmap section + the prior candidate ref; the
  curated summary is the model's future job.

- **D5 — Telemetry: per-subagent and as-a-whole, committed.** Each subagent
  records its `TurnOutcome` (turns, tokens, tool calls, mutations, ref/receipt);
  the whole run records end-to-end success, total turns/tokens, and wall-clock.
  The capture is written to a committed artifact the analyzer (P6-style) can read
  without rerunning.

- **D6 — Grading: two legs.** (a) **Deterministic** — the acceptance suite runs
  in the final checkout (`uv run pytest`), pass/fail. (b) **Agent-judged** — a
  DeepSeek pass reads the generated code against the spec and returns a "looks
  good / does not look good" verdict with reasons. The DeepSeek verdict is the
  primary quality read; the acceptance suite is the floor.

- **D7 — Headless harness, extracted loop.** The harness is a new headless
  executable target (sibling of `swiftstar-drive`). The orchestrator loop is
  extracted out of `AgentController` into a headless-drivable component, closing
  the "app target has no test target" gap.

- **D8 — n=1 first; the canonical agent test.** Start with a single run, easy and
  hard spec, n=1. The harness is the project's canonical agent test — the thing
  run to prove the agent and its subagents work.

- **D9 — Roles are the growth path.** The orchestrator role is a harness job in
  v1; the future roster — planner, orchestrator, implementer, validator, scout —
  each becomes a specialist subagent (the "specialized tool subagents" backlog
  entry). The harness's role structure is designed so a role can swap from
  deterministic code to a subagent without reshaping the test.

## Components

**SwiftStarKit** (pure): no change beyond what P11 shipped — the packet types,
scheduler, digest, context assembly are reused as-is.

**SwiftStarAppKit** (IO/Process): `WorktreeTransaction` (chained worktrees,
commit-back); the extracted `PoolOrchestrator` (spawn `--subagent-pool`, drive a
worker turn, fold the receipt) — the headless form of the loop currently inside
`AgentController`; the telemetry capture writer.

**The harness executable** (`swiftstar-agenttest`): decomposes the task, drives
the transaction phase-by-phase, captures telemetry, runs the acceptance suite and
the DeepSeek grader, prints the report.

**The task fixtures** (committed to SwiftStar): the two specs + acceptance
contract + reference/broken fixtures, copied from `local-ai-pi`'s
`examples/agentclinic/` so the canonical test is self-contained rather than
resolved to a sibling repo at run time. Running the acceptance suite needs a
Python environment with the task's deps (FastAPI, Jinja2, `turbohtml`, pytest) —
`uv run pytest` in the checkout, the same lock the task's `tech-stack.md` names.

## Data flow (one run, one spec)

1. Harness reads the spec, decomposes it into the known phases (deterministic).
2. Transaction begins at `HEAD`. For each phase:
   a. `prepare` a worktree branched from the current head (the prior commit).
   b. Build the `HandoffPacket` (phase spec + prior ref + v1-stubbed context).
   c. Dispatch the phase to a worker (the model implements it in the worktree).
   d. `finalize` → candidate ref (or receipt); record per-subagent telemetry.
   e. The candidate ref becomes the transaction's new head.
3. The final commit is the transaction's candidate ref; intermediates are discarded.
4. Grade: run the acceptance suite in the final checkout; DeepSeek reads the code
   vs the spec and returns a verdict with reasons.
5. Write the capture (per-subagent + whole telemetry + grades); print the report.

## Testing

- **Fast tier:** the pure pieces are already covered (packet, scheduler, digest,
  assembly, verdict).
- **Integration tier:** `WorktreeTransaction` (chained branches, commit-back,
  discard), the extracted `PoolOrchestrator` against the fake pool engine.
- **Live tier (the canonical test, `n=1`, headless):** run the harness against the
  real engine and weights on the easy and hard specs; the report is the evidence.
  The DeepSeek grader runs as part of the live tier (never CI).

## Concept budget

Two new terms: **transaction** (D3 — the multi-phase worktree chain ending in one
commit-back) and **role** (D9 — a slot in the harness that is deterministic code
now and a specialist subagent later). Both earn their place; neither is shorthand.

## Out of scope

Model-driven orchestration (the "implement the whole thing" main agent — the
growth path, D9); the planner/orchestrator/validator/scout specialist subagents
themselves (later); the RLM sub-query tier; batching (`n=4`) and statistical
claims (later); the full satyrn-evals oracle machinery (the grader is the
DeepSeek qualitative read, not the hidden-oracle chain).
