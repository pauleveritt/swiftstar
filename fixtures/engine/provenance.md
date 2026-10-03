# Engine fixtures: provenance

Raw stdout of `ds4-dogfood tui --ndjson`, one JSON object per line, exactly
as `EngineWireParser` reads it. Recorded by `Tools/record-engine-fixture.py`
(`just capture <scenario>`).

- **Recorded:** 2026-09-28
- **ds4-engine:** `9d96bee0` (local checkout, editable build with
  `--features bindings,engine`)
- **Model:** `laguna-xs-2.1` (`~/models/Laguna-XS-2.1-Q4_K_M.gguf`),
  context 20,000, `--seed 7`
- **Machine:** Apple M5 Max, 128 GiB, macOS 26 (Darwin 27.0, the kernel
  version — not the marketing name)
- **Source:** this repository at `HEAD` of branch
  `worktree-ds4-engine-subprocess` (P28)

| File | Scenario | What it must contain |
| --- | --- | --- |
| `tool-read.ndjson` | one prompt that reads `Package.swift` | ≥1 `tool_result` with `op` `read`, one `answer` |
| `stop.ndjson` | long prompt, `stop` after the first `tool_result` | `stopping`, an `interrupted` event, no `answer` |
| `error.ndjson` | `{"kind":"bogus"}` at the first `input` | one `{"kind":"error"}` line, then a clean quit |

`fake-ds4-dogfood` (the integration-tier stand-in) replays these files.

**Re-record rule:** re-record all three whenever ds4-engine changes its
`--ndjson` `protocol` or the telemetry `schema_version`, and check the
"must contain" column by hand. A `tool-read` recording with no tool call is
a model miss, not a wire change: re-record with another seed.

## `models-real.json` and `models.json`

`models-real.json` is a verbatim capture of `ds4-dogfood models --json`
(ds4-engine `main` at `409267a9`, run on the owner's Mac, 2026-10-04); home
paths were anonymised to `/Users/example/`. This replaces a 2026-09-29 capture
from commit `4c432171` ("TUI.33"), a `feat/models-json` branch state that
never reached `main` in that shape: the version that actually shipped (TUI.35,
`e5823e81`) sends no `schema_version`, `default_model_id`, `saved_model_id`,
`family`, `measured_contexts` or `runs_in_tui`, and names the per-model
context field `context` rather than `default_context`. `EngineModelList`'s
decoder treats a missing `schema_version` as 1 and reads `default_context`
falling back to `context`; the other fields are already optional with
graceful fallbacks (`ModelMenu`/`ContextMenu` degrade to an unlabeled "Engine
default" without them). `models.json` is hand-written in the richer,
forward-looking shape (per-model flag `runs_in_tui`, `family`,
`measured_contexts`) to cover cases the real capture lacks and to exercise
that shape if ds4-engine adds it later: a model that doesn't fit, one not
usable in the TUI, unknown keys. Re-capture `models-real.json` if ds4-engine
starts sending `schema_version` again, or bumps it.
