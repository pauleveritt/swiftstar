# Monty and the ANE watcher tier

Research note, cross-cutting P9/P11: a third tier beside the GPU main agent and
the GPU pool — AFM on the ANE as the model, and
[Monty](https://github.com/pydantic/monty) (pydantic's sandboxed Rust
interpreter for a Python subset) as the executor — hosting two roles, a
**librarian** (watcher) and an **inspector** (validator), on one substrate.

**Research, not design.** No phase spec is pre-empted here, and the phase list
is not reopened. **Nothing in this note is measured.** The economics it leans on
(prefill is the scarce resource; out-of-band host computation costs zero context)
are measured and already recorded in `docs/harvest/telemetry-findings.md`; every
claim specific to the watcher tier below is conjecture, and the section
"What would falsify this" names the two numbers that decide it.

## What Monty is (as of a 2026-08-23 pull)

Monty is pydantic's answer to "run code a model wrote, safely, without a
container." It is a Rust interpreter for a *Python subset*, built for exactly
one use case: LLM-written code as the alternative to sequential tool calls
(Cloudflare Codemode, Anthropic programmatic tool calling, Pydantic AI code
mode). The relevant properties:

- **Language-level sandbox, not OS-level.** There is no ambient authority:
  `socket`/`subprocess`/`threading`/`ctypes` are absent, not stubbed;
  `eval`/`exec`/`__import__` and all FFI do not exist. The only ways out of the
  sandbox are opt-in per call: **host functions** (execution suspends, the
  host's code runs with full authority, then resumes) and **filesystem mounts**
  (a `cap_std::fs::Dir` descriptor opened once at mount time; `..` and symlinks
  structurally cannot escape).
- **Resource limits** — memory (enforced at the allocator), *cumulative*
  execution time, recursion depth — with a crash-isolated worker subprocess pool
  so a stack-overflow or allocator abort kills the worker, not the host.
- **Type-checking built in** — `ty`, with host-function type stubs, so code is
  checked against the declared surface *before* it runs.
- **Snapshotting** — `dump()`/`load()` to bytes, and `feed_start` handing each
  host-function suspension back to the host.
- **Microsecond startup**, runtime 5x faster to 5x slower than CPython.

The ~198 commits between v0.0.18 and v0.0.21 grew the subset substantially:
user-defined classes, native `@dataclass(eq=, frozen=)`, the full `itertools`
adaptor set, `collections` (deque/namedtuple/defaultdict/Counter), plus the
mount-confinement and allocator hardening. That expansion cuts both ways for
this note: more expressible programs, but a larger surface for a model to
misuse — and dataclass/typing are precisely what make a *typed* host-function
surface ergonomic.

## The trust problem, and the mashup that dissolves it

The obvious objection to Monty-in-SwiftStar is: the local models (Laguna XS,
Mellum 2.1) cannot be trusted to write Monty-subset code from scratch, and a
failed snippet costs a re-prefill. The reframe that removes the objection is a
three-way split of *authorship*:

- **Swift owns the envelope** — the fixed template, the imports, the
  `type_definitions` stubs for every host function. Deterministic, pre-compiled,
  and it is what makes the hole small.
- **The model fills a bounded hole** — one region, primed by the envelope around
  it. This is the "unique to that moment, cannot be known in advance" part.
- **`ty` is the referee** — the type-checker runs against the stubs before
  execution, so a bad fill is a machine-readable rejection rather than a runtime
  disaster. A retry is a cheap bounded re-prefill, and a failed fill never
  reaches the sandbox's filesystem.

This is the house-style note's *"style is a gate, not a prompt"* move,
generalized from style to **code**: the compiler/type-checker becomes the
deterministic gate on the model's contribution, exactly as ruff/refurb gate
style. See
`docs/superpowers/research/2026-08-23-house-style-as-a-compiled-artifact.md`.
It is also the *dynamic* counterpart to compiled rules: compiled rules handle
what is stable (commit-invalidated); the librarian's Monty body handles what is
moment-specific (event-invalidated); the model phrases what is neither.

## Three tiers, two roles, one substrate

The watcher tier is **not** a P11 subagent. P11 workers are Laguna/Mellum on the
GPU, serialized, sharing one engine, budgeted small-ctx. The watcher tier is AFM
on the ANE — concurrent with the GPU, independent lifecycle, no queue — which is
the same observation the roadmap's P9 note already plants: "the ANE is the one
compute unit that does not contend with Laguna's serialized GPU path."

| | Trigger | Latency | Authority | State |
|---|---|---|---|---|
| **Librarian** (watcher) | event/wake — a turn ended, a file changed | async, tolerant | observational, advisory | long-lived, own small context |
| **Inspector** (validator) | tool-loop hook — a tool result landed | near-sync, rides back on the result | findings ride back on the triggering result | mostly stateless per call |

The split matters because it maps to different roadmap homes. The **inspector**
is not new: the P9 validation-cadence note already designed it, and pre-priced
its costs — *"silence-means-clean needs a system-prompt contract a small model
may not honor (measurable),"* *"silent auto-fix breaks `edit`'s exact-match,"*
*"asynchronous findings need tree-state provenance."* The Monty/AFM inspector is
a candidate *implementation* of that cadence, inheriting all three costs plus a
new latency budget: the fill + `ty` + execute must complete *within* the tool's
execution window, or it stops being latency-hidden and starts extending the
round-trip. The **librarian** has no roadmap home yet — it is the genuinely new
part.

Both roles share one substrate: AFM on the ANE, Monty as the sandbox, the
projected digest, and a narrow host-function surface. The shared substrate is
what makes them feel like one thing; the trigger/latency/authority split is what
makes them two.

## The data boundary: the process gap is the feature

A watcher wants the *live* state of the main agent — the root context, the
in-flight turn, the rolling digest — and "a separate process won't have access
to that." That is not an obstacle to work around; it is the load-bearing
feature. The librarian does not reach into state; the host **projects** it:

1. The librarian **declares interest** — what it is watching.
2. The host **projects** the rolling digest (D6) into a small slice matching
   that interest.
3. The small slice crosses the wire. **Monty never sees kv.**
4. Only when the reaction genuinely needs more does it call a narrow host
   function like `kv_query(selector) -> small_result`, where the *host* does the
   real read and returns a pre-digested result.

`read_customer(id)` is a tool; `read_file(path)` is a filesystem. Applied to kv:
**`kv_query(selector)` is a tool; `read_kv(path)` is a filesystem.** The process
boundary *forces* the reduction to happen on the side that holds the
authoritative state — the same "don't re-derive with less information"
discipline the whole design runs on. This is what answers the embedding
question: you do not embed to reach live memory; you keep the subprocess and
make the host do the projection.

The declaration of interest has three candidate shapes, at different costs: a
host DSL (deterministic, but cannot express the moment-specific interest — which
is the whole point); a Monty predicate the host runs against each digest update
(moment-specific, but pays the fill on every update even when nothing happens);
and the hybrid that fits the envelope/hole split — a coarse deterministic
host-side trigger that *wakes* the librarian, whose Monty body then decides the
moment-specific reaction only when woken.

## `ask_model`: deterministic orchestration of model calls

A host function that runs a chat prompt and returns its result turns Monty from
"execute a snippet" into a deterministic orchestrator of model calls:

```python
for each in items:
    verdicts.append(ask_model(classify_prompt(each)))
answer = ask_model(aggregate_prompt(verdicts))
```

The loop lives in cheap deterministic Monty code; each `ask_model` is a fresh,
bounded, context-cheap prefill; the aggregation is deterministic. This is the
RLM/slicing pattern (see the Backlog) with the strategy expressed as a short
program instead of a token-stream plan, and it is the authoring half of what the
"dispatch decision" backlog entry calls the hard part — except the host still
enforces the invariants (revision checks, writable files, one-session-at-a-time).
Monty replaces the authoring of moment-specific strategy, never the safety.

The constraint that must be named: the engine is serialized — one generating
session at a time, on a serialized GPU — so a Monty `ask_model` loop is
sequential by construction and each call is a prefill. That is fine (the RLM
economics say sequential shallow prefills beat one deep prefill), but it means
`ask_model` blocks the Monty worker on engine I/O. Because the librarian is a
*watcher* (outside the turn), `ask_model` simply enqueues when the engine is
free — clean. The inspector, if it ever needs `ask_model`, is inside the loop
and does not.

## Embedding, resolved against the BRIEF

The BRIEF rejected embedding `ds4` for two reasons: a Metal abort or wired-limit
kill lands in the GUI process, and per-pid memory attribution dies. Monty is
*more* embeddable — small, recursion limits designed to raise `RecursionError`
before a native stack overflow aborts, memory enforced at the allocator — but
the security model says it plainly: *"a Monty process can never be made fully
crash-proof."* Embedding gives up the one guarantee the subprocess pool exists
to provide.

What embedding would buy is direct access to in-memory Swift state — host
functions as closures over live objects — which matters only if the extension
system needs extensions to touch the app's live state ergonomically. The hidden
cost of that win: closures cannot serialize, so a snapshot of a suspended
extension mid-host-call cannot be restored across a restart (the host function
must be name-addressable, not a closure). The subprocess model *forces*
name-addressability, which is exactly what makes extensions portable,
snapshot-able, and safe. **Default: the subprocess pool + a narrow host-function
surface; Swift does the big kv access, Monty composes the small results.**
Embedding is a later, deliberate trade for the extension ergonomics case, paid
in crash isolation and snapshot portability.

## AFM invocation (verify before planning)

The premise "exclusively AFM, off-GPU, independent" is only real if the model is
callable from Swift. Per the author's platform knowledge, that is **CoreML in
macOS 26** and **CoreAI in macOS 27**. This is past this note's ability to
verify; the checkable ancestor is the `FoundationModels` framework
(`LanguageModel`, `ModelRuntime`) from the WWDC24 era. The two things to confirm
before any planning: (a) that the macOS 26 surface exposes `LanguageModel`-style
*text generation* with stop control, not only a one-shot `.mlmodel` predictor,
and (b) whether it offers a fill-in-the-middle or prompt-and-complete shape —
FIM is unverified in both the ds4 engine and the AFM surface, and the fallback
(prompt-and-complete: skeleton in the prompt, ask for the completion) works with
any autoregressive model but is a weaker prime.

## App Intents: mine the form, adopt the reaction

Rather than inventing a declaration DSL, mine Apple's App Intents — the
platform's declarative, typed, discoverable capability idiom. But be precise
about which of the librarian's three surfaces it maps to:

1. **Interest** (what to watch) — a predicate/subscription over the digest. App
   Intents has no direct analog (intents are actions, not subscriptions), but
   the typed-parameter-schema idiom transfers: "watch files `[a.swift]` for stop
   reason `.refusal`" is a typed struct the way an intent's parameters are.
2. **Projection** (host matches events → interests) — purely host-side,
   deterministic, not declarable in App Intents at all. Stays Swift.
3. **Reaction** (what to do when interest fires) — *adopt App Intents
   wholesale.* The librarian's reactions are typed, parameterized actions; if
   declared as actual App Intents, the system's AI can discover and invoke them,
   and the platform's serialization/naming machinery comes free.

So: borrow the schema idiom for (1), keep (2) in Swift, adopt App Intents for
(3). The last is the extension-system story closing its loop — a user's
librarian is not a bespoke plugin format but a set of App Intents + a Monty
body, discoverable by the system rather than by the agent.

## The extension system

Monty's sandbox + host functions + `ty` + resource limits is the right substrate
for user extensions: users write Python-subset; the sandbox makes it safe to
run; host functions are the narrow, typed API surface; `ty` and the resource
limits make a bad extension fail cleanly; snapshotting makes state resumable.
This reopens the "Swift body, Python brain" Backlog entry with a better shape —
not "agent policy in a hot-reloadable peer process" but "sandboxed Python-subset
extensions with a typed host-function surface, checked before they run." Safer
than Pi's full-authority extensions and narrower. An extension is an
*executable* skill: the house-style note argued "the skill should be the
specialist definition; inventing a parallel recipe format would be a second
source of truth" — a Monty extension is a skill whose body is code, checkable
rather than readable. It does not violate the "Python for docs only" rule
literally (Monty is a Rust binary, not CPython) but it *does* change the
identity from "no Python runtime role" to "sandboxed Python-subset execution is
a first-class runtime capability" — a decision to make deliberately, not to let
slide past D11.

## What would falsify this

Two numbers decide whether the tier is load-bearing, and neither is measured:

1. **The AFM invocation API.** Is the macOS 26 CoreML (27 CoreAI) surface
   callable from Swift for text generation with stop control? If it is a
   one-shot predictor only, or not stable enough to build on, the whole premise
   needs a different backing model.
2. **The fill-success rate.** Given a primed envelope, does the model fill the
   hole such that `ty` passes and it runs *first time*? This is the compile-
   fraction probe's twin from the house-style note. High → the mashup is real
   and the watcher tier earns its place; low → you are paying failed-fill
   prefills, and only the host-authored (no-model) Monty use survives.

A third, cheaper-to-get number bounds the inspector specifically: **the fill +
`ty` + execute latency** must fit inside the tool's execution window or the
latency-hiding in P9's cadence stops being free.

## Risks

- **A wide host-function surface rots exactly like a wide tool surface.** The
  librarian's `kv_query(selector)` must stay a narrow, pre-digested query; the
  moment it becomes `read_kv(path)` it is a filesystem, and the sandbox is
  giving you nothing you did not already have.
- **The fill loop is cheap only if the fill usually succeeds.** A model that
  fails `ty` half the time turns "bounded re-prefill" into a tax, and the
  watcher tier becomes a cost on top of the GPU tiers rather than a free
  concurrent tier.
- **Gates teach through rejection, which costs turns.** The type-checker as
  referee is free in context but not in fills; if a convention could have been
  supplied by one line of prompt instead of a rejected fill, the trade inverts.
- **"AFM only" is a bet on an API that may move.** The naming already shifted
  (CoreML → CoreAI across one OS release); building a tier on it accepts that
  churn, and the use-it-or-lose-it discipline from P11's D11 applies here too.
