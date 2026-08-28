# P22 — SSD across the Laguna line: live validation record

**Date:** 2026-08-28
**Phase:** P22 — More models: Laguna XS + model switching (SSD-across-the-line forward item)
**Status:** **live validation PASS** — S-ssd spawn admitted with a measured footprint; the DFlash × SSD exclusion composes loudly; DFlash alone works on the resident path
**Engine:** `external/ds4` @ `849f375` (`p20-dispatch-schema`), divergence #13 — a faithful port of the local `laguna-s21-ssd` branch's tip `2613723` (the branch never entered the integration; the gate's context at the pin was byte-identical, so the change re-applies cleanly). Wire-neutral (gate-only), so no golden recapture is owed — same precedent as divergence #12 (P20).

## What was validated

Probes ran the rebuilt `ds4-agent` with the app's exact spawn flag set
(`-m <model> -c 51200 --metal --non-interactive --json-events --workspace
/tmp/ssd-probe --shell off --host-tools`, plus the streaming/draft flags
under test, with the app's `DS4_METAL_*_SOURCE` shader environment).

### 1. Laguna S spawns with `--ssd-streaming` (the widened gate admits S21)

```
ds4-agent -m .../laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf -c 51200 ...
  --ssd-streaming --ssd-streaming-cache-experts 3200
```
- No refusal (pre-divergence, the gate rejected S21 with "only supported for
  Laguna XS 2.1").
- `ready`: `kv_bytes 2,592,078,872` (2.41 GiB), `scratch_bytes 6,146,969,608`
  (5.72 GiB), `model_bytes 327,548,928` (0.31 GiB resident model — the rest
  streams from SSD), **`planned_bytes 22,042,726,408` = 20.53 GiB resident**.
- Resident comparison (same ctx 51200, measured in the same session): S
  resident = `planned_bytes 56,996,119,560` = 53.08 GiB. **SSD streaming saves
  ~32.5 GiB of resident footprint.**

### 2. DFlash × SSD streaming exclusion composes loudly (load-bearing)

```
... --ssd-streaming --ssd-streaming-cache-experts 3200
    --dflash .../laguna-s-2.1-DFlash-Q8_0.gguf
```
- **Refused at admission, exit 1**: `ds4: --ssd-streaming is not compatible
  with support models yet` — the upstream exclusion the convergence doc calls
  load-bearing for correctness (keeps the residency-blind exact-decode
  verifier paths unreachable under streaming). Loud refusal, not silent
  misuse.

### 3. DFlash alone works on the resident path (the other side of the exclusion)

```
... --dflash .../laguna-s-2.1-DFlash-Q8_0.gguf   (no --ssd-streaming)
```
- Admitted; `ready`: **`planned_bytes 58,180,968,456` = 54.18 GiB** (S
  resident 53.08 GiB + the Q8_0 draft ≈ 1.1 GiB).
- stderr: `DFlash graph: block=16, history=512, KV 12.00 MiB, scratch 68.88
  MiB` — the speculative-decoding graph built.
- Generated a turn ("pong") — the draft path loads and the agent answers.

## Evidence artifacts

- `/tmp/ssd-probe-wire.jsonl` — the S-ssd `ready` plan (20.53 GiB).
- `/tmp/ssd-probe2-stderr.txt` — the DFlash × SSD loud refusal.
- `/tmp/ssd-probe3-wire.jsonl` + `/tmp/ssd-probe3-stderr.txt` — the DFlash
  resident run (54.18 GiB plan, DFlash graph, generated turn).
- S resident baseline: the 2026-08-28 model-switching live run's
  `captures/live/20260828-110319/` wire (`planned_bytes 56996119560` =
  53.08 GiB).

## Notes / open

- The 3,200-expert cache mirrors XS's tuned value; the S-ssd footprint above
  (20.53 GiB, of which expert cache ≈ 12.09 GiB = 20.53 − 2.41 − 5.72 − 0.31)
  is the first measurement — a future tuning pass can re-measure the cache
  size against S's larger experts.
- DFlash engagement under stochastic sampling still falls back automatically
  (needs `--temp 0` to engage) — unchanged engine behavior, out of scope.
- The engine-side enabling change lives on the fork's `p20-dispatch-schema`
  branch (commit `849f375`, divergence #13); the fork-ledger row documents
  what would retire it.
