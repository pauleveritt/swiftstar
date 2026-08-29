# Block C — passive capture mining (2026-08-28)

Four backlog gates, answered from captures already on disk. **No model was run.**
Read-only analysis of `captures/live/`, `captures/agenttest/`, `captures/evidence/`,
and the `captures/` root (`swiftstar-drive`).

## Method and scope

`swiftstar-analyze` (Rule 0) was run first: `list` enumerates the trees and flags
unusable captures. Its four verbs (`list`/`summary`/`trace`/`diff`) surface per-turn
token and decode arithmetic; **none of them surfaces tool-call names, parameters, or
per-turn tool sequences**, which is what all four questions need. So the counts below
come from `wire.ndjson` directly, using the *same* schema the production parser uses
(`AgentWireParser.parseToolRequest`, `WireStatusDecoder`) so the mining and the app
agree on what a tool call is.

No Σprompt arithmetic appears anywhere in this document. Where a token figure is
quoted it is either Σsuffix (from a capture's own `run-config.json`) or a raw
`ctx_used`.

**Corpus.** 285 `wire.ndjson` files:

| Tree | Files | Notes |
|---|---|---|
| `captures/agenttest/` | 272 (269 usable) | `swiftstar-agenttest` fixture tier |
| `captures/live/` | 9 (7 with a non-empty wire) | the app, real sessions |
| `captures/evidence/` | 2 | rescued `/tmp` evidence |
| `captures/` root | 3 | `swiftstar-drive`; `20260828-112625` is the in-flight run, read only |

Totals across the corpus: **3,796 `tool_request` events**, 1,137 `ready`, 284,201
`status`. 0 unparsable NDJSON lines.

### Worker filtering (the pooled-capture trap)

`PoolWireParser.worker(of:)` calls worker 0 the orchestrator, and
`swiftstar-analyze` reduces only worker-0 events. That filter is correct for the
**app**, and wrong as a filter for this corpus: `swiftstar-agenttest` dispatches its
real work to `WorkerId(1)` (implement), `WorkerId(2)` (repair), and `WorkerId(3)`
(decompose) — worker 0 is only warmed (`hello` + one 768-token prefill + `ready`,
4–12 events) and never prompted. Reducing agenttest on worker 0 alone yields
**zero** turns.

So the unit of analysis here is the **(capture, worker) session**, and turns are
segmented per session at each `ready` carrying a `stop_reason` — verified against
`captures/live/20260827-200648/outcomes.ndjson`, which holds exactly 3 `TurnOutcome`
rows against 4 worker-0 `ready` events (the extra one is the model-load `ready`, which
carries no `stop_reason`). Merging workers is never done.

This yields **283 tool-bearing turns** across **117 (capture, worker) sessions**
(agenttest 276, live 6, evidence 1). Turns with no tool call are excluded from Q1 by
construction — the question is about tool sequences.

---

## Q1 — Locate-stall count

**Operational criterion (stated up front).** Within one turn of one worker session,
take the ordered `tool_request` sequence and label each call:

- **LOCATE** — `read`, `more`, `list`, `search`, `grep`
- **ACT** — `write`, `edit`
- other (`shell`/`bash`, web tools) — neither

A **locate-stall** is a maximal run of **≥2 consecutive LOCATE calls occurring before
the turn's first ACT call** (if the turn never acts, the whole sequence is the head).
One turn contributes at most one stall, scored by its longest such run. A stall whose
turn *never* mutated anything is a **pure-locate turn** — the worst case, where every
tool call in the turn was spent finding things.

### Result

**36 of 283 tool-bearing turns (12.7%) contain a locate-stall. 9 of those 36 never
mutated anything at all.** Corpus-wide the split is 1,717 LOCATE calls against 1,598
ACT calls.

Longest pre-mutation LOCATE run, per stalled turn:

| Run length | Turns |
|---|---|
| 2 | 3 |
| 3 | 5 |
| 4 | 7 |
| 5 | 3 |
| 6 | 1 |
| 7 | 6 |
| 8 | 3 |
| 9 | 1 |
| 10 | 3 |
| 14 | 1 |
| 17 | 1 |
| 41 | 1 |
| 62 | 1 |

The distribution is bimodal and the mode matters more than the total. By tree: 32
stalls in `agenttest`, 4 in `live`. **But `live` only has 6 tool-bearing turns — so
4/6 (67%) of real app turns stalled, against 32/276 (12%) of agenttest turns**, and
the three longest runs in the entire corpus are all app turns:

- `captures/live/20260827-200648/wire.ndjson` worker 0 turn 1 — **62 consecutive
  LOCATE calls, zero mutations**, the whole turn (task: "Take a look in this project.")
- `captures/live/20260827-200648/wire.ndjson` worker 0 turn 2 — **41 consecutive
  LOCATE calls, zero mutations** (turn was 55 calls total)
- `captures/live/20260827-195452/wire.ndjson` worker 0 turn 1 — **17 consecutive
  LOCATE calls, zero mutations** (turn was 24 calls total)

All three ended `stopReason: interrupt` in `outcomes.ndjson` with `mutations: []` —
the user cut them off while they were still looking.

The agenttest population under-reports the phenomenon *by design*: its packets carry
`writableFiles` and the file list up front, so the worker is handed the locus and
rarely has to find it. Agenttest is therefore a floor on this measure, not an estimate.

### Secondary signal: redundant re-locates within a single turn

The same `(tool, path)` pair issued more than once inside one turn — strictly wasted
prefill, since the file did not change:

78 turns with a 2× repeat, 19 with 3×, 5 with 4×, 3 with 5×, 5 with 6×, and a tail
of pathological cases:

| Capture | Worker/turn | Worst repeat |
|---|---|---|
| `captures/agenttest/20260824-141830-roadmap-user-story-run3/wire.ndjson` | w1 turn 3 | **347×** `read app.py` (turn was 367 calls) |
| `captures/evidence/20260826-kind-probe/wire.ndjson` | turn 1 | **290×** `list /workspace` (turn was 621 calls) |
| `captures/live/20260827-200648/wire.ndjson` | w0 turn 2 | **30×** `read Sources/SwiftStar/AgentView.swift` |
| `captures/agenttest/20260824-183725-roadmap-user-story-run2/wire.ndjson` | w1 turn 3 | 14× `search app.py` |
| `captures/live/20260827-200648/wire.ndjson` | w0 turn 1 | 11× `read ROADMAP.md` |

This independently reproduces the 1809-capture finding already cited in ROADMAP's
context-economy entry ("one file re-read 31× = 37% of Σsuffix") on a second, larger
corpus.

### Verdict

**Gate opens.** The behavior is real and is concentrated exactly where a scout role
would pay: 4 of 6 real app turns, three of them 100% locate with zero mutation and
runs of 62/41/17. Caveat recorded honestly: the app-mode population is **6 turns**.
That is enough to establish existence and severity, not enough to estimate a rate.
Note also that the two heaviest cases (347× and 30× re-read) are answered by the
already-reopened *don't-re-read* read-guard, not by a scout — the scout's distinct
claim is the 62/41/17 first-contact exploration runs.

---

## Q2 — Shell-use classification

**Operational criterion.** Every `tool_request` whose `name` is in the shell family
(`shell`, `bash`, `bash_status`, `bash_stop`), classified by regex over its command
string (`command` / `cmd` / `job` parameter — all three spellings occur on the wire).

### Result

**463 shell-family tool calls** across 105 captures: `shell` 341, `bash` 121,
`bash_status` 1.

| Class | Count |
|---|---|
| test run (`pytest`, `-m unittest`) | 221 |
| build / import-check (`python -c 'import …'`, `swift build`, `pip install`) | 196 |
| directory listing (`ls`, `find`, `tree`) | 17 |
| run python (other) | 10 |
| `echo` / no-op | 4 |
| file inspection (`cat`/`head`/`tail`/`wc`/`sed -n`) | 3 |
| environment probe (`which`, `--version`) | 3 |
| filesystem mutation (`mkdir`/`mv`/`cp`/`rm`) | 3 |
| unclassified (`sleep N && echo …`, one empty string) | 3 |
| git | 2 |
| text search (`grep`/`rg`) | 1 |

**90.1% of all shell use is two things: run the tests, or check it imports/builds.**

### The measurement is contaminated, and that is the finding

**461 of the 463 calls are `agenttest`. Only 2 are `live`.** And agenttest's shape is
circular: each packet carries a `validationCommand` and a `selfTestCommand`
(`packet.json` / `phase-packet-N.json`), the prompt tells the worker to run them, and
`HostToolExecutor.Policy.pool(vettedCommands:)` already enforces
`BashPolicy.vettedOnly` — a prefix-match allowlist of exactly those two strings.

Measured against that existing two-entry allowlist, over the 216 shell calls in
captures that still have their packet on disk:

- **198 covered** (exact or prefix match)
- **18 not covered** — and every one is a near-miss of the same two commands:
  `cd <worktree> && uv run …` (a `cd` prefix), `uv run --project . python -c 'import
  app'` (relative `--project`), and two `echo hello`.

So a mediated bash with light normalization covers **~100% of pool-worker usage**.
That is a tautology, not evidence: the allowlist was already enforced, and the task
told the model what to run.

### The one real app-mode shell session says the opposite

`captures/evidence/20260826-spike-run/wire.ndjson` is the app running with shell on
(the basis of the "spike shell-on findings" doc). It is a pre-P9 wire — no
`tool_request` lines, so the commands were reconstructed from `tool`
`param_value` events. All **6** of its `bash` calls, verbatim:

1. `cd /private/tmp/spike-wt-221035 && git log --oneline -15 && echo "---BRANCH---" && git branch -a && echo "---STATUS---" && git status --short`
2. `cd /private/tmp/spike-wt-221035 && swift --version 2>&1; echo "---"; xcodebuild --version 2>&1 | head -5; echo "---"; ls /Applications/ | grep -i xcode 2>&1`
3. `cd /private/tmp/spike-wt-221035 && grep -n '@Observable\|class.*Controller\|class.*Model\|@MainActor\|@Observable' Sources/SwiftStar/EngineController.swift Sources/SwiftStar/AgentController.swift Sources/SwiftStar/MetricsModel.swift Sources/SwiftStar/DiagnosticsModel.swift | head -40`
4. `cd /private/tmp/spike-wt-221035 && git remote -v && echo "---" && git log --oneline -3 && echo "---WORKTREES---" && git worktree list 2>&1 && echo "---SWIFT VERSION---" && swift --version`
5. `cd /Users/pauleveritt/projects/pauleveritt/swiftstar && git worktree add -b spike-swiftui-standards ../spike-swiftui-standards && echo "---CREATED---" && git worktree list`
6. `cd /Users/pauleveritt/projects/pauleveritt/spike-swiftui-standards && swift build 2>&1 | tail -20`

Every one is a **compound pipeline** (`&&`, `;`, `|`, `2>&1`, `head`, `tail`). Call 5
**creates a git branch and a worktree outside the workspace**. A prefix-match
allowlist covers zero of these. Note also that calls 1–4 are pure *inspection*
(`git log`, `git status`, `grep -n`, `--version`) — a mediated tool surface could
serve them, but only as several dedicated tools plus a compositor, not as a
command allowlist.

The other 2 live shell calls point the same way:
`captures/live/20260827-195452` issued `cd /workspace && git log --oneline -20`, and
`captures/live/20260827-200648` issued `wc -l …/AgentView.swift` (a `read` in
disguise — this is Q1's stall behavior leaking into bash). Both were named `shell`,
which is in neither `ToolCallbackResponder.fileTools` nor `shellTools`, so both were
refused as unknown tools.

### Verdict

**Gate does NOT open on the evidence as it stands — the question is under-measured,
and the little real evidence points the wrong way.** The 90%-closed picture is an
artifact of measuring a harness whose packets dictate the commands and whose executor
already allowlists them. The 8 app-mode shell calls on disk (6 spike + 2 live) are
uniformly compound pipelines, one of them mutating git state outside the workspace.

To decide this properly: **capture ≥3 real app sessions with `--shell` on and a
task that is not a pre-declared spec build**, and reclassify. Until then, a mediated
bash should be assumed to fit the *pool worker* (where it already ships and already
works) and to **not** fit the app's agent role.

---

## Q3 — Warm-prefix overlap

**Operational criterion.** A capture is *pooled* if more than one worker id on its
wire ran real work (≥1 `tool_request` or ≥1 `ready` with a `stop_reason`). Within a
pooled capture, a path-touch by worker W "would have been warm elsewhere" if some
other worker W′ on the same wire touched the identical path at a strictly earlier
`ts`.

### Result

**66 of 285 captures are genuinely pooled.** Aggregate overlap: **10 of 391
cross-worker path-touches (2.6%)** had a prior touch by another worker, and they sit
in just two captures:

| Capture | Overlap |
|---|---|
| `captures/agenttest/20260827-153734-smoke-p12/wire.ndjson` | w2: 2/2 paths already touched by w1 |
| `captures/agenttest/20260828-012528-roadmap-directive/wire.ndjson` | w0: 4/27; w1: 4/4 already touched by the other |
| all other 64 pooled captures | 0 |

The reason is structural, not incidental: in 64 of the 66 pooled captures **only one
worker makes path-bearing tool calls at all**. The repair worker (`WorkerId(2)`) and
decompose worker (`WorkerId(3)`) complete turns (1–8 each) with **zero** file tool
calls — they receive their content inside the packet rather than fetching it. Example,
`captures/agenttest/20260826-021050-roadmap/wire.ndjson`: worker 1 makes 42 tool
requests / 40 path-touches, worker 2 makes 0 across a completed turn.

### What the wire cannot tell us — and the exact field that would

This 2.6% is **not** an estimate of warm-prefix hit rate. It is a proxy that is wrong
in both directions, and the wire does not record what would make it right:

- **The wire records tool calls, not prefix contents.** `tool_request` says a worker
  *fetched* a path. It does not say the bytes are still in that worker's KV prefix —
  a compaction, a session reset, or the `--per-worker-ctx` swap landed in P23 can
  evict them, and none of those emit a wire event naming what was dropped.
- **Packet-injected content is invisible.** The repair/decompose workers' prefixes
  are full of file contents that never crossed the wire as a tool call, so the proxy
  scores them 0 when they may in fact be the warmest sessions on the pool.
- **`status` carries `prefill_done`/`prefill_total` — token counts, not identities.**
  A prefill sync tells you `prompt == cached + suffix`; it never says *which* text
  the `cached` portion is.
- **`wire.trace` does dump prefix token text** (`tokens label=prefill_suffix start=N
  len=N` followed by per-token `token index=… text="…"` lines — confirmed in
  `captures/agenttest/20260827-153734-smoke-p12/wire.trace`), so content is
  recoverable offline. **But no trace line carries a worker id.** In that pooled
  capture the trace has 3 `agent worker start` lines and then 30 unattributed,
  interleaved `prefill sync done` / `prefill_suffix` blocks. There is no way to say
  which slot a given prefix belongs to.

**The missing field, precisely:** a `worker` (slot) id on the trace's `prefill sync
done` / `tokens label=prefill_suffix` lines — or, equivalently and much cheaper, the
`ds4_session_common_prefix` wire query itself, which answers "how many tokens of
candidate prompt P does session S already hold?" directly and needs no reconstruction.
A middle option that would make the wire self-sufficient without a new engine query:
emit a per-worker prefix digest (e.g. a rolling hash of the cached span, or the
cached-span token count *plus* slot id) on each `status` at sync time.

### Verdict

**Gate stays shut, and D11's descope is vindicated.** Nothing on disk shows a pool
workload where warm-prefix routing would have paid: 2.6% observed overlap, structurally
concentrated because the non-implement workers do no file I/O at all. But the honest
statement is stronger and more useful than the number — **the wire does not record
enough to answer this question**, and the 2.6% is a floor from a proxy, not a
measurement. Reopening this should be gated on a *workload* change (a pool where ≥2
workers independently fetch overlapping files), not on more mining of the current
corpus. If such a workload appears, add the slot id to the trace's prefill lines
first — that costs no engine patch and no golden recapture, and would let the next
Block C answer this from disk.

---

## Q4 — Malformed tool calls

**Operational criterion.** Two independent detectors, both applied to every line of
all 285 wires:

1. **Engine-side** — the engine's own bracketed markers in a `tool` `phase:"finish"`
   `status` or in generated `text`/`think`: `[invalid tool call: …]`,
   `[tool call ignored: …]`, `[tool call interrupted]`.
2. **Host-side** — a `tool_request` line that `AgentWireParser.parseToolRequest`
   would reject (missing `name`, or a `params` entry without string `name`+`value`),
   which the parser turns into `.toolRequestRefused(reason: "malformed
   tool_request: …")`.

### Result

**Host-side: 0.** Not one `tool_request` in 3,796 was malformed at the host boundary.
The P9 refusal path has never fired on disk.

**Engine-side: 13 markers across 5 captures**, of which **8 are malformed tool calls**
(the other 5 are `[tool call interrupted]` — a user/budget stop, not a malformation):

| Marker | Count | Captures |
|---|---|---|
| `[invalid tool call: expected <arg_key> in tagged tool call]` | 3 | `captures/agenttest/20260827-153322-smoke-p12/wire.ndjson` |
| `[tool call ignored: tool calling is not allowed inside <think></think>]` | 5 | `20260826-100350-roadmap` (2), `20260823-202136-roadmap-run2` (2), `20260824-134731-roadmap-user-story-run2` (1) |
| `[tool call interrupted]` (not a malformation) | 5 | `20260826-065840-roadmap` (2), `20260826-100350-roadmap`, `20260824-134731-roadmap-user-story-run2`, `20260826-021050-roadmap` |

### Did any cost a real turn? Yes — two turns were killed outright.

**Evidence A — `captures/agenttest/20260827-153322-smoke-p12/wire.ndjson`.** The model
emitted the *literal template placeholder* from its own system prompt as a tool name,
three times. Lines 437–443:

```
{"t": "text", "s": "For a function call, use exactly this format:\n", "worker": 1}
{"t": "tool", "phase": "start", "idx": 0, "worker": 1}
{"t": "tool", "phase": "tool", "idx": 0, "name": "{function-name}", "worker": 1}
{"t": "tool", "phase": "param_begin", "idx": 0, "kind": "normal", "name": "{argument-name}", "worker": 1}
{"t": "tool", "phase": "param_value", "idx": 0, "s": "{argument-value}", "worker": 1}
{"t": "tool", "phase": "finish", "idx": 0, "status": "[invalid tool call: expected <arg_key> in tagged tool call]\n", "calls": 1, "worker": 1}
```

It recovered once (line 453 issues a well-formed `shell` call), repeated the same
placeholder emission at line 720, and again at line 890. The capture's **final line
(897)** is:

```
{"t": "status", "state": "error", "generated": 144, "ctx_used": 9897,
 "error": "too many malformed tool calls in a row", "worker": 1}
```

The turn was terminated by the engine. `run-config.json` for that capture records
`sumSuffix: 3328` and `resultClass: "native agent competence"` — the run produced no
result.

**Evidence B — `captures/agenttest/20260826-100350-roadmap/wire.ndjson`.** A different
malformation, same fatal outcome. The model reasoned its way to a correct `write` call
*inside* its think block (lines 2678–2692: "The name is \"write\", arguments are path
and content… So the tool call should be a JSON object inside"), and line 2693 is:

```
{"t": "think", "s": "\n[tool call ignored: tool calling is not allowed inside <think></think>]\n\n", "worker": 1}
```

The capture's **final line (2694)**:

```
{"t": "status", "state": "error", "generated": 467, "ctx_used": 13507,
 "error": "too many malformed tool calls in a row", "worker": 1}
```

467 tokens of correct reasoning about the right file with the right content, discarded
because the call was syntactically in the wrong place.

Corpus-wide, `"too many malformed tool calls in a row"` is one of only four distinct
non-empty `status.error` strings ever recorded, and it accounts for 2 of the 5 error
statuses on disk.

### Verdict

**Gate opens — the ROADMAP condition is met verbatim.** The entry reopens
"*when a malformed tool call is observed costing a real turn*" (ROADMAP.md ~line 668).
Two turns, in two independent captures, were killed by the engine with
`error: "too many malformed tool calls in a row"` after 144 and 467 generated tokens
respectively, producing no output.

Two qualifications, so the gate opens on what the evidence actually supports:

- **Base rate is low.** 8 malformed calls against 3,796 well-formed `tool_request`
  events (0.21%), in 5 of 285 captures. This is a tail risk, not a tax.
- **The two failure modes are different, and grammar constraint fixes only one
  cleanly.** `[invalid tool call: expected <arg_key>]` (Evidence A) is exactly what a
  grammar prevents — the model cannot emit `{function-name}` if the grammar admits
  only real tool names. `[tool call ignored: … inside <think></think>]` (Evidence B,
  5 of the 8) is a *placement* error, not a syntax error; fixing it needs the grammar
  to be think-state-aware, or needs the engine to hoist a well-formed call out of the
  think block rather than discard it. Worth stating in the design, because Evidence B
  is the more common half and the more expensive one (467 tokens vs 144).

---

## Summary of verdicts

| # | Question | Number | Gate |
|---|---|---|---|
| 1 | Locate-stall | 36/283 turns; **4 of 6 real app turns**, runs of 62/41/17 with zero mutations | **Opens** (severity established; rate not) |
| 2 | Shell classification | 463 calls, 90% test-or-build — but 461 of 463 are the self-fulfilling agenttest harness; all 8 app-mode calls are compound pipelines | **Does not open**; needs ≥3 real shell-on app sessions |
| 3 | Warm-prefix overlap | 10/391 (2.6%) across 66 pooled captures, in 2 captures only | **Stays shut**; wire cannot answer — needs a slot id on the trace's prefill lines, or the `ds4_session_common_prefix` query |
| 4 | Malformed tool calls | 8 malformed / 3,796 (0.21%); **2 killed a turn** | **Opens** — condition met verbatim |
