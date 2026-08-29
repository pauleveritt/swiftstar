# Local model agency — what is settled

*P12.0's deliverable, landed 2026-08-25 — late, and at reduced scope. Read the
scope note before relying on it.*

## Scope note — what this document is and is not

P12.0 specified a single source of truth that would **replace the live-findings
role of eleven research notes**, written "as the first roadmap action." It was
never written; the phase ran without it, and the roadmap later claimed it had
shipped. That claim was false and is corrected (see
[`2026-08-25-p12-verdict-record.md`](2026-08-25-p12-verdict-record.md)).

This document is the honest reduced version: **an index of settled findings and
a pointer to where current truth actually lives**, not the full merge P12.0
described. It does not re-synthesize
[`2026-08-24-overnight-consolidation.md`](superseded/2026-08-24-overnight-consolidation.md)
(134 KB of staging that still self-describes as unmerged). What it does is stop
eleven notes from being places a reader looks for *current* truth, and say
plainly where to look instead.

**Where current truth lives now:**

| Question | Authority |
|---|---|
| What did P12 establish, and what didn't it? | [`2026-08-25-p12-verdict-record.md`](2026-08-25-p12-verdict-record.md) |
| Is Mellum usable, and how? | [`2026-08-25-p15-verdict-record.md`](2026-08-25-p15-verdict-record.md), plus P13's benchmark record |
| What is the harness contractually? | The P10/P11 design specs; `HandoffPacket`, `WorktreeDispatcher` |
| What's open? | `ROADMAP.md` — "Now" and Backlog |

## 1. What each model can and cannot do, as measured

Every figure carries its sample size. None is a reliability number; this
project's own record shows an unchanged config swinging 0/2 → 2/2 → 1/2 across
batches.

### Laguna S 2.1 (Q2_K, the deployable artifact)

- **Writes correct code.** Repeatedly reaches 13/13 on the acceptance suite when
  it acts at all.
- **Implements unreliably end-to-end.** 3/9 on the hard spec across three
  identical-config batches (3/6 among runs surviving `budgetExceeded`). Tuning
  the implement arm across those batches moved understanding, not the rate.
- **Repairs well, on the evidence available.** 3/3 × 2 fixtures (round-1 passes,
  P12.4 fixture tier); 4/4 at 13/13 in P15's text-contract arm. Both are
  small-n and neither is the full live implement→repair chain, which has never
  been observed end-to-end.
- **Localizes correctly when shown the whole surface.** Given a traceback that
  surfaces at a template and a defect in the handler, it edited the handler, not
  the decoy — and followed a failing assert's stated value (303) over the more
  common convention (302).
- **Thinking used to fail to terminate.** Fixed by `--think-budget`, verified at
  the token level: forced `</think>` lands within ~8 tokens of the ceiling. The
  next failure it exposed was *completes-and-is-wrong* (clean imports, up to 7
  assertion failures), not shallow exploration.
- **Over-explores into `budgetExceeded`** in roughly one run in three; raising
  the tool budget to 64 did not help.

### Mellum 2.1

- **Does not initiate tool calls** under the agentic harness — P13's gate. This
  is the finding that blocked it as a first-class variant.
- **Is harness-addressable, not content-broken** — P15's verdict. Removing tool
  initiation from the loop entirely (a `textContract` packet: emit `#path`
  headings plus file bodies as plain text; the host harvests and writes) reaches
  it. Under that contract: repair 4/4 at 13/13, build 3/9 at 13/13, with 0 tool
  calls.
- **Loads and admits correctly** as of P12.2 — the 9.33 GiB artifact, 339
  tensors, admission contract enforced before engine work.
- **Belief revision: unresolved, and the corpus is contradictory.** An early
  note claims Mellum cannot revise in-context; a later observation had it
  entering a genuine write → test → diagnose → fix loop. P12.3's Mellum arm
  never ran, so this was never settled. Treat any "Mellum cannot revise" claim
  as *at risk*, not established.

### DeepSeek-V4-Flash

- 284B total / 13B active MoE; a real GGUF exists locally (~91 GiB, FP4+FP8
  mixed). **Not evaluated by this project's harness.** The corpus characterizes
  it as terminating and acting but over-exploring; that is inherited from
  earlier notes, not measured here. Treat as unevaluated.
- Note the trap: `~/projects/ds4/ds4flash.gguf` was a symlink pointing at
  *Laguna*, not Flash. Removed 2026-08-25. The submodule's own
  `external/ds4/ds4flash.gguf` correctly points at the real Flash artifact.

## 2. The deployable configuration

- **Laguna S 2.1, Q2_K** (`laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`).
- **Measured at ctx=32768** (this session, directly observed): resident model
  44.94 GiB + KV 1.57 GiB = **46.51 GiB planned**, plus ~5.86 GiB of per-session
  Metal scratch the engine's own `planned_bytes` omits. Fits natively on a
  128 GB machine with no SSD-streaming dependency. Earlier corpus figures
  (49.59 GiB) were computed at different context sizes — always cite ctx with
  the number.
- **`--nothink` for implement and repair.** Thinking is a whole-process,
  spawn-time property, not per-packet; `packet.sampling` is recorded but does
  not drive the engine.
- **Pool: 3 workers** — worker 0 orchestrator, worker 1 implement, worker 2
  repair (repair always starts from a clean session).

## 3. The architecture doctrine

The host owns phase boundaries, budgets, permissions, validation, and recovery.
The model supplies judgment and code. Concretely:

- **A typed handoff packet per phase** — exact writable files, the validation
  command the host will actually run, per-file baselines read from the worktree
  rather than guessed, turn and tool-call budgets.
- **Success is never inferred from prose.** Host-authoritative facts only:
  actual mutations, real exit codes, a passing acceptance suite. A model's own
  report is not evidence, and neither is a grader's verdict (see §4).
- **Worktree isolation.** A dispatch runs in a disposable worktree and returns
  a reviewable candidate ref or a typed receipt naming the refusal. Nothing
  merges; the caller's tree is never touched.
- **Deliberation happens once, at decompose, and is crystallized into packet
  facts** so implementers execute rather than re-derive. *Aspirational, not
  demonstrated* — the decompose role has never run (P12.5). The facts mechanism
  itself is real and works: pinning a working-directory fact removed a
  measured reasoning loop.
- **Recovery at both boundaries** — acceptance (P12.4) and phase (P12.8).

## 4. The measurement rules

These make any future number trustworthy. Four of five have landed.

1. **Do not cite grader verdicts.** The project's record shows DeepSeek
   returning "good" for code that failed acceptance 7/13. Acceptance exit codes
   only. *(Rule stands; the grader still runs, its verdict is not evidence.)*
2. **Persist acceptance evidence in the capture dir** — exit code plus output.
   *Landed.*
3. **Make captures self-describing** — `run-config.json` and `packet.json` per
   run. *Landed.* A capture can now say which model and config produced it.
4. **Pin the grading environment.** A dependency bump already flipped one 13/13
   to 10/13. *Partially — the uv project is external; the acceptance suite and
   fixtures are committed.*
5. **Tag every results table with a spec version.** "Hard spec" names at least
   three different documents across this corpus. *Rule stands; apply it.*

Two additions this project learned the hard way since:

6. **State the sample size, always.** An unchanged config swung 0/2 → 2/2 → 1/2.
   A single batch quoted alone misleads in either direction.
7. **Wall-clock currently includes engine attach and weight load.** Timing
   starts before `PoolOrchestrator` is constructed, so a cold-cache run carries
   seconds of one-time cost that has nothing to do with task performance. Filed
   in the Backlog; until fixed, do not compare wall-clock across cold and warm
   runs.

## Superseded notes

Eleven research notes now carry a banner pointing here. They keep their evidence
value — the captures, the raw observations, the reasoning at the time — and stop
being places to look for current truth:

*P11 agent test (5):* the Laguna and Mellum verification records, the Laguna
hard analysis, the telemetry review, the Laguna revision-test spec.
*External model reviews of P11 (5):* the two GLM 5.3 reviews, the Kimi K3
review, the measurement gate, the smoke gate.
*Mellum agentic limits (1):* the agentic tool-use finding.

Not superseded, and deliberately so: the "designed but not built" cluster
(`monty-and-the-ane-watcher-tier`, `house-style-as-a-compiled-artifact`,
`handoff-packet-frontmatter-schema`). Those are speculative by their own
admission and should stay labelled unbuilt rather than retired — a different
category from stale findings.

The consolidation document itself was supposed to be retired the day it merged.
It has not been merged, so it stays — but it is staging, not a reference, and
anything in it that matters should end up here or in a verdict record.
