# `golden.ndjson` — capture notes (P5 recapture)

This fixture is a **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from one real
`--json-events` session, captured by the committed `swiftstar-drive` program (P5). Nothing was
hand-written or reformatted. It supersedes the P1 capture: the wire now carries the
**version handshake** (first line) and a **monotonic `ts` on every event**, and the capture
format now includes the engine's `--trace` output (`golden.trace`) and stderr (`golden.stderr`).

## Provenance

- Submodule (`external/ds4`) SHA: `24caf7b836084042130b558ae39cd6954389bdbe`
  (branch `swiftstar-integration`, the fork's tip at capture time; the SwiftStar gitlink pins
  this exact SHA).
- Built with: `just engine` (`make -C external/ds4 ds4-agent`). Binary run in place,
  `external/ds4/ds4-agent`, with `currentDirectoryURL = external/ds4` (so relative
  `metal/*.metal` sources resolve — no `--chdir`, no `DS4_METAL_*_SOURCE` vars).
- Captured by: `swiftstar-drive` (`CAPTURE_GGUF=<path> CAPTURE_CTX=32768 just capture`), which
  spawns the engine, feeds prompts over a kept-open stdin pipe one turn at a time, tees stdout
  and stderr byte-for-byte, and points `--trace` at `wire.trace`.
- Model file: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1, 48 GiB) at
  `~/projects/ds4/gguf/`.
- `DS4_LOCK_FILE=/tmp/ds4-capture.lock`.

## What the handshake adds

The first non-blank line is the version/capability handshake:

```json
{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":…}
```

Every event carries `"ts"` — monotonic microseconds since engine start
(`clock_gettime(CLOCK_MONOTONIC)`). A consumer that needs a capability not listed, or a
version it does not know, must refuse loudly (binding rule 7). The P1 receive-time sidecar is
retired; the wall-clock start is recorded in `provenance.md` for correlation with the trace's
wall-clock stamps.

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
(handshake, `ts`, status/ready shape) against the rebuilt binary, not to re-exercise the full
tool-phase zoo that the P1 capture covered. The P1 capture's tool-event coverage
(`read`/`write`/`edit`/`bash`, `idx`, param `name`, finish `calls`, the interrupted-finish
shape) was verified against this same wire contract and is not repeated here.

## Event counts

- Kinds: `hello` (1), `status` (19), `ready` (3), plus `text`/`think` as the model produced.
- `status.state` values observed: `idle`, `prefill`, `generating`.
- All 3 `ready` events carry all four memory fields, byte-identical across the session.

## Recapture rule

This fixture is the sanctioned output of `swiftstar-drive`. **On every submodule bump, it must
be recaptured** against the freshly rebuilt binary (`just engine`, then `just capture`), because
a rebase can apply cleanly and still be semantically wrong — and the handshake version/caps are
now part of what a recapture re-verifies.
