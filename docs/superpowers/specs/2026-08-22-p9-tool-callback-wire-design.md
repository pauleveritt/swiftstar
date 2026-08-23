# SwiftStar P9 design: The tool-callback wire

**Date:** 2026-08-22
**Status:** accepted by delegation (autonomous run).
**Phase:** P9 — The tool-callback wire.

This spec is the authority on *how* P9 is done. It does not reopen the phase
list or the architecture. `BRIEF.md`/`ROADMAP.md` stay settled.

## Problem

Through P8 the NDJSON wire is observation-only: `ds4-agent` executes its own
tool calls internally and the app only watches (`tool` events) plus reads the
text the agent chose to emit. `ROADMAP.md` states the phase: "SwiftStar answers
tool calls over the same pipe — including a fake app side — and condenses tool
results before they enter KV." P9 makes the wire **bidirectional**: when the
host owns tools, the agent emits a tool request and waits for the host to answer
with a condensed result. This is the schedule risk — a protocol design that P10
(isolation) and everything after depend on, and it must carry a fake *app* side
so the integration tier can exercise the round trip without a real engine.

`ROADMAP.md` dependencies: "P9 gates P10 … on an observation-only wire the app
can only watch the C child write files"; "a bidirectional wire also needs a fake
app side; that cost belongs to P9"; "P9 adds the host-authoritative facts:
actual mutations and their paths, command exit status/output digest, and whether
validation ran."

## Gardenable facts (verified against the source)

- The single dispatch chokepoint is `agent_execute_tool_calls` (`ds4_agent.c:11770`):
  it iterates the parsed DSML calls and calls `agent_execute_tool_call` per call,
  then assembles `Tool result N (name): …` text. Its caller (`:12762`) feeds the
  returned text into the existing `agent_tool_result_fits_context` /
  compaction / transcript-append path — so a host-supplied result text rides the
  exact same KV path as an internally-executed one.
- The non-interactive loop (`run_agent_non_interactive`, `:14810`) already reads
  stdin non-blocking through `agent_input_buf` (prompt lines + the ETX interrupt).
  A blocking read of one NDJSON line from stdin during dispatch is a new, small
  addition (the dispatch runs on the worker thread, which may block — the
  generation loop already runs there and already blocks on decode).

## Decisions

- **D1 — the wire is bidirectional, opt-in via `--host-tools`.** A new flag
  makes the agent **request** instead of **execute**: `agent_execute_tool_calls`
  emits one `tool_request` event per call and then blocks reading a matching
  `tool_result` line from stdin. Absent the flag, behavior is byte-for-byte
  unchanged (bare CLI keeps internal execution). The app always passes it (the
  app owns execution from P9 on).
- **D2 — the request/result protocol (documented in `json-events.md`).**
  - Request (stdout, event kind `tool_request`):
    `{"t":"tool_request","idx":N,"name":"<tool>","params":[{"name":"<p>","value":"<v>"},…],"ts":<µs>}`
    — one per call, `idx` scoped to the current block (the existing `idx` contract).
  - Result (stdin, one NDJSON line the host writes back):
    `{"t":"tool_result","idx":N,"ok":true|false,"s":"<condensed result text>"}`
    — the engine matches by `idx`, returns `s` as the tool result (or a refusal
    text when `ok:false`), and proceeds down the existing result→KV path. A
    result for an unknown `idx` is refused loudly (binding rule 7's spirit).
- **D3 — the host executes and condenses.** `AgentController` (the app) gains a
  `ToolCallbackResponder`: on each `tool_request` it (a) enforces the consent
  model host-side (workspace grant + shell toggle, the same rules P7 put in the
  engine — in host mode the app is the enforcement point), (b) executes the tool
  (reusing the app's existing file/process capabilities, or a policy that
  refuses), and (c) condenses the result before writing it back. The condenser
  (`ToolResultCondenser`, SwiftStarKit, pure) is the "condenses tool results
  before they enter KV" piece: a deterministic size cap + tail/head summary, so
  a 4 MB read never enters KV. **Host-authoritative facts** ride the result: the
  responder records the actual mutation paths, the command exit status and an
  output digest, and whether validation ran — feeding the P7 `TurnOutcome`
  (D5 below).
- **D4 — a fake *app* side.** `FakeAppSource` (SwiftStarKit, mirrors
  `FakeAgentSource`) generates a fake app program that reads `tool_request`
  events and answers with canned `tool_result` lines (deterministic, keyed by
  `idx`/`name`), so the integration tier runs fake-agent ↔ fake-app end to end.
  The fake *agent* (P7) gains a `--host-tools` mode: it replays tool blocks and
  then blocks for the app's result before continuing.
- **D5 — outcome telemetry gains host-authoritative facts.** The P7
  `TurnOutcome` tool lifecycle already records `emitted/parsed/rejected/
  executed`; in host mode `executed` is now the host's verdict (the host ran it
  or refused it), and the record gains `mutations: [String]` (paths), and for
  command results `exitStatus: Int?` + `outputDigest: String?` + `validationRan:
  Bool`. These are the facts `ROADMAP.md` says P10's handoff packet must consume.
- **D6 — no new tool semantics; the host runs what the consent flags already
  permit.** The app executes `read`/`write`/`edit`/`list`/`search`/`bash` under
  the workspace grant and shell toggle (P7). Nothing in P9 widens the surface.

## Components

**Engine (fork, `ds4_agent.c`):** `--host-tools` flag (config field, arg parse);
`agent_execute_tool_calls` in host mode emits `tool_request` and blocks on a
`tool_result` line from stdin (a small blocking line reader on the worker
thread); `json-events.md` documents the two new message kinds. A fork-ledger row.

**SwiftStarKit:** `AgentWireParser` gains `.toolRequest(...)`; a
`ToolResultCondenser` (pure, deterministic cap/digest); `ToolCallbackResponder`
logic is pure where possible (the `request → result` mapping is a pure function
over inputs; the side-effecting execution lives in the app target).
`FakeAppSource` (fake app generator). `TurnOutcome` gains the host-fact fields.

**SwiftStar (app):** `AgentController` reads `tool_request` events, routes them
through the responder (execution + condensation), writes `tool_result` lines to
stdin, and records the host facts into the per-turn `TurnOutcome`.

**Integration:** fake-agent ↔ fake-app end to end: the fake agent replays a
tool block, blocks for the result, and continues; the fake app answers.

## Testing

- **Fast tier:** `ToolResultCondenser` (caps, digests, deterministic);
  `AgentWireParser` parses `tool_request`/`tool_result`; `TurnOutcome` host-fact
  fields; `FakeAppSource` determinism.
- **Integration tier:** the round trip (fake agent emits a request, fake app
  answers, fake agent continues with the result); a refused result (`ok:false`)
  surfaces as the tool result; the responder records mutation paths/exit
  status/digest.
- **Live tier:** the recapture at the new SHA re-verifies the observation-only
  wire is unchanged (bare CLI) and, in host mode, a smoke round trip.
- **Evidence floor:** the fake app is generated from the committed capture, not
  hand-authored; the round trip is asserted by naming the fixture.

## Out of scope

Worktree isolation and the handoff packet (P10); subagent dispatch (P11); the
web tools' consent (still P9/wire, but not widened here).
