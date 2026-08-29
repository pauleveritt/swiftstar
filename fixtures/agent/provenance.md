# `golden.ndjson` — capture notes (P9 recapture at submodule `c21b831`)

This fixture is a **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from one real
`--json-events` session, captured by the committed `swiftstar-drive` program (P5 driver).
Nothing was hand-written or reformatted. It supersedes the P5 capture (`24caf7b`) and the P7
recapture (`35bf505`): the wire still carries the **version handshake** (first line) and a
**monotonic `ts` on every event**, and the capture format still includes the engine's
`--trace` output (`golden.trace`) and stderr (`golden.stderr`). The P9 recapture re-verifies
all of that against the rebuilt binary at submodule `c21b831` and, additionally, proves **D1**:
the `--host-tools` flag (divergence #10) is off by default, so the bare-CLI wire is unchanged —
**observation-only, no `tool_request` events** — while the D12 turn-outcome fields
(`stop_reason`/`generated`/`ctx_used`) the P7 bump added to every turn-end `ready` are intact.

## Provenance

- Submodule (`external/ds4`) SHA: `c21b8319866c2ac625d0c1dab7dc2d0aa75aee18`
  (the P9 bump — `--host-tools` tool-callback wire (divergence #10): the host owns tool
  execution; the engine emits `tool_request`/`tool_result` over the same pipe. The flag is off
  by default, so the bare wire here is observation-only. The amend over `741f722` also closes the
  `hello` `caps` array the `741f722` edit dropped — see "D1 + the hello `caps` fix" below. The
  SwiftStar gitlink pins this exact SHA; the P5 capture was at `24caf7b`, the P7 at `35bf505`.)
- Built with: `just engine` (`make -C external/ds4 ds4-agent`). Binary run in place,
  `external/ds4/ds4-agent`, with `currentDirectoryURL = external/ds4` (so relative
  `metal/*.metal` sources resolve — no `--chdir`, no `DS4_METAL_*_SOURCE` vars; this capture
  uses no `CAPTURE_WORKSPACE`/`CAPTURE_SHELL`, so the P5 spawn shape is unchanged).
- Captured by: `swiftstar-drive` (`CAPTURE_GGUF=<path> just capture`), which
  spawns the engine, feeds prompts over a kept-open stdin pipe one turn at a time, tees stdout
  and stderr byte-for-byte, and points `--trace` at `wire.trace`.
- Model file: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1, 48 GiB) at
  `~/projects/ds4/gguf/`.
- `DS4_LOCK_FILE=/tmp/ds4-capture-<pid>.lock`.
- Wall-clock start: `2026-08-23T05:26:25Z`; handshake `ts` anchor: `328057802413`.

## What the handshake adds

The first non-blank line is the version/capability handshake:

```json
{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":328057802413}
```

Every event carries `"ts"` — monotonic microseconds since engine start
(`clock_gettime(CLOCK_MONOTONIC)`). A consumer that needs a capability not listed, or a
version it does not know, must refuse loudly (binding rule 7). The P1 receive-time sidecar is
retired; the wall-clock start is recorded in `provenance.md` for correlation with the trace's
wall-clock stamps. With `--host-tools` off (the bare-CLI shape here), `caps` is the same seven
kinds as P5/P7 — `tool_request` is advertised only when the flag is set (see
`golden-tools.provenance.md` and the round-trip evidence in
`docs/superpowers/research/2026-08-22-p9-verification-record.md`).

## D12 turn-outcome fields (P7 bump, still present at `c21b831`)

The turn-end `ready` events carry `stop_reason` / `generated` / `ctx_used` (divergence #9 /
D12, added by the `35bf505` bump; unchanged by the `741f722`/`c21b831` P9 bump). Both turns
here ended cleanly:

```json
{"t":"ready",...,"stop_reason":"eos","generated":<N>,"ctx_used":<N>,"ts":…}
```

`stop_reason` is `eos` for these simple text-only prompts (no tool calls, no context-full, no
interrupt). The startup `ready` carries none of the three (they are turn-end fields, absent
from the boot ready — same shape as the memory-plan fields). The fixture is still **text-only**:
`grep -c '"phase"'` is `0` and `grep -c '"t":"tool"'` is `0` — no tool-call block opens, so
Task 6's no-tool-events assertion on `golden.ndjson` still holds. The `golden-tools.ndjson`
fixture is the one that exercises the tool-phase zoo.

## D1 + the hello `caps` fix (P9 bump)

The P9 bump adds `--host-tools` (divergence #10): the host owns tool execution, and the engine
emits one `tool_request` per call on stdout and blocks on a matching `tool_result` from stdin.
The flag is **off by default**, so the bare-CLI wire here is **unchanged** — `grep -c
"tool_request"` is `0` (proves D1: the bare path is observation-only; only the
`golden-tools`/round-trip path exercises the request/result wire). The `hello` `caps` array
is the same seven kinds as P5/P7 (`tool_request` appears only when the flag is set).

**The hello `caps` fix.** The `741f722` commit that added the conditional `,"tool_request"`
into `agent_emit_hello` dropped the `"]"` the parent `b91401d` closed the `caps` array with, so
the emitted `hello` was invalid JSON (`..."queued","ts","ts":<n>}` — the array never closed).
The live recapture refused it (`wire handshake refused`); `ds4_agent_test` did not catch it
(no test parsed the `hello` JSON). The `c21b831` amend closes the `caps` array after the
conditional and adds `test_agent_emit_hello_caps_array_closes` (red-then-green verified), so
the `hello` is valid JSON in both the on/off shapes. This is the defect the recapture caught.

## The memory-budget verification (and the scratch under-report)

The `ready` event's four memory fields agree exactly with the `ds4: memory:` boot line on
stderr (same cached startup memory plan). Captured boot line:

```
ds4: memory: KV 1.57 GiB (raw 1.57 + compressed 0.00) + buffers 0.00 GiB + resident model 44.94 GiB = 46.51 GiB planned
```

| field | `ready` bytes | bytes / 1024³ (2 dp) | boot-line figure | match |
|---|---:|---:|---:|:---:|
| `kv_bytes` | 1,686,110,208 | 1.57 GiB | KV **1.57** GiB | yes |
| `scratch_bytes` | 784,752 | 0.00 GiB | buffers **0.00** GiB | yes |
| `model_bytes` | 48,257,070,080 | 44.94 GiB | resident model **44.94** GiB | yes |
| `planned_bytes` | 49,943,965,040 | 46.51 GiB | **46.51** GiB planned | yes |

**This fixture carries the P11 scratch under-report verbatim.** The stderr also carries:

```
ds4: memory detail: ctx=32768 prefill_cap=1 raw_kv_rows=32768 compressed_kv_rows=512 backend=metal
ds4: Laguna GPU graph: ctx=32768, prefill=16384, KV 1.57 GiB, scratch 5862.21 MiB
```

`ready.scratch_bytes` says `784752` (the estimator's single-row value), but the allocator's own
boot line reserves **5862.21 MiB (~6.1 GB)** of session scratch (`prefill_cap=16384` rows). The
two numbers disagree by ~7,800× — the exact under-report documented in
`docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md`. Do not let the
`ready` bytes be read as the real scratch reservation.

## Prompts sent, in order

All prompts were sent by writing one line to the kept-open stdin pipe and waiting for the
`ready`-event count to advance (a fresh turn boundary) before sending the next, so none was
queued.

1. `Explain, in three sentences, why the sky is blue.`
2. `List the first ten prime numbers.`

These are deliberately simple — the recapture's job is to re-verify the wire contract
(handshake, `ts`, status/ready shape, D12 turn-outcome fields) against the rebuilt binary, not
to re-exercise the full tool-phase zoo. That zoo (`read`/`write`/`edit`/`list`/`bash`, the
block `start`/`tool`/`param_*`/`finish` sequence, a bash `output`, and the D12 `stop_reason`
on every turn-end) is covered by the P7 `golden-tools.ndjson` fixture (see
`golden-tools.provenance.md`), captured the same day against the same `35bf505` binary.

## Event counts

- Kinds: `hello` (1), `status` (18), `ready` (3), `text` (19). No `think`/`tool`/`queued`/
  `tool_request` (D1: the bare wire is observation-only).
- `status.state` values observed: `idle` (4), `prefill` (4), `generating` (10).
- All 3 `ready` events carry all four memory fields, byte-identical across the session.
- The 2 turn-end `ready` events carry `stop_reason:"eos"` plus `generated`/`ctx_used` (D12);
  the startup `ready` carries none (turn-end fields, like the memory-plan fields).
- `golden.trace` has 2 `prefill sync done` lines (one per turn) — the count the
  `TraceParserTests.goldenTraceParsesWithoutRefusing` assertion pins.

## Count/band drift (within tolerance)

The P5 capture (`24caf7b`) had 43 wire lines / 19 `status` / 5460 bytes; the P7 recapture
(`35bf505`) had 45 / 20 `status` / 5833 bytes; this P9 recapture (`c21b831`) has 41 wire lines
/ 18 `status` / 5291 bytes. The drift is count/band only — generation cadence varies
run-to-run, so `status`/`text` counts move. The test-critical values are unchanged:
`planned_bytes` is still `49_943_965_040` (the
`FixtureReplayTests.replayYieldsStatusAndReadyThroughReducer` hard-coded value), the trace
still has 2 prefill syncs (`TraceParserTests`), the capture is still text-only and
`tool_request`-free (`DiagnosticsEvidenceFloorTests` no-critical-findings floor + D1), and the
memory-plan bytes are byte-identical. No exact-value assertion drifted; only the run-to-run
cadence counts moved.

## Recapture rule

This fixture is the sanctioned output of `swiftstar-drive`. **On every submodule bump, it must
be recaptured** against the freshly rebuilt binary (`just engine`, then `just capture`),
because a rebase can apply cleanly and still be semantically wrong — and the handshake
version/caps, the D12 turn-outcome fields, the `ts` monotonicity, and (P9) the
`tool_request`-free bare wire are all part of what a recapture re-verifies. The P9 recapture
caught the `hello` `caps` defect this way (see "D1 + the hello `caps` fix" above) — the very
reason the rule exists. The recapture must also be copied to the bundled
`Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` so the integration-tier
`FixtureReplayTests.bundledFixtureMatchesRepoFixture` assertion (bundled == repo) stays green —
the P5 precedent (`9e97bc3`) established that both copies move together.

**This is manual, and stays manual (2026-08-29 audit).** A relative symlink from the
`Resources/` copy to this fixture was tried and rejected: SwiftPM's resource-copy build step
(`.process("Resources")` in `Package.swift`) preserves the symlink instead of dereferencing it,
and the relative target breaks once relocated into
`.build/.../SwiftStar_SwiftStarAppKit.bundle/` — confirmed by running
`bundledFixtureMatchesRepoFixture` against the symlinked tree, which failed with "no such file"
from `Bundle.module`. Until a build-time resource-generation step exists (out of scope for a
plain-file fix), the two copies are kept in sync by hand; see the doc comments on
`FixtureReplay` and `DiagnosticsFixture` (`Sources/SwiftStarAppKit/`), the two consumers of the
bundled copy, for the same note at the point of use.

## P11 recapture (2026-08-23) — submodule `d351b40`

Recaptured against the rebuilt binary at submodule `d351b40346629269cbd3639f9cec0345b8d94b1b`
(the P11 bump — `--subagent-pool` flag + worker-id wire + N-session multiplex, divergence #11).

**N==1 additive proof (the standing-rule check).** The recapture ran with the *default*
argv — no `--subagent-pool`, so `num_workers == 1`. Verified against the prior
`c21b831` capture:
- `hello` is structurally identical: `caps` = `["status","ready","text","think","tool","queued","ts"]`
  — no `pool` cap, no `tool_request` cap (observation-only, `--host-tools` off).
- **Zero `"worker"` fields** on any event (the worker field is emitted only when
  `num_workers > 1`, so the single-session wire is byte-identical).
- Same event kinds (`hello`/`status`/`ready`/`text`); only the model's sampled text and
  the per-event `ts` differ run-to-run, as expected.

Captured by `swiftstar-drive` (`CAPTURE_GGUF=<laguna-s-2.1 gguf> CAPTURE_CTX=32768 swift run
swiftstar-drive`), the same P5 spawn shape (no `CAPTURE_WORKSPACE`/`CAPTURE_SHELL`).

## P23 recapture (2026-08-28) — submodule `1a2dddf`

Recaptured against the rebuilt binary at submodule
`1a2dddff899e202914b15ea8ff35787b48045735` (P23 bump — divergence #14, per-turn
think + per-worker ctx). Same P5 spawn shape, same model, same `CAPTURE_CTX=32768`,
same two prompts, no `--per-turn-think` (the flag was deliberately **not**
passed — this fixture proves the cap stays absent when the flag is off).

**`hello` unchanged mod `ts`** (the recapture gate): `caps` =
`["status","ready","text","think","tool","queued","ts"]` — no `think_override`,
confirming the cap is flag-gated. **`golden.trace`'s sysprompt path is now
ctx-qualified** (`sysprompt-32768.kv`, was the fixed `sysprompt.kv`) — the
owed, expected diff from the ctx half of divergence #14 (D8).

**This recapture retires the P11 scratch under-report.** The memory-budget
table below (from the "scratch under-report" section above) is now:

| field | `ready` bytes | bytes / 1024³ (2 dp) | boot-line figure | match |
|---|---:|---:|---:|:---:|
| `kv_bytes` | 1,686,110,208 | 1.57 GiB | KV **1.57** GiB | yes |
| `scratch_bytes` | 6,146,969,608 | 5.72 GiB | buffers **5.72** GiB | yes |
| `model_bytes` | 48,257,070,080 | 44.94 GiB | resident model **44.94** GiB | yes |
| `planned_bytes` | 56,090,149,896 | 52.24 GiB | **52.24** GiB planned | yes |

`kv_bytes` and `model_bytes` are byte-identical to the P9 capture; only
`scratch_bytes`/`planned_bytes` moved, and `scratch_bytes` now agrees with the
boot line's `Laguna GPU graph: ... scratch 5862.21 MiB` figure — the exact
figure the P9 section above flagged the wire as **under-reporting** (784,752
bytes vs. the boot line's ~6.1 GB). Traced to submodule commit `0e13e14`
("Enable chunked Laguna XS prefill", 2026-07-27) — a `laguna-s2.1` fix,
unrelated to P23, that landed between the P9 capture SHA and this pin and
corrected the prefill-graph scratch estimator (previously "a one-token
scratch" regardless of the real prefill-chunk width, per that commit's own
message). **This is not a P23 config mismatch** — the fixture was simply never
recaptured since that fix landed. `planned_bytes` is `56_090_149_896` in
`FixtureReplayTests.replayYieldsStatusAndReadyThroughReducer`'s pinned
assertion as of this recapture (was `49_943_965_040`).

Copied to the bundled `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}`
per the recapture rule.

**Two capture passes.** The first pass (this same session) hit
`sysprompt-32768.kv` cold — no file existed yet under the new ctx-qualified
name for this model — so the sysprompt load was a full re-prefill (a third
`prefill sync done` line, `cached=0`), one-time fallout from D8's path
rename, not a wire-shape change. The committed fixture is the **second**
pass, run once the cache was warm: back to the original two-sync shape (one
per prompt), `sysprompt kv hit` on `sysprompt-32768.kv`. `kv_bytes`/
`scratch_bytes`/`model_bytes`/`planned_bytes` are identical across both
passes (the memory plan is fixed at model load, before either sysprompt path
is taken). `golden.trace`'s two `prefill sync done` lines: `prompt=1017
cached=951 suffix=66` and `prompt=1119 cached=1103 suffix=16` — totals
2136/2054/82, the value now pinned by
`TraceParserTests.goldenTraceSumsBothPrefillSyncLines` (was 2176/2090/86;
count/band drift only, same as every prior recapture — see "Count/band
drift" above).

## `pool.ndjson` — first real 2-worker capture (2026-08-23)

`fixtures/agent/pool.ndjson` is a **verbatim** capture of `ds4-agent -c 16384 --metal
--non-interactive --json-events --host-tools --subagent-pool 2`, driven by two prompts: a
bare prompt (→ worker 0) and a `PoolPrompt` (`{"s":…,"t":"prompt","worker":1}` → worker 1).
35 lines: `hello` advertises the `"pool"` and `"tool_request"` caps and `"worker":0`; worker
0's and worker 1's turn events are each tagged with their worker id. This retires the
hand-authored `pool.ndjson` stand-in that was created against the typed contract before the
C patch landed (D2). Submodule `d351b40`; wall-clock 2026-08-23.
