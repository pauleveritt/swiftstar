# AN.1 Implementation Plan: the session report

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development
> or superpowers:executing-plans. Steps use checkboxes. This plan follows
> `docs/sdd.md`'s local rule: each task lists files, interfaces (signatures
> only) and tests (name plus a one-line assertion). It doesn't paste code
> bodies.

**Goal:** `just last` and `/last` print the newest session's flagged steps,
summary and raw signals as Markdown (or `--json`), with no model call.

**Architecture:** one standard-library Python file of pure functions
(`load` → `steps` → `flags` / `summary` / `signals` → `report` →
`markdown`). It sits in `SwiftStarEngine`'s resources, so AN.2's app can run
the same file. `main()` is the only part that touches argv, stdout or a
subprocess.

**Tech stack:** Python 3 standard library (`json`, `argparse`, `statistics`,
`subprocess`, `unittest`), `just`, SwiftPM (declaring a resource only).

**Spec:** [`2026-10-13-an-session-analysis-design.md`](../specs/2026-10-13-an-session-analysis-design.md)
§1, §2 and §5. `E/` is `../ds4-engine` at `5451cd7d`. "123136" is the session
`~/.local/state/ds4-engine/sessions/20261013-123136-swiftstar`.

## Global Constraints

- **Python:**
  - standard library only; runs as `python3 -I`; unlinted, like `Tools/`
    (BRIEF, "Practical environment")
  - no third-party test runner: tests use `unittest`
- **Tests:**
  - no subprocess and no network in `Tools/tests`; `newest_session` takes an
    injected runner
  - every new test is shown to fail once by breaking what it pins, and the
    break is recorded in `## Result` (BRIEF rule 2)
  - a refusal has a success twin (rule 4)
  - no assertion on source text (rule 3)
- **Builds:** warnings are errors (`Package.swift:13`). The `.py` file must be
  declared, or SwiftPM warns about an unhandled file.
- **Engine facts** carry their `E/` location in a comment beside the constant
  that holds them (BRIEF, "Background").
- **Out of scope (AN.2):**
  - any Swift code that runs the script
  - `sessionDirectory` from `checkpoint`
  - `.partial.json` captures

## Decisions (made while planning)

- **P1. The capture is found by name, inside the session directory.** The
  path is `dir / basename(receipt.capture_path)`.
  - This replaces the spec's §2.4 "rewrite `capture_path` to be relative":
    the fixture's receipt stays byte-identical to what the engine wrote.
  - A session directory that was moved still loads.
- **P2. Which guard notices count as U1** (`E/` sources):
  - `already_shown`: a `result_text` starting `[Already shown above:`
    (`E/crates/ds4-native/src/shown.rs:209`)
  - `repeated_call`: `Tool error: not run. You already made this exact call`
    (`E/crates/ds4-native/src/loop_guards.rs:78`)
  - `call_cycle`: `Tool error: not run. Your last`
    (`E/crates/ds4-native/src/loop_guards.rs:81-86`)

  `answer_cap` and `self_copy` act on sampling, not on a tool result, so they
  appear in Signals only. The check against `loop_guards` totals compares
  only the three kinds above.
- **P3. One flag per step,** in the order U1, F1, U2. A loop-guard refusal is
  `result_ok` false, but the engine refused it as waste, so it is U1, not F1.
  F2 and F3 attach to prompts, not steps.
- **P4. Per-pause rates come from `checkpoint` snapshots.**
  - prefill tok/s = Δ`prefill_tokens` / Δ`sync_ms`
  - generation tok/s = Δ`eval_count` / Δ`eval_ms`

  These are deltas between consecutive checkpoints, because the snapshot is
  session-cumulative (BRIEF, finding 2); the first checkpoint's delta is from zero. A pause with Δms ≤ 0 has no rate,
  not an infinite one.
- **P5. `just test` runs `test-tools` first,** so the Python tests ride the
  existing habit.

## Review Focus

Most likely to bite first:
1. **A session with no prompts** (opened, then closed). The report shows the
   header and "no prompts", not a traceback. Task 1
   `test_session_without_prompts`.
2. **A capture missing from the directory** (pruned, or the session still
   live). The script exits 1 with a message naming the file. Task 4
   `test_main_missing_capture_exit1`.
3. **A prompt or path containing `|` or a newline** keeps the table's rows
   intact. Task 4 `test_markdown_cell_escaping`.
4. **A checkpoint with no time between it and the previous one** gives no
   rate, not a division error. Task 3 `test_zero_delta_has_no_rate`.
5. **`ds4-dogfood` missing, or no session for this repo.** One stderr line
   says which, with exit 1. Task 4 `test_newest_none_names_command`.

---

### Task 1: Load a session and group its steps

**Files:**
- Create: `Sources/SwiftStarEngine/Resources/session_last.py`
- Modify: `Package.swift:44-48`: `resources: [.copy("Resources/session_last.py")]`
  on `SwiftStarEngine`
- Create: `fixtures/sessions/123136/`: 123136's `operator-events.jsonl`,
  `receipt.json`, `run-2032219913971169475-1791909283501.json` and
  `candidate.diff`, copied byte for byte
- Create: `fixtures/sessions/provenance.md`: source path, engine commit
  `5451cd7d` (the capture's `host_commit`), model `qwen3.8-flash-next`, the
  files left out (`conversation.*`, `native.log`, `rewind/`), and a note that
  AN.1's tests pin its counts
- Create: `Tools/tests/test_session_last.py`: puts the resource directory on
  `sys.path` and imports `session_last`
- Modify: `Justfile`: add `test-tools`
  (`python3 -I -m unittest discover -s Tools/tests -v`); `test` runs it first

**Interfaces:**
- `CAPTURE_SCHEMA = 18`, `EVENTS_SCHEMA = 1`
- `load(directory: Path) -> Session`, where the dataclass
  `Session(directory, events: list[dict], receipt: dict, capture: dict, diff: str, warnings: list[str])`
- `Step(index: int, prompt: int, tool: dict | None, context_used: int | None, tokens: int)`,
  a dataclass. A step whose `tool` is None is an answer.
- `Prompt(index: int, text: str, steps: list[Step], answered: bool)`
- `steps(session: Session) -> list[Prompt]`: an answer step closes a
  prompt, and the text comes from `capture.user_turns`
- `LoadError(Exception)`: for a missing or unreadable file, naming the path

**Tests:**
- [ ] Write them:
  - `test_123136_accepted`: 4 prompts; 40 steps in all; the answer steps
    are 0, 20, 32 and 39; `warnings == []`
  - `test_capture_found_by_basename`: a copy of the fixture whose receipt
    `capture_path` is `/elsewhere/<same name>` loads
  - `test_unknown_schema_warns`: a capture with `schema_version` 19 loads,
    with one warning naming 19. Its twin is `test_123136_accepted`'s empty
    warnings.
  - `test_missing_capture_raises`: a copy without the capture raises
    `LoadError` naming the file
  - `test_session_without_prompts`: an inline session with no `user_turns`
    and no steps gives `[]`
- [ ] See each fail, then implement. `just test-tools` and `swift build`
  pass with no warning. Commit.

### Task 2: Flag failed and useless steps

**Files:**
- Modify: `Sources/SwiftStarEngine/Resources/session_last.py`
- Test: `Tools/tests/test_session_last.py`

**Interfaces:**
- `GUARD_MARKERS: dict[str, str]`: kind → prefix (P2), with a comment
  citing `E/`
- `Flag(prompt: int, step: int | None, rule: str, evidence: str)`, a
  dataclass. `rule` is one of `F1 F2 F3 U1 U2`.
- `CHECKS = ("F1", "F2", "F3", "U1", "U2")`
- `flags(prompts: list[Prompt], events: list[dict]) -> list[Flag]`.
  F2 uses the events whose `turn` equals the prompt index.
- `guard_mismatch(found: list[Flag], loop_guards: dict) -> str | None`

**Tests:**
- [ ] Write them:
  - `test_123136_flags`: exactly three flags:
    step 17 (prompt 1) F1 with evidence containing `unknown tool: run`, and steps 36 and 37 (prompt 3) U1 `already_shown`
  - `test_123136_reread_after_edit_not_flagged`: steps 18 and 30 have no
    flag
  - `test_123136_guard_totals_agree`: `guard_mismatch` is None. Its twin
    `test_guard_mismatch_reported`: with `already_shown` 3 the result names
    found 2 against counted 3.
  - `test_loop_refusal_is_u1_not_f1`: an inline `result_ok` false step
    whose text starts with the `repeated_call` marker gives U1. Its twin: a
    plain `Tool error: unknown tool: x` gives F1.
  - `test_repeat_without_edit_flagged` /
    `test_repeat_after_edit_not_flagged`: two identical `read a.swift`
    steps give U2 on the second; with an `edit` to `a.swift` between them,
    no flag.
  - `test_prompt_without_answer_flagged` /
    `test_prompt_with_answer_not_flagged`: F3
  - `test_native_end_not_ok_flagged` / `test_native_end_ok_not_flagged`:
    a `native_end` with `status: "error"` in the prompt's window gives F2.
  - `test_host_results_never_flagged`: two identical `host_results` steps
    give no U2.
- [ ] See each fail, then implement. Commit.

### Task 3: Summary rows and signals

**Files:**
- Modify: `Sources/SwiftStarEngine/Resources/session_last.py`
- Test: `Tools/tests/test_session_last.py`

**Interfaces:**
- `PauseRate(seq: int, prompt: int, prefill_tps: float | None, gen_tps: float | None, context_used: int | None)`
- `pause_rates(events: list[dict]) -> list[PauseRate]`, following P4
- `summary(session: Session, prompts: list[Prompt]) -> dict[str, str]`,
  with keys `Time`, `Context and speed`, `Work`, `Ending` and `Health`, in
  that order (spec §2.2)
- `signals(session: Session, prompts: list[Prompt]) -> dict[str, object]`:
  - `loop_guards`
  - `constraint` (`masked_token_count`, `removed_probability_mass`, `forbidden_argmax`)
  - `think_inert_openers`
  - `citation_corrections` (total)
  - `prefix_cache` (hits and misses)
  - `syncs_under_1ms`
  - `dflash`
  - `host_results_steps`
  - `result_bytes` (total and shown)

**Tests:**
- [ ] Write them:
  - `test_per_pause_rates_are_deltas`: two inline checkpoints (prefill
    955 tokens / 1950.4 ms, then 1000 / 2744.5) give a second-pause prefill
    of 45 / 794.1 × 1000 ≈ 56.7 tok/s, not the cumulative 364.4 tok/s
  - `test_zero_delta_has_no_rate`: equal `sync_ms` gives `prefill_tps`
    None
  - `test_123136_pause_rates`: 23 checkpoints give 23 rates, the first one
    from the session start
  - `test_123136_summary`:
    - `Context and speed` contains `1,021 → 7,300`
    - `Work` contains `read 10, edit 4, ls 3, grep 2, run 1` and
      `rejected: run (unknown-tool)`
    - `Work` doesn't mention `host_results`
  - `test_123136_signals`:
    - `loop_guards["already_shown"] == 2`
    - `syncs_under_1ms == 19`
    - `host_results_steps == 16`
    - `result_bytes == (8997, 8997)`
- [ ] See each fail, then implement. Commit.

### Task 4: Markdown, the command, `just last` and `/last`; AN.1 closes

**Files:**
- Modify: `Sources/SwiftStarEngine/Resources/session_last.py`
- Modify: `Justfile`: `last *ARGS` runs
  `python3 -I Sources/SwiftStarEngine/Resources/session_last.py {{ARGS}}`
- Create: `.claude/commands/last.md`:
  - runs `just last $ARGUMENTS` and shows the output as it is
  - tells Claude to answer follow-up questions from the report, and to open
    the session's files only for the steps asked about
- Test: `Tools/tests/test_session_last.py`
- Modify, at close:
  - this plan's `## Result`
  - `ROADMAP.md`: a new `## Phase AN: Analyze` table with rows AN.1–AN.4
    (AN.1 done, AN.2 next, AN.3 and AN.4 not started), and a `## Now`
    pointer to AN.2

**Interfaces:**
- `report(session: Session) -> dict`, with keys `header`, `flags`, `checks`,
  `summary`, `signals` and `warnings`
- `cell(text: str, limit: int = 200) -> str`, ported from
  `M/extensions/mellum-last.ts` `cell()`
- `markdown(report: dict) -> str`: the first line is
  `**last**: <id>, <model>, ctx <n>, <wall>, <outcome>`, then
  `, resumed from <id>` and `, rewound to <n>` when present
- `newest_session(source: Path, run=subprocess.run, executable: str | None = None) -> Path`.
  It runs `<ds4-dogfood> sessions --json --source <git root> --limit 1`.
  `ds4-dogfood` is found from `$DS4_DOGFOOD`, then `PATH`, then
  `~/.local/bin`. The function raises `LoadError` naming the command when
  there is no session.
- `main(argv: list[str] | None = None, stdout=sys.stdout, stderr=sys.stderr) -> int`
  takes `--session PATH` and `--json`, and exits 0 or 1.

**Tests:**
- [ ] Write them:
  - `test_markdown_lists_flags_first`: in 123136's Markdown, the flagged
    steps come before `| Time |`, and `Signals` comes last
  - `test_no_flags_names_checks`: a report with no flags prints
    `no flagged steps (checked F1, F2, F3, U1, U2)`
  - `test_markdown_cell_escaping`: `cell("a|b\nc")` gives `a\|b c`, and
    `cell("a\\|b")` gives `a\\\|b`
  - `test_main_session_path`: `main(["--session", fixture])` returns 0, and
    stdout starts with `**last**: 20261013-123136-swiftstar`
  - `test_main_json`: with `--json`, stdout parses, and
    `len(flags) == 3`
  - `test_main_missing_capture_exit1`: returns 1, stderr names the capture,
    and stdout is empty. Its twin is `test_main_session_path`.
  - `test_newest_from_sessions_json`: a fake runner returning
    `[{"path": X}]` gives `X`
  - `test_newest_none_names_command`: a fake runner returning `[]` raises
    `LoadError` whose message contains `sessions --json`
- [ ] See each fail, then implement. Commit.
- [ ] **Live checks.** Record each command and its first lines in `##
  Result`:
  - `just last` in this repo
  - `just last --session` on an older session (a `rewound_to` one)
  - `/last` in Claude Code
  - `just last --json | python3 -m json.tool` parses
- [ ] **Close:** `## Result` (commits, the break used for each test, what
  diverged), the ROADMAP table and `## Now`, then `just lint-docs`,
  `just test` and `just integration`. All of it goes in this task's commit
  (`docs/sdd.md`, step 4).

## Result

Not started.
