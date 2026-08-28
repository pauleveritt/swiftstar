# SwiftStar P23 design: wire-level control (per-turn think + per-worker context)

**Date:** 2026-08-28
**Status:** implemented
**Phase:** P23 — Wire-level control

This spec is the authority on P23. It supersedes the ROADMAP P23 row
([ROADMAP.md:227](../../../ROADMAP.md)), which describes about half the phase —
small-ctx workers were merged into P23 on 2026-08-27 (recorded at
[ROADMAP.md:389](../../../ROADMAP.md) and in P24's row at :228) but never folded
into the row itself.

Research and probe evidence:
[`2026-08-28-p23-wire-control-research.md`](../research/2026-08-28-p23-wire-control-research.md).
Every "what exists" claim below was verified by direct read on 2026-08-28.

## Problem

Three concrete defects, each measured rather than assumed.

**1. Thinking is unbounded and unswitchable.** Think mode is fixed at process
start; changing it means killing and re-spawning the engine. The app never sets
it at all — `AgentCommand.argv` emits `--nothink`/`--think-budget` only when
`AgentSettings.noThink`/`.thinkBudget` are set, and the only setters are
`swiftstar-agenttest` and unit tests. So the app runs the engine default,
`DS4_THINK_HIGH`, with no ceiling. **Probe A reproduced the failure this
permits in ten seconds**: Laguna XS at ctx 16,384 filled **15,873 of 16,384
tokens (97%) with reasoning across 7 rounds and never answered** — the same
failure P20's closure verdict recorded ("think-looped to the 8192-token limit
with 0 tools").

**2. Every pool worker runs at the parent's context.**
`ds4_agent.c:16488` creates every session with `cfg->gen.ctx_size`; there is no
per-worker override. In the 2026-08-27 production capture, **worker 1 answered a
consult in 18 tokens while holding a full 32,768-token session.** The cost is
~6.15 GB of scratch plus full KV per worker, where a 4k worker needs ~1.5 GB of
scratch. P11's own measurement puts the prefill ceiling at **4.2×** (one
131,072-token prefill = 2,121 s; 8 × 16,384 sequential = 500 s).

**3. Laguna XS is capped at 1/8 of the context it supports, and the cap is
mis-modelled.** The GGUF declares `laguna.context_length = 262144`;
`VariantRegistry.swift:114` declares `maxContext: 32_768`, with its own comment
naming the provenance — *"Measured on 32 GB M1 Pro… 6.53 GiB @32k."* That cap
manufactured the compaction cliff behind **37.5% of the 1809 capture's Σsuffix**
(five compactions in 24 minutes, each discarding ~23k tokens). And the anchor
that would govern any raise is wrong (D7).

### What already exists — verified by direct read, do not rebuild

- **The engine's think primitives are complete.** `DS4_THINK_NONE/HIGH/MAX`
  (`ds4.h:107-110`), public API (`ds4.h:444-449`), context-aware downgrade
  (`ds4.c:53348-53374`). Flags `--think`/`--think-max`/`--nothink`
  (`ds4_agent.c:885-890`) and `--think-budget N` (`:14312-14366`, forces
  `</think>` then bans reopening for the round). **Probe A verified all of these
  work live** (`--think` → `think=high`, `--nothink` → `think=none`). They are
  **absent from `ds4-agent --help`** — a doc gap, not a functional one.
- **`ds4-server` already implements per-request `reasoning_effort` +
  `enable_thinking`** (`ds4_server.c:860-889`, `:1163-1183`), and **`ds4_cli.c`
  already does runtime think switching** with an invalidate-only-on-change guard
  (`:1384-1396`). **P23 is porting two working reference implementations onto the
  agent wire, not inventing a mechanism.**
- **The stdin seam is already JSON.** The app sends
  `{"s":"…","t":"prompt","worker":N}` via `PoolPrompt.encode()`
  (`Sources/SwiftStarKit/PoolPrompt.swift:12-19`); the engine parses it at
  `ds4_agent.c:16725-16783` and **already tolerates unknown string/int/bool
  keys**, with a test asserting exactly that (`ds4_agent.c:11935`).
- **`agent_worker_effective_ctx_size`** (`ds4_agent.c:545-549`) already reads
  live session ctx first, and compaction thresholds, tool-result fit checks, and
  `status.ctx_size` already route through it — so per-worker ctx is threading,
  not redesign.
- **`SamplingPolicy.think`** exists in Swift (`HandoffPacket.swift:44-51`),
  written by `Decompose.build`, validated, asserted in tests — and **read by
  nothing at dispatch time**. ROADMAP.md:452 calls this a "capture-integrity
  lie."

## Binding rules (authoritative; not re-openable in this spec)

1. **The wire announces itself** (BRIEF.md binding rule 7). A new capability is
   advertised in `hello`'s `caps`, and a consumer never silently degrades.
2. **Recapture on every submodule bump that changes engine code** (`REBASING.md:7-14`).
   P23 touches an emitter, so **a golden recapture is owed** — see D9.
3. **Admission before teardown.** Nothing kills a working session for a target
   that has not been admitted (P22's rule, inherited by any context change).
4. **Every new test must be shown to fail** when the behavior it pins is broken
   (BRIEF.md rule 2).
5. **A refusal test has a sibling success test** (BRIEF.md rule 4).

## Scope (strict)

**In.**

- Per-turn think control on the agent wire (`none` | `high` | `max`), no restart.
- A think **budget** as a standing guardrail against runaway reasoning.
- Per-worker context size for subagent-pool workers.
- Laguna XS's KV anchor correction and context-ceiling raise.
- Fork-ledger row **#14**, one golden recapture, submodule reconciliation.

**Out** (each with a reopen condition, recorded in the ROADMAP backlog).

- **The toolless half of the "quick reply."** See D5 — the mechanism is
  unverified and the obvious implementation is actively harmful. Reopens when
  the ban-token approach is verified against `agent_dsml_parser`.
- Pool-protocol cancel (ROADMAP.md:496); speculative/greedy decoding
  (ROADMAP.md:671); warm-prefix routing (D11 — decide before the recapture);
  host-side tool-execution profiling.

## Design decisions

**D1 — Two legs, two different justifications; do not conflate them.** The
per-worker-context leg is the **speed** leg (4.2× prefill ceiling, ~6.15 GB →
~1.5 GB scratch per worker). The think leg is a **correctness and
responsiveness** leg. Measured ceiling for think control is **≤9.3% of session
wall-clock** (36% of generated tokens are think; generation is 25.9% of the
session). The "11× more on reasoning than answering" figure that motivated this
phase in `2026-08-26-evidence-report.md:62` **counts stream deltas, not tokens**
— the character ratio is 0.91×. That number must not be repeated.

**D2 — The per-turn override rides the existing `{"t":"prompt"}` envelope.** No
new framing. `PoolPrompt` gains optional fields; the engine's existing
unknown-key tolerance means an old engine ignores them — which is exactly why D3
is mandatory rather than optional.

**D3 — Advertise a capability; gate the *send*, not the startup.** The engine
advertises `"think"` in `hello`'s `caps` when the feature is compiled in and
enabled. The app sends a think override **only when the cap is present**, and
otherwise does not offer `/quick`. **The cap does NOT join
`AgentWireParser.requiredCaps`.** Rationale: `requiredCaps` governs what the app
must be able to *parse* to read the wire safely; refusing startup on an older
engine would break `DS4_DIR`-pointed builds for an *outbound* optional feature.
This satisfies rule 7 — the app never sends a field the engine has not claimed
to understand, so there is no silent degradation. A new
`AgentWireParser.optionalCaps` surface records what was advertised.

**D4 — Refuse the per-turn override on prefix-busting model families.** On
**Laguna the think mode contributes zero tokens to the system prompt**
(`agent_worker_build_system_tokens`, `ds4_agent.c:6237-6251` — the GLM branch is
skipped by tool syntax, the MAX branch by `!ds4_engine_is_laguna`). The only
think-dependent emission is one token in the assistant prefix
(`ds4.c:39521-39542`), at the tail, inside the suffix re-prefilled every turn.
**A per-turn think flip on Laguna costs exactly one token and invalidates zero
cached prefix.** On **GLM** the reasoning-effort text is a system message at the
front, so a flip fails the `sysprompt.kv` text `memcmp` (`ds4_agent.c:6051-6058`)
and forces a full system re-prefill *and* a cache overwrite on every flip;
**DeepSeek V4** has the same problem for MAX↔anything. The engine therefore
**refuses the override loudly for those families** rather than silently paying
the cost.

**D5 — "Toolless" is deferred, and the obvious implementation is wrong.** Tool
schemas sit at the front of the transcript inside `sysprompt.kv`
(`ds4_agent.c:1424-1652`, injected once at worker init). **Dropping them for one
turn busts the prefix in both directions** — a full re-prefill on the quick turn
and another on the next normal turn. The non-busting approach is *suppression*:
keep the schemas and ban the tool-entry token for the turn, reusing the mechanism
`--think-budget` already uses (`ds4_agent.c:14366`). That requires confirming the
Laguna tool-call opener is a single bannable token (`agent_dsml_parser`,
`ds4_agent.c:2297+`) — **unverified**, so it is out of scope. `/quick` in P23
means **no-think**, not toolless. The ROADMAP row's wording is corrected
accordingly.

**D6 — Budget and mode are different jobs.** Probe A showed the budget caps
thinking **20×** (13,438 → 655 chars) but that **neither arm converged**, and
the capped arm took *more* rounds (11 vs 7) while shifting output from think to
text. A budget set too tight converts reasoning into rambling — a worse trade,
since text tokens enter the transcript too. Therefore: **the budget is a
generous standing guardrail against runaway** (default 2,048, i.e. it fires only
on a genuine loop), and **`/quick` is the explicit per-turn choice**
(think=none). Neither substitutes for the other.

**D7 — Fix XS's KV anchor before raising its ceiling.** `MemoryBudget.kvGiB(at:)`
(`Variant.swift:186-195`) extrapolates above 32,768 from the
`kvGiBAt32k → kvGiBAt40k` slope. XS declares **both as 1.31** — slope zero, so
KV is planned flat at any context above 32k. Extending each variant's own
16k→32k slope predicts its 40k anchor, and **three of four match to four
decimals**:

| Variant | 16k | 32k | 40k declared | implied | |
|---|---|---|---|---|---|
| Mellum | 0.26 | 0.48 | 0.59 | 0.5900 | exact ✓ |
| Laguna S | 0.8203125 | 1.5703125 | 1.9453125 | 1.9453 | exact ✓ |
| DeepSeek V4 Flash | 0.742351 | 1.117839 | 1.305583 | 1.3056 | exact ✓ |
| **Laguna XS** | 0.69 | 1.31 | **1.31** | **1.62** | **MISMATCH ✗** |

XS's anchor becomes **1.62**. Only then does `maxContext` rise. Unfixed, raising
the cap under-plans KV by 19% at 40k and ~35% at 51,200.

**D8 — Per-worker context defaults to 8,192, clamped 4,096…parent.** Laguna
scratch is `rows × ~375 KB` with `rows = min(ctx, 16384)`, so **scratch savings
begin only below 16,384**. 8,192 halves scratch (~3.1 GB vs ~6.15 GB) while
leaving a worker room to hold a bounded packet. The value is a setting; the
default is 8,192. The app clamps it through the same `MemoryBudget` arithmetic
the parent uses, so a worker context can never bypass admission.

**D9 — Fork-ledger row #14, and a golden recapture is owed.** The ROADMAP's
"#13" is stale — P22's SSD widening took that slot. A new `caps` entry lives in
`agent_emit_hello`, an **emitter**, on line 1 of all five committed fixtures.
Both no-recapture precedents turn on "no wire emission touched" (#12 changed
model input; #13 a pre-wire gate). **The P9 precedent is a warning**: the commit
adding the conditional `,"tool_request"` to this exact function dropped the
closing `"]"` and shipped invalid JSON past a green suite, *"the defect the
recapture caught"* (`fixtures/agent/provenance.md:68-83`). The recapture must
also be copied to `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}`
(`provenance.md:162-166`). While adding #14, close the ledger gap: `--think-budget`
(`1f9a4c5`) and the Mellum loader changes (`32bed2d`, `f56d0ca`) are in the pin
with no row.

**D10 — Submodule reconciliation is a precondition, not cleanup.** Divergences
**#12 and #13 are unpushed** (`git branch -r --contains` is empty for both), so
a fresh `git clone --recursive` cannot resolve the pin; and the pin sits on
`p20-dispatch-schema` while `.gitmodules` declares `swiftstar-integration`
(BRIEF.md:221-222: *"pins a SHA on this branch and only this branch"*). Running
`REBASING.md`'s procedure as written today would **silently drop #12 and #13**.
Adding #14 on top compounds an unrecoverable state.

**D11 — Decide warm-prefix routing before the recapture.** The engine already
calls `ds4_session_common_prefix` every round (`ds4_agent.c:14217`); the backlog
(ROADMAP.md:563-565) says exposing it is *"free engine-side; needs a wire
query."* Adding it later costs a **second** recapture. Default: **out of
scope**, but the decision is forced at **cycle 8**, before the recapture — not
deferred indefinitely.

**D12 — Thinking is prompt-induced; scope the claims accordingly.** Probe A:
same model, same `think=high`, **zero** think output on a bare prompt vs **80%**
think output with a reasoning-inducing `-sys`. `think=high` is permission, not a
command. Consequences: the 36% figure is a property of the agent's system prompt
and task; and **`swiftstar-agenttest` defaults to `noThink: true`**
(`main.swift:568`) while the app ships think=high — the harness has been
measuring a different configuration than the app runs, which the phase records
and fixes.

## Components

### 1. `Sources/SwiftStarKit/TurnThinkPolicy.swift` (new, pure)

The single decision authority. No I/O, no engine, fast-tier tested.

```
public enum ThinkEffort: String, Sendable { case none, high, max }

public enum TurnThinkDecision: Equatable, Sendable {
    case useDefault                       // send no override
    case override(ThinkEffort)
    case refused(reason: String)          // family cannot flip without a prefix bust
}

public struct TurnThinkPolicy {
    public static func decide(
        requested: ThinkEffort?,
        family: ModelFamily,
        capAdvertised: Bool
    ) -> TurnThinkDecision
}
```

Rules: `requested == nil` → `.useDefault`; `!capAdvertised` → `.useDefault`
(D3 — never send an unadvertised field); prefix-busting family (GLM, DeepSeek
for `.max`) → `.refused` (D4); otherwise `.override`.

### 2. `Sources/SwiftStarKit/PoolPrompt.swift` (extend)

Gains `think: ThinkEffort?` and `contextSize: Int?`, emitted into the same
sorted-keys object only when non-nil. The encoder stays the single authority for
the C patch and the fake. Absent field = engine default; **byte-identical output
to today when both are nil**, which is what keeps existing fixtures valid.

### 3. `Sources/SwiftStarKit/AgentWireParser.swift` (extend) + shared decoder

`hello` parsing records the advertised caps on a new `optionalCaps` surface so
`AgentController` can gate the send (D3). **Prerequisite refactor:** the
`status`/`ready` field decoding is duplicated between
`AgentWireParser.swift:73-124` and `WireEventParser.swift:72-116` — **45
code lines each, and after normalizing the enum name the diff is empty**
(verified 2026-08-28), and
that split has already shipped a live-path bug — `status.power`/`status.error`
were added to one and not the other, documented in both files
(`AgentWireParser.swift:108-116`, `WireEventParser.swift:26-29`). Extract one
shared decoder; **keep the two enums** (the sibling-not-extension argument at
`AgentWireParser.swift:62-66` is sound for the enums, not for the field list).

### 4. `Sources/SwiftStar/AgentController.swift` (extend, and split)

- `inject(_:row:think:)` threads the decision into the `PoolPrompt`.
- `drainQueuedWorkers` passes the per-worker context.
- `TurnOutcome` gains the effort actually used, retiring the hardcoded
  `sampler: "engine-defaults"` literal — currently wrong at **four** sites
  (`AgentController.swift:1098,783`; `PoolOrchestrator.swift:62,187`) plus
  `provenance.md` the moment P23 ships.
- **`AgentController.swift:438` must call `PoolEngine.argv`** instead of
  inlining the same expression. `PoolEngine.argv` is the designated seam,
  `PoolOrchestrator` uses it, and the app does not — so a new flag added there
  would silently never reach the app. Highest-risk duplication in the phase.
- **Extract the pool worker-turn loop** (`:753-990`, 238 lines, self-contained
  around `workerTurn`/`poolState`) out of a 1,397-line file with two `// MARK:`
  dividers and ≥10 responsibilities — *before* adding per-turn state to it.

### 5. `Sources/SwiftStarKit/CommandRouter.swift` (extend)

`/quick <prompt>` → `Command.quick(task:)`, routed in `AgentView.send()`. Pure,
fast-tier testable, zero new UI — the pattern `/chat` and `/orchestrate` already
established. **No composer control in P23** (that would be the first mode control
in a 460-line view).

### 6. `Sources/SwiftStarKit/VariantRegistry.swift` (fix)

XS `kvGiBAt40k` 1.31 → **1.62** (D7), then `maxContext` raised. Anchor
monotonicity becomes a registry-wide invariant (test 4 below).

### 7. Engine patch — `external/ds4/ds4_agent.c` (divergence #14)

| Region | Change |
|---|---|
| `agent_parse_pool_prompt` (`:16725-16783`) | recognize `think` and `ctx` keys |
| prompt queue (`:16994`, `agent_prompt_queue_push`) | entries are `char *` today and `take_all` concatenates them — must carry the per-turn override. **The largest structural item and the likeliest regression source.** |
| `worker_run_turn` (`:14129-14131`) | honor the override instead of `effective_think_mode(cfg)` alone |
| `agent_emit_hello` (`:5480-5497`) | advertise `"think"`, flag-gated |
| `parse_options` (`:885-890`, `:1039-1054`) | new flag + `--json-events` requirement gate |
| `agent_worker_init` (`:16475`, `:16488`) | per-worker `ctx_size` parameter |
| `agent_worker_init` (`:16513`) | **ctx-qualify `sysprompt_path`** — see below |
| `effective_think_mode` (`:1072-1073`) | use the worker's ctx, not `cfg`'s |

**The `sysprompt.kv` hazard, and why it is load-bearing.** All workers share one
fixed `sysprompt.kv` path, and the Laguna payload loader refuses a checkpoint
saved at a larger ctx (`ds4.c:56128-56136`: `saved_ctx > s->ctx_size` → error).
A mixed-ctx pool therefore thrashes — the parent writes at its ctx, the first
small worker's load fails, falls back to full prefill, and **overwrites the file
at the small ctx**. Worker init is serialized under `pool_mu` so there is no
write race, but the file's ctx identity is unstable. **Fix: `sysprompt-<ctx>.kv`.**

**Also required:** the JSON prompt envelope is gated on `pool_mode`
(`num_workers > 1`, `ds4_agent.c:16729`). Under `--subagent-pool 1` a JSON line
is fed to the model as literal text. The new flag must also enable JSON prompt
parsing at N=1, or the feature is silently broken in single-worker
configurations.

**Reference class:** divergence #12 was 78 lines, of which ~10 were behavior and
the rest signature threading plus one gated C unit test; #13 was 4 lines. Budget
**~150–250 lines** for think and **~40–80** for per-worker ctx (estimates).

## Cycles

Ordered speed-first, with refactors landing before the code that would duplicate
into them, and the one expensive step last.

| # | Cycle | Gate | Risk |
|---|---|---|---|
| **0** | ROADMAP truth (fold in the merged leg, renumber to #14, clear the stale blocker, fix `## Now`:15 and `README.md:17,25`); delete `ShellVocabulary` + test and `fixtures/server/` | fast tier green; grep proves zero refs | none |
| **0b** | **Precondition (D10):** push `p20-dispatch-schema`; reconcile `.gitmodules`; add the missing ledger rows | `git branch -r --contains` resolves #12 and #13 | none, **blocking** |
| **1** | **XS anchor fix, then ceiling raise (D7).** Zero engine work; the speed-first lever | registry-wide anchor-monotonicity test (**fails red first** — XS is flat today); `kvGiB`-vs-slope test; admission arithmetic at the new ceiling | low |
| **2** | Think **budget** as a standing guardrail (D6). Zero engine work | fast-tier argv test **+ a gated ~10 s integration test pinning the think-to-the-wall reproduction** | low |
| **2b** | *Measure only:* what the bootstrap + `DispatchPreferenceRule` `-sys` text costs in think tokens (D12) | one scripted A/B on Σsuffix; **no code** | none |
| **3** | Share the wire decoder (component 3) | every existing parser test unchanged; new test proves a field reaches **both** parsers | low, provable no-op |
| **4** | One argv builder; extract the pool loop (component 4) | existing tests unchanged; new test proves a `PoolEngine.argv` flag reaches the app spawn | low |
| **5** | Per-turn think, app side, cap-gated (components 1, 2, 5) | fast tier: policy matrix, encoding, routing, cap negotiation, `TurnOutcome` round-trip | low |
| **6** | **Engine patch #14** (component 7, think half) | gated C unit tests **including one that parses the `hello` JSON** (the P9 defect); ~1.5 s rebuild loop | **medium** |
| **7** | Per-worker context (component 7, ctx half; D8) incl. `sysprompt-<ctx>.kv` | C tests; memory assertion on `ready` (8k worker vs parent); Σsuffix A/B | **medium** |
| **8** | Recapture, ledger row #14, submodule bump. **Decide D11 first** | recapture green; `bundledFixtureMatchesRepoFixture` green | the phase's one expensive step |

## Tests (fast tier, no model)

1. **`TurnThinkPolicy` matrix** — every (`requested`, `family`, `capAdvertised`)
   combination, including both refusal families and the no-cap degradation.
   Refusal tests get sibling success tests (rule 5).
2. **`PoolPrompt` encoding** — byte-identical to today when both new fields are
   nil (this is what keeps existing fixtures valid); correct sorted-keys output
   when set.
3. **Shared wire decoder** — one test feeds a status line carrying every field
   and asserts **both** parsers surface all of them. This is the regression the
   `power`/`error` bug needed and never had.
4. **Registry anchor monotonicity** — for every variant, the 40k anchor equals
   its own 16k→32k slope extended by 8,192, within tolerance. **Must be shown
   failing on XS before the fix** (rule 4).
5. **Per-worker context clamp (D8)** — a worker context outside `[4096, parent]`
   is clamped, the default is 8,192, and the clamped value is what reaches argv.
6. **Argv seam** — a flag added to `PoolEngine.argv` appears in the app's spawn
   arguments.
7. **`CommandRouter`** — `/quick` parses, and `/quick` with no body is rejected.

## Integration tier (fake engines / real processes, seconds)

8. **Cap negotiation** — a fake engine advertising no `think` cap causes the app
   to send no override and to not offer `/quick`; one advertising it causes the
   field to appear on stdin.
9. **Think-to-the-wall reproduction (~10 s, gated)** — the probe-A configuration,
   asserting the unbounded arm exceeds a context-fraction threshold and the
   budgeted arm does not. **This is the phase's cheapest regression guard and it
   replaces a 695 s agentclinic run.**

## Live validation (closure evidence)

- A `/quick` turn on the real engine: the wire carries the override, the trace
  reports `think=none`, the transcript records the effort, **and the next normal
  turn shows no system-prompt re-prefill** (D4's one-token claim, checked rather
  than asserted).
- A refused override on a prefix-busting family, session untouched (rule 3).
- A pool worker spawned at 8,192 while the parent runs larger: `ready`'s
  memory-plan fields differ as predicted, and `sysprompt-<ctx>.kv` shows two
  files rather than one thrashed file.
- Σsuffix A/B via `swiftstar-analyze diff` on a **fixed scripted turn sequence** —
  not an agentclinic eval, whose outcome is seed-dependent (P20's closure
  verdict) and which cannot resolve a 9% effect.

## Out of scope

The toolless half of the quick reply (D5); pool-protocol cancel; speculative /
greedy decoding; warm-prefix routing (D11 — decide, do not drift);
host-side tool-execution profiling; the 17 untested `AGENTTEST_*` variables; the
`AgentDefaultSettings` hardcoded developer path. Each stays recorded in the
ROADMAP backlog with its reopen condition.

## Note on status

House convention stamps a spec `implemented` on ship. Four recent specs (P19.1,
P20, P22 model-switching, P25) are still stamped `proposed` for shipped work;
this spec should not become the fifth.
