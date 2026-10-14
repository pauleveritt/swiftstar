# SU.6g: the punch list

A small cycle (`docs/sdd.md`): one doc, no spec. The owner, 2026-10-14:
"do the punch list", skipping SU.13's scrollbar flash. "Engine information
worth showing" is held back: it needs a look at what the engine sends and
its own decisions.

## Decisions

**D1. Throughput says what it is.** The inspector's card is "Session
averages", its rows "Prefill" and "Generation".

**D2. GPU memory: actual against planned, in GiB.** Revised by the owner
(2026-10-14): a 107.5 GiB limit beside a model that should stay under
30 GiB reads as alarming. The status bar shows allocated over the engine's
plan for this model and context (`engine_plan.total_gib`), and its ring
fills against the plan; the inspector lists Allocated, Planned, then "GPU
limit" (Metal's `recommendedMaxWorkingSetSize`, the share of memory macOS
lets the GPU use, which the engine plans against). Before a plan arrives,
the limit stands in, as now. All three in GiB, as the engine's plan is.

**D3. Numbers follow the locale:** rates, durations and the context
tooltip's percent, as counts and GiB already do.

**D4. The runner doesn't wait for nothing:** after a timeout's SIGTERM it
waits only until the child exits (up to 1 s, then SIGKILL); and once the
child has exited, its pipes get 500 ms to drain, so a grandchild holding
one can't stretch a call to its full timeout.

**D5. The recorder keeps pairs and cleans up:** `resumed.ndjson` and
`relaunch-rewind.ndjson` are kept together or not at all, and a failed
recording removes its `.tmp`.

**D6. Two stale comments go:** `clamp`'s doc on `slot(for:)`, and the
toolbar's "transcript font" wording.

## Facts this rests on

- **The labels:** `InspectorView.swift:48-59`; `MemoryStatusView.swift:12,18`
  (decimal GB via `.byteCount(style: .memory)`); `MetricsFormatting.bytes`.
- **The locale:** `rate`, `rateNumber`, `duration` and `contextTooltip` use
  `String(format:)` (`MetricsFormatting.swift`).
- **The runner:** `ProcessRunner.swift:63-71` sleeps 1 s after SIGTERM
  unconditionally, and its collector waits for EOF on both pipes.
- **The recorder:** `Tools/record-engine-fixture.py:121-125` keeps
  `resumed.ndjson` on its own exit code, before deciding the first
  recording's; `run` writes `.tmp` with no cleanup on an exception.
- **What "budget" is:** ds4-engine `first_run.py:136-147`.

## Tasks

### Task 1: Kit and the views (D1-D3, D6)

**Tests first:** `MetricsFormattingTests`: GiB for bytes; the GPU tooltip;
rates, durations and the percent in `de_DE`.

**Files:** `MetricsFormatting.swift`, `InspectorView.swift`,
`MemoryStatusView.swift`, `TranscriptFontScale.swift`, `SessionToolbar.swift`;
render their previews.

### Task 2: the runner (D4)

**Tests first:** integration: a SIGTERM-able child times out in well under
1 s past its timeout; a child that exits while a background grandchild
holds stdout returns its output in about the drain, not the timeout.

**Files:** `ProcessRunner.swift`.

### Task 3: the recorder (D5)

**Tests first:** `Tools/tests/test_record_engine_fixture.py`: a failed
first recording keeps neither file; a run whose output isn't JSON leaves
no `.tmp`.

**Files:** `Tools/record-engine-fixture.py`.

### Task 4: close

- `ROADMAP.md`: the punch list keeps only the engine-information item.
- SU.14's Result: the owner's check (the picker worked).
- This plan gains `## Result`; `just lint-docs`, `just test`,
  `just integration`.

## Result

Done 2026-10-14 on `su-ui`, in four commits after the plan (`bfd8c69`):
Task 1 (`d3d8660`), Task 2 (`5dde456`), Task 3 and this close.

**Suites:** `just test` and `just integration`, and `just test-tools` (45),
with no other test run going. Each task's tests were written first and
failed on the old code: the German-locale and GPU tooltip cases; the
runner at 1.37 s for a child that died at once, and at its full 10 s
timeout with a grandchild on the pipe (now under 0.9 s and 2 s); the
recorder's pairing and `.tmp` cases.

**Previews:** `MemoryStatusView`'s two (new: "Against the plan", "No plan
yet"), `InspectorView`'s two ("Narrow" now tall enough for every card),
`StatusBarView`'s four and `SessionToolbar`'s.

**Diverged:**
- **D2 changed mid-cycle, by the owner:** actual against the engine's plan,
  not against macOS's limit. A 107.5 GiB limit beside a model that should
  stay under 30 GiB read as alarming; the limit is now the inspector's last
  row, explained in the tooltip.
- **The preview's plan is 9.4 GiB,** not 6.0, so the ring shows a part-full
  plan rather than a full one.
- **Xcode's preview pipeline flaked** ("already been invalidated") on three
  renders, sequential this time, probably beside the owner's open canvas;
  each rendered on a retry.
