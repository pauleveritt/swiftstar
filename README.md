# SwiftStar

A macOS application for running a large language model locally on Apple
silicon.

SwiftStar launches and supervises a local inference engine, downloads model
weights, shows you what your machine is doing while the model runs, gives you
an agent — and tells you *why* your session got slow, from measurement rather
than folklore.

It does no inference itself. Inference is delegated to `ds4-agent`, a child
process built from a fork of [antirez/ds4](https://github.com/antirez/ds4)
carried as a submodule.

## Status

**A working local-agent app.** SwiftStar launches a regular macOS app — a
single Agent surface via `ds4-agent` NDJSON with tool cards, consent
controls, and interruptible turns — that downloads weights and gates model
feasibility before every spawn, replays Metrics and Diagnostics from
committed captures, bootstraps the Superpowers skills, answers tool calls
over a bidirectional wire, dispatches worktree-isolated attempts, coordinates
multi-phase work through an `/orchestrate` loop, and runs a subagent pool —
context-isolated subagents sharing one locked engine, driven through a queue
over the serialized GPU, with the context-curve win measured (3.70x realized
vs the 4.2x ceiling). A model ladder (Mellum, Laguna XS, Laguna S, DeepSeek V4
Flash) is switchable live, admission-gated before any stop. See
[`ROADMAP.md`](ROADMAP.md) for current phase status.

- [`BRIEF.md`](BRIEF.md) — the design. Read this first.
- [`ROADMAP.md`](ROADMAP.md) — phases, concept budget, backlog.
- [`docs/harvest/`](docs/harvest/index.md) — what the predecessor projects
  proved, kept as evidence rather than as source.
- [`docs/sdd.md`](docs/sdd.md) — how work happens here.

## Requirements

macOS 26 or later, Apple silicon, Swift 6. Running a model needs the weights on
disk — tens of gigabytes, depending on the variant — and enough unified memory
to hold the resident set. SwiftStar refuses a launch it cannot fit and explains
why rather than letting the engine die mid-load.

## Predecessors

SwiftStar replaces **DS4 Control**, a menu-bar app that worked and is being
retired. This is a clean-room rewrite in the gardened sense: implementation is
written fresh, while facts that cost incidents to learn cross with a citation
and a new test. See `BRIEF.md`, "Clean-room policy."

## License

Apache 2.0. See [`LICENSE`](LICENSE).
