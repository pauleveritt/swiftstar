# Pre-registration — overnight measurement campaign

**Written 2026-08-28, BEFORE any campaign cell was run.** This document fixes
the configuration, the oracle, and the cell count in advance. Amending it after
runs begin invalidates the pre-registration; a follow-up question gets its own
document and its own manifest, as `experiment-manifest-framing.tsv` did.

## The rule this campaign is built around

`/goal` v5 established it: at a fixed seed, a byte-identical prompt swung 2/3 →
0/3. **Overnight sampling here measures one pre-registered configuration at
real n. It does not compare arms and it does not tune anything.** Every block
below holds its configuration fixed and varies only the seed. Where a factor
was a variable in earlier work (repair rounds in P17), it is pinned to one
level here and the choice is justified in the manifest.

Two standing invariants, inherited from P17:

- **A recorded cell is never re-run or overwritten.** `Tools/run-experiment.py`
  enforces this by skipping any `(fixture, rounds, seed)` already present in the
  results file.
- **Seeds are disjoint from prior work.** P17 used seeds 1–3; this campaign
  starts at 4. Preflight and debugging use seeds 97–99, which appear in no
  manifest, so no diagnostic run can consume or contaminate a measured cell.

## Preflight — the gate that must pass before launch

`Tools/campaign-preflight.sh` — exit 0 means launch, non-zero means do not.

This exists because of a failure found while dry-running this very campaign.
The first Block B dry cell returned `harness-void: no capture produced` in three
seconds. Cause: `external/ds4/ds4-agent` on disk predated the P23 divergence-#14
pin bump (`a85c6c1`/`ae0b75f`), so it rejected the `--per-turn-think` that
`AgentCommand.argv` now emits — the submodule was at the correct SHA, but the
binary had never been rebuilt. Nothing in the harness or the runner notices:
`run-experiment.py` records `harness-void` and exits 0. **A campaign launched in
that state burns the whole night and measures nothing.** Fixed by
`make -C external/ds4 ds4-agent` (only `ds4_agent.o` recompiled, confirming the
staleness).

The gate checks: (1) submodule SHA equals the pin; (2) engine binary newer than
engine sources; (3) harness binary newer than `Sources/`; (4) the engine accepts
every flag `AgentCommand` emits — the check that catches exactly the failure
above, verified against a known-bad flag so it is not a false pass; (5) ≥20 GiB
free disk; (6) one real fixture cell at off-manifest seed 97 grading end to end.

## Running it

```bash
nohup bash Tools/overnight-campaign.sh > /dev/null 2>&1 &
```

Progress: `tail -f /tmp/overnight-campaign.log`. Abort before the next cell (never
mid-cell): `touch /tmp/campaign-stop`. In the morning:

```bash
python3 Tools/campaign-report.py
python3 Tools/directive-taxonomy.py
```

Both blocks are resumable — recorded cells are skipped and void cells are not
recorded as closed — so a second night continues rather than restarts.

## Block A — orchestrate-loop pass rate

**The question.** P20 closed on one live dispatch that passed once, at one seed.
The pass rate of the `/orchestrate` coordination loop is therefore unknown, and
P27 needs it. This block replaces "it passed once" with a rate and a failure
taxonomy.

**Manifest.** `experiment-manifest-orchestrate.tsv` — 30 cells, seeds 101–130.
The configuration is P20's, held fixed: `roadmap` spec, `laguna-s-2.1`, think
budget 1500, 2-worker pool, 4-round cap, 1800s per-turn timeout. Only the seed
varies. Seed 42 (P20's own run) is **not** re-run: that observation exists and
stands: re-running it would replace prior evidence with a fresh draw.

**Oracle.** The harness's own pass bar, unchanged — `main.swift:1315`,
`finalGrade.exit == 0 && totalDispatches >= 1`, where the grade is the 13-test
acceptance suite in `fixtures/agenttest/acceptance/test_acceptance.py`. The
driver parses the harness's summary line rather than re-deriving a verdict.

**Runner.** `Tools/run-orchestrate-campaign.py`.

```bash
python3 Tools/run-orchestrate-campaign.py
```

**Outcome classes.** `pass`, `fail` (graded, did not meet the bar), `timeout`
(hit the wall-clock cap), `harness-void` (no graded summary at all — the run
died before the final grade). `timeout` and `harness-void` are **excluded from
the denominator**, not counted as model failures. This is the distinction whose
absence made the original 0/40 Mellum result describe the harness rather than
the model.

**Deliverable.** A pass rate with a Wilson interval, plus a failure taxonomy
built from the captures of the failing cells (`Tools/directive-taxonomy.py`).
The failure modes are P27's cycle inputs.

## Block B — firm up Mellum's 15/17 on editing

**The question.** P17's editing claim rests on n=3 per cell (6/6, 4/5, 5/6,
pooled 15/17), with intervals P17 itself called wide. This block re-measures the
same claim at n=20 per cell.

**Manifest.** `experiment-manifest-editing-n20.tsv` — 3 editing fixtures ×
rounds=2 × seeds 4–23 = **60 cells**.

- Fixtures: `plausible-wrong-fix` (1 file), `depth-2` (2 files), `depth-3`
  (3 files). Variant `mellum-2.1`.
- `rounds` pinned at **2**. P17 measured no budget effect on editing (8/8 at
  rounds=2 against 7/9 at rounds=5) and rounds=2 is the cheaper cell. Pinning it
  makes this a measurement of one configuration rather than a comparison.
- `framing-2` (author+edit, 1/6) is **excluded**. The authoring limit is a
  different question, and pooling it with editing is what produced the number
  being firmed.

**Oracle.** Unchanged from P17, so the two bodies of evidence remain comparable:
`Tools/run-experiment.py` classifies each cell `pass` (final graded round exits
0, i.e. 13/13), `fail` (non-zero, or a round that ended with no grade at all),
or `harness-void` (validity check V5 or V6 failed). No new grading code.

**Runner.**

```bash
EXP_MANIFEST=docs/superpowers/research/experiment-manifest-editing-n20.tsv \
EXP_RESULTS=docs/superpowers/research/experiment-results-editing-n20.tsv \
python3 Tools/run-experiment.py
```

Resumable by construction: recorded cells are skipped, so an interrupted night
continues where it stopped without re-running anything.

**Deliverable.** Per-fixture pass rates at n=20 with intervals, and a statement
of whether the flat depth profile (1→3 files) survives at real n.

## Block C — passive capture mining (no engine time)

Runs concurrently with A and B because it consumes no model. All four questions
are answered from captures already on disk, via `swiftstar-analyze` first and
raw NDJSON only where the CLI cannot reach (per the `telemetry` skill's Rule 0).

1. **Locate-stall count** — the merit probe for a scout role.
2. **Shell-use classification** — the merit probe for mediated bash.
3. **Warm-prefix overlap** — how often a pooled task's files already sit in
   another session's live prefix. Bounds the value of the `ds4_session_common_prefix`
   wire query that P23's D11 deliberately left out of scope.
4. **Malformed tool calls** — a count. The backlog's grammar-constrained
   tool-calls entry reopens "when a malformed tool call is observed costing a
   real turn"; this decides whether that has happened.

**Deliverable.** One count or classification per question, each with the
capture paths it was computed from — enough to open or leave closed the four
backlog gates, and nothing more.

**Status: complete 2026-08-28**, ahead of the engine-time blocks since it needed
no model. Report:
[`2026-08-28-block-c-capture-mining.md`](2026-08-28-block-c-capture-mining.md).
Corpus: 285 `wire.ndjson`, 3,796 tool requests, 0 unparsable lines. Two gates
open (locate-stall; malformed tool calls, whose reopen condition — "a malformed
tool call costing a real turn" — is met verbatim by two killed turns), one stays
shut on the evidence (warm-prefix: the wire records fetches, not residency, and
no trace line carries a worker id), and one is reported as **contaminated rather
than answered** (shell use: 461 of 463 calls come from agenttest, whose packets
prescribe the commands and whose executor already allowlists them, so the
measurement is circular).

## Guard-rails

Each of these exists because something actually went wrong while building the
campaign, not because it seemed prudent.

- **Two coherent time budgets.** The harness's own per-turn timeout
  (`AGENTTEST_TURN_TIMEOUT`) is set to **900s** and the driver's per-cell cap
  (`RUN_CAP`) to **3600s**. The order matters: the harness's timeout unwinds
  cleanly and stops its engine, the driver's kill does not. An earlier
  configuration had the cap *below* the turn timeout, which made the violent
  path the normal path. P20's passing run took 695s in total across two turns,
  so neither bound is expected to bind.
- **Process-group kill.** The harness spawns the engine as a grandchild and
  installs no signal handler; `main.swift:1317`'s `exit(1)` also skips its own
  `defer`. So a killed cell leaves a 46 GB engine resident. Each cell therefore
  runs in its own process group and a timeout kills the group.
- **Orphan reaping before every cell.** ds4 holds a global instance lock —
  `another ds4 process is already running (pid N); refusing to start`. One
  orphan fails every later cell in about a second. **Observed for real:** a
  killed driver orphaned its engine, and the next cell voided in 1s. The driver
  reaps campaign engines (matched by their agenttest workspace, never the
  user's own session) before each cell, and preflight refuses to launch while
  any engine is resident.
- **Void cells stay re-runnable.** Only `pass` and `fail` close a cell.
  A `timeout` or `harness-void` row is a diagnostic, not a measurement — if
  those closed cells, a single orphan cascade would silently and permanently
  fix n at whatever ran before it.
- **One driver at a time.** The driver takes `flock` on
  `/tmp/swiftstar-campaign-blockA.lock`. Without it, a second instance's
  reaper destroys the first instance's in-flight cell — which happened once
  during development, killing a live 12-minute cell at 98s.
- **Leaked worktree sweep.** The same skipped-`defer` bug leaves
  `$TMPDIR/agenttest-directive-*` git repos behind on every non-passing cell.
  The driver sweeps them between cells.
- **Stop file.** `touch /tmp/campaign-stop` aborts before the next cell, never
  mid-cell.
- **Disk budget.** Captures are ~1 MB each, so a 90-cell night is well under
  2 GiB against 213 GiB free. Preflight fails below 20 GiB.
- **Provenance.** Directive mode writes no `run-config.json`, which is why
  P20's own seed and think budget survive only as prose in its verdict doc with
  no machine-readable counterpart. This campaign closes that gap: every Block A
  cell gets a `campaign.json` and a `campaign-stdout.txt` written into its
  capture directory, alongside the results row.
- **The morning deliverable is a verdict doc backed by the analyzer and the
  taxonomy tool**, not a reading of the logs.

## What this campaign cannot answer

It measures pass rates for fixed configurations. It cannot say why a
configuration is better than another one, because it runs no other one. Any
comparison read out of these numbers against a differently-configured earlier
run inherits every confound the `/goal` v5 result warned about.
