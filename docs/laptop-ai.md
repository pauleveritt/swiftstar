# Laptop AI

SwiftStar's premise is **AI that lives on your laptop and runs on your
battery.** A laptop is a resource-constrained device — GPU, CPU, RAM, and a
battery that is one budget with the thermals — and the standard server harness
assumes none of those constraints. Laptop AI is the argument that the
constraints are the design, not a limitation: run a model that *fits*, keep its
context *small*, do expensive work *once* and reuse it.

## The budget: GPU, CPU, RAM — and the battery

- **The measured cost is GPU prefill at deep context.** On Apple silicon, CPU
  and GPU share one die and one fan: the CPU stays under 7% regardless, while
  the GPU goes from ~36% at ~3,400 tokens to ~98% at ~92,500 — a ~7x drop in
  prefill throughput. It is compute-bound: the prefix cache stays healthy;
  compaction only helps by shrinking the context.
- **Energy and heat are one budget.** Energy drains the battery; heat engages
  the fan, throttles the chip, makes the chassis un-lappable. Idle draw is
  under 1W, so the budget is all active compute.
- **Two levers, not the same.** *Do less work* — fewer tokens prefilled, saving
  energy directly. *Do the same work out-of-band* — prefill during idle, reuse
  later, flattening the power curve, which is what the fan and throttle care
  about.
- **The resource ladder:** each step down adds a technique — full residency →
  aggressive mixed quantization → SSD streaming → a smaller family. 128 GB runs
  the flagship resident; 64 GB the big model; 32 GB streams its experts; 16 GB
  runs the small one.

## The model ladder

One principle: the *smallest model that stays resident* beats a bigger one that
thrashes against the memory wall.

**128 GB — flagship (DeepSeek V4 Flash).** The best open weights for the
biggest laptop — heavily quantized, corpus-tuned, resident. The reference the
others are measured against.

**64 GB — big local model (Laguna S).** Full residency via aggressive
quantization of the routed experts, plus a draft model that recovers decode
speed. Not streamable.

**32 GB — streamed model (Laguna XS).** The same class, run from disk: sparse
experts stream in behind inference over what is resident. Target 32 GB; 16 GB
looks feasible but is unconfirmed.

**16 GB — small model (Mellum).** A smaller family; resident decode is fast.
The shipping artifact has never been built — that gap is what a future phase
inherits.

## How the engine shrinks models and keeps them smart

The engine's bet: **small enough to fit, still good enough to use.**

- **Quantize where the size is, preserve where the quality is** — only the
  routed experts (the bulk) are aggressively quantized.
- **Tune to a corpus, not a formula.**
- **Verify, don't trust** — scored against known-good continuations.
- **Pick models the approach tolerates.**
- **One Metal graph, not per-op dispatch.**
- **Stream what doesn't fit.**
- **Compact memory** — long contexts are practical.
- **Speculate to recover speed.**

## How the agent changes the game

The agent lives *inside* the engine, in the same process as its memory —
memory-economy tricks no hosted harness can reach.

- **The bootstrap is prefilled once, ever** — checkpointed and restored from
  disk; hosted harnesses re-process theirs each session.
- **Skills survive compaction structurally** — memory rebuilds from the system
  prompt.
- **Long sessions are practical** — snapshot/restore in seconds, not minutes of
  re-prefill.
- **Bounded reads** — a read can't blow the context.
- **A periodic reminder re-asserts the rules for free.**
- **Parsing stays in the engine; execution moves to the host** — enabling
  condensation, per-tool consent, tool parallelism.
- **Tool results are condensed before entering memory.**
- **An observable, interruptible wire.**

One line: **a hosted agent pays a compounding tax as everything it touches
re-enters a growing context; a laptop agent lives with its memory — reuse,
checkpoint, keep small.**

## The Laptop AI playbook

- Condense tool results before they enter memory.
- Lead metrics on *absolute* context, not a percentage.
- Isolate context with subagents; the win is the sequential context curve, not
  concurrency.
- Don't re-read unchanged files — answer "unchanged."
- Route to the session whose memory already holds the files.
- Recurse over slices with a small root context.
- Snapshot idle sessions to disk; restore instead of re-prefill.
- Prefill the shared bootstrap once, ever.
- Persist pre-compaction context and search it.
- Compute diagnostics deterministically; the model only phrases.
- Offload phrasing and condensation to the neural engine — it doesn't contend
  with the GPU.
- Do anticipated work during idle and reuse it.
- Refuse infeasible launches with an actionable explanation.

## Projected impact

A guess, stated plainly: **notable on battery and on all three thermal symptoms
(fan, throttle, lap), with the win coming mostly from "less work" and only
second-order from out-of-band.** Idle is already under 1W, so the win is doing
less and re-timing the rest, not capping watts. The floor: a session pins fixed
GPU memory, the GPU path is serialized, and a deep prefill is still a deep
prefill.

## What this buys, and for whom

Grouped by what a person gets, ordered value-first. The framing that makes it
worth doing: **locally, prefill is the scarcest resource** — every token the
model doesn't have to read is measured seconds off the wall clock.

| operation | tokens | shallow ctx | 90k ctx |
|---|---:|---:|---:|
| re-read an unchanged 500-line file | 6,000 | 20s | 133s |
| 40 raw pytest failures + tracebacks | 8,000 | 27s | 178s |
| …clustered to 2 representatives | 400 | 1s | 9s |
| model typing a 40-line reformat | 600 decode | — | ~10s |
| `ruff check --fix` doing the same | — | — | ~0.02s |

### Never read the same thing twice

- **"You're about to blow your context budget."** Tokenize a read *before*
  submitting it, and show the slice that matches the query instead of the whole
  file.
- **"You already read that, and it hasn't changed."** Hash + mtime every file
  the agent reads; answer "unchanged since turn 7" instead of the contents — up
  to 133s saved per avoided re-read.
- **"Send this task where its files are already warm."** Route work to the
  session that has already prefilled what it needs.
- **"Keep the cache hot."** Run tasks touching the same module consecutively.

### Fix it before the model ever sees it

- **"12 issues fixed automatically; 3 need your judgment."** Deterministic
  rewriters apply themselves; only the residue reaches the model.
- **"2 root causes, not 40 failures."** Group failures by type and common
  frame, show representatives — the 178s → 9s row.
- **"That edit didn't parse — here it is back."** Syntax-check every edit
  before spending minutes on a doomed test run.
- **"Only the tests your change can affect."** Diff-driven test selection.
- **"Dead code, unused dependencies, import cycles."** Static checks.

### The parts of the workflow a machine can check

- **"Requirement 4.2 has no task."** Spec-to-task coverage, before
  implementation starts.
- **"This plan still says TBD."** A placeholder scan.
- **"That task said two files; the diff touches five."** Plan-versus-diff
  reconciliation.
- **"Task 6 is done but nothing was committed."** Ledger reconciliation.
- **"The spec references a function that doesn't exist."** Spec-to-code drift.
- **"Three tasks blew their budget."** Budget overruns signal plan-sizing
  problems.
- **"Here's what this module does."** A semantic index, mostly free from
  docstrings and type hints.

### Memory that survives compaction

- **"What did we decide four hours ago?"** A `recall(query)` tool over the
  transcript — compaction becomes lossy-in-context but lossless-on-disk, with
  zero extra inference.
- **"Find that session from last Tuesday."** Browse and full-text search every
  past session, no model and no engine load.

### Telling you why it got slow

- **"Compaction ran: 127k → 19k, keeping a 15k tail."** Surface the real
  rebuild statistics instead of guessing.
- **"This model won't fit, and here's by how much."** A feasibility gate with
  an actionable number, not a percentage heuristic.

### Things that happen without being asked

- **"Run the checks the moment a file is saved."** On-save lint, index update,
  impacted-test recomputation.
- **"Do the work on the neural engine."** The one compute unit that doesn't
  contend with the GPU.

### Work that needs the model, or the engine

- **"Five projects open at once, switching instantly."** One session pool,
  three lifetimes: a project is long-lived, a subagent short-lived, a recursive
  sub-query ephemeral. One deep context becomes several shallow ones — up to
  ~4.2x cheaper, with zero concurrency.
- **"Summarize this without stealing a turn."** Offload to the neural engine
  while the model is blocked on a slow tool anyway. Two-stage: deterministic
  code clusters, the small model only phrases.
- **"Compaction that can't misremember."** A deterministic skeleton — files and
  commands are reconstructible, so the model summarizes only goals, decisions,
  and rejected approaches.
- **"Rolling per-turn summarization."** Summarize each turn as it lands,
  instead of one wall at the compaction threshold.

### Where the boundary is

The machine must not decide: whether a failure is a real bug or a bad test;
which non-auto-fixable finding matters; how to fix a logic error; anything
involving intent. **Its job is to guarantee the model only sees those.**

Two rules that keep it safe:

- **Findings gate completion; they don't interrupt.** Validation attaches to
  file mutations (many per step) and gates at step boundaries (few) — fusing
  those clocks is what makes in-loop validation expensive.
- **Acting autonomously needs a blast-radius rule.** Auto-applying a formatter
  is safe and reversible; auto-committing, auto-pushing, or auto-editing a spec
  is not — those surface a proposal, never a fait accompli.

## Caveats

The 7x curve was measured on an idle machine, over sessions under ~25 minutes,
on a narrow workload — no hour-plus thermal soak, so the heat/fan link was
never observed at that scale. The out-of-band and ladder claims are design
intent, not measurement: the enabling facts are measured, but the reuse win has
not been.
