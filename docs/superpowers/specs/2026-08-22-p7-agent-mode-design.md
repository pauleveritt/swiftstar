# SwiftStar P7 design: Agent mode

**Date:** 2026-08-22
**Status:** approved by delegation ("proceed through the spec and plan, following your
own recommendations"). Consent direction A (spawn-time flags) approved explicitly.
**Phase:** P7 — Agent mode.

This spec is the authority on *how* P7 is done. It does not reopen the phase list, the
architecture, or the engine seam. `BRIEF.md` and `ROADMAP.md` stay settled.

## Problem

P0–P6 shipped a working Chat tab (SSE), a fixture-driven Metrics tab, and the
deterministic diagnostics analyzer. P7 makes the **Agent** tab real: it spawns a live
`ds4-agent` child on the NDJSON wire (`--json-events`), renders the stream as a transcript
with **tool cards**, applies two consent controls — a **workspace grant** and a **shell
toggle** — and supports **interruptible turns**.

`ROADMAP.md` states the phase in one line: "Spawn `ds4-agent`, NDJSON transcript, tool
cards, workspace grant, shell toggle, interruptible turns." `BRIEF.md` states the split:
"Chat and Agent stay separate: they are different wires (SSE vs NDJSON), different consent
models, and different products."

## The consent model (the decision that shapes the phase)

The engine (`ds4_agent.c`) currently executes its tools **unconditionally** — only the
web tools (`google_search`, `visit_page`) have a built-in consent gate, and that gate lives
in the engine's own terminal UI, not on the NDJSON wire. The wire is observation-only
through P8; per-tool consent on the wire is P9 (the tool-callback protocol), which
`ROADMAP.md` flags as the schedule risk and says "must not be discovered inside" another
phase.

Three options were weighed:

- **A — spawn-time flags** (chosen): patch `ds4-agent` with `--workspace DIR` (set cwd +
  confine the file tools to `DIR`) and `--shell on|off` (gate the `bash` tools). Real
  gating, set when SwiftStar spawns the session, changeable by starting a new session.
- **B — app-side observation only**: a "toggle" that does not toggle and a "grant" that
  does not confine. Rejected: it is the class of lie this repo exists to avoid, and it
  forecloses P7's *point*, which is the consent model.
- **C — a wire round-trip now**: pull part of P9 forward. Rejected: P9's cost (a
  bidirectional wire plus a fake *app* side) would be discovered inside P7.

**D1 (consent is spawn-time, enforced in the engine).** `--workspace DIR` sets the agent's
cwd *and* confines `read`/`more`/`write`/`list`/`edit`/`search` to `DIR` (fail closed:
an unresolvable or escaping path is refused). `--shell off` removes `bash`,
`bash_status`, `bash_stop` from the tool schema *and* refuses them in dispatch. Without
this patch, "grant" is cosmetic (`--chdir` only changes cwd; the file tools `fopen(path)`
with no confinement — verified in `ds4_agent.c`).

**D2 (engine defaults preserve the bare CLI; the app opts out).** `--shell` absent = `on`,
`--workspace` absent = no confinement (current behavior unchanged for anyone running
`ds4-agent` directly). The *app* always passes both flags explicitly, with the shell
**defaulting to `off`** — the agent gets shell only when the user grants it. This is the
coherent reading of "grant": the app's default posture is deny, and `--shell on` is the
explicit grant.

## Gardenable facts (with citations)

The authoritative wire contract is `external/ds4/docs/json-events.md` (derived from
`ds4_agent.c`, not from any brief). Facts P7 consumes:

- **Event kinds:** `hello | text | think | tool | status | ready | queued`. First non-blank
  line is the `hello` handshake (`v:1`, `caps`). Every event carries `ts` (monotonic µs).
- **`tool` event:** `{"t":"tool","phase":<phase>,"idx":<int>,...}` with phases `start`,
  `tool` (carries `name`), `param_begin` (carries `kind`+`name`), `param_value` (carries
  `s`), `param_end`, `output` (carries `s`), `finish` (carries `calls`, optional `status`).
  `idx` is zero-based **within the current block** and resets at each `start`.
- **`idx` contract:** `start` always `idx:0`; `finish` carries the last real call's `idx`
  (plus `calls`, because `idx:0` alone cannot distinguish "one call" from "zero calls").
  `output` events arrive **after** their block's `finish` and **before the next block's
  `start`** (dispatch is a synchronous loop).
- **Which tools emit `output`:** only `bash`/`bash_status`/`bash_stop` (plus the unknown-tool
  fallback). `read`/`more`/`write`/`list`/`edit`/`search`/`google_search`/`visit_page` never
  emit `output`; their result is only inferable from their `param_*` events and `finish`.
- **No turn-end event.** A consumer infers turn end from `status.state` transitioning to
  `idle` (state changes bypass the 200 ms status throttle, so the transition is never
  coalesced away).
- **`text`/`think` arrive chunked**, not line-delimited: reassemble by concatenation. A
  `text` event's `s` never mixes think and non-think content.
- **Leading-newline quirk:** the first `text` after a `</think>` close starts with `\n\n`
  (renderer artifact). Strip all leading whitespace on the first post-think `text` chunk.
- **Interrupt is an ETX byte, not SIGINT.** `--json-events` requires `--non-interactive`,
  which has no terminal, so it never receives SIGINT. `agent_input_buf_take_interrupt()`
  strips byte `0x03` (ETX) from buffered stdin and latches an interrupt; DS4 Control's
  `AgentSession.interrupt()` wrote the same bare ETX (`ds4_agent.c` ~:514–521). The patch
  set already ships the turn-interrupt + stale-interrupt latch.
- **`--json-events` requires `--non-interactive`** (startup error otherwise); the agent
  reads one prompt per stdin line and emits a `ready` event when idle and waiting for stdin.

The existing `fixtures/agent/golden.ndjson` (P5 recapture) is **text-only** — it carries
`hello`/`status`/`ready`/`text` and **no** `tool`/`queued`/`think` events, because P5's
prompts were deliberately simple. P7 therefore needs a **tool-event fixture** (D7).

## Decisions

- **D3 — a new `AgentWireParser`, not an extension of `WireEventParser`.** `WireEventParser`
  is the Metrics/Diagnostics telemetry parser (`status`/`ready`); its consumers
  (`MetricsReducer`, `DiagnosticsAnalyzer`) switch exhaustively over `WireEvent`. The agent
  transcript needs `text`/`think`/`tool`/`queued` on top, with different required caps
  (`text`,`tool`,`status`,`ts`). Two parsers, one shared `StatusSnapshot`. Clean seam:
  telemetry stays on `WireEventParser`; the transcript gets `AgentWireParser`.
- **D4 — `AgentTranscript` reconstructs tool cards from the phase stream.** A `.tool` row
  is appended when a call's `tool` phase announces its name (so the UI shows a running
  card), then `param_end`/`output`/`finish` phases mutate that row in place. Cards are
  keyed by `idx` scoped to the current block; the key map is cleared at `start` (the wire
  guarantees `output` lands before the next block's `start`, so late `output` is never
  attributed to a same-`idx` call in a following block).
- **D5 — interrupt = write one `0x03` byte to the child's stdin.** No SIGINT, no new wire
  command. The engine latches it, emits `finish.status="[tool call interrupted]"` when
  mid-block, and returns to `idle`.
- **D6 — turn end is inferred**, from `status.state` → `idle` (no turn-end event exists).
  The transcript does not synthesize a turn marker; the controller tracks turn state.
- **D7 — tool fixture via live recapture.** P7 recaptures `golden.ndjson` (re-verifying the
  wire contract at the new submodule SHA — the standing rule) and captures a new
  `fixtures/agent/golden-tools.ndjson` from tool-inducing prompts (`read`/`list`/`write`/
  `edit`/`bash`), committed with `golden-tools.stderr`, `golden-tools.trace`, and a
  `provenance.md`. The fake agent (D8) is generated from this real capture, never
  hand-authored.
- **D8 — a fake `ds4-agent`, generated from the capture** (mirroring `FakeServerSource`),
  for the integration tier. It validates its argv strictly (including `--workspace` and
  `--shell`), replays the NDJSON to stdout, and honors an ETX byte on stdin as an interrupt.
- **D9 — Metrics and Diagnostics stay fixture-driven in P7.** The Agent tab is the live
  surface; re-wiring Metrics/Diagnostics to the live agent's status/trace is not in P7's
  scope (it is a later, separate concern; the live process's `status` events are already
  parseable by `AgentWireParser` when that wiring happens).
- **D10 — think is handled, not toggled.** `--think` is left at the engine default; the
  parser and transcript handle `think` events defensively. A think-effort control is out
  of P7 scope.
- **D11 — web tools out of consent scope.** `--shell` gates only the `bash` tools.
  `google_search`/`visit_page` keep the engine's existing terminal-UI approval (which is
  not on the wire); their consent is a P9/wire concern.

## Components

**SwiftStarKit (pure, fast-tier):**

- `AgentWireParser.swift` — `AgentEvent` (hello/status/ready/text/think/tool/queued/
  ignored/refused), `ToolEvent` (phase + idx), `AgentWireParser`. Binding rule 7: first
  non-blank line must be a v1 `hello` whose `caps ⊇ {text, tool, status, ts}`.
- `AgentTranscript.swift` — `ToolParam`, `ToolCard` (name/params/output/status),
  `AgentTranscriptRow` (thinking/content/tool/system), `AgentTranscript` reducer. Pure,
  tested with hand-built event sequences in the fast tier.
- `AgentCommand.swift` — `AgentSettings` (engineDir/modelPath/contextSize/workspace/
  shellAllowed) and `AgentCommand.argv`/`binaryPath`. The one argv contract, validated by
  the fake agent and unit-tested.
- `FakeAgentSource.swift` — generates the fake `ds4-agent` Swift source from a committed
  NDJSON capture (mirrors `FakeServerSource`).

**SwiftStar (app):**

- `AgentController.swift` — spawns `ds4-agent` (stdin/stdout/stderr pipes), drains stdout
  line-by-line through `AgentWireParser` → `AgentTranscript`, tracks turn state, writes
  ETX on interrupt, enforces the spawn-time consent flags.
- `AgentView.swift` — status bar, transcript with tool cards, composer, interrupt button,
  consent controls (workspace picker + shell toggle). Replaces the Agent placeholder in
  `MainView.swift`.

**Engine (fork, `external/ds4/ds4_agent.c`):**

- `--workspace DIR` and `--shell on|off` flags; file-tool path confinement (fail closed);
  bash gating in schema + dispatch. A fork-ledger row (divergence #8).

**Fixtures:**

- `fixtures/agent/golden-tools.ndjson` (+ `.stderr`, `.trace`, `provenance.md`) — the tool
  capture. `fixtures/agent/golden.ndjson` recaptured at the new SHA.

## Testing

- **Fast tier** (`just test`): parser (hand-built NDJSON lines + `golden.ndjson` +
  `golden-tools.ndjson` via `#filePath`), transcript reducer (hand-built event sequences,
  including the leading-newline quirk and the post-`finish` `output` attribution),
  `AgentCommand.argv`, `FakeAgentSource` determinism. No process/socket (tripwire).
- **Integration tier** (`just integration`): a fake `ds4-agent` (generated from the real
  tool capture) is spawned via the production `AgentCommand` argv; the harness asserts argv
  validation (including `--workspace`/`--shell`), a full stream → transcript with tool
  cards, and interrupt (ETX → the fake emits an interrupted `finish` and stops).
- **Live tier** (`just capture`, never CI): the recapture that produces `golden.ndjson` and
  `golden-tools.ndjson` against the real engine and real weights.
- **Evidence floor (binding rule 6):** the parser accepts both `golden.ndjson` and
  `golden-tools.ndjson` (naming the fixtures) and refuses a non-handshake first line; the
  fake agent is generated from the real tool capture, not hand-authored.
- **Binding rule 2:** every new test is shown to fail before its implementation passes
  (in a compiled language, "fail" = the test target does not compile or the assertion fails).

## Out of scope (Backlog, not this phase)

- Per-tool consent on the wire (P9), tool-result condensation before KV (P9), fake *app*
  side (P9).
- Live Metrics/Diagnostics from the spawned agent (D9).
- Web-tool consent (D11); think-effort control (D10).
- A live mid-turn consent change (spawn-time only; P9 enables live toggles).
