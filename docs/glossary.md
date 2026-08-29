# Glossary

The naming authority for SwiftStar's modes, roles, and delegation mechanisms.
Command names, `PacketRole` cases, and UI copy must agree with this file; when
they don't, the code is wrong, not the glossary. Code mappings are current as
of 2026-08-27 and updated in the same commit that renames a symbol.

**Naming rule (P24):** a **tool** is deterministic host code (no model); a
**subagent** has a model in the loop. The same word must not describe both.

This is the *domain* vocabulary. The *UI* vocabulary (component/region names
for the shell — sidebar, toolbar, inspector, …) is the separate component/region
registry defined by P19.1 (D5). Two vocabularies, one principle: names are
load-bearing, so they are written down and pinned by tests where they are
machine-readable.

## Modes

| Term | Meaning | In code |
|---|---|---|
| **agent** | The default mode. Reads, writes, plans, and *escalates to orchestration* when a task warrants it. The app's normal behavior. | `AgentController` + `AgentView`; the `dispatch` tool and the pool are its escalation paths. Not a named enum today — it is "the app." |
| **chat** | Read-only conversation: answer, explain, propose — no mutation. Reached via `/chat`, or auto-detected when the prompt looks like a question rather than a task. | Formerly the `/orchestrate` command's read-only worker (renamed when the glossary reserved "orchestrate" for the coordination loop). Write-gating already exists: `ToolCallbackResponder` consent confines file tools and gates shell. |
| **orchestrate** | The coordination loop: *plan → per-task handoff packets → dispatch implementers → validate → iterate → write files*. Escalated-to by agent mode, or forced via `/orchestrate`. | `PacketRole` (decompose/implement/repair), `DispatchPacketBuilder`, `DispatchReceipt`, `PoolOrchestrator` (headless), `OrchestrateDirective` (the app's `/orchestrate` directive, P20). **Not** the removed `OrchestrateCommand` — that thin read-only delegation is now chat. |
| **fast reply** | A think-off, toolless per-turn control — the cheap quick answer. A sub-mode of a turn, not a verb. | None yet (P23, planned). |

## Roles

Roles differ by their bounding policy — how much deliberation is useful and
how expensive failure is — not by persona text.

| Term | Meaning | In code |
|---|---|---|
| **orchestrator** | The coordinating role: writes the plan, builds each task's handoff packet, interfaces with outside context, iterates, evaluates implementer results against validation. Writes files. | `DispatchPacketBuilder` ("the orchestrator model supplies the objective"), `DispatchReceipt` ("folds back from a worker into the orchestrator's next turn"), `PoolOrchestrator`. |
| **implementer** | A tightly-bounded subagent doing one task; mistakes expected. | `PacketRole.implement`, `ContextAssembly` (sizes the brief to the implementer), pool workers. |
| **decompose** | Read a spec, emit the plan/phases — the plan step of orchestration. | `PacketRole.decompose`, `Decompose.swift`. |
| **repair** | Fix an implementer's mistake. | `PacketRole.repair`. |

## Mechanisms

| Term | Meaning | In code |
|---|---|---|
| **dispatch** | The orchestrator's per-task verb: hand one bounded task to an implementer in an isolated worktree, get back a candidate ref or a typed receipt. Not a user surface. | `HandoffPacket`, `WorktreeDispatcher`/`WorktreeDispatch`, `DispatchOutcome`. The old GUI form (`DispatchView` + `AgentController.dispatchAttempt`) was dissolved 2026-08-27. |
| **handoff packet** (P10) | The typed contract a dispatched attempt runs under: objective (`taskText`), the exact `writableFiles` (worktree-relative), the `validationCommand` the parent will actually run, a per-file `FileBaseline` (`sha256` + `lineEnding` + Unix `mode`) read from the worktree at dispatch time rather than guessed, and turn/tool-call budgets. The worker gets `read`/`write`/`edit` (+`list`/`search` as read aids) and no `bash`; every mutation is revision-checked against `writableFiles`. It consumes P9's host-authoritative facts — success is never inferred from prose. | `HandoffPacket`. |
| **candidate ref** (P10) | The reviewable commit a dispatched attempt returns when the turn ends without a revision-check violation and (when the packet's `validationCommand` is set) validation passes: the dispatcher commits the worktree's diff to a throwaway branch and returns the SHA. The ref resolves via `git rev-parse` after the worktree is removed (the commit object survives); the parent reviews it. Nothing merges automatically. | `DispatchOutcome`. |
| **receipt** (P10) | The typed refusal a dispatched attempt returns otherwise, naming the reason: a mutation outside `writableFiles` (`.refusedTool`, first offending path), a turn/tool-call budget exceeded (`.budgetExceeded`), the validation command failing (`.validationFailed`, exit status + stdout digest), or no mutations (`.noChanges`). The reason is machine-computed from P9's `TurnOutcome`, not inferred from the transcript. | `DispatchReceipt`. |
| **revision check** (P10) | The membership test a dispatched attempt runs on every mutation: a `write`/`edit` whose workspace-relative path is not in the packet's `writableFiles` is refused host-side, so an out-of-set write never lands in the worktree. Two checks by design — the host-side refusal is the production confinement; the pure verdict's `.refusedTool` is the backstop (a mutation that *is* in `allowedMutations` but outside `writableFiles` — a symlink escape, or a scripted test mutation). | `ToolCallbackResponder.consent` (host-side refusal). |
| **tool** | Deterministic host code — no model, millisecond Swift (P24 naming). Today: the host-executed file/shell tools; later P24's `test`/`scout`/`lint`. | `ToolCallbackResponder` (consent/respond); P24. |
| **subagent** | A model-backed session (P24 naming) — the escalation that applies or summarizes when a tool's digest isn't decision-adequate. | pool workers, `PacketRole` roles. |
| **pool** | Context-isolated sessions sharing one locked engine; a worker is a session id on the pooled wire. | `PoolEngine`, `PoolScheduler`, `WorkerId`, `--subagent-pool`. |
| **variant** | A first-class model the app can run: identity, model file, family, declared sampler, and an enforced **runtime contract** (architecture, rope, quant layout, memory budget) verified before any engine spawn. A variant is *not* a file path — a bare `modelPath` is the unverified escape hatch. | `Variant`, `VariantRegistry` (identity), `VariantResolver` (path resolution), `VariantGate.admit` (contract + memory admission), `VariantVerifier` (gguf metadata vs contract). Registered today: Mellum 2.1. Laguna S is the *default* but has no Variant, so it is ungated; Laguna XS's lives on `p13-laguna-xs-variant`. |
| **pre-chewed context** | The condensed, RLM-digested context a worker receives (plus the ability to pull more relevant bits). Context *strategy*, not a user verb. | `RollingDigest`, `ContextAssembly`, the RLM lever (backlog). |

## Concepts

Design vocabulary from ROADMAP.md's former "Concept budget" — terms that name
something the design needed at the phase cited, checked against the same bar
as Modes/Roles/Mechanisms above: a term earns its place by naming something
the design actually needs, not by being convenient shorthand.

- **feasibility** (P3) — the engine's startup memory plan vs. available RAM,
  computed, with an actionable refusal (deficit, levers, re-check number).
- **seam** — the spawned-child-plus-wire boundary between the app and the engine.
- **wire** — the byte stream on that seam (P2: SSE from `ds4-server`).
- **capture** — a byte-for-byte recording of the seam (wire + stderr + trace),
  timestamped on the wire and anchored in wall-clock by its provenance.
- **handshake** — the wire's first line: a version/capability `hello` object; a
  consumer refuses a mismatch loudly (binding rule 7).
- **trace** — the engine's `--trace` channel, a separate timestamped file carrying
  what the wire suppresses (compaction rebuild stats); captured alongside the wire.
- **fixture** — a committed capture used by tests.
- **finding** (P6) — a machine-computed diagnostic result: a typed value with a
  severity and the computed numbers it reports; phrased by a deterministic
  renderer now, a model later.
- **baseline** (P6) — a session's own early prefill throughput (highest
  `prefill_tps` at `ctx_used ≤ 8,192`), against which later throughput is
  compared; the session measures itself, no external calibration.
- **diagnostic** (P6) — a finding the analyzer computes from a capture, never a
  model's judgment. The model only phrases.
- **workspace** (P7) — the confinement root plus the cwd the app grants at
  spawn (`--workspace`); the file tools (`read`/`more`/`write`/`list`/`edit`/
  `search`) fail closed outside it — an unresolvable or escaping path is
  refused, not silently `chdir`'d.
- **tool card** (P7) — the transcript's per-call reconstruction of one tool
  invocation from the wire's phase stream (`start`/`tool`/`param_*`/`output`/
  `finish`); appended at the `tool` phase, mutated in place by `param_end`/
  `output`/`finish`, keyed by `idx` scoped to the current block.
- **turn outcome** (P7) — the capture-grade per-turn record (model/build/sampler
  and task, token and context use, stop reason, and each tool-call lifecycle
  transition) that P10's handoff packets consume instead of trusting the
  transcript's prose.
- **bootstrap** (P8) — the deterministic skills index `SuperpowersBootstrap`
  renders from a skills dir (`name`/`description` front-matter, sorted by name,
  one line per skill), passed to the agent via `ds4-agent -sys`; the engine's
  existing `sysprompt.kv` rebuild-on-mismatch makes it "prefilled once." A
  missing skills dir degrades to "No skills available in this workspace."
  rather than fabricating skills the agent cannot `read`.
- **progressive disclosure** (P8) — the index lives in the system prompt; the
  full skill bodies are staged into the workspace (`.swiftstar/skills/<name>/`)
  at spawn and `read` on demand inside the workspace grant. The bootstrap never
  inlines skill bodies, so the agent pays the prefill cost only for the skills
  it loads.
- **tool request** (P9) — the `--host-tools` wire event the engine emits on stdout
  when the host owns execution: `{"t":"tool_request","idx":N,"name":"<tool>",
  "params":[…],"ts":<µs>}`, one per tool call in a block. The engine blocks on a
  matching `tool_result` from stdin; a mismatched `idx` or any non-`tool_result`
  line is a loud refusal. `hello` advertises `"tool_request"` in `caps` iff the
  flag is set.
- **tool result** (P9) — the host's answer on stdin:
  `{"t":"tool_result","idx":N,"ok":true|false,"s":"<condensed result text>"}`.
  `ok:false` is a result, not an absence — the engine consumes it and continues.
  The `s` is condensed (`ToolResultCondenser`, cap 8000) before it enters KV.
- **host tool execution** (P9) — the app owns tool execution: with `--host-tools`,
  the engine emits `tool_request` and blocks; the app's `ToolCallbackResponder`
  enforces the workspace/shell consent, executes the call, condenses the result,
  writes the `tool_result` back, and records the host facts into the per-turn
  `TurnOutcome`. Without the flag the engine executes internally and the wire is
  observation-only.
- **rolling digest** (P11) — the objective-independent "always-want" reduced
  form of the conversation, maintained incrementally and inference-free by the
  host: strip tool noise, keep the host-authoritative ledger (files touched,
  refs, receipts, exit statuses). Backed by the session `.kv` rendered text for
  crash recovery. The packet-maker's extraction reads this, never the raw
  conversation — Layer 1 of context distillation, pre-chewed before the
  objective is known.
- **context assembly** (P11) — the packet-maker's `deterministic-load → rolling
  digest → adaptation → packet` pipeline: the `dispatch` tool's objective plus
  the digest plus staged read names plus the deterministic adaptation (D7) become
  a *prepared* packet `taskText`, not P10's bare sentence.

## Retired / renamed

| Old name | New name | Why |
|---|---|---|
| `/orchestrate` (the read-only worker command) | **chat** | It delegated a read-only question, not coordination. "Orchestrate" is reserved for the coordination loop. |
| Dispatch tab / `DispatchView` | (none — internal `dispatch`) | Dispatch is the orchestrator's verb, not a user surface; the GUI form is dissolved. |
