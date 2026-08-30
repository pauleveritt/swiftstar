# P24.1 window-honoring reads — the "after" measurement (2026-08-30)

**Status: the pre-registered falsifier was not tripped. The loop signature is
absent.** Recorded with its limits below — this is one session against a
different session, not a paired A/B.

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

## What is weak about this, stated plainly

1. **Not a paired bill.** Different session, different prompts, and a workspace
   holding a copied subset of the repo. `swiftstar-analyze diff` was not run,
   because comparing Σsuffix across two different sessions confounds the change
   with the session — the objection already recorded against the withdrawn
   design's measurement plan. A true paired arm needs a guard-off control of
   *this same script*, which is now cheap to run (`CAPTURE_HOST_TOOLS=0`) and is
   the obvious next measurement.
2. **Shorter and smaller.** ~4.5 minutes of turns and one compaction, against
   the baseline's 24 minutes and five. Fewer opportunities to loop.
3. **One residue worth naming.** The two post-compaction reads were `255/90`
   and `257/90` — a two-line shift, the closest thing here to re-asking. Two
   asks is not a loop, but it is not zero either, and a longer session is the
   way to find out whether it grows.
4. **One session, one seed.** P20's closure verdict recorded seed dependence on
   a comparable claim; this has the same exposure.

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

`captures/20260830-104542-laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`
(`laguna-s-2.1-RoutedQ2_K-Last27Q3_K`, `-c 32768`, host tools on, shell off,
12 prompts, 14:45:42 → 14:50:20).
