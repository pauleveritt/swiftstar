# P23 pre-brainstorming research — wire-level control

**2026-08-28.** Research only: no design approved, no code written. Six parallel
investigations across the pinned engine, the app's seam plumbing, the fork-ledger
process, the repo's speed thesis, the test apparatus, and a fossil audit. Every
number below is cited to where it was read or measured; **measured** and
**assumed** are labelled separately throughout.

The short version: **the ROADMAP row describes about half of P23, sells it on a
metric that does not survive recounting, and books it against a fork-ledger row
that is already taken.** The phase underneath is real, cheaper than expected in
its engine work, and more valuable in the leg the row omits.

---

## 1. Five corrections to the ROADMAP before planning starts

| # | ROADMAP says | Actually |
|---|---|---|
| 1 | P23 = "per-turn think on the agent wire" ([ROADMAP.md:227](../../../ROADMAP.md)) | Small-ctx workers were **merged into P23** on 2026-08-27 — recorded at [ROADMAP.md:389](../../../ROADMAP.md) and again in P24's row at :228, but **never folded into the P23 row itself**. The row describes half the phase. |
| 2 | The merged patch is "fork-ledger row #13" (:389) | **#13 is taken** by P22's SSD gate widening (:226). P23's row is **#14**. The slot is double-booked. |
| 3 | Small-ctx workers depend on "P22's XS golden recapture" (:389) | That **shipped 2026-08-28** (:226). The stated blocker is cleared and nothing says so. |
| 4 | "Additive engine patch" | Accurate as an intent, and `BRIEF.md:243-253` already warns this phrase is *"a goal, not a description, and pretending otherwise is a trap."* P23 patches `ds4_agent.c` in three high-churn regions. |
| 5 | `## Now` (:15) — "4b wants review" | P25 Cycle 4b shipped and closed; the row at :229 was fixed, the summary bullet at :15 was not. Residue from today's fix. |

Two more, outside P23 but read while planning: `README.md:17,25` still says
"Phases P0–P11 complete… see ROADMAP for what is next (P12)" — off by thirteen
phases; and four spec files (P19.1, P20, P22 model-switching, P25) are still
stamped `proposed` for work that shipped.

---

## 2. The engine already has think control. This is plumbing, not capability.

The single most useful finding, and it reframes the phase.

**Three-valued think mode is a first-class engine primitive**, not something P23
invents: `DS4_THINK_NONE / DS4_THINK_HIGH / DS4_THINK_MAX` (`ds4.h:107-110`),
with a public API (`ds4.h:444-449`) and a context-aware downgrade
(`ds4_think_mode_for_context` demotes MAX→HIGH below ctx 393,216,
`ds4.c:53348-53374`).

**The agent already has the flags**, process-scoped: `--think` / `--think-max` /
`--nothink` (`ds4_agent.c:885-890`) and `--think-budget N` — a per-round
thinking ceiling that forces `</think>` and then bans reopening for the rest of
the round (`ds4_agent.c:14312-14366`). Default is `DS4_THINK_HIGH`
(`ds4_agent.c:788`).

**`ds4-server` already implements exactly the per-request semantics P23 wants.**
`parse_reasoning_effort_name/value` (`ds4_server.c:860-889`) maps
`low|medium|high|xhigh → HIGH`, `max → MAX`, unknown → reject; and
`parse_chat_template_kwargs` (`:1163-1183`) honours llama.cpp's
`{"enable_thinking": false}`. Four request parsers converge on one call. **The
agent simply never got the same treatment.**

**The CLI already does runtime switching**, with the right guard: `/think`,
`/think-max`, `/nothink` mutate the mode mid-session (`ds4_cli.c:1647-1662`) and
`repl_chat_apply_think_prefix` invalidates the session **only when the rendered
prefix actually changed** (`ds4_cli.c:1384-1396`).

So P23 is not "add think control to the engine." It is **"port the server's
per-request semantics onto the agent wire, using the CLI's change-detection
guard."** Two working reference implementations already live in the same
repository as the code being patched.

> **Ledger gap found.** `--think-budget` (`1f9a4c5`) and the Mellum loader
> changes (`32bed2d`, `f56d0ca`) are in the pinned tree with **no fork-ledger
> row**. Verified: `git merge-base --is-ancestor 1f9a4c5 79b8590` = yes. The
> ledger's count of 13 understates the real divergence count. P23 should close
> this while adding #14.

---

## 3. The KV question, answered: on Laguna, a per-turn think flip costs one token

This was the design's biggest risk going in — a think toggle that busts the
cached prompt prefix every turn would be a performance disaster, the exact
opposite of the phase's goal. It was worth checking and the answer is decisive.

**The sysprompt cache key is `(model_id, quant_bits, exact rendered
system-prompt text)`** — an exact `memcmp` on the rendered text
(`ds4_agent.c:6051-6058`), plus model and quant header checks (`:6040-6049`).
`ctx_size` is written into the header (`:6199`) but never compared there.

**`agent_worker_build_system_tokens` consults think mode in exactly two
branches** (`ds4_agent.c:6237-6251`), and **both are skipped for Laguna**: the
first is gated on GLM tool syntax, the second is explicitly guarded by
`!ds4_engine_is_laguna(...)`.

Therefore, per family:

| Family | Think flip busts the cached prefix? | Cost |
|---|---|---|
| **Laguna** (S, XS — SwiftStar's line) | **No** | **One token.** The only think-dependent emission is in `ds4_chat_append_assistant_prefix` (`ds4.c:39521-39542`), which pushes `think_start_id` vs `think_end_id` at the **tail**, inside the suffix that is re-prefilled every turn anyway. |
| Mellum | No (system prompt); a 5-token empty think block, suffix-only | ~5 tokens |
| **GLM** | **Yes, catastrophically** | `"Reasoning Effort: High"` is a **system message at the front** (`ds4.c:39105-39112`). Flipping the mode changes the first message → `memcmp` fails → full system re-prefill *and* an overwrite of `sysprompt.kv`, every flip. |
| DeepSeek V4 | Yes for MAX↔anything (`ds4.c:379-384`); no for HIGH↔NONE | — |

**This is the strongest technical argument for P23 and it is written down
nowhere.** On the model line SwiftStar actually ships, per-turn think control is
free of KV cost.

**The corollary is a design constraint, not a nicety.** A "toolless fast turn"
implemented by *dropping the tool schemas* would bust the prefix — the schemas
sit at the very front of the transcript inside `sysprompt.kv`
(`ds4_agent.c:1424-1652`, injected once at worker init via
`agent_worker_reset_to_sysprompt`). Dropping them for one turn means a full
re-prefill, then another on the next normal turn. **A toolless turn must be
built by suppression, not removal** — banning the tool-entry token for the turn,
reusing the exact mechanism `--think-budget` already uses at
`ds4_agent.c:14366`. *(Unverified: whether the Laguna tool-call opener is a
single bannable token. Check `agent_dsml_parser` before committing.)*

---

## 4. The speed case, honestly: think control is weak, small-ctx workers are strong

You said you want to impact execution and make things faster. This section is
the one that should change the plan, so it is deliberately blunt.

### The metric that motivated the phase does not survive recounting

`2026-08-26-evidence-report.md:62` names P23's justification as *"the
1,232-think-events budget split"*, from
`2026-08-26-spike-shell-on-findings.md:35-37`: *"think 1,232 events vs text 107
— think=high spent ~11× more on reasoning than on answering."*

**That counts stream deltas, not tokens.** Recounted on the production capture
(`captures/live/20260827-200648/`): the same event-count ratio is 2.2×, while
the **character** ratio is **0.91× — think is smaller than text.**

### What think actually costs, measured on the production capture

Segmenting the generated-token stream on the `</think>` control token:

- **8,394 generated tokens** across 120 rounds; **3,024 (36.0%) are think
  tokens** — ~25 per round.

Wall-clock decomposition from the wire's `status` transitions (total 1,666.5 s):

| State | Seconds | Share |
|---|---:|---:|
| **prefill** | 764.3 | **45.9%** |
| generating | 431.1 | 25.9% |
| idle (user reading/typing) | 297.5 | 17.8% |
| compacting | 173.6 | 10.4% |

**A perfect no-think mode saves at most ~36% × 431 s ≈ 155 s ≈ 9.3% of session
wall-clock** — and only if the model needs no extra rounds without reasoning.
Prefill, which P24 attacks, is **4.9× larger**.

Second-order effect is real but small: think tokens are never stripped from the
transcript (`ds4_agent.c:13948` pushes every token), so they deepen context and
pull the compaction cliff closer — but 3,024 tokens is **2.1% of Σsuffix
(144,631)**.

**Verdict: think control is a UX and correctness lever, not a throughput lever.
It should not be sold as one.** In the taxonomy: it is (a) fewer generated
tokens only. Not smaller prefill, not less KV pressure, and it may *increase*
round-trips if the model reasons worse without thinking.

### Small-ctx workers is where the measured speed is

- **4.2× upper bound**, from P11's own integration of the measured prefill
  curve: one 131,072-token prefill costs **2,121 s**; 8 × 16,384 run
  sequentially cost **500 s** — with zero concurrency required, which matters
  because Metal batch eval excludes Laguna unconditionally, so pool workers are
  serialized anyway. *The P11 doc's own caveat stands: this prices two context
  shapes, not one task done two ways.*
- **Memory: a 4k worker is ~1.7 GB, not ~8.7 GB** (ROADMAP.md:384). Laguna KV is
  exactly `49,152 × ctx + 75,497,472` bytes; scratch sums to ~375 KB/row with
  `rows = min(ctx, 16384)`, i.e. **~6.15 GB for any ctx ≥ 16,384, but ~1.5 GB at
  4k**.
- **Today every pool worker runs at the full parent ctx.**
  `ds4_agent.c:16488` — `ds4_session_create(&w->session, engine, cfg->gen.ctx_size)`
  for every worker, no override. In the production capture, worker 1 answered a
  consult **in 18 tokens** while holding a full 32,768-ctx session.

**And the patch is small**, because the session layer is already per-worker and
already ctx-parameterized: `agent_worker_effective_ctx_size` (`:545-549`)
already reads live session ctx first, and everything downstream (compaction
thresholds, tool-result fit checks, `status.ctx_size`) already routes through
it. Estimated **40–80 lines**.

**One real hazard turns this from trivial to non-trivial.** All workers share one
`sysprompt.kv` path (`ds4_agent.c:16513`, a fixed filename), and the Laguna
payload loader refuses a checkpoint saved at a larger ctx (`ds4.c:56128-56136`,
`saved_ctx > s->ctx_size` → error). A mixed-ctx pool therefore thrashes: the big
parent writes the file at its ctx, the first small worker's load fails, falls
back to full prefill, and **overwrites the file at the small ctx**. Worker init
is serialized under `pool_mu`, so there is no write race — but the file's ctx
identity is unstable. **Fix direction: ctx-qualify the path (`sysprompt-<ctx>.kv`).**

---

## 5. The strongest argument for think control is correctness

P20's own closure verdict records the failure: an unseeded run **think-looped to
the 8,192-token limit with 0 tool calls** — a completely lost turn. That is a
reliability defect, and it is what a think *budget* exists to bound.

Two more correctness items P23 retires:

- **`packet.sampling.think` is filed dead wiring.** `SamplingPolicy(think:)`
  exists in Swift (`HandoffPacket.swift:44-51`), is written by `Decompose.build`,
  is validated, and is asserted in tests — and **nothing at dispatch time reads
  it**. `swiftstar-agenttest` derives think from `AGENTTEST_THINK` instead,
  bypassing the packet's declared intent. ROADMAP.md:452 calls this a
  *"capture-integrity lie"* and says *"real per-worker think control needs new
  machinery."* That machinery is P23.
- **`sampler: "engine-defaults"` is hardcoded at four sites**
  (`AgentController.swift:1098,783`; `PoolOrchestrator.swift:62,187`) plus
  `provenance.md`, with a doc comment asserting the app passes no sampler flags.
  **The moment P23 ships, that literal is false at every site.**

---

## 6. Cost: the patch is cheap, the recapture is the bill

**Reference class**, measured across all 13 divergences: an additive,
flag-gated `ds4_agent.c` divergence is **4–200 lines, median ≈80**, in 1–3
submodule commits plus one ledger row. Divergence #12 (the `dispatch` schema) is
the closest structural analogue at **78 lines, of which roughly 10 are behavior**
— the rest is signature threading and one gated C unit test. Divergence #13 is
literally **4 lines**.

**Budget P23's engine patch at ~150–250 lines for think + ~40–80 for
per-worker ctx** (estimates, not measurements — three touch regions instead of
#12's one).

**Engine rebuild is not a scheduling consideration.** Measured on this machine,
compiling to scratch: `ds4_agent.c` (17,569 lines) in **1.39 s**, link in
0.07 s. **~1.5 s incremental** for a `ds4_agent.c`-only change; ~15 s cold.

**Golden recapture IS owed. This is the phase's one expensive step.**

The written rule (`REBASING.md:7-14`, mirrored in `fork-ledger.md:3-6` and
`Justfile:23-27`) carves out only docs-only bumps. The *practice* carve-out —
"wire-neutral divergence, no recapture" — was established at #12 and cited at
#13, and both turn on **no wire emission touched**: #12 changed model *input*
(the system prompt), #13 changed a pre-wire admission gate.

**P23 touches an emitter.** A new `caps` entry lives in `agent_emit_hello`
(`ds4_agent.c:5480-5497`), and the `hello` line is **line 1 of all five
committed fixtures**. Current state:

| Fixture | `caps` |
|---|---|
| `golden.ndjson`, `golden-tools.ndjson`, `golden-tools-xs.ndjson` | the base 7 |
| `tool-rounds.ndjson` | 7 + `tool_request` |
| `pool.ndjson` | 7 + `tool_request` + `pool` |

**The P9 precedent is a warning, not a permission.** `fixtures/agent/provenance.md:68-83`
records that the commit adding the conditional `,"tool_request"` to
`agent_emit_hello` **dropped the closing `"]"`, emitting invalid JSON — past a
green test suite, because no test parsed the `hello` JSON.** *"This is the defect
the recapture caught."* A conditionally-appended `caps` entry is the precise
edit class that has already broken this wire once, silently.

Recapture also carries a second, easily-missed obligation
(`fixtures/agent/provenance.md:162-166`): copy the result to
`Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` so
`FixtureReplayTests.bundledFixtureMatchesRepoFixture` stays green.

Scope depends on gating: a cap gated behind a **new flag** that no existing
capture passes changes **zero bytes** of the existing goldens — but P23 must
still capture one new fixture exercising the flag, exactly as #11 produced
`pool.ndjson` and #10 produced `tool-rounds.ndjson`.

---

## 7. Precondition: the submodule is in an unrecoverable local state

Found while researching the ledger process. **This blocks P23 and is not P23's
fault.**

1. **Divergences #12 and #13 are unpushed.** `git branch -r --contains 96286b3`
   and `--contains 849f375` both return **empty**. The parent gitlink points at
   commits that exist only in this machine's submodule clone. **A fresh
   `git clone --recursive` cannot resolve the pin.** `REBASING.md:47` step 6
   ("push") has not been run for P20 or P22.
2. **The pin is on the wrong branch.** `.gitmodules` declares
   `branch = swiftstar-integration`; `BRIEF.md:221-222` says *"the submodule
   pins a SHA on this branch and only this branch."* The pin (`79b8590`) is on
   `p20-dispatch-schema`, **301 commits ahead** of local `swiftstar-integration`.
   **Running `REBASING.md`'s rebase procedure as written today would silently
   drop #12 and #13.**
3. Upstream drift: the pin is 219 commits ahead of `upstream/main` and 51 behind;
   last fetch 2026-08-25. Nobody has rebased since P1.

Adding #14 on top compounds this. **Push the branch and reconcile
`.gitmodules` before the engine patch, not after.**

---

## 8. Fossils and refactors in the blast radius

The code is in better shape than the docs — P19's Chat retirement was thorough
(no `EngineController`, `SSEParser`, `ChatView`, `Supervisor`, `ServerCommand`
survive anywhere), P20's `orchestrateStub` is fully gone, and every P22
unification genuinely holds. **There is nothing to resurrect for "Chat's use case
surviving"; P23 builds on the agent wire from scratch.**

Four items are in P23's blast radius and worth fixing *inside* the phase:

1. **Two wire parsers with 44 of 45 identical decoding lines.**
   `AgentWireParser.swift:73-124` and `WireEventParser.swift:72-116` differ only
   in return type. **This split has already shipped a bug** — `status.power` and
   `status.error` were added to one parser and not the other and stayed broken on
   the live path for multiple phases; both files now carry comments documenting
   the incident (`AgentWireParser.swift:108-116`,
   `WireEventParser.swift:26-29`). The sibling-not-extension argument is sound
   for the **two enums**; it is not an argument for two copies of the **field
   decoding**. P23 is *wire-level control* — it will touch these decoders.
2. **`AgentController.swift:438` inlines what `PoolEngine.argv` exists to
   centralize.** `PoolEngine.argv` is the designated seam, `PoolOrchestrator`
   calls it, and **the app — the path that ships — does not.** A P23 flag added
   to `PoolEngine.argv` would silently never reach the app. Highest-risk
   duplication for this phase; one-line fix.
3. **Four `PoolPrompt` write sites** — `AgentController.swift:1105,787` and
   `PoolOrchestrator.swift:196,69`. A per-turn field must thread through all
   four or the app and the harness diverge on the wire.
4. **Three different `.ready` turn-end discriminators**
   (`AgentController.swift:584`; `PoolOrchestrator.swift:155,293`) — any change
   to `.ready`'s payload must be applied at all three.

**`AgentController.swift` is 1,397 lines with two `// MARK:` dividers and at
least ten responsibilities** — and P23 must edit it for spawn/argv, turn send,
wire consumption, turn outcome, *and* the pool loop. The pool worker-turn loop
(`:753-990`, 238 lines, self-contained around `workerTurn`/`poolState`) is the
clean extraction, and it is exactly the region small-ctx workers touches. **Split
before P23 adds per-turn think state, or it gets worse.**

Proven dead, cheap to remove: **`ShellVocabulary.swift`** (44 lines; zero
production consumers, zero uses of its 21 region ids as literals, zero
`accessibilityIdentifier` uses anywhere — a speculative registry with a test
suite that makes it look alive) and **`fixtures/server/`** (763 KB of SSE
captures whose parser no longer exists).

---

## 9. Testing: the loop is ~5 seconds, and nothing here needs a 3-hour run

**Measured just now: the fast tier is 746 tests in 106 suites in 0.050 s
(3.04 s wall including an incremental build).** Combined with the **~1.5 s**
engine rebuild, **the P23 inner loop is about five seconds end to end.**

Why it is that fast, and how to stay inside it:

- **The house pattern is pure decision function + fast-tier test + thin wiring.**
  `ModelSwitchEvaluator`, `PoolScheduler`, `CommandRouter`,
  `ToolCallbackResponder`, `PoolPrompt` are all pure and separately tested. P23's
  logic — which think mode a turn gets, which ctx a worker gets, whether the cap
  permits the override — is all expressible this way.
- **Two enforcement layers keep slow tests out.** `FastTierGuard`
  (`Package.swift:55`) fails the build on `Process(`, `URLSession`,
  `posix_spawn`, `socket(` in fast-tier sources; and `SwiftStarKit` itself
  contains **zero** spawn primitives, so the obvious bypass is closed. All 27
  integration files carry the `SWIFTSTAR_INTEGRATION` gate — **no leaks**.
- **The engine has its own C unit tests** (`make -C external/ds4 test`), and #12's
  template included a gated C test for exactly this kind of change. A ~1.5 s
  rebuild plus a C unit test is a complete engine-side loop.
- **`FakeAgentSource` validates argv byte-exactly** (`:83-89`, `:286-292`). Any
  new flag breaks every integration fake-agent test until fixtures update —
  that is a *feature*, a free conformance check.
- **`swiftstar-analyze diff` already exists** and prints **Σsuffix** for A and B
  plus a ratio, with the honest reason in its own source
  (`swiftstar-analyze/main.swift:214-215`): *"the only additively meaningful
  trace metric is Σsuffix (Σprompt is cumulative + double-counts)."* Confirmed on
  the production capture: Σcached/Σprompt = 92.1%, which looks like a cache-hit
  rate and is not one.

**Therefore the evidence plan is:** everything except **one golden recapture**
and **one short scripted A/B** lives in the five-second loop. The A/B should be a
**fixed scripted turn sequence** measured on Σsuffix + wall-clock — *not* an
agentclinic eval, whose outcome is seed-dependent (P20's closure verdict says so
explicitly) and which costs ~695 s per run for a binary score that cannot resolve
a 9% effect.

**Cost table for the kinds of evidence available:**

| Evidence | Cost |
|---|---|
| Fast-tier suite (746 tests) | **0.05 s** (3 s with build) |
| Engine rebuild, `ds4_agent.c` only | **~1.5 s** |
| Engine C unit tests | seconds |
| Integration tier (fake engines, real processes) | seconds–minutes |
| `swiftstar-drive` golden recapture | minutes–~25 min |
| agentclinic eval run | ~695 s, seed-dependent |

---

## 10. Fresh ideas the phase should consider

Each is grounded in something read in this codebase, not invented.

1. **Ship `--think-budget` first — it needs zero engine work.** The flag exists
   end-to-end today: `AgentSettings.thinkBudget` → `AgentCommand.argv:101-103` →
   engine enforcement at `ds4_agent.c:14344-14366`. **The app never sets it.** It
   bounds the observed 8,192-token think-loop *without amputating reasoning the
   way `--nothink` does*, and it is measurable with the apparatus that already
   exists. This is a strictly cheaper first increment than the wire patch.
2. **Expose `ds4_session_common_prefix` as a wire query — same patch surface, one
   extra event.** The engine already calls it every round
   (`ds4_agent.c:14217`); the backlog (ROADMAP.md:563-565) says it is *"free
   engine-side; needs a wire query"* and calls it warm-prefix routing — the
   cheapest pool-routing speed lever available. Since P23 is opening the wire
   anyway, this is nearly free to add and expensive to add later (another
   recapture).
3. **The XS 32,768 ceiling is doing damage the docs blame on context depth
   generally.** `VariantRegistry.swift:114` caps XS at 32,768 while the app
   default is 51,200. The 1809 capture's five compactions in 24 minutes — which
   *manufactured* the repeated 1,809-token tails that are 37.5% of Σsuffix — are
   a property of running XS as the *main* agent. The spike run at ctx 51,200 saw
   **no compaction at 42k**. Pairing XS as the *worker* and a larger-ctx variant
   as the parent removes that cliff with **no new code**. Arguably the cheapest
   speed action available today, and it is on no list.
4. **Speculative decoding is implemented and switched off by a sampler default.**
   `ds4_session_eval_speculative_argmax` runs at `ds4_agent.c:14415-14425` (up
   to 16 draft tokens), gated on `temperature <= 0.0f`; Laguna's default is 0.7
   (`ds4.c:63348-63352`) and **the app exposes no `--temp` at all**. The DFlash
   draft head was live-loaded and generated a turn on 2026-08-28. ROADMAP.md:671
   declines it on the behavioural ground that it forces greedy decoding — a fair
   objection, but it makes **greedy itself a measurable knob** with the
   paired-bill tool already built. *Flag as a candidate; do not scope into P23.*
5. **Nobody has profiled the host half of the round-trip.** 297.5 s (17.8%) of
   the production capture is "idle" while the host executed 118 tool requests.
   No backlog entry exists. *Measurement, not a P23 deliverable.*
6. **Compaction is under-budgeted in its own backlog entry.** ROADMAP.md:595
   sizes deterministic compaction as *"payoff is real but small (fires roughly
   once per full context)"* — that predates the 1809 capture, where it fired
   **five times in 24 minutes and cost 173.6 s (10.4%) of pure generation.** The
   entry's reopen condition fired; its *sizing* should be revised upward too.
7. **Rule out tool-schema trimming.** The whole system prompt + tool schema is
   only **1,179 tokens** (the capture's first sync is `prompt=1179 cached=0`).
   There is a ~1.2k-token ceiling here; not worth chasing.

---

## 11. Probe results (run 2026-08-28, before the spec)

Two pre-spec probes were approved. **Probe B was answered statically — better
than a live run would have, and it found a latent bug that guards against its
own proposal.** Probe A was run live against the real engine.

### Probe B — the XS context ceiling. Answered; do not raise the cap yet.

**The cap is a memory-tier choice, not a model limit.** Read directly from the
GGUF header: `laguna.context_length = 262144`, `rope.scaling.type = yarn`,
`factor 32.0`, `original_context_length 8192`. The registry's
`maxContext: 32_768` ([VariantRegistry.swift:114](../../../Sources/SwiftStarKit/VariantRegistry.swift))
carries its own provenance in the comment above it — *"Measured on 32 GB M1 Pro
(mini-notes §8); 6.53 GiB @32k."* **On a 128 GiB machine XS is running at 1/8 of
the context the model supports, because of a budget sized for a 16/32 GB
target** — and that cap is what manufactured the compaction cliff behind 37.5%
of the 1809 capture's Σsuffix.

**But raising it today would silently under-plan memory.** `MemoryBudget.kvGiB(at:)`
([Variant.swift:186-195](../../../Sources/SwiftStarKit/Variant.swift)) extrapolates
above 32,768 from the `kvGiBAt32k → kvGiBAt40k` slope. XS's two anchors are
**both 1.31** — the slope is **zero**, so KV would be planned as flat 1.31 GiB at
*any* context above 32k. Every other variant is strictly increasing, and S's are
exactly linear:

Extending each variant's own 16k→32k slope by 8,192 tokens predicts its 40k
anchor. **Three of four match to four decimals. XS is the sole outlier.**

| Variant | 16k | 32k | 40k declared | 40k implied by its own slope | |
|---|---|---|---|---|---|
| Mellum | 0.26 | 0.48 | 0.59 | 0.5900 | **exact** ✓ |
| Laguna S | 0.8203125 | 1.5703125 | 1.9453125 | 1.9453 | **exact** ✓ |
| DeepSeek V4 Flash | 0.742351 | 1.117839 | 1.305583 | 1.3056 | **exact** ✓ |
| **Laguna XS** | 0.69 | 1.31 | **1.31** | **1.62** | **MISMATCH ✗** |

The other three were clearly derived from a linear model; XS's 40k anchor is a
copy of its 32k value. By XS's own slope, `kvGiBAt40k` **should be 1.62**.
As written it under-plans KV by **19% at 40k** and **~35% at 51,200** (1.31
planned vs ~2.01 actual). The error is dormant *only* because `maxContext:
32_768` makes `kvGiB` return nil above the cap — and raising that cap is exactly
what this probe proposed. **Fix the anchor first; then raise the ceiling.** Both
belong in the phase.

### Probe A — the think budget. Flags work; thinking is prompt-induced, not flag-induced.

Run live against the real engine (XS, ctx 16,384, SSD streaming), ~10 s per arm.

**Flags verified working.** `--think` → `think=high` in the trace; `--nothink` →
`think=none`; `--think-budget N` accepted. Note two operational facts worth
recording: **none of the four think flags appear in `ds4-agent --help`** (the
engine does reject genuinely unknown flags loudly, so they are real, just
undocumented); and **the engine chdir's to `--workspace`**, so a relative
`--trace` path lands inside the workspace, not the cwd.

**The finding that matters:**

| Configuration | Think output | Text output |
|---|---|---|
| `--think` (think=high), **no system prompt**, bare arithmetic question | **0 chars / 0 events** | 352 tokens, all text |
| `--think` (think=high), **reasoning-inducing `-sys`**, multi-step problem | **13,438 chars / 1,498 events (80%)** | 3,376 chars |
| Production capture (agent `-sys` + tools, think=high) | 14,298 chars / 757 events | 15,706 chars |

**`think=high` is permission to think, not a command.** The same model, same
flag, produced zero thinking on one prompt and 80%-thinking on another. **The
36%-of-generated-tokens think cost measured in the production capture is a
property of the agent's system prompt and task, not of the think flag.**

**The budget works mechanically — and the unbounded arm reproduced P20's
think-to-the-wall failure in ten seconds.** Same model, same prompt, same
system prompt, ctx 16,384:

| Arm | Rounds | Think chars | Text chars | Peak `ctx_used` |
|---|---|---|---|---|
| `--think` (unbounded) | 7 | **13,438** | 3,376 | **15,873 / 16,384 — 97%, hit the wall** |
| `--think --think-budget 64` | 11 *(killed by me, still running)* | **655** | 2,076 | 8,188 / 16,384 |

Two conclusions, one firm and one deliberately not:

- **Firm (mechanism, which is what this probe pre-registered):** the budget caps
  thinking — a **20× reduction** in think characters, 1,498 think events down to
  38. `--think-budget` does what its documentation claims.
- **Firm, and unexpectedly valuable:** the unbounded arm **filled 97% of its
  context with reasoning and never answered** — the exact failure P20's closure
  verdict recorded ("think-looped to the 8192-token limit with 0 tools") and the
  strongest correctness argument for the phase. **It reproduces in ~10 seconds on
  a bare engine.** That means the failure P23 exists to fix can be a gated
  integration test, not a 695 s agentclinic run — see §9's cost table.
- **Explicitly NOT claimed:** that the budget improves outcomes. **Neither arm
  converged**, and the capped arm took *more* rounds (11 vs 7) while shifting
  output from think to text. That is a real design risk — a budget set too tight
  may convert reasoning into rambling, which is a worse trade, since text tokens
  enter the transcript too *and* the answer degrades. But this is **n=1 on one
  deliberately hard prompt with no seed**, and the pre-registration forbids a
  success claim from it. **Design against the risk; do not conclude it.**

Consequences for the plan:

1. **Cycle 2's lever is narrower than it looked.** A think *budget* only bites
   where the prompt already induces long thinking. It is still the right fix for
   the observed 8,192-token think-loop — that is precisely a runaway — but it
   will be a no-op on most turns, and should be described that way.
2. **The system prompt is a think lever nobody has pulled.** If thinking is
   induced by `-sys`, then the bootstrap + `DispatchPreferenceRule` text the app
   appends at spawn is part of the think cost. That is a **zero-engine-work,
   zero-wire-change** lever that is not in P23's scope and probably should be
   measured before the engine patch is written.
3. **`swiftstar-agenttest` defaults to `noThink: true`**
   ([main.swift:568](../../../Sources/swiftstar-agenttest/main.swift)) while the
   app ships think=high. **The harness has been measuring a different
   configuration than the app runs** — worth knowing before any harness-derived
   think evidence is cited.

**Pre-registered and honoured: this probe measured mechanism only, not task
success.** n=2 cannot resolve success on this apparatus — P17 and `/goal` v5
already established a byte-identical prompt at a fixed seed swinging 2/3 → 0/3
between runs. No success claim is made or implied here.

---

## 12. Proposed phase shape

**Framing the phase honestly:** P23 is *two* legs with different justifications.
Selling both as "faster" would repeat the 11× mistake.

> **P23 — Wire-level control.** Per-turn think and per-worker context on the
> agent wire. The think leg buys **correctness and responsiveness** (bounds the
> observed think-loop-to-the-wall failure; delivers the glossary's "fast reply";
> retires the inert `packet.sampling` wiring) at **one token of prompt
> divergence on Laguna**. The per-worker-context leg buys **measured speed and
> memory** (4.2× prefill upper bound; ~1.7 GB vs ~8.7 GB per worker). One engine
> patch, fork-ledger row **#14**, one golden recapture.

Cycles, ordered so that value ships early, refactors land before the code that
would duplicate into them, and the one expensive step is last.

| # | Cycle | Change | Gate | Risk |
|---|---|---|---|---|
| **0** | **Truth and dead weight** | Fold small-ctx workers into the P23 row; renumber the ledger slot to #14; note the XS blocker cleared; fix `## Now`:15 and `README.md:17,25`. Delete `ShellVocabulary` + test and `fixtures/server/`. | Fast tier green; grep proves zero refs | none |
| **0b** | **Unblock the submodule** *(precondition)* | Push `p20-dispatch-schema`; reconcile `.gitmodules` vs the pinned branch; add ledger rows for `--think-budget` and the Mellum loader changes. | `git branch -r --contains` resolves #12 and #13 | none, but **blocking** |
| **1** | **Fix XS's KV anchor, then raise its ceiling** *(probe B)* | `kvGiBAt40k` 1.31 → **1.62** (the variant's own 16k→32k slope), *then* raise `maxContext` above 32,768 on the memory the machine actually has. **Zero engine work.** The cheapest real speed action available: it removes the compaction cliff behind 37.5% of the 1809 capture's Σsuffix. | Fast-tier: an anchor-monotonicity test across **all** variants (XS is flat today, so this test fails red first); a `kvGiB`-vs-slope test; admission arithmetic at the new ceiling | low — **the speed-first lever, and it ships without touching the engine** |
| **2** | **Bound the think-loop with the flag that already exists** | App sets `AgentSettings.thinkBudget` from a real setting. **Zero engine work.** Scope it honestly per probe A: this bites runaways, not ordinary turns — and the budget value must be **tuned against the convert-thinking-into-rambling risk**, not just set. | Fast-tier argv test; **plus a gated ~10 s integration test pinning the think-to-the-wall reproduction** (probe A's unbounded arm hit 97% ctx) — the phase's cheapest regression guard | low |
| **2b** | *(measure, don't build)* **The system prompt as a think lever** | Probe A showed thinking is induced by `-sys`, not the flag. Measure what the bootstrap + `DispatchPreferenceRule` text costs in think tokens before the engine patch is written. | One scripted A/B on Σsuffix; **no code** | none — may retire part of the think leg |
| **2** | **Share the wire decoder** | Extract the identical `status`/`ready` decoding behind one decoder; keep both enums. | Every existing parser test passes **unchanged**; new test proves a field reaches **both** parsers | low, provable no-op |
| **3** | **One argv builder, one prompt writer** | `AgentController:438` → `PoolEngine.argv`; collapse the four `PoolPrompt` write sites. Extract the pool worker-turn loop out of `AgentController`. | Existing tests unchanged; new test proves a flag added to `PoolEngine.argv` reaches the app spawn | low |
| **4** | **Per-turn think, app side, cap-gated** | `PoolPrompt` gains `think:`; `/quick` in `CommandRouter`; `TurnOutcome` records the effort actually used (retiring the `"engine-defaults"` literal). **The app sends the field only when `hello` advertises the cap** — so this is safe before the engine patch and never degrades silently. | Fast-tier: encoding, routing, cap-negotiation, `TurnOutcome` codable round-trip against an existing capture | low |
| **5** | **The engine patch: per-turn think + the cap** | Parse `think` in `agent_parse_pool_prompt`; thread the override into `worker_run_turn`; advertise the cap in `agent_emit_hello`, flag-gated. Refuse the override for GLM / DeepSeek-MAX (prefix-busting families). Handle the `pool_mode` gate so JSON prompts parse at N=1. | Gated C unit tests incl. **a test that parses the `hello` JSON** (the P9 defect); ~1.5 s rebuild loop | **medium** — three high-churn regions |
| **6** | **Per-worker context (the speed leg)** | `--subagent-ctx N`; thread into `agent_worker_init`; **ctx-qualify `sysprompt_path`**; make `effective_think_mode` use the worker's ctx. App-side clamp so it cannot bypass admission arithmetic. | C tests; memory assertion (4k worker vs full on `ready`); Σsuffix A/B | **medium** — the shared `sysprompt.kv` is what makes this non-trivial |
| **7** | **Recapture, ledger row #14, bump** | New fixture exercising the flag; copy to bundled resources; ledger row; submodule bump. | Recapture green; `bundledFixtureMatchesRepoFixture` green | the phase's one expensive step (minutes–~25 min) |
| **8** | *(optional)* **Warm-prefix routing query** | Expose `ds4_session_common_prefix` as a wire event — same surface, one extra event, avoids a second recapture later. | C test + parser test | low, but **decide before cycle 7** |

**Explicitly out of scope**, recorded so they are deferred rather than forgotten:
pool-protocol cancel (ROADMAP.md:496), speculative/greedy decoding
(ROADMAP.md:671), the XS-ceiling pairing (idea 3 — a zero-code experiment worth
running *before* the phase, not inside it), and host-side tool-execution
profiling.

---

## 13. Open questions for the design

1. **Does the new cap join `AgentWireParser.requiredCaps`?** Rule 7 says a
   consumer refuses a mismatch loudly; adding it there makes the app **refuse
   every older engine build**, which breaks `DS4_DIR`-pointed binaries. The
   cap-gated send in cycle 4 is the alternative — advertise-and-degrade rather
   than refuse. **Leaning: gate the *send*, not the *startup*** — refusing to
   launch on an older engine is a bigger harm than silently not offering a
   quick-reply mode.
2. **Should the toolless half ship at all in P23?** The KV analysis says it must
   be built by token-banning, not schema removal — and that mechanism is
   unverified (is the Laguna tool-call opener a single bannable token?). It may
   be cleaner to ship *think* control in P23 and let *toolless* follow, since
   the ROADMAP row bundles them but the engine does not.
3. **What ctx do small workers get?** 4k is the number the memory arithmetic
   quotes; 16,384 is where scratch stops shrinking (`rows = min(ctx, 16384)`).
   Below 16k the scratch saving is real; above it there is none. **Leaning 8k or
   16k**, pending one measurement.
4. **Is `/quick` the right surface, or a composer control?** `/chat` and
   `/orchestrate` are the existing per-turn mode selectors and are pure,
   fast-tier-tested, and zero new UI. A composer toggle would be the first mode
   control in a 460-line view. **Leaning `/quick` first.**
5. **Does cycle 1 alone satisfy the phase's correctness goal?** If a think
   *budget* bounds the think-loop adequately, the per-turn *mode* leg is
   justified by responsiveness alone — worth knowing before paying for the
   engine patch.
