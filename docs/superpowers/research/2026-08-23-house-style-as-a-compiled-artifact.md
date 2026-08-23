# House style as a compiled artifact

Research note, cross-cutting P9/P10/P11: the long-term goal is an agent that
writes code the way the author would have written it. The cheap approach —
let the model infer house style from surrounding code on every prompt — is a
recomputation of a function whose input barely changes. This note works out
what to compute once, what to recompute incrementally, and which part of the
problem should never reach the model at all.

**Research, not design.** No phase spec is pre-empted here. **Nothing in this
note is measured.** The economics it leans on (prefill is the scarce resource;
`ruff --fix` beats the model typing the same edit by ~500x) are measured and
already recorded in `docs/harvest/telemetry-findings.md`; every claim specific
to *style* below is conjecture, and the section "What would falsify this"
names the one number that decides whether the approach is load-bearing.

## The question

Agents are genuinely good at matching the style of surrounding code. But what
they match is *the nearest example in context*, not the dominant convention
across the corpus — so the inference drifts on first-of-a-kind files, and it
faithfully reproduces an outlier when the outlier is what grep surfaced. Worse,
the inference is redone every prompt, against a corpus that changes on the
scale of days.

Deterministic tools (ruff, pyrefly, refurb) have the complementary shape: exact,
free, and permanently blind to idiom — composition, functions vs. classes, DI
boundaries, naming that tracks domain semantics. Those are exactly what a
project like `tdom` encodes as practice and what no linter can check.

So the question is not "which one" but: what is the smallest artifact that
turns the model's one-time inference into something deterministic, and how does
it stay true as the corpus moves?

## The load-bearing answer: style is a gate, not a prompt

The reframe that makes the rest fall out — **the agent does not need to know
the house style if it cannot finish a turn without matching it.**

P9/P10 already build the machinery: host-owned validation, declared objectives,
a turn that cannot complete while objectives fail. Style compliance is just
another objective. The model then discovers the convention from rejection
messages rather than carrying it in context, which costs zero tokens per
prompt, is exact, and degrades *gracefully* precisely where inference is
weakest — a first-of-a-kind file has no precedent to copy, but it still has a
gate.

This inverts the usual instinct. The instinct is to describe the style better.
The lever is to make non-compliance non-terminal.

### Why P11's own numbers force this

P11 workers are short-lived, share the parent's bootstrap prefix, and get a
per-worker `ctx_size` of roughly 4k–16k that *is* their budget — exceeding it
is a receipt, not a compaction (D8). A prose style guide packed into a worker
competes directly with the task context inside that budget.

That is the argument, in this project's own terms, for pushing style into
checks rather than recipes: **a compiled rule costs zero of a 4k budget; a
prose convention costs some of it on every single dispatch.**

## Move 1 — use the model once as a rule compiler

An out-of-band pass reads the corpus and emits *executable* rules. Note the
division, because the tools are not interchangeable: **ruff and refurb are
selected, not authored** — the pass decides which of their built-in rules the
corpus already obeys and writes that into configuration — whereas
*project-specific* patterns need a pattern engine that takes user-written rules
(`ast-grep`, `semgrep`). Ruff has no user-defined-rule API; a note that assumes
otherwise will produce a plan that cannot be built. The model is used once, as
an authoring tool for determinism, and then never again for that rule.

Two properties make this worth more than it first looks:

- **A compiled rule is permanently free.** It never re-enters context, and it
  runs at tool speed, where the measured ~500x advantage lives.
- **Executable rules cannot rot silently.** A prose convention drifts out of
  date invisibly; a check that no longer matches the code *fails*, and the
  failure is the notification. This is the same preference the project already
  applies to fixtures and gates.

The metric to optimize is the **compile fraction**: what share of house style
survives translation into a check. Everything below that line stays prose — but
prose is then the residue, not the plan.

### The deterministic surface, concretely

The tools stratify into three tiers, and the tier decides how each one is used.
This matters more than the individual tool choices: a fixer the agent is allowed
to hand-simulate is a wasted 500x, and a checker treated as advice is not a gate.

| Tier | Tools | Role |
| --- | --- | --- |
| **Fixers** — deterministic, apply themselves | `ruff check --fix`, `ruff format` | The agent must **never type these edits**. This is where the measured ~500x lives. Run before the model sees the file, and again before the turn can complete. |
| **Checkers** — deterministic, report only | `pyrefly` (types), `refurb` (idiom), HTML validation of rendered output, CSS validation | Objectives in the P9/P10 sense: they gate turn completion and cost zero context until they fail. All have or can be given machine-readable output. |
| **Executable truth** — the thing that cannot be narrated | `pytest`, `sybil` (doctested examples), `sphinx` build | The packet's validation command. A claimed pass here is worthless without a host-recorded execution. |

Three observations that change the design:

- **`refurb` partially falsifies the "linters can't check idiom" claim.** Its
  whole purpose is "there is a more Pythonic form of this", which is idiom, not
  formatting. It does not reach composition or DI boundaries — but it moves the
  compile-fraction line further than a first estimate suggests, and it should be
  measured on the corpus before concluding a convention is irreducible.
- **For a `tdom`/t-strings project, validation does not stop at Python.** The
  deliverable is *rendered HTML*. Validating the output — well-formedness,
  required attributes, CSS that resolves — is a gate the agent cannot satisfy by
  narrating, and it catches a class of error (an invalid template that still
  imports and still passes a shallow unit test) that no Python-level tool sees.
  This is the strongest argument that the gate approach generalizes past style.
- **`sybil` makes documentation examples executable**, which folds "does the
  doc match the code" — normally the softest convention there is, and the one
  that rots fastest — into tier three. A doc example that drifts becomes a test
  failure rather than an unnoticed lie.

The tier-three point connects to a finding recorded elsewhere: an agent will
report tests as passing that it never ran. Every tool above is only worth its
place if the host runs it and records the result; a tool the model is trusted
to invoke and self-report has no gate value at all.

Two practical notes. **Machine-readable output is not optional** — `ruff
--output-format json`, `pytest` with a structured report — because the
digest-into-something-actionable step is what keeps a 40-failure run from
eating a small worker's budget (the measured 178s→9s clustering win). And
`uv` is the execution substrate: these tools are project dependencies, and a
host-run check must resolve them the same way the project does or it gates on
a different toolchain than the one the author uses.

## Move 2 — elect exemplars instead of hoping for good precedent

For what resists compilation, the fix is not a longer description. It is to
stop making the agent *search* for precedent.

The out-of-band pass elects, per pattern-kind — a component, a service
registration, a domain object, a test — the single canonical instance, and
records `kind → file:symbol`. The packet then carries "you are writing a
component; canonical is `X:42`", and the worker reads one known-good file
instead of inferring over whatever a grep surfaced. This directly removes the
outlier-precedent failure mode, and it fits D5 exactly: **staged reads carry
names only**, so an exemplar costs a name in the packet and a read the worker
was going to spend anyway.

Invalidation is precise and cheap: a changed file re-triggers election only if
it *is* the current exemplar, or plausibly beats it.

## Move 3 — mine the correction stream

Under P9/P10 the host already records what actually happened — which objectives
failed, which turns were rejected. Every rejection is a labeled example of
un-housely code, produced by the real system, for free.

Anti-patterns are the easiest thing to compile into rules ("we don't do that
here" is a grep more often than a judgment), and they arrive continuously. This
makes the artifact **incremental by construction and grounded in observed
failure** rather than in speculation about what the style might be — the same
discipline the roadmap applies everywhere else.

## Where this attaches: D6 is already the right shape

None of this needs new machinery. P11's D6 rolling digest is *already* defined
as objective-independent, deterministic, out-of-band, maintained incrementally
by the host with no model and no inference. A compiled style artifact is a
second thing with exactly those properties, maintained by the same pass, on a
slower clock.

The natural boundary: **D6 is what the conversation established; the style
artifact is what the corpus established.** Both are host-owned, both are
inference-free to maintain, both feed D5's packet assembly. The style artifact
differs only in being invalidated by commits rather than by events.

## The specialist question, and the constraint that bounds it

Specialist subagents that carry recipes — a tdom specialist that knows
composition, DI, functions vs. classes — are attractive, and the existing
`tdom`, `hopscotch`, `svcs`, `t-strings` skills are already most of the content.
**The skill should be the specialist definition**; inventing a parallel recipe
format would be a second source of truth for the same thing.

But the obvious economic argument for specialists — "pool them, keep them warm,
the recipe is already in the KV cache, so specialization is free after the
first task" — **does not survive contact with this engine.** KV reuse is
exact-prefix-only, and P11's workers are short-lived and share the *parent's*
bootstrap prefix (D8). A per-specialist recipe is a divergent prefix by
definition: it either breaks the shared root, or it lives in long-lived
per-specialist sessions, and each Laguna session pins ~1.5–6.1 GB of scratch.
That is a real cost, not a free lunch, and it is the same residency arithmetic
that put "Multi-project residency" in the backlog.

So the honest position: **specialists are for the part of style that could not
be compiled**, sized against a genuine memory cost, and they get smaller as the
compile fraction goes up. That is another reason the compile fraction is the
number that matters.

## What would falsify this

One cheap probe, and it is falsifiable:

> Point a compiler pass at tdom's practices and measure what share of "when do
> we use a class vs. a function", "where does DI belong", "what is a service vs.
> a domain object" survives translation into an actual executable check.

- **High compile fraction** → the gate approach is load-bearing, specialists
  stay small, and the work belongs with the out-of-band pass alongside D6.
- **Low compile fraction** → style is mostly irreducible judgment, recipes carry
  the weight, and the real problem becomes the residency cost above rather than
  rule generation. That outcome kills Moves 1–3 as the primary lever and should
  be recorded as such rather than worked around.

Either way the number is small to obtain and decides the shape. Nothing further
should be built here before it exists.

## Risks

- **A non-executable style artifact becomes a second source of truth** and
  drifts from the code silently. This is the reason to push as hard as possible
  on compiled rules and treat prose as residue. Any prose recipe that ships
  needs an owner and a reason it cannot be a check.
- **Generated rules can encode an accident.** If the corpus is small or
  inconsistent, the pass will faithfully compile an outlier into a rule and then
  enforce it forever. Election and rule generation both need a notion of
  *dominant* rather than *first seen*, and probably a human confirmation step on
  first generation.
- **Gates teach through rejection, which costs turns.** Style-as-objective is
  free in context but not free in rounds. If a worker burns its budget
  discovering a convention a single line of prompt would have supplied, the
  trade inverts — this is measurable once P9's objectives exist, and is the
  second number worth having.
