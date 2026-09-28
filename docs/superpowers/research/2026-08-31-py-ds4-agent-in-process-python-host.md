# `py-ds4-agent`: an in-process Python host for ds4

Research note, brainstormed 2026-08-31, revised the same day after a
hard-evidence audit of the C engine's global state: a proposed
**`py-ds4-agent`** — a long-running Python peer process that hosts the ds4
engine **in-process** via a CPython C extension over the existing
`external/ds4/ds4.h` boundary, and speaks the existing NDJSON wire outward to
SwiftStar. The Swift UI still talks to it out-of-process, exactly as it talks
to `ds4-agent` today. A separate companion ACP client/bridge would be a plain
NDJSON client of `py-ds4-agent`, decoupling IDE integration from the core —
**ACP is explicitly out of scope for this note and not proposed as core
work.**

**Research, not design.** No phase spec is pre-empted here, and the phase
list is not reopened — this does not become a phase until D11 is revisited
deliberately (see "Risks," below). **Nothing in this note is measured.** The
economics it leans on (prefill is depth-scaled; KV reuse is exact-prefix-only;
the warm session serves 85–95% of every prompt from cache; the 7x prefill
degradation curve) are measured and already recorded in
`docs/harvest/telemetry-findings.md` and
`docs/superpowers/research/2026-08-26-heavy-session-telemetry-findings.md`.
The C engine's global-state findings in this revision **are** verified
against source, with citations, and are the one part of this note that is not
conjecture. Everything else specific to an in-process Python host is still
conjecture.

**Revision, 2026-08-31 (post-review): Rust first, Flash first.** The next
step is not a Python host. It is a bounded, single-threaded Rust experiment
over `ds4.h`, using **DeepSeek V4 Flash** as the control model. Flash is the
engine's mature DeepSeek4 implementation and, unlike Laguna and Mellum, is
eligible for the existing Metal session-batch path when its configuration
allows it (`ds4.c:67511-67544`). The spike exists to measure the mechanism —
project-derived constraints plus rollback — before making D11's Python-runtime
decision. It reuses SwiftStar's *workspace-isolation contract* (a disposable
worktree, per-file baselines, candidate-or-discard outcome), not a second,
unpaired model-state story. The proposed experiment below names the outcome
that decides whether either Rust productization or `py-ds4-agent` is worth
building.

## The spine: the fastest inference is the inference you don't do

Every capability below is organized around one reframe, supplied by the human
partner, and it is the note's organizing principle rather than a section:
**the metric is not tokens/second, it is accelerator work required to complete
the task correctly.** Frontier will usually retain a raw-speed advantage, but
how much computation a task *needs* is also an architecture property. A
stateful local host may be able to win on that axis; this note proposes to
measure it rather than assume it.

Every idea in this note is one of eight moves against that total:

- **Inference you don't redo.** Failure is not a quality concern competing
  with speed — it is the single largest source of wasted inference. A ~68%
  pooled success rate (`ROADMAP.md:244`) implies roughly 1.5 attempts per task
  only under independent, stationary attempts; real retries are correlated and
  must be measured. The second attempt can cost *more* than the first, not the
  same: at ~32k context, a repair round "carrying round 1's full injection
  *still resident in the session* plus a *second* full injection of updated
  contents and new failure output — is arithmetically impossible in most
  runs" (`2026-08-24-p12-4-repair-role-fable-review.md:82`). Constrain so
  failure is structurally unrepresentable; rewind rather than repair.
- **Prefill you don't repeat.** The measured 31 re-reads of one file costing
  37.5% of a session's entire Σsuffix
  (`2026-08-27-1809-prefill-tail-findings.md:29-33`) is a direct measurement
  of inference performed thirty times that needed doing once.
  `ds4_session_common_prefix` (`ds4.h:569`) is the primitive that answers "is
  this already in the live prefix."
- **Context you never admit.** The CAG note's two-costs finding is load-
  bearing here: recompute is cached (85–95%,
  `2026-08-26-heavy-session-telemetry-findings.md:51`), but the
  **attention-depth tail is saved by nothing** — it scales with total context
  regardless of how little is new
  (`2026-08-28-cag-and-the-librarian.md:71-88`). The only lever on it is
  exclusion. Pre-chewing context (a live object graph instead of a read file)
  is not an ergonomic nicety here; it is the primary speed lever, because
  nothing else touches this cost.
- **Inference replaced by computation.** Every deterministic answer deletes
  a stretch of generation outright. `apps.get_models()` supplies field names
  the model would otherwise have had to recall or guess; `makemigrations`
  writes the migration; `manage.py check` verifies it. Wrapping a tool is not
  ergonomics — each wrapper is inference that no longer has to happen.
- **Inference not at full depth.** The RLM pattern: splitting a 131k prefill
  into eight sequential 16k prefills is up to ~4.2x cheaper by the measured
  curve, with zero concurrency required
  (`ROADMAP.md:108-111`, `2026-08-22-p11-engine-constraints-and-corrections.md`).
- **Inference not at all.** The engine's `.kv` session files already store
  the full rendered conversation as plain UTF-8
  (`ROADMAP.md:481-482`, the `recall`-tool Backlog entry) — re-deriving a
  fact a past session already established is repeated inference paid by
  choice, not necessity.
- **Generation you stop.** The token-wall problem — filed as "the one P15
  item that is not host-addressable" (`ROADMAP.md:626`) — is inference that
  produces nothing usable and runs to completion anyway because nothing can
  cancel it mid-flight.
- **Tokens that don't lead to action.** Think-without-acting is the same
  category from the other direction: pathology #2, "correctly diagnosed a
  bug… then reasoned its way out of fixing it" (`docs/pathologies.md:13-15`),
  is generation that happened and then produced zero action.

**Why this compounds rather than just adding up.** The 7x prefill-depth
curve (`docs/harvest/telemetry-findings.md:16-22`) means every token *not*
admitted into context makes every subsequent token in that session cheaper,
because depth is the thing the curve is a function of. Savings on this axis
multiply against the curve; a faster GPU shifts the whole curve uniformly and
leaves its *shape* untouched. That asymmetry is why this is the axis worth
competing on rather than raw throughput.

**What a locally owned runtime uniquely exposes.** Hosted agents can retain
server-side state, cache prompts, retrieve history, checkpoint a workspace,
and run validation; none of those should be treated as structurally absent.
What their public interfaces normally do *not* expose is application-controlled
KV state and logits: a caller cannot rewind a model checkpoint, inspect its
live token prefix, or apply an exact per-token mask before sampling. That is
the narrower, defensible differentiator here. Everything below is either a
description of an elimination move or a finding about what limits it.

## Two drivers, both from the human partner

**(a) Get more value from the stateful agent.** Unlike an agent that talks to
an out-of-process inference server, ds4-agent already holds KV, session
state, and inference together in one place. The spine above is the sharpened
version of this question: what becomes reachable if a host can sit *inside*
that boundary and act on accelerator cost, not just tokens/sec?

**(b) Non-Swift, pro-Python — stated plainly as political/strategic, not
technical.** The human partner is part of Satyrn (satyrn.io), building
`satyrn-engine` and `satyrn-evals` in Python. **Satyrn compatibility is a
nice-to-have here, not a requirement — this note's scope is SwiftStar.** And
it should be recorded precisely what "compatibility" would even mean today:
`satyrn-engine`'s own README states, of itself, "Despite the name, it is not
an engine in the AI sense: no model, no inference, no server. It is ordinary
Python that runs anywhere Python runs"
(`~/projects/pauleveritt/satyrn-engine/README.md:19-20`). There is, in other
words, no existing Python inference layer on the Satyrn side for
`py-ds4-agent` to slot into — if this is ever built, it introduces the first
Python inference surface in either project, not a bridge to one that already
exists.

## The D1 reversal — the most important framing point

`BRIEF.md` D1 rejected embedding the engine, and did so deliberately and
adversarially — see
[`docs/superpowers/specs/2026-08-21-swiftstar-design.md`](../specs/2026-08-21-swiftstar-design.md)
at `### D1 — Engine integration: spawned child processes` (line 24) and the
full reasoning in
[`docs/harvest/swiftstar-md.md`](../../harvest/swiftstar-md.md). Both
documents state the objection to embedding at the same level of precision:
*embedding puts the engine inside the GUI process.* A Metal abort or a
wired-limit kill takes the app down with it against 46–52 GiB planned budgets
(`docs/harvest/swiftstar-md.md:41`); per-pid memory attribution — the thing
that made the original telemetry investigation possible — disappears; and
swapping models means restarting the whole app rather than a child
(`docs/harvest/swiftstar-md.md:44-45`, `BRIEF.md:152-154`).

Read literally, none of that is an objection to embedding *per se* — it is an
objection to embedding **in the GUI process specifically**. A separate
long-lived Python peer process is still a child process from the Swift app's
point of view: a crash in it does not take SwiftStar down, `top`/`ps` still
attributes its RAM separately, and a model swap restarts the Python peer, not
the app. Every protection D1 names survives. What changes is only what the
*Python* process itself can do, because it is no longer talking to the engine
across a pipe — it links `ds4.h` directly.

`docs/harvest/swiftstar-md.md:35-39` already concedes, "stated fairly," the
two capabilities that genuinely require embedding rather than an additive
C-side wire patch: **dynamic per-token host-defined logit masking** (a
vocabulary-sized round trip per token at 40–360 tok/s is a non-starter over a
pipe) and **zero-copy logits and embeddings access**. Both become reachable
to an in-process Python host for the same reason they were unreachable to
Swift: no pipe in the loop. This is exactly the condition the Backlog's "An
embedding spike" entry names as its reopen trigger — "only if dynamic
Swift-defined per-token logit masking becomes critical-path"
(`ROADMAP.md:713-715`) — except the mover here is a *second process*, not the
GUI, so the D1 tradeoff the Backlog entry assumes (embed = give up crash
isolation) does not actually apply to this shape.

**What is *not* new C surface.** `ds4.h` is a clean, narrow library boundary —
688 lines, and it says so about itself: "Keep this header narrow so HTTP/CLI
code does not depend on tensor internals" (`external/ds4/ds4.h:16-17`).
Confirmed three separate frontends already consume exactly this header as
three independent `main()` entry points: `ds4_agent.c` (18,320 lines,
`external/ds4/ds4_agent.c:18256`), `ds4_server.c` (18,440 lines,
`external/ds4/ds4_server.c:13373`), and `ds4_cli.c` (2,344 lines,
`external/ds4/ds4_cli.c:2175`). A `py-ds4-agent` CPython extension over
`ds4.h` is a **fourth consumer of an existing, already-multiply-consumed
boundary** — not a new capability carved into the engine. What *is* new,
squarely, is program logic that today lives only inside `ds4_agent.c`: DSML
tool-call parsing, the host-tools protocol, and the NDJSON emitter itself
would all need reimplementation in Python. That is real, non-trivial work
(see "Risks"). **The global-state audit below (§ "What one process can hold")
narrows this section further: the header is narrow, but the state behind it
is not, and that changes what "a fourth consumer" is actually allowed to do.**

## The central finding: the Backlog is blocked on access, not ideas

Reading the ROADMAP Backlog with this question in mind — "is this blocked on
a good idea, or on getting at a boundary?" — surfaces something more
concrete than a general architecture argument: **a large fraction of open
Backlog entries name the process boundary, or a not-yet-written engine patch,
as their stated blocker, and several of those name functions that already
exist in `ds4.h` today and simply have no wire representation.** By my own
count of the Backlog section (`ROADMAP.md:177-982`) — an approximate tally
from reading, not a machine-checked count — at least a dozen entries fall in
this category; the table below cites the clearest ones, each verified
against both the Backlog entry and the `ds4.h` signature it depends on. Read
against the spine above, nearly every row is a **"prefill you don't repeat"**
or **"inference you don't redo"** move that is already implemented in C and
simply has no wire.

**Correction, 2026-08-31 (post-review): access is not synonymous with
in-process access.** Most rows can also be reached with a narrow additive wire
command, or with a per-turn constraint automaton uploaded once to the existing
agent. A sandboxed Python subprocess can produce Django's symbol table without
sharing a process with inference. The experiment must therefore compare an
uploaded-constraint wire arm with the in-process Rust arm. Only a measured
advantage for the latter establishes that the peer host, rather than the
mechanism itself, is necessary. The genuinely in-process candidate is
arbitrary, latency-sensitive, per-token logit policy.

| Backlog entry | Stated blocker (ROADMAP.md) | Host-side resolution to test | Spine category |
|---|---|---|---|
| Generation-time stopping control (`:623-626`) — filed as "the one P15 item that is not host-addressable" | "the engine's pool protocol has no cancel, so a degenerate run pays to the token wall before the host can react" | a direct host-owned decode loop can stop between token steps; `ds4_session_set_cancel` protects sync/prefill boundaries | Generation you stop |
| Warm-prefix routing (`:463-476`, item 2 of "Context-economy tooling") | "still needs the `ds4_session_common_prefix` wire query" | `ds4_session_common_prefix` exists today, `ds4.h:569` | Prefill you don't repeat |
| Snapshot-before-risk, rewind-on-failure (`:557-569`) | "nothing in the codebase exercises `rewind`/`save_payload`/`load_snapshot` today" beyond a disk-swap use elsewhere | Flash supports the named primitives; position rewind, RAM snapshot, and disk payload need separate measurement, while Mellum is unsupported | Inference you don't redo |
| Per-worker think control (`:297-305`) — `AGENTTEST_REPAIR_THINK` is inert | "real per-worker think control needs new machinery (per-worker engine control, or a second engine)" | `think_mode` is already a per-call argument to `ds4_chat_append_assistant_prefix` (`ds4.h:506`) | Inference not at full depth |
| Small-ctx worker sessions / worker-2 ceiling (`:444-461`) | "needs engine + pool-wire work — its own small phase" | `ds4_session_create` already takes a per-session `ctx_size` (`ds4.h:528`) | Context you never admit |
| Deterministic compaction skeleton (`:506-523`) | "requires forking the compaction path in `ds4_agent.c`" | an alternate host loop avoids that particular C path, but must still own canonical transcript and tool-result semantics | Inference you don't redo |
| Compare-before-commit via shared-prefix forks (`:571-582`) | needs a cheap judge; explicitly **"not a concurrency win"** | the session primitives (snapshot/rewind) exist; this entry is honest that it buys answer quality, not wall-clock | Inference you don't redo |
| Multi-project residency (`:547-555`), a `recall` tool / session browser (`:478-504`), cross-session fact mining (`:609-619`), `.kv`/wire replay fixtures (`:598-607`), admission-control scheduler (`:584-596`) | various — mostly "host-side work, once the pool/wire exists" | ordinary host operations once a narrow API or wire command exists; no Python co-location required | Inference not at all / prefill you don't repeat |

Two entries deserve their own treatment because they are the sharpest and the
most recently reopened.

### Grammar-constrained tool calls

Reopened 2026-08-29, "the condition is met three times over"
(`ROADMAP.md:664-667`). Two distinct failure classes are named, and only one
of them is fixed by a grammar: **malformed names** (the model emits its own
system-prompt placeholder, `"name": "{function-name}"`) and **placement** — a
well-formed tool call emitted *inside* `<think>`. Placement is "not a syntax
error and a grammar over tool-call text will not catch it"
(`ROADMAP.md:678-679`), it is the more expensive and more common class (5 of
8 observed malformed calls, `ROADMAP.md:680`), and the engine's own corrective
nudge ("finish thinking before emitting `<tool_call>`") did not stop a model
from repeating the mistake — "so text feedback is not the remedy"
(`ROADMAP.md:685`).

In-process, placement is a solvable constraint rather than a text-level
correction, because both halves of the condition are already exposed on
`ds4.h`: whether the session is currently inside a think span
(`ds4_token_is_thinking_control`, `ds4.h:512`; `ds4_token_think_start` /
`ds4_token_think_end`, `ds4.h:516-517`) and the ability to hold and mask the
next-token distribution before sampling (`ds4_session_ban_token`, `ds4.h:575`;
raw logits via `ds4_session_copy_logits`, `ds4.h:589`). A host that can see
"we are inside `<think>`" and ban tool-call-opening tokens for exactly that
span makes the failure unrepresentable rather than correctable-after-the-fact
— an "inference you don't redo" move, since today's fix is a corrective nudge
that costs a whole extra turn when it works and a killed run when it doesn't.
This is precisely the "think-state-aware constraint" the Backlog entry asks
for (`ROADMAP.md:679`), with no grammar engine required. § "Constrained
decoding" below generalizes this same mechanism well past tool-call
placement.

### DFlash speculative decoding — a correction to my own first framing

The Backlog entry declines DFlash today because `--dflash` forces **greedy
decoding** for the whole session — "a behavior change to agent turns, not a
free speed knob" (`ROADMAP.md:696-697`). My first pass at this note proposed
that an in-process host could call `ds4_session_eval_speculative_argmax`
(`ds4.h:613`) *per region* — greedy-with-speculation for a rote lookup,
ordinary sampling for the rest of the same turn — and thereby dissolve the
Backlog entry's objection. **That framing does not survive checking the
source, and the follow-up audit below (§ "What one process can hold") kills
the fallback I proposed for it too — see § 8, Corrections.** `dflash_path`
and `mtp_path` are fields on `ds4_engine_options` (`ds4.h:210-211`), read
only once, inside `ds4_engine_open` (`external/ds4/ds4.c:62001-62530` reads
`opt->dflash_path`/`opt->mtp_path` exclusively during engine construction).
The draft model is loaded **per engine**, not per session and not per call —
`ds4_session_eval_speculative_argmax` is callable per session, but only
sessions on an engine that was opened with a draft model attached can use it
at all, and every session on that engine shares the same draft model. Being
in-process does not change this; the whole-session objection in the Backlog
entry is really a whole-*engine* objection.

## The named ideas the human asked about

### RLM — the strongest hit, and a genuine negative result to build on

A probe already exists at
`external/ds4/tests/orchestrator-eval/rlm/RESULTS.md` and returned a
negative: **"No configuration produced a correct answer"**
(`RESULTS.md:21`). It is worth being precise about scope: the probe ran five
model configurations (`grpo`/`instruct`/`Thinking`, think on and off) through
an OpenAI-compatible endpoint against a bounded six-hop Python-REPL loop over
a 475-line document — it is not a probe of Laguna or Mellum specifically, and
its `RESULTS.md` does not name which underlying checkpoints those
configuration labels map to. The generalizing finding does not depend on
that detail: **"A false stop signal is worse than no stop signal"**
(`RESULTS.md:38`) — a confidently wrong termination propagates upward as
though verified, while a missing termination at least fails loudly against
the hop cap. This is a "generation you stop" failure read backwards: the
probe's loop *didn't* stop when it should have, which cost the same class of
wasted inference as a token wall that never gets cancelled.

That is a **calibration** failure, and calibration is exactly what
`ds4_session_top_logprobs` (`ds4.h:587`) and `ds4_session_token_logprob`
(`ds4.h:588`) measure. Today nothing reads them for this purpose: they
appear zero times in `external/ds4/docs/json-events.md` (grepped directly —
no `logprob` field is on the wire at all), and their one live call site,
`ds4_agent.c:14646`, uses `ds4_session_top_logprobs` for a narrower and
unrelated job — repairing a malformed structural token by scanning ranked
candidates for one that keeps the tagged grammar viable, not for exposing
confidence to a host. Gating fold-back on the terminating span's confidence —
refusing to trust a `FINAL:` answer whose top-logprob margin is thin — is a
legitimate, cheap, and previously wire-unreachable attack on the documented
reason this probe's RLM loop failed. **Do not overclaim: entropy is not a
hallucination oracle**, and nothing here has measured whether low-confidence
correlates with the *specific* failure the probe found (fabricated synthesis)
rather than with ordinary sampling noise. § "Constrained decoding" below adds
a second, related calibration signal — mask-rejection rate — that is cheaper
than reading raw logprobs because the mask is already computed for other
reasons.

Both stated RLM economic constraints from the Backlog are already exactly
`ds4.h` primitives: a sub-query session "must be a small-ctx *template kept
alive and rewound*, not a fresh allocation" (`ROADMAP.md:536-537`) is
`ds4_session_rewind` (`ds4.h:623`); "the shared preamble is repeated per
sub-query, so the win shrinks with preamble size" (`ROADMAP.md:538-539`) is a
pinned shared prefix, the same exact-prefix-only KV reuse the rest of the
project already leans on.

### Librarian / CAG — a reframe, not a rebuild

[`2026-08-28-cag-and-the-librarian.md`](2026-08-28-cag-and-the-librarian.md)
concludes CAG fits the librarian because it is the one component with a
bounded stable corpus and a warm session, and it explicitly assumes an
AFM/ANE backing model. In-process, a librarian does not need AFM at all: it
could be **a small-ctx ds4 session on the same engine, with a pinned stable
prefix and truncate-to-reset** — which is exactly `ds4_session_rewind`
(`ds4.h:623`), i.e. CAG's own "reset." **This is now a genuine choice, not a
forced one — see the AFM reversal immediately below**, which retires the
objection that made this reframe necessary in the first place. Either shape
sidesteps CAG's still-unmeasured falsifier 3 (the ANE's unmeasured
attention-depth crossover), because a ds4-session librarian runs on the same
GPU engine whose depth curve is already measured.

More concretely: the CAG note's proposed `kv_query(selector)` — described as
"the librarian's entire edge layer," the narrow host function standing
between the librarian and the main session's live state
(`2026-08-28-cag-and-the-librarian.md:53,118`) — **does not exist today**. I
read the whole of `ds4.h` and confirmed no such symbol exists on the wire or
in the header. In-process it becomes reachable as a real, if narrow,
function: `ds4_session_tokens` (`ds4.h:631`) returns `const ds4_tokens *` —
the session's token-id sequence. That is worth being precise about too: it is
the *rendered token sequence*, not the raw attention/KV tensor state, so
"query the session" in this shape means "read what was said," not "read the
model's internal representation." A `kv_query(selector)` built on top of it
would be a deterministic search over token text, the same substrate the
Backlog's `recall` tool and session browser already lean on
(`ROADMAP.md:478-504`), not a new class of introspection. **§ "What one
process can hold" below is the reason this stays a *deterministic Rust
function*, not a general-purpose read: `read_kv(path)` must remain absent by
construction, not merely discouraged.**

Critically, the CAG note's central architectural claim — **"the process gap
is the feature"** (`2026-08-28-cag-and-the-librarian.md:103`, borrowed from
the Monty note) — survives this reframe intact. That argument is about
*authority*: the host does the reduction because it holds the authoritative
state, and a watcher that reached in directly would be re-deriving with less
information. A Python host projecting a digest slice into a sandboxed
executor (Monty, or any bounded interpreter) preserves that exactly — the
argument was never about which process is doing the projecting, only that
projection happens on the side that holds the truth.

### Monty — gets easier, and the identity question in the note it comes from is unchanged

Monty is pydantic's Rust interpreter for a Python subset
(`2026-08-23-monty-and-the-ane-watcher-tier.md`); a Python host is its native
neighborhood, not a Swift-to-Rust FFI problem. That note already reopens
"the 'Swift body, Python brain' Backlog entry with a better shape" while
naming the cost plainly: it "does change the identity from 'no Python runtime
role' to 'sandboxed Python-subset execution is a first-class runtime
capability' — a decision to make deliberately, not to let slide past D11"
(`2026-08-23-monty-and-the-ane-watcher-tier.md:233-237`). `py-ds4-agent` is a
second, larger instance of the same identity question, not a new one — see
"Risks."

### The AFM reversal — a risk retired, with real caveats kept

My first pass recorded the ANE watcher tier "moving further away" under a
Python host, on the grounds that `FoundationModels` is a Swift-only
framework. **The human partner reports the AFM team is shipping a Python
extension in macOS 27. That objection is retired.**

If it ships as described, it changes the librarian/inspector question above
from "AFM forces Swift, so a Python host and the ANE tier pull in different
directions" to a strict improvement: **the ANE tier and the GPU tier could
live in one host process**, instead of needing Swift to bridge both — no
cross-language handoff between "the model that watches" and "the model that
does the work," and one process for the CAG note's stable-layer caching
discipline to live in rather than two.

Two caveats must travel with this and not get dropped the next time this
note is quoted:

1. **It is an unshipped forward dependency on macOS 27.** Nothing about it is
   verifiable today the way `LanguageModelSession` on macOS 26 was
   independently confirmed in
   [`2026-08-30-foundation-models-latency.md`](2026-08-30-foundation-models-latency.md).
   Treat it exactly as unmeasured as everything else in this note, with the
   added property that it cannot even be probed yet.
2. **The Monty note's own warning stands verbatim**: "'AFM only' is a bet on
   an API that may move" (`2026-08-23-monty-and-the-ane-watcher-tier.md:270-272`)
   — the naming already shifted once, CoreML to CoreAI across one OS release,
   before settling on the public `FoundationModels` name confirmed in
   `ROADMAP.md:867-874`. A second shift, to a Python-extension shape, is the
   same class of churn recurring, not a settled fact to build on.

Falsifier 2 from the Monty note — the fill-success rate, does a primed hole
type-check and run first time — remains unmeasured regardless of which
language hosts it.

### Inspector — the negative case, unchanged

The inspector is near-synchronous, inside the tool loop: budget is "the fill
+ `ty` + execute must complete *within* the tool's execution window"
(`2026-08-23-monty-and-the-ane-watcher-tier.md:93-94`), and CAG's lesson for
it is explicitly negative — "don't try to preload a standing context for it"
(`2026-08-28-cag-and-the-librarian.md:130-138`). An extra host hop does not
help a latency-bounded, stateless-per-call role; if anything, a Python host
adds one more process boundary between the tool call and the answer versus
doing it in the same Swift process that owns the tool loop. State this as
negative space: nothing about `py-ds4-agent` improves the inspector case, and
a design that put the inspector through it would be adding latency to buy
nothing.

## Constrained decoding as dynamic semantic terminals

This is bigger than the existing "grammar-constrained tool calls" Backlog
entry, and the note should say why: what a live-introspection host enables is
not "check the syntax is right," it is a **new class of terminal** in the
grammar sense — one whose valid-token set is not fixed in a `.gbnf` file but
drawn from the live object graph of the project being edited.

**Mechanics.** BPE means you cannot simply "ban invalid field names" — you
ban *token sequences*, so this needs a prefix trie over the valid identifier
set plus position awareness: the constraint only applies where an identifier
is expected, never in free prose. That is ordinary grammar-constrained-
decoding machinery, but with a **dynamic terminal set drawn from live
introspection** instead of a static one authored in advance. The distinction
worth stating precisely: a static grammar says *"a string goes here"*; only
the live object graph says *"one of these fourteen strings goes here."*
Syntax versus semantics. **Position detection is the hard part, not the
vocabulary** — tractable inside a structured tool-call parameter (the DSML
parser already knows it is inside a `path` or a field-name argument), not
inside free-form prose where "is this an identifier reference" is itself
ambiguous.

**Implementation correction, 2026-08-31.** The current public primitive,
`ds4_session_ban_token`, bans only one token for the *next* sample; a trie
needs an allowed-set mask at every constrained position, not a loop that
bans a vocabulary complement one FFI call at a time. Flash can support a
Rust spike through copy/mask/set logits, but a product-grade path likely needs
one narrow C-side mask/allowed-set hook. This is not evidence that Python must
be in-process: a static-for-the-turn trie can be compiled by a sandboxed
introspection process and uploaded to the existing agent once. The Rust arm
tests the remaining case — a genuinely dynamic per-token policy — against
that uploaded-automaton control.

**Three honest limits, stated as limits and not as reasons to abandon it:**

1. **It kills fabrication, not wrongness.** `created_at` when the correct
   field was `updated_at` sails through the mask untouched, because both are
   real fields. This closes one failure *class* — hallucinated identifiers —
   not an error rate.
2. **It can manufacture confident wrong answers.** If the correct response to
   "add a field to Complaint" is "that field doesn't exist yet, you need a
   migration first," a mask restricted to existing fields makes that answer
   unsayable — the model is structurally forced to pick from what exists,
   even when the right move is to say nothing exists yet. This is the RLM
   "a false stop signal is worse than no stop signal" finding
   (`RESULTS.md:38`) wearing a different costume, and it needs a deliberate
   escape hatch (an explicit "none of the above / needs a new field" token
   left unmasked) or it trades one confident-wrong-answer failure mode for
   another.
3. **Renormalizing a heavily masked distribution can degrade output** when
   most of the model's probability mass was on now-banned tokens — the
   remaining distribution the sampler draws from may be a poor one even
   though every option in it is individually valid.

**The payoff that comes directly out of limit 3 — a first-class new idea:
mask-rejection rate may be a calibration signal.** If satisfying the
constraint requires stripping the overwhelming majority of probability mass,
the model's un-constrained guess and the actually-valid answer barely
overlapped — i.e., the model didn't really know. That is a signal to rewind
and retry under a different policy rather than force a low-probability token
through. It is not free: it needs normalization of the original and masked
distributions, with the sampling policy (temperature and truncation) stated
precisely. Nor is it calibrated merely by existing; it varies with the size
of the allowed set and needs a measured risk-coverage curve. It may still be
better targeted than raw entropy or top-logprob margin (§ RLM, above), because
it measures disagreement with the live object graph rather than only the
model's own uncertainty.

**Connect this back to the spine.** The constraint *substitutes for context*:
if field names are enforced at the sampler, less of `models.py` may need to be
read merely to avoid a fabricated field. Relations, types, validators, local
conventions, and task intent still need evidence; this is a reduction in
context, not a substitute for understanding. The reduction is nevertheless
valuable because it removes tokens at the most expensive place there is —
depth, per the attention-depth-tail finding above.

**It generalizes past Django.** Nothing about this is Django-specific:
SQLAlchemy models, Pydantic schemas, FastAPI route names, or simply the
project's own AST for names currently in scope are all live object graphs a
Python host can introspect the same way. Django is the best-fit example in
this note — an enumerable vocabulary plus a fast deterministic oracle plus a
predictable file set, see the Django section below — not the only one where
this mechanism applies.

## Genuinely new ideas judged feasible

1. **Counterfactual evals.** `ds4_sample_logits` and `ds4_session_sample`
   both take a caller-owned `uint64_t *rng` (`ds4.h:576-578`). Paired with
   snapshot/rewind, a host can rewind to token N and re-run the *same*
   prefix under a different sampling policy from bit-identical KV state.
   Contrast with the eval-CLI design's ABBA-pairs-plus-shared-seed approach
   (below), which pins the seed but still concedes "the arms differ in
   system prompt and schema by construction, so their token streams diverge
   from position 0 and the shared seed pairs nothing… the deltas are mostly
   trajectory noise, seed or no seed"
   (`.worktrees/eval-cli/docs/superpowers/specs/2026-08-30-eval-cli-design.md:202-207`,
   branch-only, see below). A shared-prefix counterfactual removes that
   noise structurally, because both arms literally start from the same
   tokens and the same KV — not merely the same seed. This changes what is
   *measurable*, not what is true; it does not itself validate any policy.
2. **Speculative tool-call preflight.** Snapshot → emit the call → check it
   parses and its paths exist → if not, rewind and re-sample with the
   offending tokens banned (`ds4_session_ban_token`, `ds4.h:575`). This kills
   the `[invalid tool call]` failure class the grammar-constrained-tool-calls
   entry is chasing, with no grammar engine — a cheaper attack on the same
   problem than the placement fix above, for the malformed-*name* half of it.
3. **Middle-eviction compaction.** Exact-prefix-only KV reuse blocks dropping
   a stale result from the *middle* of context without rebuilding everything
   after it. `ds4_session_common_prefix` (`ds4.h:569`) plus
   `ds4_session_rewrite_from_common` (`ds4.h:566-568`) name the desired
   boundary, but **do not implement it yet**: the current implementation
   reports `DS4_SESSION_REWRITE_REBUILD_NEEDED` for a replaced live suffix.
   Middle eviction is therefore a future engine change, not an exposed
   in-process capability; it is out of the Rust spike.

**Correction, 2026-08-31 (post-review):** preflight detects an invalid
sequence; it does not, by banning one token, make every resample valid. It
still needs a sequence-aware grammar/trie or a bounded retry policy. The
existing one-token-next-sample API is useful for the narrow think-placement
case, not a replacement for general grammar machinery.

Selective speculative decoding (my originally-proposed idea 4) is retired —
see § 8, Corrections, and the DFlash section above.

## The Django / routine-work thesis

The human partner asked a sharper question than "what becomes possible":
could `py-ds4-agent`, on 32 GB, with a reasonable 16 GB story, be competitive
or faster than frontier agents on routine work — Django, specifically?

**Lead with the honest crux, restated against the spine: speed is not the
gap here, accelerator work to a verified-correct change is.** Mellum's editing
rate is contested, not settled — P17's clean 15/17 read "does not replicate
on new data" (`ROADMAP.md:48`, citing
[`2026-08-29-block-b-negative-result-analysis.md`](2026-08-29-block-b-negative-result-analysis.md)),
and the corrected pooled figure is "real editing rate ~68% pooled"
(`ROADMAP.md:244`). `/orchestrate` measured 93% [78%, 98%] on one task
(`roadmap`, `ROADMAP.md:721-722`) and 67% [35%, 88%] on a second
(`roadmap-user-story`, `ROADMAP.md:746`), filed explicitly as "signal, not
confirmation; still open" (`ROADMAP.md:720`). Under the old framing, a high
failure rate was a competing concern next to speed. Under the spine, it
*is* the speed number: every failed attempt is inference performed and
discarded, and per the repair-round citation above, the discarded inference
on a retry costs *more* than the original attempt, not the same. The thesis
this section tests, stated precisely: *the architecture converts local's
structural latency advantage into affordable verification, and eliminating
wasted inference — not raw speed — is what would close the quality gap, if
it closes it at all.*

**The structural advantage is real and separately measured.** Hosted
frontier agents are stateless clients: every turn re-sends the conversation,
and prompt caching (where it exists at all) is prefix-only and TTL'd.
ds4-agent is genuinely stateful — the KV *is* the session, measured at 85–95%
of every round's prompt served from cache in a warm session
(`2026-08-26-heavy-session-telemetry-findings.md:51`). Routine work is many
short turns, exactly the regime where per-turn fixed overhead (re-sending
context a stateful session never has to re-send) dominates. **Do not
overclaim raw throughput**: decode is likely same order of magnitude either
way, the engine is serialized — one generating session at a time, on one
GPU — and Laguna is excluded from the engine's batched Metal decode path
outright (`docs/harvest/swiftstar-md.md:23`, `ROADMAP.md:100-105`). The
claim that survives is "comparable throughput per attempt," and the actual
win this section argues for is per **verified** attempt, not per token.

**Why Django specifically.** Three properties line up with what this
architecture is actually good at: (1) an enumerable vocabulary — model
names, field types, `related_name`s, URL names, settings keys, migration
naming — is exactly the shape the constrained-decoding mechanism above
targets well; (2) a fast, deterministic oracle already exists in the
ecosystem (`manage.py check`, `makemigrations --check --dry-run`, ruff, a
type checker, targeted tests); (3) a bounded, predictable file set per change
(model → migration → serializer → view → URL → test), which matters
specifically because the measured prefill-depth curve makes shallow context
the whole game: 231→114 tok/s from 12k→30k ctx (`ROADMAP.md:586`, composited
from the two live captures above), and — the same session's own reported
prose, flagged rather than silently trusted, because its own table does not
show this exact pairing — "prefill time roughly doubled (2,044 → 11,557 ms)"
for the same ~1,700–1,900-token suffix as context filled
(`2026-08-26-heavy-session-telemetry-findings.md:44-46`). **This number needs
its own flag**: the source document's own table two lines above it tops out
at 9,741 ms, not 11,557 ms, for the same session
(`2026-08-26-heavy-session-telemetry-findings.md:38-43`). I did not find a
reconciling source elsewhere. Treat "2,044 → 11,557 ms" as a real figure
carried faithfully from its stated source, and treat its consistency with
that source's own table as unverified — the qualitative point (prefill cost
scales steeply with depth for a fixed suffix) is independently supported by
the 231→114 tok/s curve and does not depend on this specific pairing.

**Python tooling, not a Python-host-only superpower.** `django.setup()` plus
`apps.get_models()` gives a live object graph — exact field names,
`related_name`s, URL resolvers, settings — as an executable symbol table,
not a grep index. Feeding that into the constrained-decoding mechanism above
means the model structurally cannot emit a field name that does not exist.
The Backlog's `scout` tool (folded into P24's direction, `ROADMAP.md:55`)
approximates this deterministically from static text; live introspection is
the exact version. It can run in a sandboxed subprocess and return a finite
symbol table to either the existing agent or the Rust spike; it need not share
a process with the inference engine. **Caveat that must be priced, not waved
past**: importing user code runs its
`settings.py` and can touch a real database at import time — this wants
either a sandboxed subprocess for the introspection step, or an AST-only
fallback that trades exactness for safety. Nothing here has designed that
boundary.

**The economic hypothesis — not yet a competitive claim.** Hosted agents also
run tests and preserve workspace state; the local advantage to test is
application-controlled KV/logit state combined with inexpensive local
validation. A failed attempt is not automatically cheap: an in-memory snapshot
serializes the live KV to host memory, and a disk payload adds I/O. A retry also
needs an intentional changed condition — a different seed, a stronger dynamic
constraint, or compact external validation evidence — rather than replaying the
same KV and RNG state.

The proposed loop is therefore paired state management: checkpoint model state
*and* create a disposable worktree → generate under project-derived constraints
→ validate in that worktree → on failure discard it and rewind or restore the
model state → retry under a stated changed policy → surface only an accepted
candidate. SwiftStar already has the file-state half in P10's
`WorktreeDispatcher` / `WorktreeTransaction`; the Rust spike reuses that
candidate-or-discard contract rather than pretending that a KV rewind reverts
files. The question is whether this paired loop lowers accelerator-seconds to a
verified result, not whether it can make a retry count look good.

**32 GB.** Laguna XS 2.1 is measured at 6.53 GiB planned / 6.46 GiB task
footprint (`ROADMAP.md:641-642`) — real headroom on 32 GB. But each Laguna
session pins its own ~6.1 GB of GPU scratch for the session's lifetime
(`BRIEF.md:158-159`), so "spin up sessions freely" is the wrong mental model;
the right one is one engine, few sessions, and a kept-alive small-ctx
template that is *rewound*, not reallocated, between uses — the same lever
the Backlog already prices: "a 4k worker is ~1.7 GB, not ~8.7 GB"
(`ROADMAP.md:448-449`). **Finding E below (§ "What one process can hold")
softens this further for the specific case of multiple same-shaped sessions
on one engine: the ~6.1 GB prefill-scratch figure is paid once per engine,
not once per session, when the engine opts into
`share_session_prefill_workspace` — see the correction to the Backlog's
multi-project-residency pricing there.**

**16 GB: genuinely unknown — flag, do not promise.** The Backlog is explicit:
"feasible, unconfirmed" — the clearing numbers "come from a 128 GB dev
machine, whose OS page cache hides SSD-miss throughput"
(`ROADMAP.md:644-646`). SSD streaming is the entire mechanism the 16 GB story
depends on, and page cache is exactly the thing a 16 GB machine does not have
in the same abundance. The committed target stays 32 GB. In-process access
adds *mitigations* here — snapshot idle state to disk, hold project context
hard, keep one rewound template instead of allocating fresh sessions — not an
answer; the deciding measurement has been owed since P22 and nothing in this
note resolves it.

**Experiment target, deliberately separate from the product rungs.** The
first experiment uses DeepSeek V4 Flash, whose mixed Q2–Q4 artifact has a
documented minimum need of 95.85 GiB at ctx 16,384
(`2026-08-27-p25-deepseek-v4-flash-variant-design.md:136`). It is therefore a
128-GB-class control experiment, not a 32-GB or 16-GB product promise. This
choice removes Mellum's unsupported snapshot/rewind behavior and Laguna's
unconditional batch exclusion from the first test. If the mechanism cannot
show value on this stable, feature-complete engine line, it has no evidentiary
case for the smaller rungs.

## What one process can hold: a global-state audit of the C engine

Everything above assumed a Python host inside the process boundary can hold
whatever it needs to. That assumption needed checking against the actual C,
not against `ds4.h`'s public signatures alone — a header can be narrow while
the state behind it is not. Three parallel audits of the engine's global
mutable state were run and cross-checked; the load-bearing findings below
were independently spot-checked against source for this revision (exact
line numbers corrected where the original audit's citation was off by a few
lines — noted inline). The rest of the audit's citations were not
independently re-verified here, per instruction, and are reported as given.

### Finding A — one engine per process, ever

`static ds4_shape g_ds4_shape` (`external/ds4/ds4.c:731`) holds the entire
model architecture — layer count, head dims, RoPE parameters, everything a
Laguna vs. a DeepSeek4 vs. a Mellum shape differs on. **46 macros** expand to
its fields (`ds4.c:775-820`, e.g. `DS4_N_LAYER` → `g_ds4_shape.n_layer`), and
by my own count those macro names occur roughly 5,400 times across `ds4.c`
(`grep -oE` over the 46 names, counted directly for this revision — higher
than the audit's original "2,237," which I could not reproduce with any
counting method I tried; both counts establish the same qualitative point,
pervasive dependence, so I am reporting my own reproducible number rather
than repeating one I could not verify). `config_validate_model`
(`ds4.c:6545`) overwrites the whole struct per model family — confirmed at
each of the four family-specific assignment sites: `g_ds4_shape =
DS4_SHAPE_FLASH` (`ds4.c:6035`), `DS4_SHAPE_PRO` (`ds4.c:6046`),
`DS4_SHAPE_GLM52` (`ds4.c:6277`), and `DS4_SHAPE_LAGUNA_S21` /
`DS4_SHAPE_LAGUNA_XS21` / `DS4_SHAPE_MELLUM2` in the Laguna and Mellum
validators (`ds4.c:6348-6350`, `6461`). A second engine open on a different
model would silently reshape the first engine's arithmetic through this one
struct.

`ds4_engine_open_internal` calls `ds4_acquire_instance_lock()`
(`ds4.c:62028`, confirmed exact), which `flock(LOCK_EX | LOCK_NB)`s
`/tmp/ds4.lock` (or `$DS4_LOCK_FILE`) and calls **`exit(2)`** on conflict
(`ds4.c:53385-53425`; the specific `exit(2)` on a held lock is at
`ds4.c:53412`, not `:53406` as the original audit cited — verified directly,
correcting the line number while confirming the finding). `flock` locks
belong to the *open file description*, not the process: each call to
`ds4_acquire_instance_lock` performs its own fresh `open()` of the lock file,
so a second call **within the same process** produces a second, independent
open file description and collides with the first exactly as a second
process would. I did not independently rerun the audit's compiled Darwin
probe, but the behavior follows directly from POSIX `flock` semantics visible
in the source itself, not from the probe's say-so: the lock cannot
distinguish "another process" from "this process, a second time."

The authors know the global is dangerous: a test helper saves and restores
it around a probe —
```
uint64_t ds4_test_laguna_xs21_scratch_bytes(uint32_t prefill_cap) {
    const ds4_shape saved = g_ds4_shape;
    g_ds4_shape = DS4_SHAPE_LAGUNA_XS21;
    const uint64_t bytes = laguna_graph_scratch_bytes(prefill_cap);
    g_ds4_shape = saved;
    return bytes;
}
```
(`ds4.c:61732-61735`, confirmed verbatim and at the exact lines cited).

**Trap to record, and not to walk into: do not fix the flock first.** Fixing
only the instance lock converts a loud `exit(2)` into silent cross-engine
shape corruption via `g_ds4_shape` — worse, not better.

### Finding B — concurrent sessions are structurally impossible, not merely unsafe

`static ds4_thread_pool g_pool` (`ds4.c:1900`, confirmed exact) has exactly
one work slot. `ds4_parallel_for_min_rows` writes `g_pool.fn`, `g_pool.ctx`,
and `g_pool.n_rows` under its mutex (`ds4.c:2013-2015`; the original audit
cited `2013-2016`, one line generous — `n_rows` is the last field written at
`2015`) and then **releases the mutex** (`ds4.c:2023`, not `:2022` as
originally cited — corrected) before the job actually runs. A second
concurrent caller would overwrite `fn`/`ctx`/`n_rows` mid-flight: this is
data corruption, not merely a race that happens to be benign. `ds4_threads_init`
is a racy lazy singleton — a plain, non-atomic check-then-act on
`g_pool.initialized` (`ds4.c:1947`, not `:1955` as originally cited —
corrected by a wider margin, the actual check is eight lines earlier) guards
`pthread_create` of up to 32 threads.

The Metal backend has on the order of hundreds of file-scope mutable
statics: one global device/queue/library —
`static id<MTLDevice> g_device; static id<MTLCommandQueue> g_queue; static
id<MTLLibrary> g_library;` (`ds4_metal.m:51-53`, confirmed exact) — plus a
single shared in-flight command buffer, `g_batch_cb`
(`ds4_metal.m:54`, the original audit's "54-56" range also covers the
adjacent `g_batch_enc`/`g_batch_has_work` declared immediately after it),
whose `ds4_gpu_begin_commands` (`ds4_metal.m:8803`, confirmed exact) returns
0 if one is already open. I did not independently count "~505" statics or
"~230 pipeline globals" or verify "exactly three mutexes… none protects a
Metal object" — those specific tallies are reported as given, not
re-verified for this revision, but the shape they describe (one shared
device/queue/command-buffer, guarded by return-0-on-conflict rather than by
a lock) is directly visible in the lines checked above.

**`ds4_sessions_eval_batch` is a batching API, not a concurrency API** — its
implementation (`ds4.c:68275`, confirmed exact) amortizes one GPU submission
across N sessions on **one calling thread**. Nothing in this note should be
read as implying otherwise; correcting that possible misreading is the point
of naming it here.

The shipped server confirms the contract independently: `ds4_server.c`
serializes every engine-touching path behind one process-wide
`pthread_mutex_t inference_mu` (declared `ds4_server.c:8731`, confirmed
exact) — roughly a dozen lock/unlock pairs around it, confirmed by direct
grep (25 individual lock/unlock calls total), not the specific "13" the
original audit named, which is close enough to be the same finding counted
slightly differently.

**The load-bearing comment, quoted verbatim** — `ds4_agent.c`, immediately
preceding a `pthread_mutex_lock(&pool_mu)` (`pool_mu` itself declared
`ds4_agent.c:463`):

> /* P11 (fork divergence #11): serialize init with the same pool mutex that
>  \* serializes turns — the system-prompt reset prefills on the shared
>  \* engine's Metal device, and two workers doing it concurrently race (a
>  \* Metal command-buffer assertion kills the process). */

(confirmed verbatim, at `ds4_agent.c:15734-15738` in this revision's
verification — close to the original audit's `:15736-15739`). The
serialization is a real constraint the frontend exists to enforce, not a
lock-scoping accident the frontend merely happens to also have.

### Finding C — why Laguna is excluded from batched decode

Not hardware. `ds4_metal_mellum.m`'s own header comment says it directly:

> This is #included by ds4_metal.m rather than compiled separately, and that
> is deliberate: these functions reach twelve file-static helpers and seven
> mutable module globals -- g_initialized, the shared flash-attention
> scratch, and pipeline caches owned jointly with the Laguna and GLM paths.

(`ds4_metal_mellum.m:1-9`, confirmed verbatim), and it is in fact
`#include`d, at `ds4_metal.m:44354` — the last line of a 44,354-line file
(both confirmed exact). Mellum's grouped-decode path writes and reads a
shared `g_flash_attn_tmp_buffer` across two dispatch passes
(`ds4_metal_mellum.m:136-174`, confirmed present at those lines), consistent
with the header comment's claim of scratch shared with the Laguna and GLM
paths. This is shared-scratch aliasing, fixable in principle at the cost of
un-sharing those seven globals — not a hardware limit. Metal itself supports
multiple command queues, and the code does declare a second one,
`g_tp_keepalive_queue` (`ds4_metal.m:~9101`) — worth a caveat the original
audit's framing elides: that second queue is a **special-purpose keep-alive
queue for tensor-parallel mode**, not a general concurrent compute queue, so
its existence demonstrates the API is available, not that concurrent Metal
compute across ordinary sessions is exercised anywhere in this codebase.

### Finding D — the good news, lightly spot-checked

`ds4_ssd.c`, `ds4_kvstore.c`, and `ds4_layer_pack.c` have no file-scope
mutable variables that I could find (a targeted grep for `static` declarations
that are not function prototypes and not `static const` found none in any of
the three). `ds4_tp.c` and `ds4_distributed.c` were not fully re-audited for
this revision; I spot-checked the same grep pattern against both and found
only forward-declared `static` functions, no mutable state, which is
consistent with the audit's claim but not an exhaustive re-check of either
file. The supporting C layer these five files represent looks reusable as-is
from what I checked; treat the two unaudited files as reported rather than
independently confirmed.

### Finding E — a roadmap-relevant repricing

`share_session_prefill_workspace` (`ds4.h:249`, confirmed exact) is real.
The first session on an engine with this option set allocates the shared
prefill scratch; every later session on that same engine gets a pointer copy
of the tensor handles rather than its own allocation
(`metal_graph_copy_prefill_workspace_pointers`, defined `ds4.c:16863`, called
at the alias site `ds4.c:18521`; the transfer that hands the first session's
allocation to the engine happens at `ds4.c:63798` via
`metal_graph_transfer_prefill_workspace`, defined `ds4.c:16875` — all four
line numbers confirmed exact against the original audit's citations). The
engine's own log line says it plainly: "each additional session aliases this
allocation" (`ds4.c:63801-63805`, confirmed verbatim). So the ~6.1 GB prefill
scratch is paid **once per engine, not once per session**, when this option
is on — the Backlog's multi-project-residency pricing, "five 64k-ctx
sessions ≈ 89 GiB with the model" (`ROADMAP.md:548-550`), looks too
pessimistic for a host that opts into this flag, since the ~6.1 GB scratch
term would not multiply by five.

**Caveat that keeps this from being a free lunch**: the aliased buffers
include per-layer working state that is *ping-ponged* across the batch —
"the cur/next pair (`batch_cur_hc`/`batch_next_hc`) is ping-ponged per layer
step on each tier" (`ds4.c:18504-18505`, confirmed verbatim) — which means
this sharing is unconditionally incompatible with concurrent prefill across
those sessions. It is a memory-for-parallelism trade, and it is sound only
*because* execution on this engine is already serialized by Finding B above,
not despite it. Sessions sharing this workspace must take turns for a reason
that has nothing to do with `share_session_prefill_workspace` itself.

**A likely misreading to head off: the sharing is content-free, not
content-based.** The natural question — "how much overlap do two projects
need for this to help?" — has the answer "none." The buffers shared here are
the transient GPU working set *during* a prefill (the ping-ponged
activations just cited), overwritten every prefill and carrying zero
semantic content between uses. It is a shared workbench, not shared work: a
Django session and a FastAPI session share it exactly as well as two Django
sessions do. Only one of the three layers below is content-dependent:

| Layer | Size | Shared? | Needs content overlap? |
|---|---|---|---|
| Prefill scratch (this finding) | ~6.1 GB | Always, once opted in | **No** — content-free |
| KV prefix (bootstrap, tool schemas, system prompt) | small, session-specific | Only if byte-identical | **Yes, exactly** |
| Per-session KV proper | `49,152 × ctx + 72 MiB` (`ROADMAP.md:548-549`) | Never | n/a |

The middle row is unforgiving because KV reuse is exact-prefix-only: "a
per-specialist recipe is a divergent prefix by definition: it either breaks
the shared root, or it lives in long-lived per-specialist sessions"
(`2026-08-23-house-style-as-a-compiled-artifact.md:182-184`). Design rule:
everything common first, everything project-specific last. A Django session
and a FastAPI session share nothing at the framework-knowledge layer — no
live shared prefix primes both — even while sharing the scratch layer
perfectly. A sizing figure of this general shape exists but is from a
different system and must be labeled as such, not transcribed as if it
described this one: the **Pi developer harness's** Superpowers bootstrap
(not the ds4-agent's own `sysprompt.kv`, for which I found no measured
token count anywhere in this repo) runs "~1.1k tokens" plus "~700 tokens" of
always-on skill descriptions (`ROADMAP.md:968,972`) — an order-of-magnitude
anchor for "what a bootstrap-sized prefix costs," not a claim about what a
Django or FastAPI primer would actually cost.

**The in-process move that sidesteps the exact-prefix wall**: keep
pre-computed framework primers as **snapshots on disk**, not branches of one
live KV tree — a Django-primed state and a FastAPI-primed state, each loaded
via `ds4_session_load_snapshot` (`ds4.h:673`) instead of re-prefilled every
time. This does not fight exact-prefix reuse, because nothing branches a
live tree; it restores a saved state instead. **Estimated, not measured**: a
few thousand tokens of primer may load faster than re-prefill, but it is not a
small file by default: payload size includes live KV state and must be measured
alongside disk I/O and GPU synchronization. Nothing in this repo exercises
`save_payload`/`load_snapshot` today — the Backlog says so explicitly
(`ROADMAP.md:563-564`).

**Two different wins, kept separate rather than conflated under
"multi-project":** **residency** — N projects resident at once, so switching
back avoids a full re-prefill — is pure elimination and needs no content
overlap. Shared scratch makes it materially cheaper, not free: every resident
session still owns its KV proper. **Cross-project learning** is a different
thing entirely and does not come from KV sharing at all: it comes from the
`.kv` corpus, past sessions' rendered conversations stored as plain UTF-8
behind a fixed 48-byte header (`ROADMAP.md:480-482`) — the backlogged
`recall`/cross-session-fact-mining substrate. What transfers there is the
author's conventions and preferences, not framework knowledge or symbols; it
is a retrieval feature with its own cost, not a byproduct of shared scratch.

### What this kills, stated plainly

- **Two engine instances for two draft models** — the workaround this note
  proposed for the DFlash correction above — is dead. It fails for a
  *second*, independent reason beyond the DFlash-specific one: `Finding A`
  means two engine opens in the same process race the instance lock and the
  process exits, full stop, regardless of what either engine was configured
  with.
- **Multi-model routing is not a scheduling change.** It is the `g_ds4_shape`
  refactor — on the order of thousands of call sites depending on exactly
  how the dependency is counted (my own count: ~5,400 macro-name
  occurrences; the original audit's: 2,237 — see Finding A). Any plan that
  treats multi-model routing as cheap is mis-scoped by roughly that factor.
  Record this as the honest price of a "deep fork" that touches engine
  internals rather than adding a new consumer of the existing header.
- **In-process Q2-vs-Q4 paired logit comparison** (§ "Heavy quantization"
  below) needs two engines and is therefore also dead in-process for the same
  reason. It is repairable as two separate processes, each recording logits
  to disk, diffed offline — noted at the point of use below.
- **Free-threading is settled as not worth it for now.** It cannot help
  engine work at all — the ceiling on that side is a hard global lock, not a
  GIL. It can only help the non-engine Python around the engine: digest
  projection, AST parsing, Django introspection, logit post-processing. That
  is real and bounded, but unmeasured, and nothing here prices it as urgent.

### What it does not touch

Every primitive the core thesis of this note rests on is a single-threaded,
single-engine operation: snapshot, rewind, `common_prefix`, logit masking,
`set_cancel`, `ban_token`. The audit lowers the *concurrency* ceiling and
leaves the *elimination* ceiling — the spine's whole point — completely
untouched. Per the spine, not doing inference is single-threaded anyway; the
global-state findings above constrain what a `py-ds4-agent` can do *at the
same time*, not what it can avoid doing in the first place.

## Heavy quantization

Context for this section: upstream (`antirez/ds4`) is working on a
Qwen-3.8-Flash quantized to Q2 to fit 64 GB — a frontier-class model with
heavy-quantization damage. Does this architecture lessen the hit, or does it
just hide it?

**The hypothesis to test:** Q2 may damage capabilities this architecture can
partly replace more than it damages reasoning. Decompose possible damage into
four categories: (1) memorized specifics — exact identifiers, API surface,
long-tail facts; (2) format adherence — malformed calls, schema drift,
tool-call misplacement; (3) compounding drift — per-token error accumulating
over a long generation; and (4) reasoning. The proposed mechanism plausibly
attacks 1–3 and does little for 4, but neither the decomposition nor the claim
that reasoning degrades more gracefully is established here. The Flash experiment
must classify its observed failures rather than inherit that ordering as fact.

- **On (1):** the object-graph constrained-decoding mask above is a
  *quantization prosthesis*, not just a correctness feature — the model does
  not need to remember `related_name` if the sampler can only ever emit the
  real one, regardless of how badly quantization damaged that specific
  memorized fact.
- **On (2):** the think-state-aware placement constraint plus the
  tool-call-preflight idea both remove format-adherence failures at the
  sampler rather than relying on the model to get the format right from a
  degraded weight matrix.
- **On (3):** snapshot/rewind bounds the blast radius of drift — short
  verified hops mean drift never accumulates past the last checkpoint,
  because a bad hop is discarded rather than built on.

**An instrument this makes available, with a real limit.** A per-token
quantization damage map — comparing a Q2 engine's logit distribution against
a higher-precision one via `ds4_session_copy_logits` (`ds4.h:589`) — would be
a direct, measured answer to "where does this quant actually hurt." **But
Finding A above means this needs two engines**, so in-process comparison is
not available; it is two separate processes, each recording logits to disk
for the same prefix, diffed offline — the same repair Finding A already
forces on the two-draft-model idea, reused here. Cheaper and already
exposed regardless: `ds4_engine_routed_quant_bits` (`ds4.h:627`) and
`ds4_engine_layer_compress_ratio` (`ds4.h:420`) let a host *know* how
quantized the loaded model is and condition policy on it directly — tighter
constraints and shorter verify hops at Q2 than at Q8. The mask-rejection
rate is a candidate live signal, not a free quantization meter; it needs the
normalization and calibration work stated in the constrained-decoding section.

**The serious risk, given prominence rather than a footnote: this
architecture can hide a bad quant.** A constrain-and-retry loop means a Q2
model that would fail 60% of the time unconstrained can still *finish* every
task — it just burns five attempts silently doing it. Measured only by
success rate, this looks like a working system. It is not: it is a working
system that costs 5x the inference of a model that didn't need retrying,
and nothing about "the task got done" surfaces that cost. This ties directly
to the spine's own metric: per-task accelerator time, with all attempts
retained, catches this immediately; a success-rate metric actively defeats
detecting it, because success rate is exactly the number a retry loop is built
to keep high regardless of underlying quality.
State the trade as one question, and answer it honestly whenever this is
measured: *did the larger model at Q2 reduce accelerator work per task case,
or did it just relocate the cost from "worse answers" into "more retries"?*

**One unmeasured hypothesis, flagged as a hypothesis and nothing more:**
heavily-quantized models may degrade faster with context depth than
full-precision ones — precision loss compounding with long-range attention
in a way full precision doesn't. If true, the context-grooming program above
(pre-chewing, exclusion, shallow-depth discipline) is doubly valuable at Q2,
not merely as-valuable. This is cheap to check with the same paired
two-process logit-comparison setup described above, once it exists; nothing
here has checked it.

## Fast feedback and repair as the instrument

This section follows directly from the risk named in "Heavy quantization":
the repair loop as currently used is the thing capable of hiding a bad
quant's cost. It can be the *detector* instead, but only if it is
instrumented for it.

**The diagnostic that matters is the failure-*class* mix, not the failure
rate.** Three classes, in increasing order of how expensive they are to
detect and how untreatable they are by this architecture:

1. **Constraint-caught** — the mask stripped the bad token before it ever
   existed as output. Visible before damage occurs and readily observable once
   the constraint path records it; its probability mass and whether it is a
   useful intervention still need calibration.
2. **Validation-caught** — a well-formed change that `manage.py
   check`/tests say is wrong. Cheap to detect (an oracle already exists for
   Django, per the section above), and recoverable only with the paired
   workspace/model rollback and a changed retry policy.
3. **Reasoning failure** — well-formed, every identifier real and valid, but
   the wrong change. This class needs a grader or a human to catch, and it
   is **untreatable by anything in this note's architecture** — no mask, no
   rewind, no constraint touches a syntactically and semantically valid
   answer that is simply the wrong one.

If a quantization change (or any other change) shifts failures toward
classes 1 and 2, the architecture genuinely compensates for it — those
failures were always going to be cheap to catch and fix. If it instead grows
class 3's share, the architecture does not compensate at all; retries under
a constrain-and-retry loop are just repeated sampling from a model whose
reasoning was wrong, which the constraint cannot see. **Failure rate alone
cannot distinguish these two situations. The class mix can, and only the
class mix can.**

**A real baseline for class 3 already exists in this project, not a
hypothetical.** The 2026-08-29 failure classification found **7 of 24**
non-passing repair captures sharing one shape — the model correctly names
the bug on a first pass, then explicitly reasons itself out of fixing it and
never emits the file: `"I don't see any issues with the <html> tag"`
(`ROADMAP.md:800-808`, and `docs/pathologies.md:13-15`, pathology #2). That
is the largest single failure population the classification found, larger
than the delivery defect the campaign spent a day chasing (2 of 24), and it
was filed unprompted as the next highest-yield target — "nothing has been
tried against it" (`ROADMAP.md:806`). Holding this same taxonomy fixed
across a future quantization change makes the comparison direct: **if the
class-3 share grows materially above roughly 29% (7/24) under a heavier
quant, that quant damaged reasoning, and no amount of constraint work
recovers it** — this is exactly the failure mode "Heavy quantization" above
flags as untreatable by category (4).

**Rewind can turn retries into controlled trials, at a measured cost.** A
Flash rewind can give attempt N+1 the same KV prefix, but the workspace must
also be reset and the retry policy must intentionally differ; otherwise it
replays the same failure. A snapshot can be much more expensive than a
position rewind. The experiment records both facts. This still gives a better
shared-prefix control than comparing two app builds whose prompts diverge from
position zero (`.worktrees/eval-cli/docs/superpowers/specs/2026-08-30-eval-cli-design.md:202-207`),
but it is not free and does not by itself make a retry informative.

**Three disciplines this needs, or the instrument lies:**

1. **Count every retry into the headline number.** A success on attempt 4 is
   four attempts of inference, not one success — exactly the spine's own
   accounting, and exactly what "Heavy quantization" above needs to detect
   the hiding risk.
2. **Never discard the failed attempt's evidence.** This project already
   has a recorded, confirmed defect of precisely this shape:
   `RepairLoop.swift:193-207` leaves `head` unchanged on `.validationFailed`,
   so round N+1 re-prepares from the same base and round N's work is simply
   gone — not stale, gone. Confirmed by a red probe test
   (`ROADMAP.md:271-287`, `2026-08-26-probe-validationfailed-discards-work.patch`),
   still open as recommendation 1 of the 80-cell verdict
   (`2026-08-26-overnight-80-cell-verdict.md`). A repair loop that silently
   discards a failed attempt's evidence is a concealment machine, not an
   instrument — it is structurally the same failure as "measure success
   rate and never notice the retries."
3. **Make the class-mix check a tripwire, not a one-time report.** This
   project has its own recorded warning about the alternative: an
   under-specified guard "yields something that gets disabled in three
   months" (`ROADMAP.md:918-921`, on the standing-guard-against-
   under-specified-prompts item). A class-mix regression check that runs
   once and gets forgotten is exactly that pattern.

**What stays expensive, stated honestly rather than smoothed over:**
class-3 detection. Classes 1 and 2 become directly observable once the
constraint and validation machinery exist, but masking, validation, rollback,
and retry all have measured costs. Class 3 needs a grader, and
`DeepSeekGrader` is still advisory pending calibration
(`ROADMAP.md:825-834`). The honest position is: two of three failure classes
may be cheaper to detect and recover under this architecture; the most dangerous
one — a confidently wrong, well-formed answer — stays exactly as expensive to
catch as it is today, no cheaper. It is also worth pricing that validation itself
is not free: a verification step costing more than the failure it would have
caught is a net loss, not a safety margin.

## What this would mean for Mellum

Mellum is the 16 GB model and is currently parked — "Mellum is INACTIVE
until 2026-09-05" (`ROADMAP.md:241`) — so this is a five-days-out question,
not a live one. **Sourcing note: several claims below started as the human
partner's own session memory, not repo fact — each was searched and verified
against source before inclusion; none is transcribed on recollection alone.**

**The thesis: Mellum's recorded history is dominated by instrument defects,
not model defects, and that is exactly the class this architecture attacks
hardest.** Three confirmed recurrences:

1. **0/40 in the overnight matrix, and no repair round ever saw a failing
   assertion.** "No Mellum repair round in the matrix was ever shown a
   failing assertion. Zero cells reached a state where the brief's question
   was observable" (`2026-08-26-overnight-80-cell-verdict.md:100-101`) —
   `RepairLoop` discarding round N's work before N+1 ran caused 18 of 40
   cells; an import-chain harness defect caused 20 more.
2. **An earlier "1 in 4" build-arm read was measuring the parser.** "The
   number was measuring the parser, not the model"
   (`2026-08-25-p15-verdict-record.md:84`); a lenient harvest fixed it, and
   the corrected figures are **repair 4/4 at 13/13, build 3/9 at 13/13, 0
   tool calls** (`ROADMAP.md:46`) — not "3/5," which I could not find any
   source for and have not used.
3. **A separate RLM probe's "0 valid code blocks" rows are a harness
   mismatch.** That checkpoint snapshot emits a `<tool_call>` JSON block
   instead of a fenced ` ```python ` block, and "the no-think
   'terminated=NO' rows measure the harness, not the model"
   (`external/ds4/tests/orchestrator-eval/rlm/RESULTS-sft3015.md:15-17,36`) —
   a different snapshot from the RLM probe cited earlier in this note, so
   treat it as the same *class* of finding, not the same run.

**Why the architecture helps, sharpest mechanism first:**

- **Constrained decoding moves parsing into the trusted measurement path.** A
  correct parser/trie can make a constrained sequence unrepresentable; it does
  not remove parser risk. The spike must fixture-test the parser and record its
  state transitions, so recurrence 3 cannot be replaced by a quieter parser
  defect.
- **Direct in-process metrics reduce one translation boundary**, but do not by
  themselves prove the wire or trace was a source of drift. The spike records
  raw engine counters and an outward capture, then checks them against each
  other rather than selecting one on faith.
- **The failure-class taxonomy above (§ "Fast feedback") is computed, not
  inferred from text after the fact** — precisely where the lenient-harvest
  ambiguity in recurrence 2 entered.

**On the ~68% pooled editing rate** (contested — P17's clean 15/17 "does not
replicate on new data," `ROADMAP.md:48`): a small model's characteristic
failure is fabricating symbols that don't exist, i.e. class 1 — exactly what
the object-graph mask makes unrepresentable. Promising, and **entirely
unmeasured for Mellum specifically**; nothing more should be claimed than
that.

**The 7-of-24 "talks itself out of it" population is a genuine new
intervention, not a repeat of the above.** The architecture does not stop
the model doing this — it is a class-3 reasoning failure, untreatable by
constraint or rewind per § "Fast feedback." But it is **trivially
detectable**: no write tool call occurred. Today that is simply scored as a
failure. In-process it becomes a **rewind trigger**: detect deterministically,
rewind, retry under a different think policy (`--nothink` is a real flag,
`external/ds4/ds4_agent.c:964`; think mode is already a per-call argument to
`ds4_chat_append_assistant_prefix`, `ds4.h:506`). That moves the largest
known failure population from "scored" to "retried" — the first
intervention against it on record, since the entry itself says "nothing has
been tried against it" (`ROADMAP.md:806`).

**Correction, 2026-08-31 (post-review): this cannot currently be a Mellum
rewind trigger.** `ds4_session_rewind` invalidates a Mellum session and
snapshot save/load rejects Mellum. The intervention remains a hypothesis for a
future Mellum engine change, but is not available to the Flash-first spike and
must not be counted in a Mellum performance case today.

**One structural alignment.** Mellum's session path exists "because a
resident session carries a KV cache and sampling state that a diagnostic
open has no way to release correctly" (`ds4.h:298-301`, confirmed verbatim).
Mellum is already the model family most dependent on the resident-session
model — which is exactly what a persistent Python host is.

**What it does not help.** Mellum is the 16 GB model, and Finding E's shared
prefill scratch only benefits the second session onward — nothing for a
single-session 16 GB deployment. Mellum is also explicitly excluded from the
current Metal session-batch path (`ds4.c:67511-67521`). It is not the right
control for a first experiment about a host boundary.

## Implementation language and concurrency posture

**Rust first, not Rust between C and Python.** The first artifact is a
standalone research harness over `ds4.h`, not a Python extension or a product
agent. Its value is **narrowed** relative to what a first pass might hope for: not
"make concurrent sessions safe," because Finding B above shows that is not
achievable at any reasonable cost — the ceiling is structural, not a lock
that was merely placed wrong. Three things Rust is actually good for here:

1. **One engine per process, enforced by construction.** A handle type that
   cannot be constructed twice means `ds4.c:53412`'s `exit(2)` branch is
   never reached in the first place, rather than being reached and handled.
2. **A single coarse engine lock that sessions are only reachable through.**
   This is what `ds4_agent.c`'s `pool_mu` (`ds4_agent.c:463`) already is in
   C — written down as a type-system-enforced invariant instead of a
   convention every caller has to remember to honor.
3. **The projection boundary for watchers, made structural.** Keep the
   engine handle and sessions crate-private, and expose only
   `kv_query(selector)` at the crate boundary, so `read_kv(path)` is
   **absent from the API surface entirely** rather than merely discouraged
   in a comment. This restores the Monty note's own guard — *"`kv_query(selector)`
   is a tool; `read_file(path)` is a filesystem"*
   (`2026-08-23-monty-and-the-ane-watcher-tier.md:118`) — as a compile-time
   fact rather than a convention, without needing a separate process
   boundary to enforce it. The experiment runs as its own process, so crash
   isolation from SwiftStar is preserved without first choosing a Python host.

Two bonuses worth naming: Rust is a good home for fixture-driven parser/trie
tests, and Monty is already Rust-native if a later experiment earns that
integration. The spike must not reimplement all of `ds4-agent`: it owns only
the minimum direct token loop and one bounded structured-output contract needed
to test masking, rollback, and measurement. DSML, NDJSON parity, ACP, watchers,
and a general tool runtime are explicit non-goals.

**Costs to state plainly, not minimize.** C, Rust, and Swift are already a
substantial concept budget; Python is deferred rather than assumed. The
`unsafe` FFI boundary between Rust and the C engine is hand-verified, not
compiler-verified; Rust's safety guarantees stop exactly where most of the
bugs in this audit actually live (shared mutable globals reached through raw
pointers). Metal, C, and Rust must still cooperate in one build.

**Timing recommendation.** Do not adopt free-threading, a Python runtime role,
or a deep fork of the engine's global state before this experiment answers the
mechanism question. The first cycle is single-threaded, watcher-free, and needs
only the small set of engine functions cited throughout this note. This is the
project's own binding rule applied to itself: "no machinery ahead of the
contract it serves" (`BRIEF.md:328`). Net position: **Rust for the bounded
experiment, then decide whether a Rust service, an additive wire extension, or
`py-ds4-agent` has earned product status; free-threading and engine-global
refactoring, not yet.**

## Proposed experiment: Flash + Rust + paired workspace state

This is a research harness, not a new product surface or a new phase. Its
purpose is to distinguish three propositions that the larger Python-host idea
currently bundles together:

1. Project-derived constraints improve accepted changes.
2. Rewind plus a workspace transaction reduces retry cost.
3. Direct in-process per-token policy improves on an uploaded, per-turn
   constraint automaton enough to justify a new host boundary.

**Model and process.** Run DeepSeek V4 Flash in one dedicated Rust process on
128-GB-class hardware. It opens exactly one engine and exposes sessions only
through one serialized command path. Flash is selected because it is the most
stable feature-complete implementation for this question, including eligibility
for the existing Metal batch implementation; the experiment does not claim or
require a parallel-throughput win. Python, ACP, a Swift UI, multiple engines,
Mellum, Laguna-specific memory claims, middle eviction, and a `g_ds4_shape`
refactor are out of scope.

**Named non-goal for cycle 1 — SSD streaming, retained as a future execution
mode.** Run this experiment with Flash fully resident: SSD streaming is off.
This is a measurement decision, not an architectural exclusion. The public
engine options already make routed-expert streaming, its cache budget, and its
preload policy available to a Rust host (`ds4.h:226-242`), and the shared
prefill-workspace path is selected before the session's streaming graph is
configured (`ds4.c:63766-63811`). The host's paired workspace/model-state
contract, one-engine rule, serialized command path, snapshots, and rollback do
not rely on weights being resident. SSD streaming remains a legitimate later
capacity mode because moving routed experts out of the resident set can create
the session headroom that KV, scratch, and the OS need; it does not make those
other allocations disappear (`external/ds4/README.md:395-432`).

There are two reasons not to silently turn it on for this cycle. First, it is
not feature-neutral today: an SSD-streaming session rejects the current native
Metal multi-session batch path (`ds4.c:67511-67544`). More resident sessions
may still be useful, but the experiment must not equate that with batched
decode; until the engine gains streaming-aware batching, the scheduler treats
streaming as a serialized capacity mode. Second, its latency depends on two
cache layers. The ds4 routed-expert cache and preload state are controllable;
the operating system's file/page cache can satisfy nominal SSD misses from RAM,
then relinquish those pages when KV or additional sessions create pressure.
Thus a warm, lightly loaded 128-GB machine can make streaming appear more
resident and more stable than the capacity workload actually is. This does not
break correctness or make timing unusable, but it makes an uncontrolled
wall-time difference an implausible treatment effect for the cycle-1
cost/success frontier.

Streaming earns a separate later experiment, not a blanket ban. That protocol
must declare ds4 cache/preload state and an OS-cache regime (cold start, warmed
steady state, and sustained memory pressure), say whether initial I/O belongs
in the headline cost, and record memory pressure, bytes read/page faults where
available, cache budget, session count, and batching eligibility. In
particular, `--ssd-streaming-cold` is useful for disabling ds4's normal
hot-expert preload for a measurement, but it is not proof that macOS's page
cache is cold (`external/ds4/README.md:424-432`). A long-term host should make
resident versus streaming a scheduler-visible mode with different admission and
latency expectations, not pretend they are interchangeable configurations.

**State pair.** Each candidate attempt starts from the same committed source
revision in a disposable worktree, with P10's per-file baseline and
candidate-or-discard semantics. The model checkpoint and the worktree are one
transactional unit: validation success produces a candidate ref; validation
failure discards the worktree and either rewinds the Flash session or restores
its measured snapshot. The harness records whether a restore is position rewind,
in-memory snapshot, or disk payload; it never calls all three "rollback."
If direct source reuse with `WorktreeDispatcher` is impractical across Rust and
Swift, the Rust adapter must pass the same lifecycle fixtures and candidate/refusal
contract rather than inventing a weaker file-state model.

**Task and oracle.** Use a preregistered set of routine Django changes with
held-out acceptance tests. `manage.py check`, migrations, lint, and type checks
are fast intermediate signals, not the definition of correctness. Freeze the
model artifact, context size, sampler policy, prompt, tool budget, timeout,
workspace contract, and attempt cap before collecting results. Run all arms on
the same tasks and seeds, and retain every timeout and failed task in the result.

**Arms.** The harness compares a current unconstrained baseline with: (a) a
static symbol trie compiled by sandboxed introspection and uploaded once per
turn to the existing-agent-style control; (b) the same constraint implemented
through the Rust in-process logit path; (c) the in-process path plus paired
workspace/KV retry under a predeclared changed policy. The final comparison is
the important one: if an uploaded trie has the same effect as in-process
masking, this experiment has validated the constraint but not `py-ds4-agent`.

**Measures and decision.** Report a paired cost/success frontier rather than a
single token ratio: accepted-task rate under fixed wall-clock and energy budgets;
accelerator milliseconds, wall time, joules when available, and validation time
per task case; prefill milliseconds indexed by context depth; generated tokens;
attempt count; snapshot bytes and restore time; peak memory; and the three-way
failure mix (constraint, validation, reasoning). Token totals are diagnostic,
not a proxy for depth-weighted accelerator cost. Publish uncertainty intervals
and individual task outcomes, not only a pooled headline.

**Falsifier.** Do not build a Python host if the Rust combined arm fails to
improve the preregistered cost/success frontier over both the unconstrained
baseline and the uploaded-automaton control. In that result, the useful pieces
belong in host tools or an additive wire patch; the new runtime boundary has
not earned its complexity. A win for the in-process arm supports revisiting D11,
not automatically choosing Python over a Rust service.

## Risks

- **Serialization is unchanged, and is now known to be structural, not
  incidental.** Finding B above confirms one generating session at a time on
  one serialized GPU is not a lock that was placed conservatively — it is
  the only correct answer given `g_pool`'s single work slot, the Metal
  backend's unguarded shared statics, and the frontend's own comment naming
  the exact crash a second concurrent prefill would cause. Compare-before-
  commit is explicitly "not a concurrency win" (`ROADMAP.md:573-574`), and
  Laguna's batched-Metal-decode exclusion is unconditional and family-wide
  (`ROADMAP.md:100-105`) — the audit adds *why*, for the general case, not
  just for Laguna specifically (Finding C).
- **The fork bill, measured.** An engine-editing branch accumulated "seven
  textual conflicts and three semantic collisions that git merges silently"
  in four days, where a purely additive branch fast-forwarded
  (`docs/harvest/swiftstar-md.md:90-92`). Every submodule bump already owes
  a golden-fixture recapture (`docs/sdd.md:117-118`); a second consumer of
  `ds4.h` does not by itself add engine-side patch risk, but "multi-model
  routing" specifically does — Finding A prices that at thousands of call
  sites, not a scheduling change, and anyone scoping it as the latter is
  simply wrong by that factor.
- **The identity change.** `BRIEF.md` states plainly, under "Practical
  environment": "Python exists in this repository for documentation and
  nothing else" (`BRIEF.md:336-337`), and D11 records "no Python runtime
  role… Backlogged with a condition" (`2026-08-21-swiftstar-design.md:140-143`).
  This is a D-level decision, not a phase-level one, and the Monty note
  already flagged the identical tension for a much smaller Python footprint
  (sandboxed extension execution) than a full inference host. Nothing in
  this note should be read as making that decision.
- **One new boundary for the spike; two only if Python earns its place.** The
  Rust harness crosses Rust↔C and stays a separate process from SwiftStar.
  A later `py-ds4-agent` would add Python↔Rust/C and Swift↔Python. Finding B
  makes the engine-side rule straightforward: one coarse lock around the
  whole engine, matching `ds4_agent.c`'s `pool_mu` and `ds4_server.c`'s
  `inference_mu`. Packaging a Metal-linked Rust binary is still work, but it
  is smaller and easier to evaluate than a distributed Python extension.
- **Duplicated turn-loop logic is the principal architecture risk.** The spike
  deliberately owns only a bounded structured-output loop. A product Rust or
  Python host that reimplements DSML, host tools, transcript canonicalization,
  compaction, and NDJSON independently would create another semantic owner.
  Before productization, evaluate extracting a reusable agent-runtime layer
  from `ds4_agent.c`; that is some fork work, but may cost less than permanent
  divergence between two or three complete turn loops.
- **This architecture can hide a bad model or a bad quant, and needs its own
  discipline to avoid doing so.** See "Heavy quantization" and "Fast
  feedback and repair as the instrument" above in full — recorded here as a
  risk in its own right because it is a risk the architecture itself
  introduces, not one it merely inherits.

## § 8 — Corrections I owe, recorded beside the originals

Per `docs/sdd.md`'s "kept as it was written" convention, these are recorded
as corrections next to the claims they correct, not edited over them:

- **My "selective speculative decoding per region" idea was wrong twice
  over.** First correction (this note's own D1 revision): draft models are
  loaded per-engine, not per-session, so no in-process trick selects DFlash
  for one region of one turn. Second correction (this revision, from Finding
  A): the two-separate-engines fallback I proposed to work around the first
  correction is *also* dead — two engine opens in the same process race the
  instance lock and the process exits. The idea does not survive either
  correction and is retired, not merely narrowed.
- **My "compare Q2-vs-Q4 logits in-process" idea needs the two-process
  repair from Finding A.** Recorded at the point of use in "Heavy
  quantization" above: it is two separate processes, each recording logits
  to disk, diffed offline — not a single in-process comparison as first
  imagined.
- **My "roughly sixteen Backlog entries blocked on access" count stays
  exactly as originally written** — an approximate, unverified tally, not a
  machine-checked count, and this revision did not attempt to make it one.
- **My middle-eviction reading was wrong.** `ds4_session_rewrite_from_common`
  currently reports a rebuild requirement for a replaced live suffix; it does
  not preserve the prefix and refill only the tail. That idea is removed from
  the exposed-capability list and from the first experiment.
- **My snapshot/rewind framing was too broad.** A position rewind, an
  in-memory snapshot, and a disk payload have different costs, and Mellum
  supports neither snapshot save/load nor useful partial rewind today. The
  Flash experiment records the chosen mechanism and pairs it with workspace
  discard rather than calling all of them cheap rollback.
- **My proposed headline metric was dimensionally wrong.** Counting prefilled
  and generated tokens equally cannot represent the measured cost of context
  depth. The experiment now reports a cost/success frontier with accelerator
  time, task-level outcomes, and uncertainty rather than a single ratio.

## Related in-flight work worth linking

There is an **unlanded worktree** at `.worktrees/eval-cli` (branch
`eval-cli`, confirmed via `git worktree list`) whose design doc,
[`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)
(branch-only — **not on `main`**, read at
`.worktrees/eval-cli/docs/superpowers/specs/2026-08-30-eval-cli-design.md`),
extracts an `AgentSession` from `AgentController` because "the app's turn
loop lives in `Sources/SwiftStar/AgentController.swift`, a 66 KB SwiftUI type
neither runner can link" (design doc, lines 44-46). This is relevant to
`py-ds4-agent` twice over: it documents the identical drift problem — one
turn loop, multiple runners that each risk reimplementing it — from the
Swift side of this exact boundary, and it is the source of the four
instrument-defect narrative this note borrows the "verify, don't assert"
discipline from (a 2.2x speedup that was actually an unrecorded `--power`
setting; see the design doc's opening section). A future `py-ds4-agent`
would be a *fourth* implementation of a turn loop in this project if the
eval-cli extraction and the Python host are ever both built without one
deferring to the other. The Rust experiment deliberately remains below that
line: it is a bounded direct-token-loop harness, not another general agent.

## Related reading

- [`docs/harvest/swiftstar-md.md`](../../harvest/swiftstar-md.md) — the
  original D1 rejection of embedding, and exactly which capabilities were
  conceded to genuinely require it. This note's central move is showing that
  a second *process* satisfies every objection this document raises.
- [`docs/superpowers/specs/2026-08-21-swiftstar-design.md`](../specs/2026-08-21-swiftstar-design.md) —
  D1 in its original decision-record form, with the alternatives that were
  rejected alongside it.
- [`2026-08-27-p25-deepseek-v4-flash-variant-design.md`](../specs/2026-08-27-p25-deepseek-v4-flash-variant-design.md)
  — the Flash artifact and 128-GB-class admission basis for the experiment;
  Flash is the feature-complete control, not a 32-GB product claim.
- [`Sources/SwiftStarAppKit/WorktreeDispatcher.swift`](../../../Sources/SwiftStarAppKit/WorktreeDispatcher.swift)
  and [`Sources/SwiftStarAppKit/WorktreeTransaction.swift`](../../../Sources/SwiftStarAppKit/WorktreeTransaction.swift)
  — P10's disposable-worktree, candidate-or-discard semantics that the Rust
  experiment must reuse at the contract level, paired with each model-state
  checkpoint.
- [`2026-08-23-monty-and-the-ane-watcher-tier.md`](2026-08-23-monty-and-the-ane-watcher-tier.md) —
  source of "the process gap is the feature," the D11 identity-change
  warning this note's Risks section reuses directly, and the "'AFM only' is
  a bet on an API that may move" line the AFM reversal section keeps as a
  caveat even after retiring the risk it originally supported.
- [`2026-08-28-cag-and-the-librarian.md`](2026-08-28-cag-and-the-librarian.md) —
  the librarian reframe in this note (ds4 session instead of AFM) is a direct
  response to this document's own falsifiers, and its two-costs finding
  (recompute is cached, the depth tail is not) is the spine's "context you
  never admit" category in its original, measured form.
- [`2026-08-23-house-style-as-a-compiled-artifact.md`](2026-08-23-house-style-as-a-compiled-artifact.md) —
  the "style is a gate, not a prompt" move this note's constrained-decoding
  section leans on for why a deterministic constraint beats an inferred one.
- [`docs/harvest/telemetry-findings.md`](../../harvest/telemetry-findings.md) —
  the original 7x prefill-degradation measurement everything about "shallow
  context is the whole game," and the spine's compounding argument, depends
  on.
- [`2026-08-30-p24-1-read-guard-before-measurement.md`](2026-08-30-p24-1-read-guard-before-measurement.md) —
  a worked example, in this same project, of a plausible-sounding number
  ("55 redundant re-reads") that turned out to be measuring the wrong thing;
  cited here as the standard this note tries to hold itself to on the
  2,044→11,557 ms figure above.
- [`2026-08-30-foundation-models-latency.md`](2026-08-30-foundation-models-latency.md) —
  confirms `FoundationModels`/`LanguageModelSession` is real, stateful, and
  Swift-native on macOS 26; still the only independently-verifiable half of
  the AFM story, pending whatever macOS 27's Python extension turns out to
  actually be.
- [`docs/pathologies.md`](../../pathologies.md) — the observed-failure
  catalog this note's Django thesis and "Fast feedback" section are trying
  to move the needle on; #2 ("talk yourself out of the answer") is the exact
  class-3 baseline behavior cited there, and #10 ("silent framework
  substitution") is a second candidate for a project-derived constraint to
  foreclose structurally rather than catch after the fact.
- [`external/ds4/docs/json-events.md`](../../../external/ds4/docs/json-events.md) —
  the NDJSON wire `py-ds4-agent` would need to speak outward, and the
  document that confirms `logprob` fields are not on it today.
- [`external/ds4/ds4.h`](../../../external/ds4/ds4.h) — the boundary this
  whole note is about; every `ds4_session_*` citation above is read directly
  from this file. The global-state audit's Findings A–E are read from
  `ds4.c`, `ds4_metal.m`, `ds4_metal_mellum.m`, `ds4_server.c`, and
  `ds4_agent.c` — the files behind the header, not the header itself.
- [`external/ds4/tests/orchestrator-eval/rlm/RESULTS.md`](../../../external/ds4/tests/orchestrator-eval/rlm/RESULTS.md) —
  the existing RLM negative result this note's calibration ideas (top-logprob
  margin and mask-rejection rate, both) are built to address.
- `BRIEF.md`, `ROADMAP.md` — the settled design and the Backlog table this
  note's central finding is read directly out of.
- [`2026-08-30-eval-cli-design.md`](../specs/2026-08-30-eval-cli-design.md)
  (branch `eval-cli`, **not merged**) — the Swift-side turn-loop
  duplication problem this note's Risks section says a Python host would
  make worse, not better, unless the two efforts coordinate; also the source
  of the "no headline ratio" discipline this note's own falsifier section
  follows.
