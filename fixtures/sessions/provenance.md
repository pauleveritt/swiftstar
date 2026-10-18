# Session fixtures

Session directories copied byte for byte from
`~/.local/state/ds4-engine/sessions/`. At AN.1 they were for
`session_last.py`'s tests. Since AN.4 they are what
`fixtures/engine/report.json` is recorded from: run `ds4-dogfood report` on
this directory again to re-capture it. The Kit tests pin the report's counts,
so a new fixture is added beside these rather than replacing one.

## `20261013-123136-swiftstar`

- **Recorded:** 2026-10-13, by SwiftStar driving `ds4-dogfood tui --ndjson`
  against this repository, resumed from `20261013-122439-swiftstar`.
- **Engine:** ds4-engine `5451cd7d` (the capture's `host_commit`), capture
  `schema_version` 18, events `schema_version` 1.
- **Model:** `qwen3.8-flash-next`, context 20,000, on an Apple M5 Max.
- **What happened:** four prompts: a greeting; break a test and try to run it
  (the model called a `run` tool that doesn't exist: step 17); the same
  again; revert both changes (two re-reads answered "Already shown above":
  steps 36 and 37). The candidate's diff ends empty.
- **Kept:** `operator-events.jsonl`, `receipt.json`, the final capture
  `run-2032219913971169475-1791909283501.json`, `candidate.diff`.
- **Left out:** `conversation.json`, `conversation.kv` (349 MB), `native.log`
  and `rewind/`. The report doesn't read them.
- The receipt's absolute paths are as the engine wrote them. The engine's
  report finds the capture by its file name.

## `20261018-112154-su-ui` (EN.2)

- **Recorded:** 2026-10-18, by `just capture resumed-answered`, in a
  scratch state at ds4-engine `a84b79bd`. It's the resume of
  `20261018-112142-su-ui`, whose prefix-cache miss is
  `fixtures/engine/prefix-changed.ndjson`.
- **Model:** `qwen3.8-27b`, context 16,384, `--seed 7`.
- **What happened:** the resumed conversation's saved state loaded
  (`conversation_state`, 319,346,360 bytes in 23 ms), then one prompt was
  answered: "4 + 4 = 8."
- **Kept:** `operator-events.jsonl`, `receipt.json`, the capture
  `run-2682026648164563704-1792315317778.json` and the empty `candidate.diff`.
- **Left out:** `conversation.json`, `conversation.kv` (325 MB),
  `native.log` and `rewind/`.
