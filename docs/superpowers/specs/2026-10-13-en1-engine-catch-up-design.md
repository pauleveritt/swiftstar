# SwiftStar EN.1 design: catch up to ds4-engine `5451cd7d`

**Date:** 2026-10-13
**Status:** design approved in conversation 2026-10-13; this written spec
awaits owner review.
**Phase:** EN (the engine contract), cycle EN.1
**Evidence:** [the engine catch-up and repo audit](../research/2026-10-13-engine-catch-up-and-repo-audit.md)
§1 (cited below as "the audit"). `E/` is `../ds4-engine` at `5451cd7d`.

## Goal

SwiftStar works against the engine as it is now, and uses what the engine
already offers its front-end:

1. A saved model the engine dropped no longer stops a session from starting.
2. Calls the engine declines appear in the transcript.
3. `/model`, `/rewind` and `/resume` work, through the engine's `relaunch`
   contract (TUI.34, `E/docs/tui.md:1771-1810`).
4. The fixtures, and the tool that records them, match the current engine.

## Decisions

The owner chose each of these on 2026-10-13.

**D1. A stale saved model: clear it, note it, start.**
- Before spawning, the controller checks the saved model id against the
  model list.
- If the engine doesn't offer that id, the setting is cleared, the
  transcript gets one notice, and the session starts on the engine
  default.
- If the list can't be loaded, the start goes ahead as today.
- This mirrors the engine's own handling of a stale `config.toml` model
  (`E/src/ds4_engine/first_run.py:337-344`).

**D2. After a relaunch, the transcript is rebuilt from `resumed`.**
- The rows are replaced by a divider plus the turns the new process reports.
- This stays truthful after `/rewind`, which drops turns.
- Earlier tool cards and thinking are not in `resumed.turns`, so rebuilt
  turns show the prompt and the answer only.

**D3. The model menu uses `/model` while a session runs.**
- The `/model` relaunch starts a new conversation but keeps the candidate
  files, where today's menu pick throws the session away.
- When no session runs, or when the engine refuses `/model` without a
  `relaunch`, the pick falls back to a fresh start.
- The context-size menu keeps the fresh start, because a relaunch doesn't
  change the context size.

**D4. Narration against answer is decided on evidence.** On the 27B the
`answer` is `finish`'s summary, and the text before the call arrives as
`narration` (`E/crates/ds4-host/src/contract/mod.rs:306`). Whether the two
repeat each other is checked in the 27B recording (§3.4), not assumed.

## 1. What the wire carries

Read in engine source, and to be confirmed by the recordings in §3.4.

- **`tool_rejected`.** The fields are `name`, `reason`, `path` and `text`.
  - `reason` is one of `unknown-tool`, `malformed`, `reserved-token`,
    `path-refused`, `invalid-pattern`, `tools-closed`, `context-reserve` or
    `not-approved`, plus the loop guards' `repeated-call` and `call-cycle`
    (`E/crates/ds4-native/src/loop_guards.rs:65-66`).
  - It arrives at the next pause (`E/docs/tui.md:1739-1763`).
  - Today SwiftStar drops it: there is no case at
    `Sources/SwiftStarKit/EngineWireParser.swift:57-143`.
- **`resume_refused`, `model_refused`, `rewind_refused`.**
  - When the command can run, the event carries `relaunch`: the full argv
    after the executable, starting at `tui` and ending with `--ndjson`.
  - It has no `--commit`. `/model` adds `--model-id X --new-conversation`.
  - The front-end quits, waits for the exit, then spawns the executable with
    `relaunch` exactly as given (`E/src/ds4_engine/tui_cli.py:343-362`).
- **`resumed`.** Sent by the relaunched process before its first `input`
  (`E/src/ds4_engine/tui_cli.py:535-560`). Its fields are `session`,
  `path`, `commit`, `files_changed`, `context_used`, `rewound_to`,
  `compacted`, and `turns`: a list of `{prompt, answer, stopped}`.

## 2. Design

### 2.1 Stale model (D1)

- **Kit:** `ModelMenu.validated(saved: String, list: EngineModelList?) -> (modelID: String, notice: String?)`.
- **Controller:**
  - `start()` becomes `async`. It awaits `loadCatalogIfNeeded()`, which is
    bounded by the loader's existing timeout, then applies `validated`.
  - When the id changes, it writes the cleared setting and posts the notice.
  - `SessionView`'s two launch `.task`s become one, so the start no longer
    races the list load.
  - Callers of `start()` (`SessionToolbar.swift:27`, `restart()`) await it.

### 2.2 Declined calls

- **Kit:**
  - A new `EngineToolRejection { name, reason, path?, text }` and an event
    `.toolRejected(EngineToolRejection)`.
  - `EngineTranscript` appends a tool card in a new *declined* state.
  - Its header is the name, or "a call" when the name is empty. Its one line
    is `text`. Its label is a short form of `reason`:
    - `repeated-call` reads "repeated"
    - `call-cycle` reads "loop"
    - `unknown-tool` reads "unknown tool"
    - any other reason is shown as sent
- **View:** `ToolCardView` draws the declined state greyed, with an
  `xmark.circle` icon.

### 2.3 Relaunch and resumed (D2, D3)

- **Kit, the wire.**
  - A `*_refused` event with a non-empty `relaunch` array becomes
    `.relaunch(EngineRelaunch)`, carrying `kind` (`.resume`, `.model` or
    `.rewind`, taken from the event name), `argv` and `reason`.
  - A `*_refused` event without `relaunch` stays `.refused`.
  - `resumed` becomes `.resumed(EngineResumed)`, carrying `turns`,
    `rewoundTo`, `filesChanged` and `contextUsed`.
- **Kit, the transcript.** `.resumed` replaces the rows with:
  - a divider row whose text depends on how the relaunch started:
    - "Rewound to prompt N"
    - "Switched to M: new conversation, files kept"
    - "Resumed session ID"
  - then, for each turn, a prompt row and an answer row. A stopped turn's
    answer row reads "Stopped".

  `EngineSessionModel` keeps the pending relaunch kind and target, so it
  can label the divider when `.resumed` arrives.
- **Controller.**
  - On `.relaunch`, it runs `quit()` and then `start(arguments:)` with the
    same executable and `relaunch` as given.
  - For `.model`, it saves the `--model-id` value from the argv, so the
    toolbar agrees.
  - `start(arguments:)` is the existing `start()` with an argv override. It
    still validates the executable and stays in the normal refused-to-start
    path on an exit before `ready`.
- **Model menu (D3).**
  - With a session running, `select(modelID:)` sends `/model X` through
    `send`, and the relaunch takes it from there.
  - With no session running, or after a `model_refused` without `relaunch`,
    it does today's fresh restart.
  - The two branches are decided in Kit by
    `ModelMenu.selectionAction(phase:) -> .sendModelCommand | .restart`.

### 2.4 Narration against answer (D4)

The 27B `tool-read` recording (§3.4) settles this.
- **If narration repeats the answer:** `EngineTranscript` drops a narration
  row whose trimmed text equals the turn's answer, or is contained in it.
  This gets a fixture test.
- **If it doesn't:** nothing changes, and the plan's Result says so.

### 2.5 Stale copy and fossils

- `SessionView.swift:37`'s "e.g. laguna-xs-2.1" becomes the current default.
- `EngineEvent.swift:30` says "only `laguna-xs-chat` reports one".
- `PreviewFixtures.swift:31` uses a Laguna model id.
- The tests use Laguna ids as data; they move to `qwen3.8-27b` as their
  fixtures are re-recorded.

## 3. Testing

### 3.1 Fast tier

Every new test is shown to fail when its behaviour is broken.

- **`ModelMenu.validated`:**
  - an offered id is kept
  - a dropped id is cleared, with the notice text
  - an empty id stays empty
  - with no list, the id is kept

  This is the refusal-and-success pair binding rule 4 asks for.
- **The parser:**
  - `tool_rejected` maps to `.toolRejected`
  - a refusal with `relaunch` maps to `.relaunch`; one without maps to
    `.refused`
  - `resumed` maps to `.resumed`

  Each is asserted against the recorded fixture by name (rule 5), or
  against the hand-written payload named in `provenance.md`.
- **The transcript:**
  - the declined card's header, label and icon
  - `.resumed` replacing rows, with the divider text for each kind
  - a `/model` relaunch with an empty `turns`
  - a stopped turn
- **`ModelMenu.selectionAction`:** each phase.

### 3.2 Integration tier

`fake-ds4-dogfood` learns:
- `/rewind N` and `/model X` refused with a `relaunch` argv
- emitting `resumed` when started with `--resume`
- `tool_rejected` under an env switch

All payloads come from the recordings. The tests:
- a relaunch quits, re-spawns with exactly that argv (the fake logs it), and
  rebuilds the transcript
- a model-menu pick while running sends `/model`; while idle it restarts
  fresh
- a stale saved model is cleared before the spawn, so the logged argv has
  no `--model-id`
- a relaunch whose start is refused ends in the refused-to-start state with
  the engine's reason, and the old transcript isn't left looking alive

### 3.3 Previews

`#Preview`s for:
- the declined tool card
- a rebuilt transcript under each divider kind

Each is rendered with `RenderPreview` and looked at, as the `ui-loop` skill
requires.

### 3.4 Recordings, which come first

- **The recorder.** `Tools/record-engine-fixture.py` takes the model as a
  parameter, defaulting to `qwen3.8-27b`, and gains the scenarios
  `relaunch-rewind` and `tool-rejected`.
  - `relaunch-rewind` runs two prompts, then `/rewind 1`, saves that
    process's stdout, then runs the `relaunch` argv and saves its stdout as
    `resumed.ndjson`.
  - `tool-rejected` asks for an unknown tool and retries seeds 1–6. If no
    seed produces the event, its payload is written from
    `E/docs/tui.md:1748` and listed as hand-written.
- **What gets re-recorded on the 27B:** `tool-read`, `stop`, `error` and
  `models-real.json`. Every recording's "must contain" column is checked by
  hand.
- **`provenance.md`:** record the engine commit, model, context and machine,
  and drop the stale note.
- **Needs:** the GPU free for about 10–15 minutes, and the owner's go-ahead.

## 4. Done when

- On this Mac, with `engineModelID = laguna-xs-2.1` still saved, the built
  app starts a session on `qwen3.8-27b` and shows the notice. After that
  run the setting reads empty.
- Live, `/rewind 1` relaunches and the transcript shows only prompt 1's
  turn.
- Live, a model-menu switch mid-session relaunches with "files kept", and
  the toolbar shows the new model.
- Both test tiers pass, the build has no warnings, and the new previews have
  been rendered.
- `ROADMAP.md`:
  - EN.1 is closed
  - the "Model fixtures document a dropped lineup" and real-engine
    recapture items it absorbed are gone
  - `## Now` points at SU.5

## 5. Risks

- **A relaunch whose start is refused.** One example: `/resume` of a
  Laguna-era session, which adopts its own model id, now unknown. It must
  land in the refused-to-start state with the engine's reason. A test in
  §3.2 pins this.
- **`start()` becoming async.** It touches every caller and the SU.3
  fixture-controller guard. The guard on fixture controllers stays first,
  so a preview still spawns nothing.
- **`/model` sent while a turn is busy.** The relay queues it like any
  prompt, so the relaunch comes after the turn ends. That is acceptable; the
  menu shows the pick at once, and the toolbar's model label follows the
  `session` event as today.
- **Size.** About 400–500 code lines. The plan splits into EN.1a (the
  recordings, the stale model, declined calls) and EN.1b (relaunch,
  resumed, the model menu) if one plan won't fit under 400 lines.
