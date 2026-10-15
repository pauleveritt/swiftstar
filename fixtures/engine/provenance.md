# Engine fixtures: provenance

Raw stdout of `ds4-dogfood tui --ndjson`, one JSON object per line, exactly
as `EngineWireParser` reads it. Recorded by `Tools/record-engine-fixture.py`
(`just capture <scenario>`).

- **Recorded:** 2026-10-13 (EN.1)
- **ds4-engine:** `5451cd7d` (its own `.venv/bin/ds4-dogfood`, an editable
  build)
- **Model:** `qwen3.8-27b`, context 20,000, `--seed 7`; state and config in
  a throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME`
- **Machine:** Apple M5 Max, 128 GiB, macOS 26 (Darwin 27.0, the kernel
  version — not the marketing name)
- **Source:** this repository at `main` (`88bf1b2`)

| File | Scenario | What it must contain |
| --- | --- | --- |
| `tool-read.ndjson` | one prompt that reads `Package.swift` | ≥1 `tool_result` with `op` `read`, one `answer` |
| `stop.ndjson` | long prompt, `stop` after the first `tool_result` | `stopping`, an `interrupted` event, no `answer` |
| `error.ndjson` | `{"kind":"bogus"}` at the first `input` | one `{"kind":"error"}` line, then a clean quit |
| `relaunch-rewind.ndjson` | two prompts, then `/rewind 1` | `rewind_refused` with a `relaunch` argv that starts `tui` and ends `--ndjson` |
| `resumed.ndjson` | that `relaunch` argv, run as is | `session` with `rewound_to` 1, then `resumed` with one turn |

`fake-ds4-dogfood` (the integration-tier stand-in) replays these files.

**Narration and answer on the 27B (EN.1, D4).** In `tool-read.ndjson` the
`narration` (line 26) is the full, formatted reply, and `answer` (line 27)
is `finish`'s one-sentence summary of it. They don't repeat each other's
text, so nothing is dropped; how to present the pair is an SU.6 question.

**Hand-written, not recorded** (cases a real engine won't produce on
demand):

| File | What it is |
| --- | --- |
| `bad-handshake.ndjson` | a first line that isn't `ready` (`{"kind":"input"}`) |
| `garbage-after-ready.ndjson` | `ready`, then a line that isn't JSON, then `input` |
| `tool-rejected.ndjson` | `ready`, then one `tool_rejected` event copied from ds4-engine `docs/tui.md:1748`. The 27B wouldn't call a missing tool (seeds 1–6), nor trip the loop guard with three identical reads (seeds 1–6), on 2026-10-13 |
| `models.json` | the richer catalog shape; see below |

**Re-record rule:** re-record the recorded files whenever a ds4-engine change
reaches the wire. That covers a `--ndjson` `protocol` or telemetry
`schema_version` bump, and also payload changes the relay forwards
untouched: new event kinds, new or dropped fields, a changed model lineup.
Check the "must contain" column by hand. A `tool-read` recording with no
tool call is a model miss, not a wire change: re-record with another seed.

## `models-real.json` and `models.json`

`models-real.json` is a verbatim capture of `ds4-dogfood models --json`
(ds4-engine `main` at `5451cd7d`, run on the owner's Mac, 2026-10-13); home
paths were anonymised to `/Users/example/`. The lineup is `qwen3.8-27b`,
`qwen3.8-flash-next` and `qwen3.8-flash-next-q2`. This replaces a 2026-09-29 capture
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
starts sending `schema_version` again, or bumps it, or changes its model
lineup.

## `sessions.json` (SU.7a)

`ds4-dogfood sessions --json --source . --limit 12`, run in this repository
on 2026-10-13 against ds4-engine `5451cd7d`. It's the owner's real session
list, pretty-printed, with home paths redacted to `/Users/example` and the
`projects/<owner>/` segment dropped. It holds:
- a chain of three (`123136` ← `122439` ← `122106`)
- a chain of four whose newest two can't be resumed (`121809` ← … ←
  `121116`)
- five standalone sessions, none of which can be resumed (`problems` such
  as "no capture" or "no receipt")

That makes seven conversations from twelve entries.
- empty `first_prompt`s

Re-capture it if `sessions --json` changes its fields.

## `sessions-all.json` (SU.7b)

Hand-written, in the shape of `sessions --json --all` (ds4-engine
`5451cd7d`), with only the fields the app reads plus a few others. Two
sources:
- `alpha`: one resumable session
- `beta`: a chain of two (`110000` ← `100000`, titled "Add a menu"), and a
  newer standalone session that can't be resumed but has prompts, so it
  stays a row and must be skipped for the older one

The integration tests rewrite beta's `source` to a temporary repository.

## `report.json` (AN.4)

Raw stdout of `ds4-dogfood report fixtures/sessions/20261013-123136-swiftstar
--json` (`schema` `ds4-session-report/1`). It was recorded on 2026-10-15
with the installed engine, built from ds4-engine `1732611c`, the top of the
stack that holds `report` (#231, #233). The `dir` field is the relative path
it was given. The fake engine's `report` mode prints it
(`FAKE_ENGINE_REPORT`).

Re-capture it if the report's schema or labels change.
