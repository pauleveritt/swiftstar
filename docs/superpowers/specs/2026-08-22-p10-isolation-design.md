# SwiftStar P10 design: Isolation

**Date:** 2026-08-22
**Status:** accepted by delegation (autonomous run).
**Phase:** P10 — Isolation.

This spec is the authority on *how* P10 is done. `BRIEF.md`/`ROADMAP.md` stay
settled.

## Problem

The Agent tab (P7–P9) works in place: the agent edits the workspace directly.
P10 makes a dispatched attempt **isolated**: the app hands the agent a typed
contract and a disposable git worktree, and gets back a reviewable **candidate
ref** (a commit) or a **receipt** (a refusal naming why). Nothing merges; the
caller's tree is never touched. This is what the roadmap's "handoff packet"
backlog entry names, and it consumes the host-authoritative facts P9 added
(actual mutations, command exit status/output digest, whether validation ran)
rather than inferring success from the transcript.

`ROADMAP.md`: "Worktree-isolated dispatch: a handoff packet in, a candidate ref
or a receipt out." The handoff-packet backlog entry: "a typed contract carrying
task text, the exact writable files, the validation command the parent will
actually run, and a per-file baseline of SHA-256 plus line-ending and mode read
from the worktree rather than guessed; the worker gets `read`/`write`/`edit` and
no `bash`, under turn and tool-call budgets, with every mutation
revision-checked." The dispatch-decision backlog entry names the three routing
axes (parallelism, thinking requirement, executor) — P10 implements the
single-attempt, no-bash, full-context case; the routing axes stay backlog.

## Gardenable facts (verified against the source)

- P9 made the wire bidirectional (`--host-tools`): the app owns execution,
  condenses results, and records host facts (mutations, exit status, output
  digest, validation ran) into the `TurnOutcome`. P10's packet **is** the
  writable-file + validation contract, and the candidate's evidence is the
  P9 `TurnOutcome` for the dispatched turn — no inference from prose.
- `git worktree add` gives an isolated checkout with its own branch; `git
  rev-parse HEAD` on that worktree is the candidate ref. The engine (ds4-agent)
  already confines file tools to `--workspace` (P7) and, in host mode, the app
  enforces consent — so a dispatched agent pointed at the worktree with
  `--workspace <worktree>` and shell off can only touch the worktree's files.

## Decisions

- **D1 — `HandoffPacket` is a typed, Swift-side contract.** `taskText: String`,
  `writableFiles: [String]` (exact, relative to the worktree root),
  `validationCommand: String?` (the command the parent will actually run),
  `baselines: [String: FileBaseline]` where `FileBaseline` is `sha256`, `lineEnding`
  (`lf`|`crlf`|`mixed`), `mode` (Unix mode bits) — each read from the worktree at
  dispatch time, never guessed. `turnBudget` and `toolCallBudget` (turn and
  tool-call caps).
- **D2 — the attempt runs in a disposable worktree, no bash, revision-checked.**
  The dispatcher creates a worktree on a throwaway branch, points the agent at
  it (`--workspace <worktree>`, `--shell off`), and the app's host executor (P9)
  records every mutation and **revision-checks** it: a write/edit outside
  `writableFiles` is refused (the host refuses the tool, not the engine). The
  agent gets `read`/`write`/`edit` (and `list`/`search` as read aids); `bash` is
  off (the packet's validation command runs parent-side, not in the attempt).
- **D3 — the outcome is a candidate ref or a receipt.** On a turn that ends
  without a revision-check violation and (when `validationCommand` is set) with
  the validation command passing, the dispatcher commits the worktree's diff to
  the throwaway branch and returns the commit SHA (`candidateRef`). Otherwise it
  returns a typed `receipt` naming the reason (refused tool, budget exceeded,
  validation failed with exit status + digest, no changes). The caller's tree is
  never touched; nothing merges.
- **D4 — the packet consumes P9's host facts.** `DispatchOutcome` (the Swift
  record a dispatch returns) carries the P9 `TurnOutcome` (mutations, exit
  status, output digest, validationRan) as the candidate's evidence, plus the
  candidate ref or receipt. A handoff packet must not be built from, or its
  success inferred from, prose.
- **D5 — single-attempt, in-process.** P10 is the one attempt, the
  full-context agent, the no-bash surface. Parallelism, thinking-requirement
  routing, and the specialized one-command workers stay backlog (they are P11+).
  No new wire; the dispatch uses the existing agent spawn.

## Components

**SwiftStarKit:** `HandoffPacket.swift` (packet + `FileBaseline` + budget types);
`WorktreeDispatch.swift` (pure: the `request → verdict` mapping — given the
packet, the allowed mutations, and the P9 facts, decide candidate vs receipt);
`DispatchOutcome.swift` (candidate ref / receipt).

**SwiftStarAppKit:** `WorktreeDispatcher.swift` (creates/removes the worktree,
reads baselines, runs the validation command, commits the candidate).

**SwiftStar:** `AgentController` runs a dispatched attempt when given a packet
(host mode, shell off, the P9 responder revision-checking against
`writableFiles`); the Dispatch tab (a minimal surface) submits a packet and
shows the outcome.

## Testing

- **Fast tier:** packet/baseline serialization; the pure `request → verdict`
  mapping (allowed mutations → candidate; a mutation outside writable files →
  receipt; validation failed → receipt with exit status/digest; no changes →
  receipt). All typed; no source-text assertions.
- **Integration tier:** a real worktree is created for a fixture repo; a
  scripted attempt writes an allowed file → candidate ref commits it; a write
  outside the set → receipt; `git rev-parse` on the candidate ref resolves.
- **Evidence floor:** the receipt names the reason; the candidate ref is a real
  commit that resolves; the packet's baselines are read from the worktree (a
  changed file differs from its baseline).

## Out of scope

Subagent pool / parallelism / specialized workers (P11); the routing axes
(backlog); merging the candidate (the parent reviews the ref; merge is a human
act); `recall`/session browser (backlog).
