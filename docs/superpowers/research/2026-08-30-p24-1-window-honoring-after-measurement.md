# P24.1 window-honoring reads — the "after" measurement (2026-08-30)

**Status: a paired control arm reproduced the loop on demand — that is the
result this note stands on.** With only `readResult` reverted to its pre-P24.1
body, the identical prompt took 12 reads of one file and the turn was killed at
the timeout; with P24.1 it took 3 and completed.

**The numeric falsifier is post-hoc and must not be cited as pre-registered.**
See the section below; the honest claim is the behavioral difference, not the
metric.

## The falsifier: what was pre-registered, and what was not

**Pre-registered (spec, Live validation, written before implementation):** a
prose criterion —

> many distinct windows clustered on one region of one file

**Not pre-registered:** the numbers. The first operationalization, committed in
`00aa6e2` as `Tools/window-spread.py`, was `distinct >= 5 AND calls >= 8` per
path — it ignored the word "clustered" entirely. **The treatment run trips that
threshold** (8 calls, 8 distinct on `AgentView.swift`). It was then rewritten in
`1ca240a` — the same commit that reports the treatment as passing — to
`repeat_rate >= 1.3 AND concentration >= 0.5`, under which the treatment passes.

So: the metric was revised after seeing the data it then cleared. The revision
is defensible on the merits — the prose criterion says *clustered*, and the
original code measured no such thing — but revising a threshold against the run
under test is not a pre-registered result, and this note previously claimed it
was.

Three specific weaknesses in the revised metric, which the numbers above should
be read through:

1. **The concentration leg does not discriminate in this experiment.** The 12
   prompts direct the model at `bottomStatusBar` in one file, so clustering is
   guaranteed by design in *both* arms — treatment 57%, control 71%, both over
   the 0.5 bar. The verdict rides on repeat rate alone.
2. **Repeat rate is largely a bare-read counter.** `window-spread.py` treats
   `(start=-, max=-)` as one window, so the control's 1.38 comes mostly from its
   4 parameterless whole-file reads; among its 7 *windowed* reads all 7 were
   distinct (repeat 1.00). Bare re-reads after failed windows are real loop
   behavior, so the reading survives — but it is a narrower signal than "repeat
   rate" suggests.
3. **The thresholds sit next to the observations.** 1.3 and 0.5 are 0.08 and
   0.07 from the measured values, and were written with both arms' data visible.
   A plausible healthy session (bare read → edit → bare re-read → three
   clustered verify windows: 6 calls / 4 distinct = 1.5, high concentration)
   false-trips; a starvation loop of purely distinct shrinking windows — like 17
   of the 1809 baseline's 22 — evades. The baseline's second path sits at
   exactly 1.10 / 50%, one repeat from a false trip.

The detector does trip on the 1809 baseline and only on `AgentView.swift`, which
is the file the baseline documented as the culprit. That is a genuine check, but
it is one point of validation, not a calibration.

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

The control's **read/more** calls, in order, all against the same file:

```
(bare)  1/80  80/80  more  (bare)  150/100  (bare)  100/50  1/10  200/50  60/50  (bare)
```

**That is the read subset of a 27-tool-call turn**, not the whole turn: the
control also issued 5 `edit` calls, a `dispatch`, a `visit_page`, and a
`bash_status`. An earlier revision of this note described the twelve reads as if
they were the turn, which overstated the tidiness of the picture. The flailing
across other tools is consistent with a starved model, but it is not evidence
this measurement isolates.

The treatment answered the identical prompt with `(bare) → 150/320 → 275/200`
and moved on, making no writes or edits at all (16 read, 7 search, 2 bash with
shell off) — so the reused workspace was not contaminated between arms.

Because only `readResult` differs between the two runs, this is paired evidence,
and it is stronger than a token comparison: the control **could not complete the
task at all**.

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
5. **"Timed out" is relative to a timeout nobody can see.** Both arms ran with
   `CAPTURE_TURN_TIMEOUT=240`, well under the tool's own 900 s default, and the
   provenance files do not record it. Nothing here rules out the control
   converging at 400 s. The claim is "did not finish in 240 s while the
   treatment finished in ~33 s," not "cannot finish."
6. **The protocol is not reproducible from the repo — the P26 lesson,
   repeated.** The 12 prompts, the run invocation, and the control's reverted
   `readResult` all lived in an ephemeral scratchpad, and the control branch was
   deleted after the run. Nobody can re-run either arm, or audit the diff that
   defined the control, from what is committed. **Committing the protocol is the
   next task**, and until it is done these numbers are a report rather than an
   experiment.

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
