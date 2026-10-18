# Engine fixtures: provenance

Raw stdout of `ds4-dogfood tui --ndjson`, one JSON object per line, exactly
as `EngineWireParser` reads it. Recorded by `Tools/record-engine-fixture.py`
(`just capture <scenario>`).

- **Recorded:** 2026-10-18 (EN.2), replacing EN.1's of 2026-10-13
- **ds4-engine:** `a84b79bd`, the installed `ds4-dogfood` (a `uv tool`
  install from the ds4-engine checkout at `main`)
- **Model:** `qwen3.8-27b`, context 20,000, `--seed 7`; state and config in
  a throwaway `XDG_STATE_HOME`/`XDG_CONFIG_HOME`
- **Machine:** Apple M5 Max, 128 GiB, macOS 26 (Darwin 27.0, the kernel
  version — not the marketing name)
- **Source:** this repository's `su-ui` worktree at `1866984` (branch
  `en2-catch-up`). The recorder's EN.2 edits were uncommitted, so the
  `baseline` summaries name them as files left out. Sessions are named after
  the worktree (`…-su-ui`).
- **Time:** about 2 minutes of GPU for all six scenarios. Each loads the 27B
  (`tool-read` took 22 s, `resumed-answered` 29 s for three sessions).

| File | Scenario | What it must contain |
| --- | --- | --- |
| `tool-read.ndjson` | one prompt that reads `Package.swift` | ≥1 `tool_result` with `op` `read`, one `answer` |
| `stop.ndjson` | long prompt, `stop` after the first `tool_result` | `stopping`, an `interrupted` event, no `answer` |
| `error.ndjson` | `{"kind":"bogus"}` at the first `input` | one `{"kind":"error"}` line, then a clean quit |
| `relaunch-rewind.ndjson` | two prompts, then `/rewind 1` | `rewind_refused` with a `relaunch` argv that starts `tui` and ends `--ndjson` |
| `resumed.ndjson` | that `relaunch` argv, run as is | `session` with `rewound_to` 1, then `resumed` with one turn |
| `prefix-changed.ndjson` | `resumed-answered`'s second session: a fresh one at context 16,384 after one at 20,000, in the same scratch state | a `prefix_cache` miss with `changed` `["context"]` |
| `bash-run.ndjson` | SU.18: under `--allow-bash`, "run `cat Package.swift`, then run `ls Sources \| wc -l`" (2026-10-18) | a `read` of `Package.swift` (the engine mapped the `cat`, and nothing on the wire says so), then `op` `run` with an empty `path` and a `[exit 0 in 0.0 s]` header, then an `answer` |
| `resumed-answered.ndjson` | that second session resumed, with one more prompt | `resumed` with one turn, `conversation_state` `loaded`, then an `answer` |

Every recording at `a84b79bd` also carries the start-up reports: `baseline`,
`candidate_ready`, `env_sync` (`skipped`, since this repository has no
`uv.lock`), `project_instructions` (`CLAUDE.md`, about 311 tokens) and
`index_primed`. The prefix grew from 944 to 1,333 tokens, because it now
holds CLAUDE.md.

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
| `tool-rejected.ndjson` | `ready`, then one `tool_rejected` event copied from ds4-engine `docs/tui.md:1748`. The 27B wouldn't call a missing tool (seeds 1–6), nor trip the loop guard with three identical reads (seeds 1–6), on 2026-10-13. Nor would it at `a84b79bd`, seeds 1–5 and 7–9 (2026-10-18). The event's shape is unchanged |
| `models.json` | five models in the engine's keys; see below |

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
context field `context` rather than `default_context`. Since EN.2 (2026-10-17), `EngineModelList`
decodes only the keys the engine sends (`tui_cli.py:196-222` at
`a84b79bd`), and a missing `schema_version` means 1. `models.json` is
hand-written in those same keys. It covers what the real capture lacks: a
model that doesn't fit, one not on this Mac, one with no size or plan, and
an unknown key. Re-capture `models-real.json` if ds4-engine
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
--json` (`schema` `ds4-session-report/2`). It was first recorded on
2026-10-15 as `/1`, at ds4-engine `1732611c`. It was re-recorded on
2026-10-17 as `/2`, with the installed engine built from ds4-engine
`a84b79bd` (`main`). The `dir` field is the relative path
it was given. The fake engine's `report` mode prints it
(`FAKE_ENGINE_REPORT`).

Re-capture it if the report's schema or labels change.

## `report-resumed.json` (EN.2)

Raw stdout of `ds4-dogfood report fixtures/sessions/20261018-112154-su-ui
--json` at `a84b79bd`. That session is `resumed-answered`'s third: a
resumed conversation whose state loaded. It names its earlier session in
`earlier[]`, whose directory was a scratch one and is gone. The session's
small files are under `fixtures/sessions/` (see its provenance).

## The engine's own test lines

`Tests/SwiftStarKitTests/EngineStartupEventsTests.swift`'s first suite and
`PreviewFixtures.runningModel` use lines taken from ds4-engine `a84b79bd`'s
tests and code, each with its source. They cover what the recordings
can't: a `failed` or `absent` state, a hit with `entry_fill_ms`, and an
`analysis`. The `env_sync` and `project_instructions` summaries in them are
illustrative wording, not the engine's. The recordings are pinned by
`EngineStartupRecordingTests`.

## `analysis-remedies.ndjson` (AN.3)

Assembled from two recordings, for Analyze's fork over the fake engine:
- **Start:** `resumed.ndjson` through its first `input` (the 27B at
  `a84b79bd`).
- **Turn:** a live 27B turn at `a84b79bd` (2026-10-18), from its `prompt` to
  the next `input`. Its narration holds a three-line `agents-md` block.

The live turn was a fresh session, given the fixture session's report and
AN.3's instruction, against the main checkout; a fork only resumes one. The
prompt line in it is that test's, not the app's. Re-record it if the
analysis instruction changes much.
