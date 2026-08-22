# SwiftStar P5 design: capture is a program, not a lost file

**Date:** 2026-08-22
**Status:** approved by delegation ("brainstorm and implement it yourself; take your
own recommendations"). The phase list and architecture are settled by `BRIEF.md` /
`ROADMAP.md`; the capture-driver contract is `docs/harvest/capture-driver.md`; the
trace-channel requirement is the roadmap's P5 dependency note.
**Phase:** P5 — Capture is a program, not a lost file.

This spec is the authority on *how* P5 is done. It does not reopen the phase list, the
architecture, or the engine seam.

## Problem

P1's golden captures were taken by a **throwaway** line-stamping script. Three things
were left unfinished, and P6 cannot start without them:

1. **The capture program is still a script, not a committed executable.** The
   predecessor's capture driver was lost twice because it lived as an uncommitted test
   file; P1's bootstrap script is throwaway by design. The roadmap's contract is that
   from P5 onward `swiftstar-drive` is the *only* sanctioned source of a fixture.
2. **The wire has no version and no timestamps.** `json-events.md` confirms the wire
   carries none; P1 faked timestamps with a sidecar. Binding rule 7 says the wire
   announces itself from P5 — a version/capability handshake is the first NDJSON line
   and a mismatch refuses loudly.
3. **The capture format omits the `--trace` channel, and P6 needs it.** Compaction's
   rebuild statistics (`old`, `new`, `tail_start`, `tail`) are deliberately suppressed
   on the `--json-events` wire but already emitted via `agent_trace()` to the file
   opened by `--trace` (`ds4_agent.c:11735`, `agent_trace_time`). "Would compaction
   help" — the diagnostics surface's first job — is answerable only from that trace.

## Gardenable facts (with citations)

- **Emit choke points** (`external/ds4/ds4_agent.c`): five emitters build NDJSON and
  hand each complete line to `agent_publish_raw` (the mutex-protected append-only
  buffer drained to stdout): `agent_emit_event_str` (text/think),
  `agent_emit_tool_event`, `agent_emit_bare_event` (queued/bare ready),
  `agent_emit_ready_event` (memory budget), `agent_emit_status_event` (status).
- **`--trace <path>`** (`ds4_agent.c:714`, `:14126`) opens the trace file with
  `fopen(path, "ab")`; `agent_trace()` (`:1495`) writes timestamped lines to it; the
  timestamp is wall-clock (`CLOCK_REALTIME`, `agent_trace_time`). Compaction's line is
  `compacted reason="…" old=%d new=%d tail_start=%d tail=%d` (`:11735`).
- **No wire timestamps** (`external/ds4/docs/json-events.md`); P1's sidecar stamped
  receive times with `date +%s%N` (`docs/harvest/capture-driver.md`).
- **Binding rule 7** (`BRIEF.md`): the wire announces itself from P5; the handshake is
  the first NDJSON line; a mismatch refuses loudly. Before P5 a parser must not refuse
  the handshake's absence.
- **The swiftstar-drive contract** (`docs/harvest/capture-driver.md`): compose the
  production types (no `@testable` gymnastics), write a capture directory (raw wire
  verbatim + provenance + progress log), be the source of every fixture from P5 onward,
  and be re-run on every submodule bump.

## Decisions

### D1 — `swiftstar-drive` is a committed executable target

A new SwiftPM executable target `swiftstar-drive`, run as `just capture`. It composes
`SwiftStarKit`'s `WireEventParser` (not a copy) to watch for the `ready` event that
marks a turn boundary, and drives the real engine:

- Spawns `ds4-agent --json-events --non-interactive --trace <trace> -m <gguf> -c <ctx>`
  with the P1-documented environment (all 21 `DS4_METAL_*_SOURCE` vars, a
  `DS4_LOCK_FILE`), working directory inside `external/ds4`.
- Feeds prompts through a FIFO on stdin, one at a time, waiting for the `ready`-event
  count to advance before sending the next (the P1 methodology, now inside the program).
- Tees stdout, stderr, and the trace file to the capture directory **byte-for-byte**
  while it also parses stdout for `ready`/`status` events.
- Writes `provenance.md` (submodule SHA, command line, model, ctx, wall-clock start) and
  a `progress.log`.

Env knobs (P1's, kept): `CAPTURE_GGUF`, `CAPTURE_CTX` (default 32768),
`CAPTURE_PROMPTS_FILE`, `CAPTURE_MODEL_LOAD_TIMEOUT` (900s), `CAPTURE_TURN_TIMEOUT`
(900s), `CAPTURE_PROGRESS_LOG`. The output directory is a fresh timestamped directory.

### D2 — The capture format

One capture is one directory:

```
captures/<timestamp>-<model>/wire.ndjson     # stdout, verbatim (handshake + ts + events)
captures/<timestamp>-<model>/wire.stderr     # stderr, verbatim (boot lines, memory plan)
captures/<timestamp>-<model>/wire.trace      # the --trace file, verbatim
captures/<timestamp>-<model>/provenance.md   # command line, SHA, model, ctx, start time
captures/<timestamp>-<model>/progress.log    # live progress lines
```

The verbatim-raw rule applies throughout: nothing is reformatted or hand-written into
the three wire files. Timestamps are **on the wire** (`ts`), so the P1 sidecar is
retired — no sidecar in the format. A committed fixture is a capture directory copied
to `fixtures/`.

### D3 — The wire announces itself: handshake + timestamps (fork divergence #7)

A new engine patch, the seventh divergence in the fork ledger:

- **Handshake.** The first non-blank NDJSON line is
  `{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":<µs>}`
  emitted once at worker start when `--json-events` is active, before any other event.
- **Timestamps.** Every event gains a `ts` field — monotonic microseconds since
  boot (`clock_gettime(CLOCK_MONOTONIC)`; only deltas are meaningful), written by one
  shared helper called from all five emitters and the handshake. The provenance
  records the wall-clock start for absolute anchoring.

The patch lands as ledger divergence #7 (retires when upstream lands structured
events with a version/timestamp), and extends upstream proposal #1. The
recapture-on-submodule-bump rule now covers the handshake too.

### D4 — The parser enforces the handshake and reads `ts`

`WireEventParser` (Kit) gains `private var sawHandshake = false`. On the first non-blank
line:

- `t:"hello"` with a known `v` (1) and the required caps (`status`, `ready`, `ts`) →
  emit `.hello(version: Int, capabilities: [String])`; mark `sawHandshake`.
- anything else as the first line → `.refused(String)` (binding rule 7: refuse loudly).
- an unknown `v` or a missing required cap → `.refused(String)`.

`StatusSnapshot` gains `ts: UInt64`. `ready` and the other events keep their shape; `ts`
on events Swift doesn't model is simply ignored (as `power`/`error` already are).

### D5 — Fixtures recaptured; the sidecar retires

Using `swiftstar-drive` against the freshly rebuilt binary, recapture the agent fixture
so the committed set becomes `golden.ndjson` (handshake + `ts`), `golden.trace` (new),
`golden.stderr` (new), and an updated `provenance.md`. `golden.ndjson.sidecar` is
deleted. `swiftstar-drive` is now the only sanctioned fixture source.

### D6 — Scope discipline

P5 does **not** ship: telemetry-to-disk capture (the `MachineSnapshot` stream — P6's
diagnostics don't need it and P4 already surfaces it live; reopen if P6 needs
cross-correlation), `ds4-server` capture (chat SSE is not the diagnostics wire), or
automating the live capture in CI. `just capture` stays a manual, never-in-CI live tier.

## Done when

1. **Engine patch:** the rebuilt `ds4-agent --json-events` emits the handshake first and
   `ts` on every event; ledger divergence #7 and the upstream-proposal extension are
   committed; the recapture rule mentions the handshake.
2. **`swiftstar-drive`:** `just capture` (with the real weights) produces a capture
   directory with `wire.ndjson`/`wire.stderr`/`wire.trace`/`provenance.md`/`progress.log`,
   all byte-verbatim, and the wire starts with the handshake.
3. **Parser (fast tier):** handshake accept, missing-handshake refusal, unknown-version
   refusal, missing-cap refusal, and `ts` on `StatusSnapshot` are pinned; every existing
   parser test now feeds the handshake first; all shown-fail records stand.
4. **Fixtures:** `golden.ndjson` (handshake + `ts`), `golden.trace`, and `golden.stderr`
   are committed; `golden.ndjson.sidecar` is gone; `just test` and `just integration`
   are green against the recaptured fixtures.
5. **ROADMAP** marks P5 complete; concept budget reviewed (**handshake** and **trace**
   earn definitions; **capture** and **fixture** are already defined).
