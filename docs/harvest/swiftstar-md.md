# Harvest: SWIFTSTAR.md, the rival design

**Source:** `~/projects/ds4`, branch `paul/laguna`, file `SWIFTSTAR.md` —
roughly 1,800 lines of July–August 2026 research. It also owns a Swift package
at `swift/` (`DS4Kit`: `Condenser`, `GrammarMask`, `Router`, `SessionStore`,
`TraceLog`, `Vocabulary`), plus a tokenomics roadmap and a divergence policy.

SwiftStar takes its **name** from this document and rejects its **central
claim**. The document argues that a Swift desktop app should embed the DS4
engine in-process, treating `ds4_agent` as a library and replacing its terminal
UI with a GUI. SwiftStar supervises child processes instead. This brief records
why, and what survives the rejection.

## Why embedding was rejected

Reviewed adversarially on 2026-08-21 against the document's own citations.

**The capabilities embedding was supposed to unlock are mostly reachable across
the wire with an additive C patch:**

- **Cheap multi-session** — already being built behind the process boundary; the
  subagent-pool plan ports the server's N-sessions-one-engine shape into the
  agent. And since batched Metal decode excludes Laguna outright, embedding buys
  **zero** decode throughput anyway.
- **KV snapshot and restore** — the document itself establishes that snapshots
  are eager serializations to host RAM, not shared-memory magic. A wire command
  moves handles, never payloads.
- **Energy-aware pacing** — a runtime control message. The agent already accepts
  a power percent at launch. Pipe latency is irrelevant at 100ms granularity.
- **Grammar-constrained tool calls** — the grammar state machine is already in
  C. An independent review of the subagent-pool design reached the same
  correction in the same words: *it's an `ds4_agent.c` patch, not a
  SwiftStar-exclusive capability.*

**What genuinely requires embedding, stated fairly:** dynamic per-token
*Swift-defined* logit masking — vocabulary-sized round trips per token at
40–360 tok/s is a non-starter over a pipe — and zero-copy logits and embeddings
access. Static tool grammars, the actual use case, do not need either. Ship the
grammar to the C side at launch.

**What the document undersells about embedding's costs:** a Metal abort or a
wired-limit kill takes the GUI down with it, against 46–52 GiB planned budgets.
The supervisor, crash detection, and restart machinery all evaporate. The clean
per-pid memory attribution that made the telemetry investigation possible
disappears. And swapping models means restarting the app rather than a child.

## Ideas worth keeping

Kept as Backlog items with reopen conditions, or already folded into the design.

- **The parse/execute cut.** Keep model-coupled tool *parsing* in C; move
  OS-coupled tool *execution* to the host. This is the document's best idea, and
  it is **orthogonal to the process boundary** — a child can call back over the
  same pipe. **Folded in as P9**, because the wire as first specified is
  observation-only, and that, not embedding, is what forecloses condensation,
  tool parallelism, container isolation, and per-tool consent.
- **Condensing tool results before they enter context.** The document names this
  the top candidate for offloading. It is also the best available mitigation for
  the measured 7x context tax — a 5,000-token log entering KV is exactly the
  compounding cost. **Folded into P9.**
- **Intra-turn tool parallelism** as a Swift task group. The document calls it
  the largest speedup for the least work. Depends on P9.
- **Heterogeneous compute routing** across ANE and GPU, deterministic rules
  first and model judgment last. Backlogged; it needs P9's loop ownership, which
  the document conflates with embedding.
- **Energy as a design axis** — pace-to-read decoding, watts-aware routing.
  Backlogged; current measurement says idle draw is already under 1W.
- **"Swift body, Python brain"** — agent policy in a hot-reloadable uv-managed
  peer process, testable against a fake body without a Mac. A real idea and a
  real scope increase. Backlogged with a condition: reopen if agent policy
  starts changing faster than the app can ship.
- **APFS copy-on-write clones plus KV snapshots** to make agent turns
  transactional. Related to P10's candidate-ref model; revisit there.
- **Small-context discipline** — bounded tool observations, a replaceable
  working set, a durable ledger. Now independently supported by measurement.

## What is explicitly not inherited

- **The 8K context budget table.** It describes Apple's foundation-model tier
  and does not apply to this engine, which runs at 150,000.
- **The Pi-over-localhost-HTTP route.** The document already marks it moot.
- **`DS4Kit` as code.** Its concerns — condensation, grammar masking, routing,
  session storage — reappear in SwiftStar under the clean-room policy, written
  fresh, if and when a phase needs them.

## What does travel intact: the divergence policy

The three rules governing the fork are inherited wholesale because they already
work, and one of its recorded measurements is now load-bearing evidence *against*
calling SwiftStar's own patch set "strictly additive": an engine-editing branch
accumulated **seven textual conflicts and three semantic collisions that git
merges silently** in four days, while a purely additive branch fast-forwarded.
See `BRIEF.md`, "The fork."
