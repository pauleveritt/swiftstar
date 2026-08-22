# SwiftStar P3 design: it can get its weights

**Date:** 2026-08-22
**Status:** approved by delegation (overnight work; the human partner pre-authorized
"work unattended and use your recommendations for spec and plan"). The phase list and
architecture are settled by `BRIEF.md` / `ROADMAP.md` / `2026-08-21-swiftstar-design.md`.
**Phase:** P3 — It can get its weights.

This spec is the authority on *how* P3 is done. It does not reopen the phase list, the
architecture, or the engine seam.

## Problem

P2 proved the app can launch the engine and stream a turn — but only against weights that
already exist on disk. A fresh install has no weights, and the app cannot tell the user
*whether the machine can even run a given model before it spends an hour downloading it*.
Two things must land: a **chunked parallel download with bitmap resume across restarts**
(the weights are 48–150 GB; a lost connection must not cost the whole download), and a
**feasibility gate that refuses an infeasible launch with an explanation a person can act
on** (the download script already carries per-model RAM guidance — the app should carry
the same judgment, computed, not prosaic).

## Gardenable facts (with citations)

- **Model source:** the P1 model is `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` from
  `antirez/Laguna-S-2.1-GGUF` at revision `706fa69799926b6afde1af9e24ca2a4923f110a1`
  (the `laguna-q2-q3` target of `external/ds4/download_model.sh`, which uses the official
  HF CLI for large GGUFs). HuggingFace `resolve` URLs serve HTTP Range requests, so a
  chunked Range downloader works:
  `https://huggingface.co/antirez/Laguna-S-2.1-GGUF/resolve/706fa69799926b6afde1af9e24ca2a4923f110a1/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
- **Feasibility inputs:** the engine's startup memory plan — `kv_bytes`,
  `scratch_bytes`, `model_bytes`, `planned_bytes` — is on every `ready` event
  (P1 fixtures, `fixtures/agent/golden.ndjson`) and the `ds4: memory:` boot line
  (P2 live smoke). For our P2 config the plan is 46.51 GiB planned (`planned_bytes`
  49,943,965,040). Feasibility compares `planned_bytes` against available RAM.
- **Per-model RAM guidance already exists** in `download_model.sh`'s targets section
  ("Recommended model for 96 and 128 GB RAM machines" for q2-imatrix; q4-imatrix for
  256 GB+). P3's refusal messages must be at least this actionable.

## Decisions

### D1 — Feasibility is a pure Kit function, computed from the engine's own numbers

`Feasibility.check(plannedBytes:availableBytes:modelName:) -> FeasibilityVerdict` in
Kit. `FeasibilityVerdict` is `.feasible` or `.infeasible(FeasibilityReason)`, where
`FeasibilityReason` carries a **computed** message a person can act on: the deficit
("needs 46.5 GiB, 24 GiB available"), the two concrete levers (close memory-heavy apps;
pick a smaller quant — naming the quant sizes from the download targets), and the exact
number to re-check against. The judgment is arithmetic on the engine's own `planned_bytes`
— never a percentage heuristic. Evidence floor: a known-good case (fits) and a
known-broken case (doesn't) are pinned fixtures in the fast tier (binding rule 6).

The app gathers `availableBytes` (Darwin `host_statistics64`, HOST_VM_INFO: free +
inactive, matching Activity Monitor's notion) in the app target — Kit stays pure. The
engine's `planned_bytes` is read from the boot line / `ready` event (already parsed at
P2). Where no plan is known yet (first launch), the app refuses only on an obviously
infeasible model (planned ≥ total RAM) and otherwise defers to the engine's own refusal
— which the supervisor already surfaces.

### D2 — Launch refusal is Kit policy applied by the app

`EngineFailure` gains `.infeasible(String)`. `EngineController.startEngine` computes
feasibility first; on `.infeasible` it sets `state = .failed(.infeasible(message))`
**without spawning** (no supervisor transition needed — no process exists). The Chat
status bar already renders `.failed` with the message; the actionable text now shows
before the download, not after a failed load. The refusal is the same code path a user
sees after choosing a model in Settings.

### D3 — The downloader: Kit plan + bitmap, SwiftStar transport

**Kit (`ChunkedPlan`, `DownloadBitmap`)** — pure, fast-tier tested:
- `DownloadBitmap`: a fixed-size bitset over chunks (`init(chunkCount:)`, `set(_:)`,
  `isSet(_:)`, `completedCount`, `isEmpty`, `serialize() -> Data`,
  `deserialize(Data, chunkCount:) throws`, and a count/validity check that rejects a
  bitmap whose width mismatches the plan).
- `ChunkedPlan`: `chunkSize` (default 16 MiB), `chunkCount(forTotalBytes:)`,
  `range(forChunk:) -> Range<Int>`, `completedBytes(bitmap:totalBytes:)`,
  `missingChunkIndices(bitmap:) -> [Int]`, `isComplete(bitmap:)`.
- `DownloadSpec`: `url`, `destination`, `chunkSize`, `maxConcurrency` (default 4).

**SwiftStar (`DownloadRunner`)** — network + files, app target:
- HEAD request for `Content-Length` (with a Range-probe fallback when HEAD is
  unsupported — many CDNs).
- Loads the persisted bitmap (see storage) and skips chunks whose bit is set **and**
  whose `.part` file exists with the right size; anything else is redownloaded
  (self-healing bitmap: trust the file, not just the bit).
- Fires up to `maxConcurrency` concurrent Range requests (`Range: bytes=a-b`), each
  writing its own `<chunk>.part`; on each completion, sets the bit and atomically
  persists the bitmap (write-temp-then-rename).
- On completion: concatenates the chunk files in order into `destination.tmp`, renames
  to `destination`, clears the download state (bitmap + chunks removed).
- Cancellation and error handling: a failed chunk is retried (bounded); a persistent
  failure surfaces as a runner error with the partial state preserved (resumable).
- Progress: `bytesCompleted / totalBytes` from the bitmap — the same number the resume
  logic uses (one source of truth).

### D4 — Storage layout (resume across restarts)

A download lives in `SWIFTSTAR_DOWNLOAD_DIR` (env, for tests) or
`~/Library/Application Support/SwiftStar/Downloads/<model-file>/`, containing:
`bitmap.bin`, `<chunkIndex>.part` per incomplete/complete chunk, and on success the
final file at `..` (the download dir root) or the user-chosen destination. The bitmap is
small (a 48 GB model at 16 MiB chunks = ~3000 bits = 375 bytes). Restart = re-read the
bitmap, verify part files, resume missing chunks. A corrupt/absent bitmap starts fresh
(and stale part files are ignored by the size check).

### D5 — App surface

Settings → Engine pane gains a **Download model** section: a picker with the known
targets (the P1 Laguna q2/q3 entry first; the others from `download_model.sh`'s targets
list as metadata), a **Download** button, progress (bytes + percent + active-chunk
count), a **Cancel**, and the resume state ("resumed N of M chunks"). The download runs
in the app target via `DownloadRunner`; the runner's state (`DownloadState`: idle,
downloading(progress), done, failed) is an `@Observable` model in the app, and its
progress math is Kit's `ChunkedPlan` (so the fast tier pins the numbers). On completion
the model path in Settings can be pointed at the downloaded file (one click).

### D6 — Scope discipline

P3 does **not** ship: multi-repo cataloguing (a hardcoded target list), resumable
*engine* state, torrent/aria strategies, P2P, per-file checksums beyond HTTP semantics,
or a Downloads tab. The downloader is single-file, HTTP Range, chunked-parallel,
bitmap-resumed — the brief's exact scope. Feasibility covers RAM only (disk is checked
by the downloader's own free-space guard — a simple refuse-if-not-enough message).

## Done when

1. **Feasibility (fast tier):** known-good and known-broken cases pass; the refusal
   message contains the deficit, the machine's available bytes, and at least one
   actionable lever; a model with `planned_bytes ≥ total RAM` is refused even with no
   prior engine run.
2. **Launch refusal (integration + smoke):** starting the engine with an infeasible
   budget refuses **before spawning** (no child process appears) and the status bar
   shows the actionable message.
3. **Chunked parallel download (integration tier):** a local Range-server serves a
   generated file; a full download is byte-identical to the source; a killed-then-resumed
   download (bitmap + part files pre-seeded) completes byte-identically, downloading only
   the missing chunks (asserted by the server's range log); a server error (416) fails
   cleanly with the partial state preserved.
4. **Bitmap/plan (fast tier):** serialize/deserialize round-trip, chunk-count validity
   rejection, progress math, missing-chunk computation — all pinned, with the
   shown-fail-first record.
5. **App (smoke):** Settings → Engine shows the Download section; a download (against a
   local range server via `SWIFTSTAR_DOWNLOAD_DIR` + a test URL) shows progress and
   lands a byte-identical file; the model path points at it.
6. Every new test shown to fail first (binding rule 2); refusal tests have sibling
   success tests (binding rule 4); no source-text assertions (binding rule 3).
7. `ROADMAP.md` marks P3 complete; concept budget reviewed (new terms: **variant**
   earns its definition here or stays a seed term; **feasibility** is now defined).
