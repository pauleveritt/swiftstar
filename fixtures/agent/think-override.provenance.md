# `think-override.ndjson` — capture notes (P23, fork divergence #14)

A **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from one real
`--per-turn-think --json-events` session, captured by the committed
`swiftstar-drive` program. It exercises the P23 wire surface: the flag-gated
`think_override` cap on `hello`, and the prompt envelope's `think` key parsed
at N=1 (the single-session JSON path, distinct from pool mode).

## Provenance

- Submodule (`external/ds4`) SHA: `1a2dddff899e202914b15ea8ff35787b48045735`
  (P23 divergence #14 — `44b70b5`/`5fa6ee0` plus the same-day review-follow-up
  `09e73b8` and the fork-ledger row itself, `1a2dddf`).
- Built with: `make -C external/ds4 ds4-agent`. Binary run in place,
  `external/ds4/ds4-agent`.
- Captured by: `swiftstar-drive` with `CAPTURE_PER_TURN_THINK=1` (appends
  `--per-turn-think`), `CAPTURE_CTX=16384`, no `CAPTURE_WORKSPACE`/
  `CAPTURE_SHELL` (bare P5 shape, same as `golden.ndjson`).
- Model file: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1) at
  `~/projects/ds4/gguf/`.
- Prompts (`CAPTURE_PROMPTS_FILE`), sent in order over the kept-open stdin
  pipe:
  1. `Explain, in one sentence, what a KV cache is.` (bare text — no override;
     addresses worker 0 implicitly)
  2. `{"t":"prompt","worker":0,"think":"none","s":"List three prime numbers under twenty."}`
  3. `{"t":"prompt","worker":0,"think":"high","s":"What is 2 to the 8th power?"}`
- `DS4_LOCK_FILE=/tmp/ds4-capture-<pid>.lock`.
- Wall-clock start: `2026-08-28T22:39:00Z`.

## What the capture proves, and what it does not

**Proves (mechanism, live-verified on this capture):**
- Line 1's `hello` carries `"caps":[...,"think_override"]` and is valid JSON
  (the P9 closing-bracket defect class) — the cap is flag-gated, present here
  only because `--per-turn-think` was passed.
- The N=1 JSON-envelope path parses correctly: prompts 2 and 3 are JSON lines
  (not the plain-text prompt 1's shape), and each turn answers its own
  distinct question correctly (three prime numbers under twenty; 2^8), which
  is only possible if the `s` field was extracted from the envelope rather
  than the whole JSON line being fed to the model as literal text (the exact
  failure the N=1 fix in `44b70b5` retires).
- Turn 2 (`think:"none"`) has **zero** `{"t":"think",...}` events.

**Does NOT prove:** that turn 3 (`think:"high"`) caused the model to
visibly think. It also has zero `{"t":"think"}` events. This capture uses no
system prompt (`swiftstar-drive` has no knob for one, matching every other
committed fixture's bare-CLI shape), and this phase's own research finding
(`docs/superpowers/research/2026-08-28-p23-wire-control-research.md`, "Probe
A") is that **`think=high` is permission to think, not a command** — the
same model, same flag, produced zero thinking on a bare arithmetic question
and 80%-thinking on a system-prompt-driven multi-step problem in that probe.
A bare "what is 2^8" is exactly the 0%-thinking condition from that table's
first row, so the absence of think events on turn 3 is expected, not a
defect. Two live follow-up probes (a multi-step algebra word problem, and
probe A's own recorded system-prompt wording) run directly against the
engine outside this fixture also produced zero think events without a
system prompt — see
`docs/superpowers/research/2026-08-28-p23-think-to-the-wall-repro-attempt.md`
for the related (and similarly inconclusive) think-to-the-wall reproduction
attempt.

**Consequence for the replay test:** `FixtureReplayTests` pins the cap
advertisement and the envelope's mechanical correctness (turns 2/3 each
answer their own distinct question), not the presence of think events on the
high-turn — asserting the latter would pin a false claim about this specific
capture.

## Memory-budget cross-check

`ready`'s memory fields agree with the boot line, same cross-check as
`golden.ndjson`'s: `kv_bytes` 880,803,840 (0.82 GiB), `model_bytes`
48,257,070,080 (44.94 GiB), `planned_bytes` 55,284,843,528 (51.49 GiB) — Laguna
S at ctx 16,384 (smaller KV than the 32,768 golden capture, same model file).
