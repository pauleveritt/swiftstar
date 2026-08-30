# P24.1 window-honoring reads — the "after" measurement (2026-08-30)

**Status: the pre-registered falsifier was not tripped, and a paired control
arm reproduced the loop on demand.** With only `readResult` reverted to its
pre-P24.1 body, the identical prompt took 12 reads of one file and timed out;
with P24.1 it took 3 and completed. Limits recorded below.

## The falsifier, as pre-registered

The spec's Live validation names the failure condition:

> many distinct windows clustered on one region of one file

That is two measurements, not one, and the first attempt at this note got it
wrong by counting only the first half. Distinct windows alone are *healthy* — a
model walking a file asks a different range each time. The starvation loop has
both of:

- **repeat rate** — the same window asked again, because the answer never
  contained what was asked for;
- **concentration** — the asks piling onto one narrow band, the region the model
  cannot reach.

`Tools/window-spread.py` measures both. It is validated against the 1809
baseline, where it trips on `AgentView.swift` and **only** on
`AgentView.swift` — matching the documented finding that one file was the
culprit, and not firing on `ROADMAP.md` or the p12 plan.

## Result

| | 1809 baseline (pre) | 2026-08-30 (post) |
|---|---|---|
| read/more calls | 76 | 16 |
| …on `AgentView.swift` | 32 | 8 |
| distinct windows there | 22 | 8 |
| **repeat rate** | **1.45** | **1.00** |
| **concentration** | **81%** (lines 171–271) | 57% (lines 231–331) |
| verdict | **TRIPPED** | **not tripped** |
| compactions | 5 | 1 (28,300 → 4,928) |

**No window was asked twice anywhere in the session** — repeat rate 1.00 on
every path, not just the hot one.

### The post-compaction recovery, which is the case that matters

The baseline blamed compaction churn: each compaction discards ~23k tokens and
is followed by recovery re-reads of the same file. This session reached one
compaction (28,300 → 4,928, the same shape), and the four reads after it were:

```
Sources/SwiftStar/AgentView.swift  start=255 max=90
ROADMAP.md                         (bare)
ROADMAP.md                         start=30  max=15
Sources/SwiftStar/AgentView.swift  start=257 max=90
```

Two reads of the hot file, no repeated window, then it moved on. The baseline's
answer to the same situation was 32 reads across 22 clustered windows.

## The paired control arm (2026-08-30, added after the above)

The comparison above is against a *different* session. A real control was then
run: **the same script, prompts, workspace, model, and drive host-tool loop,
with only `HostToolExecutor.readResult` reverted to its pre-P24.1 body**
(whole file, window parameters ignored, straight into the 8000-byte condenser).
Built on a throwaway branch, discarded after the run.

**A first correction, because it was wrong in this note's previous revision and
in the ROADMAP row:** `CAPTURE_HOST_TOOLS=0` is **not** the control. It makes
the *engine* serve reads with its own `agent_read_range`, which already honored
windows — that is the null arm, and it is how the first measurement attempt
failed. The control must keep host tools ON and change only the function under
test.

### Result: the control did not survive prompt 1

| | control (pre-P24.1) | treatment (P24.1) |
|---|---|---|
| read/more calls **on turn 1** | **12** | **3** |
| all on `AgentView.swift` | yes | yes |
| turn 1 outcome | **timed out at 240 s** | completed (~33 s) |
| session outcome | **FAILED at prompt 1 of 12** | 12/12 in 4.5 min |
| repeat rate (hot file) | **1.38** | 1.00 |
| concentration | **71%** (lines 1–101) | 57% |
| falsifier | **TRIPPED** | not tripped |

The control's twelve calls, in order, all against the same file:

```
(bare)  1/80  80/80  more  (bare)  150/100  (bare)  100/50  1/10  200/50  60/50  (bare)
```

That is the 1809 pathology reproduced live and on demand: window after window,
a `more` attempt (which the pre-P24.1 host errors on), falling back to bare
re-reads, never converging, until the turn was killed. The treatment answered
the identical prompt with `(bare) → 150/320 → 275/200` and moved on.

Because only `readResult` differs between the two runs, this is the paired
evidence the earlier revision said was outstanding, and it is stronger than a
token comparison: the control **could not complete the task at all**.

## What is still weak about this, stated plainly

1. **The control failed too early to compare bills.** It never reached prompt 2,
   so there is no Σsuffix comparison across matched sessions — only the
   task-completion difference above. That is arguably the better evidence
   (rule 5: a tool that starves the model faster also reduces Σsuffix), but it
   is not the paired bill the P24 guardrail describes, and no `swiftstar-analyze
   diff` number is claimed here.
2. **Shorter and smaller than the baseline.** ~4.5 minutes of turns and one
   compaction, against the 1809 session's 24 minutes and five.
3. **One residue worth naming.** The two post-compaction reads were `255/90`
   and `257/90` — a two-line shift, the closest thing here to re-asking. Two
   asks is not a loop, but it is not zero, and a longer session is the way to
   find out whether it grows.
4. **One session per arm, one seed.** P20's closure verdict recorded seed
   dependence on a comparable claim; this has the same exposure. The control
   tripping on its first turn makes a fluke less likely, not impossible.

## What made the measurement possible

The first attempt (recorded in this note's superseded revision, commit
`00aa6e2`) measured nothing: `swiftstar-drive` had no host-tool loop, so the
*engine* ran `read` itself via `agent_read_range` — code that already honored
windows and is not what P24.1 changed. Zero `tool_request` events against the
baseline's 119.

`swiftstar-drive` now takes `CAPTURE_HOST_TOOLS=1` (opt-in, so the P5 capture
shape and its golden fixtures are untouched; requires `CAPTURE_WORKSPACE`), uses
`AgentWireParser` so it can see `tool_request`, and answers each request through
the same `ToolCallbackResponder` + `HostToolExecutor(.app)` pair the app uses.
This capture carries **26 `tool_request` events**, so `HostToolExecutor.readResult`
— the function this cycle rewrote — actually ran.

That gap was worth closing on its own: before this, no committed tool could
capture the app's real tool path, which is why the 1809 baseline had to be
hand-driven.

## The 1809 counterfactual

`bottomStatusBar` — the content the baseline session spent 32 reads failing to
reach — is at `Sources/SwiftStar/AgentView.swift:261`. A
`start_line=252, max_lines=80` window renders to **4,484 bytes**, under both the
7000-byte budget and the 8000-byte condenser cap, so it arrives whole. In this
session the model asked `255/90` and got what it needed.

## Follow-up found while measuring

`swiftstar-analyze rereads` reports "no read/more tool_requests" on this capture:
it parses with `PoolWireParser`, which expects worker-tagged pooled events, and
a `swiftstar-drive` capture is single-session. The verb should fall back to
`AgentWireParser` for non-pooled captures. Not blocking — `Tools/window-spread.py`
reads the raw NDJSON — but the committed verb cannot currently analyse the
committed capture program's output.

## Capture

- **Treatment:** `captures/20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
  (`-c 32768`, host tools on, shell off, 12 prompts, 14:45:42 → 14:50:20).
- **Control:** `captures/20260830-105947-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
  (identical env; `readResult` reverted to pre-P24.1; FAILED at prompt 1,
  14:59:47 → 15:03:50).
- **Null arm** (kept as the record of how the first attempt failed):
  `captures/20260830-103238-…` — host tools off, 0 `tool_request` events.
