# `golden.ndjson` — capture notes (P1 recapture)

This fixture is a **verbatim, byte-for-byte copy of `ds4-agent`'s stdout** from one real
`--json-events` session at the P1 pinned submodule SHA. Nothing in it was hand-written or
reformatted. It exists to replace prose description of the wire format with an actual observed
sample — and, per the P1 plan, this recapture is a **re-verification** that the rebase (the
22-commit patch set on `swiftstar-integration`) preserved the wire contract against the rebuilt
binary.

## Provenance

- Submodule (`external/ds4`) SHA: `b3d2b5e0d4b15f223d333921797b4a6fd018aeae`
  (branch `swiftstar-integration`, tip of the fork at capture time; the SwiftStar gitlink pins
  this exact SHA — confirmed by `git submodule status` and `git -C external/ds4 rev-parse HEAD`).
- Built with: `just engine` (which runs `git submodule update --init external/ds4` then
  `make -C external/ds4 ds4-server ds4-agent`). Binaries run in place,
  `external/ds4/ds4-agent` / `external/ds4/ds4-server`.
- Command line actually run:

  ```
  ./ds4-agent -m ~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf \
    -c 32768 --chdir /tmp/ds4-capture-agent/work --metal --non-interactive --json-events
  ```

  with one `DS4_METAL_<BASENAME_UPPERCASED>_SOURCE` env var per file in
  `external/ds4/metal/*.metal` (21 vars total — **required**), and
  `DS4_LOCK_FILE=/tmp/ds4-capture.lock`. stdin attached to a FIFO so prompts could be injected
  one at a time without the agent seeing EOF or the model being reloaded.

- Model file used: `laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (Laguna S 2.1, 48 GiB) at
  `~/projects/ds4/gguf/`.
- Working directory for the session (`--chdir`) contained two seed files:
  `notes.txt` (three lines of plain ASCII text) and `other.txt` (two lines of different plain
  ASCII text), used as read targets.
- **Harness gotchas found this run, worth carrying forward:**

  1. **`--chdir` breaks the relative Metal-source defaults.** The engine loads
     `metal/*.metal` shaders at runtime relative to the process CWD, and `--chdir` switches
     CWD *before* the shader load, so the plan's Step 3 command as literally written fails with
     `Metal source metal/flash_attn.metal not found`. The fix is the engine's documented
     "running from elsewhere" escape hatch: all 21 `DS4_METAL_*_SOURCE` vars, absolute (generated
     from `external/ds4/metal/*.metal`). This is the same set of vars DS4 Control's capture used;
     the P1 plan's "no env vars needed from inside external/ds4" note is only true without
     `--chdir`.
  2. **A hung external `ds4` held `/tmp/ds4.lock`.** A `decode_sweep.sh` (Mellum 2.1 resident
     profile, from another agent session on this machine) had a `ds4` process stuck at 0.5% CPU
     for 30+ minutes, holding the default instance lock, so `ds4-agent` refused to start with
     `another ds4 process is already running`. Rather than kill that process (it was not ours to
     touch), the capture used `DS4_LOCK_FILE=/tmp/ds4-capture.lock` to give this session its own
     lock. The ds4 source (`ds4_acquire_instance_lock`) honors that env var.
  3. **FIFO keepalive**: a background `while :; do sleep 3600; done` loop held the FIFO open
     read-write for the life of the session, so each individual prompt write didn't transiently
     drop the writer count to zero and hand stdin an EOF. (`sleep infinity` is not a macOS
     `/bin/sleep` argument — use the loop.)

## The memory-budget verification

The `ready` event's four memory fields must agree exactly with the `ds4: memory:` boot line on
stderr (same cached startup memory plan). Captured boot line:

```
ds4: memory: KV 1.57 GiB (raw 1.57 + compressed 0.00) + buffers 0.00 GiB + resident model 44.94 GiB = 46.51 GiB planned
```

| field | `ready` bytes | bytes / 1024³ (2 dp) | boot-line figure | match |
|---|---:|---:|---:|:---:|
| `kv_bytes` | 1,686,110,208 | 1.57 GiB | KV **1.57** GiB | yes |
| `scratch_bytes` | 784,752 | 0.00 GiB | buffers **0.00** GiB | yes |
| `model_bytes` | 48,257,070,080 | 44.94 GiB | resident model **44.94** GiB | yes |
| `planned_bytes` | 49,943,965,040 | 46.51 GiB | **46.51** GiB planned | yes |

All four agree exactly. All 7 `ready` events in the fixture carry byte-identical values.

## Prompts sent, in order, and what each produced

All prompts were sent by writing one line to the FIFO and waiting for the `ready`-event count in
the capture file to increase (a fresh turn boundary) before sending the next, so none was ever
queued — see "Gaps" below.

1. **Reasoning puzzle** (reliably produces a non-empty `<think>` block and cannot be answered
   from memory):

   > Five people (Alice, Bob, Carol, Dave, Eve) occupy houses numbered 1 to 5, one each.
   > Constraints: Alice is not in house 1 or house 5. Bob is directly to the right of Carol.
   > Dave is in an even-numbered house. Eve is somewhere to the left of Bob. Carol is not in
   > house 3. Work out every assignment that satisfies all constraints, showing your deductions.

   Result: real `think` content (all 838 `think` events in the fixture came from this one turn —
   the model was very thorough) followed by `text` events reaching the fully-deduced answer.

2. **Read + write, non-ASCII payload**: "Please read the file notes.txt in the current
   directory, then write a new file called result.txt containing exactly this text:
   Café — €12 total. Do both the read and the write."

   Result: one tool block containing `read` at `idx:0` (notes.txt) and `write` at `idx:1`
   (`path`="result.txt", `content`="Café — €12 total.") with `finish idx:1 calls:2`. The em dash
   and euro sign round-tripped through the wire intact; `result.txt` on disk after this turn
   reads exactly `Café — €12 total.`

3. **Edit**: "Edit result.txt: change the word Café to Bistro, keeping the rest of the line the
   same."

   Result: one `edit` tool block with `diff_old` ("Café — €12 total.") and `diff_new`
   ("Bistro — €12 total.") parameters. `result.txt` on disk after this turn reads exactly
   `Bistro — €12 total.`

4. **Multi-call block**: "Please read both notes.txt and other.txt right now, one after the other
   in the same response, then briefly compare their contents."

   Result: one tool block containing two calls — `read` at `idx:0` (notes.txt) and `read` at
   `idx:1` (other.txt), with `finish idx:1 calls:2`; `idx` is non-decreasing and increments by
   exactly 1 across the two calls.

5. **Bash output containing `#`**: "Run a bash command that prints the exact line:
   # Section Heading"

   Result: one `bash` tool block (`bash_command` = `echo "# Section Heading"`) whose `output`
   event's `s` is `"# Section Heading\n"` — confirming `#` arrives via `tool`/`output`, not
   `text`.

6. **Long generation + interrupt**: "Write a very detailed, thorough 1200-word essay about the
   history of chess. Cover its origins in ancient India, its spread through Persia and the
   Islamic world, its adoption and rule changes in medieval Europe, the rise of formal
   competition and world championships, the Soviet school of chess, the Fischer-Spassky match,
   and the computer-chess era." The interrupt trigger was `generated >= 200` tokens (per the
   plan).

   Result: generation was fast this run (58.9 t/s) — the first poll already saw `generated=1117`,
   and the bare ETX byte (`0x03`) was sent immediately. The block's `finish` event carries
   `"status":"[tool call interrupted]\n"` with `calls:1` — the documented shape for a block that
   was still open when generation was interrupted.

After prompt 6, the `ds4-agent` process was shut down with `SIGTERM` and exited cleanly; the
keepalive helper was terminated; the FIFO was removed. No other `ds4` process was touched (the
hung Mellum `decode_sweep` process was left running — see gotcha 2).

## Event kinds and tool phases present

All of these appear at least once in the fixture:

- Kinds: `text` (179), `think` (838), `tool` (59), `status` (1053), `ready` (7).
- Tool phases: `start` (6), `tool` (8), `param_begin` (12), `param_value` (13), `param_end` (12),
  `output` (2), `finish` (6).
- Tool names (`phase:"tool"` events): `read` (3), `write` (2), `edit` (1), `bash` (2).
- `status.state` values observed: `idle` (7), `prefill` (37), `generating` (1009).
- Every `tool`-kind event carries `idx` (checked programmatically over all 59 — none missing).
  Every `param_begin` carries a non-empty `name` (checked over all 12 — none missing).
  `param_begin.kind` values observed: `path` (6), `content` (2), `diff_old` (1), `diff_new` (1),
  `bash_command` (2).
- One `finish` event carries `"status":"[tool call interrupted]\n"` (prompt 6); the other five
  omit it (all completed cleanly), matching the documented "present only when the block did not
  complete cleanly" rule.
- Every `ready` event (all 7) carries all four memory fields (`kv_bytes`, `scratch_bytes`,
  `model_bytes`, `planned_bytes`), byte-identical across the session — see the memory-budget
  verification above.

## Gaps — what was not captured, and why

- **`queued` was not captured.** Every prompt was sent only after the previous turn's `status`
  returned to `idle` and a fresh `ready` was observed, so no prompt was ever submitted while the
  worker was busy — the one precondition for `queued` to fire. Not attempted here: it risks
  interleaving/losing keystrokes relative to the clean single-instance model this fixture
  otherwise exercises. A genuine gap, not an invented absence.
- **`status.state` values `compacting`, `draining`, `saving`, `error`, `stopped` were not
  observed.** Nothing in this session triggered context compaction, a shutdown drain/save
  sequence, or an error condition. Only `idle`, `prefill`, and `generating` appear.
- **Only one `finish.status` value was captured** (`"[tool call interrupted]\n"`, from prompt 6).
  No DSML parse-error case (`"[invalid tool call: ...]\n"`), no edit-preflight case
  (`"[tool call stopped: edit old selector failed]\n"`), no hard-failure case
  (`"[tool call failed: ...]\n"`). None was deliberately exercised, and none occurred
  incidentally.
- **Absent `output` events for `read`, `edit`, and `write` are expected behavior, not a capture
  gap.** Per `external/ds4/docs/json-events.md`, only `bash`, `bash_status`, `bash_stop`, and the
  internal "unknown tool name" fallback ever emit `tool`/`output`; `read`, `write`, `edit`,
  `list`, `search`, `google_search`, and `visit_page` results are appended directly to the
  model's transcript and never reach the wire. The `bash`/`output` shape is directly exercised
  by prompt 5.
- `google_search` and `visit_page` were not exercised at all (out of scope for a local-only,
  offline capture session).
- **The `ready` event's bare (no-memory-fields) form was not captured.** Per
  `external/ds4/docs/json-events.md`, that form only occurs when the engine was opened with
  `ctx_size <= 0`; this session always used `-c 32768`, so every `ready` in this fixture carries
  the four memory fields.

## Sanity checks run

- Every line parses as valid JSON (Python `json.loads` over all 2136 lines — zero failures).
- Every `text`, `think`, `param_value`, and `output` payload's `s` field (and every `finish`
  event's `status` field) was independently re-decoded as UTF-8
  (`str.encode("utf-8").decode("utf-8", errors="strict")`) — zero failures across all 1033 such
  fields in the file.
- `idx` presence checked on all 59 `tool`-kind events (0 missing) and `name` presence checked on
  all 12 `param_begin` events (0 missing/empty), by direct field inspection rather than sampling.
- All 7 `ready` events' four memory fields checked for byte-identical equality across the
  session (they are), and the first one's bytes-to-GiB conversion checked against the
  `ds4: memory:` stderr boot line from the same process (they match exactly — see above).
- Wire shape cross-checked against the DS4 Control reference fixture
  (`agent-events-golden.ndjson` at `8267745`): event kinds, tool phases, `idx`/`name` presence,
  the interrupted-`finish` shape, and the `ready` memory fields all match. (Line counts differ
  only because this session's model output was more verbose; the wire contract is unchanged.)
