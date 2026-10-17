# SwiftStar EN.2 design: catch up to ds4-engine `a84b79bd`

Date: 2026-10-17. Status: **written, awaiting the owner's acceptance.**

## Goal

Read what the engine has put on the `tui --ndjson` wire since EN.1
(`5451cd7d`) and show the parts a user can act on. Close SU.6's last
punch-list item, engine information worth showing, inside this cycle.
Re-check the ROADMAP's engine requests against the code. Re-record the
fixtures on the 27B; that step uses the GPU and waits for the owner's go.

Out of scope:
- the report, done in AN.4 on `ds4-session-report/2`
- validating fixtures against the engine's JSON Schemas (SCH.1), which
  goes in the backlog
- SU.7c (windows); see §5

## Decisions

- **D1. Startup lines are the engine's.** `baseline`, `env_sync` and
  `project_instructions` each carry a `summary`. A non-empty one becomes
  an info row in the transcript, the rule the TUI uses (`tui.py:64`,
  `:250`). SwiftStar writes none of that text.
- **D2. A Start-up section in the Session card.** It shows the raw figures
  behind those lines:
  - the candidate's commit (`resolved`, short) and `excluded_count`
  - `candidate_ready`'s `created_ms` and `waited_ms`
  - `env_sync`'s `outcome` and `duration_ms`
  - `project_instructions`' `file`, `tokens`, and `cut` when true
  - `index_primed`'s `since_start_ms`, which arrives at the first pause
    (`operator.py:240`, `session_receipt.py:122`)

  This is the punch list's `candidate_ready`/`index_primed` line.
- **D3. The prefix line says what the engine says.**
  - On a miss with a non-empty `changed`, it adds `· changed: model, shaders`.
  - On a miss with `changed: []`, it adds `· its entry did not load`.
  - On a hit with `entry_fill_ms`, it adds `(filled in 1.7s)`.

  SwiftStar computes no "saved" figure. The report has the engine's.
- **D4. A resumed conversation's state, once.** A `conversation_state`
  event becomes a system row such as
  "Saved conversation state loaded · 0.3 GiB in 1.2s". For `failed`, the
  row is "… not loaded: failed (<error>)"; for `absent` and `unsupported`,
  "… not loaded: absent". It appears only on resume, and the Session card
  keeps the latest.
- **D5. `git` and `test` tool cards.** Their `path` is `""`, so the card
  stays a plain header with no link (`EngineTranscript.swift:26`, `:52`).
  Each gets its own icon. A `git` result is colored as `diff`
  (`CodeLanguage.swift:14`); a `test` result's first line, such as
  `[pytest with the project's .venv: exit 1 in 2.3 s]`, becomes the
  card's metadata. The doc tool was never on `main` and needs nothing.
- **D6. A typed `/analyze` shows its lines.** The engine answers `analysis`
  `{lines}`, and SwiftStar drops it today (`EngineWireParser.swift:5`'s
  inner `default`). It becomes a report card, like Analyze's. That's text
  only, with no fork. `analyze_refused` already shows as a refusal.
- **D7. The model catalog decodes what the engine sends.**
  - `models --json` sends `size_bytes`, `context` and `plan_gib`
    (`tui_cli.py:196-222`). SwiftStar decodes `family`, `default_context`,
    `measured_contexts` and `runs_in_tui`, which it never sends.
  - The model menu shows the file size and plan: "Qwen3.8 27B — 15.7 GiB,
    plans 24.7 GiB".
  - The context menu's "Engine default" names the engine's `context` and
    plan: "Engine default (131,072 · 24.7 GiB)". The round sizes stay.
  - The four unsent fields go, along with `defaultModelID`. Where
    `ToolbarMenus.swift:75`, `:117` and `:118` read them, they get the
    fallback they already use.
  - `fixtures/engine/models.json`, the hand-written one, loses those fields.
- **D8. Stderr start notices: dropped.** The engine prints nothing new on
  stderr in `--ndjson` mode; `uv sync` output goes to `env_sync.output`
  (`candidate_env.py:126-144`). The startup events in D1 are what the
  engine means to show.
- **D9. The relaunch after a second `/rewind` is by design.**
  `rewind_refused` with `--rewind-to 0` is the expected argv; the bug was
  the turns resumed after it, fixed by #226 (`sessions.py:296-321`).
  SwiftStar already honours `relaunch` as given. A recording pins it.
- **D10. Recordings, after the owner's go.** Every fixture in
  `fixtures/engine/*.ndjson` is re-recorded on the 27B at `a84b79bd` with
  `just capture`. Two are new:
  - **`resumed-answered.ndjson`:** a resume, then one more prompt answered.
    This is AN's follow-up, and it holds a `conversation_state`.
  - **A session directory with key records:** a second run after a miss,
    for `report.json` and a live `prefix_cache.changed`.

  Until then, the fast-tier tests use lines copied from the engine's own
  tests, named as such in `provenance.md`. For example,
  `tests/test_resume_conversation.py:244-250` for `conversation_state`.
  The recordings replace them.

## 1. What the wire carries now

Every new kind arrives inside `{"kind":"event","event":{...}}`. The relay
(`ndjson_process.py:64`) and the presenter (`tui_process.py:114`) haven't
changed since `5451cd7d`, so SwiftStar's unwrap already covers them. No kind
was renamed or removed.

| Kind | New or changed | What SwiftStar reads | Cited at `a84b79bd` |
|---|---|---|---|
| `baseline` | new (TUI.47) | `resolved`, `excluded_count`, `summary` | `candidate.py:82-96`, `tui_cli.py:1144` |
| `env_sync` | new (TUI.49) | `outcome`, `duration_ms`, `reason`, `summary` | `operator.py:770-772`, `candidate_env.py:151-248` |
| `project_instructions` | new (TUI.48) | `file`, `tokens`, `cut`, `summary` | `operator.py:776-784`, `project_instructions.py:116-131` |
| `conversation_state` | new | `outcome`, `bytes`, `load_ms`, `error` | `operator.py:256-258`, `driver.rs:469-500` |
| `analysis` | new (`/analyze`) | `lines` | `tui_cli.py:141` |
| `index_primed` | not new, first read now | `since_start_ms` | `operator.py:240`, `session_receipt.py:122` |
| `prefix_cache` | added fields | `changed`, `entry_fill_ms` | `prefix_cache.rs:75-86`, `bindings.rs:1616-1619` |
| `tool_*` | new ops `git` and `test`, with `path: ""` | `op`, the result preview | `operator.py:385-393` |
| `tool_rejected` | text lists `git`, `test` and `finish` | unchanged (text shown as sent) | `driver.rs:3085-3101` |
| `*_refused` | `relaunch` may carry `--no-sync-env` | unchanged (argv run as given) | `tui_cli.py:373-378` |

The startup order is `session`, then `resumed` if resuming, `baseline`,
`candidate_ready`, `env_sync`, `project_instructions` if present, and
`memory`. The first `prompt` event's text doesn't change: AGENTS.md is
added only to what the model sees (`operator.py:326`, `:367`). Also
unchanged: `delegate`, which `tui` can't turn on (`tui_cli.py:609`), and
`models --json` and `sessions --json` beyond D7.

## 2. Engine requests, re-checked

| Request | Status at `a84b79bd` | ROADMAP change |
|---|---|---|
| Second `/rewind` (#219) | fixed by #226; the argv is by design (D9) | close |
| A miss doesn't say why | answered, live and in the report | close |
| Live-prefix reuse between turns | open: captures still hold only `prompt_len`, `ms` (`capture.rs:339`) | keep. Resume is now covered by `conversation_state` |
| `prefill_tokens` isn't prefill | open: unchanged (`operator_telemetry.py:101-113`) | keep |
| `models --json` has no `default_model_id` | open: internal only (`models.py:170`) | keep. D7 shows the default context instead |
| No power throttle | open | keep |
| `resumed.turns` has no narration | open (`sessions.py:45-50`) | keep |
| Satyrn rename | not happened (`pyproject.toml:13`) | keep as a watch |

## 3. Testing

- **Fast tier (Kit).** One test per decision, over lines from the engine's
  tests until the recordings exist:
  - D1: each startup kind's `summary` makes a row, and a null one doesn't.
  - D3: three prefix lines.
  - D4: four outcomes.
  - D5: icons, `diff` coloring and the test card's metadata.
  - D6: an `analysis` event makes a report card.
  - D7: decoding `models-real.json`; the model and context menu titles.

  Each is shown to fail with its behavior broken.
- **Integration.** The fake engine replays the new recordings. A resume
  over `resumed-answered.ndjson` shows the state row and answers.
  `EngineModelCatalogLoaderTests` and `SessionReportLoaderTests` rerun.
- **Previews.** Rendered with `RenderPreview`: the Session card's Start-up
  section, tool cards for `git` and `test`, and the state row. Checked in
  the gallery by screenshot: the model and context menus.

## 4. Done when

- Every decision is built, with its tests shown failing first, and both
  tiers are green.
- The previews and the gallery screenshots have been looked at.
- After the owner's go, the fixtures are re-recorded at `a84b79bd` and
  `provenance.md` is pinned to it.
- ROADMAP's engine requests are as in §2. SU.6 closes, and EN.2 has its
  row and Result.

## 5. Risks and a finding

- **D7 changes two menus** the owner uses. The gallery shows them before
  anything merges.
- **Startup rows add up to three lines** before the first prompt. If
  that's noise, D1 falls back to the Session card only, without changing
  the parser.
- **Until the recordings land, the fast tier rests on the engine's test
  data.** That is the engine's own expectation, not a capture.
- **Finding: SU.7c may not be blocked by the engine.** The engine allows
  one engine per process, not per machine. It is a process-wide flag
  (`crates/ds4-host/src/engine.rs:1-25`), and no machine-wide lock was
  found. Each window would load its own weights, so GPU memory is the
  practical limit: two 27B windows plan about 49 GiB of the 107.5 GiB
  budget. Whether to reopen SU.7c is the owner's call. This spec doesn't
  change it.
