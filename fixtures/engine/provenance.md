# Engine fixtures: provenance

Raw stdout of `ds4-dogfood tui --ndjson`, one JSON object per line, exactly
as `EngineWireParser` reads it. Recorded by `Tools/record-engine-fixture.py`
(`just capture <scenario>`).

- **Recorded:** 2026-09-28
- **ds4-engine:** `9d96bee0` (local checkout, editable build with
  `--features bindings,engine`)
- **Model:** `laguna-xs-2.1` (`~/models/Laguna-XS-2.1-Q4_K_M.gguf`),
  context 20,000, `--seed 7`
- **Machine:** Apple M5 Max, 128 GiB, macOS 27.0
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
