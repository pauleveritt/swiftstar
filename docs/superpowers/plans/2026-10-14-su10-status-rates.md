# SU.10: the status bar's rates

A small cycle (`docs/sdd.md`): one doc, no spec. The owner, 2026-10-14,
on the status bar at start: "Prefill avg — · G…n avg — · Ready" is ugly.

## Decisions

The owner made D1 and D2; D3 and D4 follow from them.

**D1. Just the two numbers:** prefill, then generation, in tok/s, with no
labels or unit. A tooltip explains them.

**D2. They don't move:** each number sits in a fixed slot as wide as
"8888.8" in monospaced digits, so the layout holds as digits come and go.

**D3. The label stands alone.** The status text on the left is the
composer's label ("Ready", or the exit message); the rates sit on the
right, before the GPU memory, and only while the session runs. Before a
measurement each number is "—".

**D4. The tooltip says they're session averages.** "Prefill 189.8 tok/s,
generation 65.3 tok/s: averages over this session." This settles the
punch list's "label Throughput's averages session avg" for the status bar.

## Facts this rests on

- **Today** `MetricsFormatting.statusLine` (`MetricsFormatting.swift:23`)
  joins both rates and the label into one string, which truncates in the
  middle at 18 pt.
- **`.help` works on text** (the owner's SU.6e hover check: the GPU
  figures showed their tooltip), so the rates need no `NativeTooltip`.

## Tasks

### Task 1: the formatting in Kit

**Files:**
- Modify: `Sources/SwiftStarKit/MetricsFormatting.swift`
- Test: `Tests/SwiftStarKitTests/MetricsFormattingTests.swift`

**Interfaces:**
- `rateNumber(_ value: Double?) -> String`: "189.8", or "—"
- `ratesTooltip(prefill: Double?, generation: Double?) -> String`
- `rateSlot = "8888.8"`: the widest number a slot is sized for
- `statusLine` goes: the label is shown as it is

**Tests first:** the number and the dash; the tooltip with and without
measurements; `statusLineRunningAndNot` is replaced.

### Task 2: the status bar

**Files:**
- Modify: `Sources/SwiftStarUI/Session/StatusBarView.swift`

**Steps:**
1. The label on the left, alone.
2. While running, a rates view on the right: two numbers, each in a
   hidden-`rateSlot` frame, a faint "/" between, `.help` with the tooltip.
3. Render the four previews, at 18 pt and in `SessionView`'s "Large font".

### Task 3: close

- `ROADMAP.md`: SU.10's row, one line; the punch list's "session avg"
  item goes.
- This plan gains `## Result`.
- `just lint-docs`, `just test`, `just integration`.
