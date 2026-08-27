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
| **orchestrate** | The coordination loop: *plan → per-task handoff packets → dispatch implementers → validate → iterate → write files*. Escalated-to by agent mode, or forced via `/orchestrate`. | `PacketRole` (decompose/implement/repair), `DispatchPacketBuilder`, `DispatchReceipt`, `PoolOrchestrator` (headless). **Not** the removed `OrchestrateCommand` — that thin read-only delegation is now chat. |
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
| **handoff packet** | The typed per-task contract: objective, exact writable files, validation command, budgets. | `HandoffPacket`. |
| **candidate ref / receipt** | An implementer's outcome: a reviewable commit, or a typed refusal naming why not. | `DispatchOutcome`, `DispatchReceipt`. |
| **tool** | Deterministic host code — no model, millisecond Swift (P24 naming). Today: the host-executed file/shell tools; later P24's `test`/`scout`/`lint`. | `ToolCallbackResponder` (consent/respond); P24. |
| **subagent** | A model-backed session (P24 naming) — the escalation that applies or summarizes when a tool's digest isn't decision-adequate. | pool workers, `PacketRole` roles. |
| **pool** | Context-isolated sessions sharing one locked engine; a worker is a session id on the pooled wire. | `PoolEngine`, `PoolScheduler`, `WorkerId`, `--subagent-pool`. |
| **variant** | A first-class model the app can run: identity, model file, family, declared sampler, and an enforced **runtime contract** (architecture, rope, quant layout, memory budget) verified before any engine spawn. A variant is *not* a file path — a bare `modelPath` is the unverified escape hatch. | `Variant`, `VariantRegistry` (identity), `VariantResolver` (path resolution), `VariantGate.admit` (contract + memory admission), `VariantVerifier` (gguf metadata vs contract). Registered today: Mellum 2.1. Laguna S is the *default* but has no Variant, so it is ungated; Laguna XS's lives on `p13-laguna-xs-variant`. |
| **pre-chewed context** | The condensed, RLM-digested context a worker receives (plus the ability to pull more relevant bits). Context *strategy*, not a user verb. | `RollingDigest`, `ContextAssembly`, the RLM lever (backlog). |

## Retired / renamed

| Old name | New name | Why |
|---|---|---|
| `/orchestrate` (the read-only worker command) | **chat** | It delegated a read-only question, not coordination. "Orchestrate" is reserved for the coordination loop. |
| Dispatch tab / `DispatchView` | (none — internal `dispatch`) | Dispatch is the orchestrator's verb, not a user surface; the GUI form is dissolved. |
