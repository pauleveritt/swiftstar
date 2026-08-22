# P9 research: host-side validation and where findings enter context

Research note for Phase P9 ("The tool-callback wire"): once the host owns tool
execution, *validation* — lint, type check, tests — can run host-side instead
of being something the model remembers to invoke. This note works out where
findings should enter the transcript, and what that is and is not worth.

**Research, not design.** P9's design spec is a later artifact and this note
does not pre-empt it. **The claims below survived a skeptical pass that
retracted three of them; the retractions are recorded in "What was wrong"
rather than edited away**, per the precedent set in
`2026-08-22-p4-sequencing-findings.md`.

## The question

A phase of work is a multi-step code-generation loop. Traditionally the model
runs validation inside that loop — generate, lint, fix, continue — and every
validation costs a tool round: decode to emit the call, the round trip, and the
tool's output prefilled back into context.

If validation instead runs host-side, the loop and the validator are on
different clocks. The host sees files change, runs checks, finds problems — and
the model has already moved to the next step. So: what is the correct cadence,
and where do findings land?

## The load-bearing answer: the tool result, not a new turn

The agent loop fully pauses generation during tool execution — it emits a call,
waits, then re-prefills with the result. Under P9 the host owns that window. So
validation findings do not need a turn of their own; they ride back **attached
to the tool result of the mutation that triggered them**:

```
Tool result 1 (write): wrote parser.py (42 lines)
  ruff: 3 fixed (import order, quotes) · ty: parser.py:12 incompatible return type
```

One tool result instead of three. The model never spent tokens *deciding* to
validate, and never saw raw tool output.

**Size the win honestly.** This saves one tool round per validation — roughly
30–80 tokens of decode plus a short re-prefill, on the order of a couple of
seconds each. It is a structural tidiness win, not a throughput win. The large
numbers in the telemetry harvest (a raw 40-failure pytest dump costing ~178s of
prefill at depth versus ~9s condensed) belong to **condensing tool output**,
which is a separate mechanism that pays off wherever findings are injected.
The two must not be quoted together as though the second were evidence for the
first.

## Routing: by blast radius, not by latency

A finding's correct handling depends on how far it propagates, not on how long
it takes to produce:

| Class | Example | Handling |
|---|---|---|
| **Auto-fixable, semantically neutral** | format, import order, `pyupgrade` | Apply in the write window; report as one line. Nothing downstream depends on the model knowing. |
| **Blocking** | syntax error, type error in the file just written | **Must be synchronous.** These invalidate every subsequent step; deferring a type error to step 6 means steps 4 and 5 built on a broken foundation. Cheap enough to be sync anyway (`ast.parse` is instant; single-file type check ~1s). |
| **Slow and wide** | full test suite | Run the diff-scoped subset (`--lf` plus coverage-derived impacted tests) in the write window; run the full suite asynchronously. |

Async is *actively worse* than in-loop for the blocking class. The saving is
not "defer everything"; it is "defer only what cannot invalidate work in
flight."

## What makes lateness safe: the gate, not interruption

Async findings do not need to interrupt the loop. They need to **block
completion**. A step is not done while validation is outstanding or failing.

That decouples two clocks that traditional loops fuse: validation attaches to
**file mutations** (several per step), and gates at **step boundaries** (few
per phase). Coupling them 1:1 is what makes in-loop validation expensive.

In this repository's terms the gate already exists — it is the per-task
done-when in each phase plan. What changes is that the host feeds it, rather
than the model remembering to.

## Four hazards, none of them incidental

1. **Unconditional attachment costs tokens rather than saving them.** If
   validation is clean 90% of the time, appending "ruff: clean" to every write
   result is pure added prefill. The convention must be **silence means
   clean** — which requires a system-prompt contract ("validation runs
   automatically; do not invoke linters yourself"). A small local model is
   exactly the kind that ignores such a contract and calls `ruff` anyway, at
   which point both costs are paid. **Whether the contract holds is
   measurable and should be measured**, not assumed: count model-initiated
   linter invocations in a capture.

2. **Silent auto-fix makes the model's file model stale.** The `edit` tool
   matches exact text; a formatter that reruns while the model is mid-task can
   break the next edit on whitespace it never saw change. The safe rule is
   **do not auto-fix inside the model's active edit window** — apply fixes at
   step boundaries, not per-write. (A tempting alternative — have the host
   retry a failed exact match against a whitespace-normalized comparison — is
   **rejected**: exact-match uniqueness is what prevents an edit landing at the
   wrong one of several similar blocks, and relaxing it reintroduces exactly
   that ambiguity.)

3. **Async findings need provenance, not just a place to land.** "Tests
   failed," arriving three steps later, is not actionable and may be stale if
   the file changed since. An async finding must carry the tree state it was
   computed against — "failed against the tree as of the write to `parser.py`
   in step 3" — and be discarded or recomputed if that state is superseded.
   That is real machinery; it belongs in P9's cost, not discovered inside it.

4. **The tool result is where a finding *lands*, not what makes the model act
   on it.** Attaching a type error to a write result guarantees the model sees
   it; only the gate guarantees anything happens about it.

## What was wrong

Recorded rather than removed.

- **"The injection point already exists."** It exists in the loop *structure*,
  not in this app. The C child owns tool execution today, so there is no host
  window to run anything in. Every claim here is P9-dependent.
- **"`ruff --fix` beats a model-typed reformat by ~500x."** This compared the
  model hand-typing a corrected file against the host running the formatter —
  but an agent with a `bash` tool already calls `ruff` rather than retyping
  files, so most of that gap is captured by ordinary tool use. The real
  difference is narrower: a host-side pass never emits a tool call at all, and
  it runs whether or not the model thought to.
- **The GPU-idle framing was a red herring.** Validation is CPU work and never
  needed the tool-execution window to be free. That window buys *latency
  hiding* — the model is already blocked — not free capacity.

## What this does not settle

- **The condensation budget.** P9's own direction already includes condensing
  tool results before they enter KV; how aggressively, and whether the model
  can request the full output, is a P9 design decision this note does not make.
- **Which validators run.** Nothing here argues for a particular tool set;
  `ruff`/`ty`/`pytest` are illustrative.
- **Whether a specialized worker runs them.** The Backlog's "Specialized tool
  subagents" entry proposes reasoning-light workers owning one tool's
  lifecycle. That is a *dispatch* question, downstream of this one: this note
  says where a finding enters context, not who produced it.
