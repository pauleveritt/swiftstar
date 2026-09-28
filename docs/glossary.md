# Glossary

The naming authority for SwiftStar's domain terms. Type names and UI copy must
agree with this file; when they don't, the code is wrong, not the glossary.
Code mappings are current as of the P28 cut-over (2026-09-28) and updated in
the same commit that renames a symbol.

Since P28 SwiftStar is a front-end for one ds4-engine session. Most of the
older vocabulary (orchestrate, dispatch, pool, variant, handoff packet) named
machinery that was removed; it is listed at the end so old documents stay
readable.

## Terms

| Term | Meaning | In code |
|---|---|---|
| **engine** | ds4-engine, a sibling project. It owns the model, memory plan, tools, candidate worktree, session capture and evals. SwiftStar spawns it and never links it. | `EngineCommand` (executable and argv), `EngineSession` (the child process). |
| **`ds4-dogfood`** | ds4-engine's command-line entry point. SwiftStar runs `ds4-dogfood tui --ndjson --source <root> --commit HEAD`. | `EngineCommand`. |
| **seam** | The spawned-child-plus-wire boundary between the app and the engine. | `EngineSession`. |
| **wire** | The byte stream on that seam: NDJSON on the engine's stdout, JSON commands on its stdin. | `EngineWireParser`. |
| **handshake** | The first stdout line, `{"kind":"ready","protocol":1}`. Anything else ends the session with a protocol error. | `EngineWireParser`, `EngineEvent.ready`. |
| **session** | One held engine process: from spawn to `close`. There is one session at a time. | `EngineSession`, `EngineController`. |
| **session directory** | The engine's capture directory for a session, under `~/.local/state/ds4-engine/sessions/`; the parent of `closed.capture_path`, else the `Session artifacts:` stderr line. | `EngineEvent.closed`. |
| **candidate diff** | `candidate.diff` in the session directory: the edits the engine made in its own worktree. Nothing reaches the user's checkout until applied. | shown by the app, never applied by it. |
| **apply** | `ds4-dogfood apply <id>`, run in a terminal, where `<id>` is the session directory's last path component. SwiftStar shows the command; it has no Apply button. | `EngineController`. |
| **turn** | Prompt to `input`. The engine is busy for the whole turn, across native calls and tools. | `EngineTranscript`. |
| **pause** | A `checkpoint` event: the engine stopped between native calls and reported a snapshot. The unit of metrics; there is no live throughput. | `PauseMetrics`, `EngineEvent.pause`. |
| **prefill / generation tok/s** | `prefill_tokens / sync_ms` and `eval_count / eval_ms` from a pause's snapshot. A field the snapshot lacks yields no rate rather than zero. | `EngineMetricsReducer`. |
| **context used** | Absolute tokens in context, from `answer`. Thresholds anchor on this, never on a fraction of the window. | `EngineMetricsReducer`. |
| **tool card** | The transcript's rendering of one tool call: `tool_start` (op, path), `tool_end` (status, duration), `tool_result` (kind, preview, truncated). | `EngineTranscript`, `AgentToolCardView`. |
| **notice / refusal** | System row and error row for the engine's replies to slash commands (`help`, `status_report`, … and `apply_refused`, `resume_refused`, …). | `EngineEvent.notice`, `EngineEvent.refused`. |
| **fixture** | Raw stdout of a real `ds4-dogfood tui --ndjson` run, committed under `fixtures/engine/` with a `provenance.md`. | `just capture SCENARIO`. |
| **fake `ds4-dogfood`** | A small Python stand-in that replays a fixture and honours `prompt`, `stop`, `quit`, `0x03` and stdin EOF; the integration tier's engine. | `fixtures/engine/fake-ds4-dogfood`. |
| **workspace** | The folder the user picks; its git root is passed as `--source`. A non-repository ends in the engine's exit-2 refusal. | `EngineCommand`. |

## Retired at P28

Terms from the pre-P28 app. The machinery is gone; the words remain in
`docs/superpowers/` and `docs/harvest/`, kept as written.

| Old term | What it was | Now |
|---|---|---|
| `ds4-agent`, `ds4-server`, the fork | The forked C engine and its two binaries, carried as `external/ds4`. | ds4-engine. |
| `--json-events` wire, `hello`, trace | The fork's NDJSON dialect, its handshake, and its `--trace` side channel. | `--ndjson`, `ready`. |
| host tools, `tool_request`, `tool_result`, condenser | The app executing the agent's tools and condensing results before KV. | The engine runs its own tools. |
| orchestrate, decompose, implementer, repair, `PacketRole` | The coordination loop and its roles. | Removed. |
| dispatch, handoff packet, candidate ref, receipt, revision check | Worktree-isolated attempts under a typed contract. | The engine's candidate worktree and `candidate.diff`. |
| pool, worker, rolling digest, context assembly | Context-isolated subagent sessions on one engine. | Removed. |
| variant, feasibility | A model as a runtime contract, and the memory-admission gate. | The engine chooses the model and admits memory. |
| capture, finding, baseline, diagnostic | SwiftStar-side session recording and the deterministic analyzer. | The engine's session directory. |
| bootstrap, progressive disclosure | The staged Superpowers skills index. | Removed. |
| chat, fast reply | A read-only mode and a think-off turn. | Slash commands go to the engine verbatim. |
| turn outcome | The capture-grade per-turn record the handoff packet consumed. | Removed. |
