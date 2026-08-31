# P26: Eval-System Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the "Now" gap identified by the 2026-08-29 eval-system audit — an
untracked pile of pre-registered campaign evidence, a stale overturned claim
still sitting on the roadmap, duplicated-with-drift cell-classification logic
between the two campaign runners, and an unflagged uncalibrated LLM-judge
acceptance claim — so the *next* campaign cell that runs is comparable to the
last one and nothing here corrupts trustworthy measurement.

**Architecture:** Three independent-as-possible tasks. Task 1 is git-only
(commit what already exists). Tasks 2 and 3 touch disjoint files (`Tools/*.py`
vs. `ROADMAP.md`'s P22 row) and run in parallel after Task 1 lands, since Task
2 needs the files Task 1 commits to exist under version control first.

**Tech Stack:** Python 3 (stdlib only — `csv`, `os`; no new dependency), git.
No Swift changes, no engine invocation.

**Spec:**
[`2026-08-29-eval-system-audit-and-later-work.md`](../research/2026-08-29-eval-system-audit-and-later-work.md)
(the "Later" half) and the P26 row in
[`ROADMAP.md`](../../../ROADMAP.md) (the "Now" scope this plan implements).

## Global Constraints

- **No task in this plan invokes the engine, spawns `ds4-agent`, or runs the
  real `run-experiment.py` / `run-orchestrate-campaign.py` end-to-end.** A
  live campaign (the pluralfix arm) is running against the engine on Metal
  right now (`run-experiment.py`, pid group rooted at 18249/18253, driving
  `ds4-agent --fixture depth-2 --variant mellum-2.1`) — do not start a second
  instance of either runner, and do not touch
  `docs/superpowers/research/experiment-results-editing-pluralfix.tsv` (its
  live results file) or `docs/superpowers/research/experiment-manifest-editing-pluralfix.tsv`.
  Editing `Tools/run-experiment.py` on disk is safe (the running process
  already has the old bytecode loaded and never re-reads the file), but
  verify any refactor with a standalone unit test, never by launching the
  real runner.
- **Do not resume live model-ladder / campaign work from this session until
  40 minutes have elapsed from plan kickoff.** This plan's own tasks don't
  need the engine, so the constraint is satisfied by construction — it
  exists to stop scope creep into "let's also kick off a verification run."
- **Python stays limited to what it already does** (documentation and
  process-babysitting) per `BRIEF.md`'s "Python exists in this repository for
  documentation and nothing else" and the settled direction in the Later
  research doc: no new Python analysis/reporting logic beyond de-duplicating
  what already exists across the two runners.
- **Append-only.** Never modify a historical row in any
  `experiment-results-*.tsv`. Task 2's refactor changes *how* a row is
  written and *how* closure is checked, never rewrites what's already on
  disk.
- **Do not touch `Sources/swiftstar-agenttest/main.swift`.** It has an
  unrelated pre-existing uncommitted change that is not part of P26 — leave
  it as-is in the main worktree; it will not be present in the P26 worktree
  at all (worktrees only see committed history).

---

## Task 1: Commit the P26 planning docs and the pre-registered campaign evidence

**Do this in the main worktree, before creating the P26 worktree** — these
files are currently untracked/modified only in the main checkout, and a new
git worktree only sees committed history, not another worktree's uncommitted
or untracked files.

**Files:**
- Modify: `ROADMAP.md` (P26 phase entry, backlog entry, and the three stale
  flat-depth-profile corrections — already written in the working tree)
- Modify: `Tools/run-experiment.py` (already carries an uncommitted
  resume-safety fix — commit as-is; Task 2 will refactor it further)
- Create (already written, untracked): `docs/superpowers/research/2026-08-29-eval-system-audit-and-later-work.md`,
  `docs/superpowers/plans/2026-08-29-p26-eval-system-hygiene.md` (this file)
- Add (untracked): `Tools/campaign-preflight.sh`, `Tools/campaign-report.py`,
  `Tools/directive-taxonomy.py`, `Tools/overnight-campaign.sh`,
  `Tools/run-orchestrate-campaign.py`
- Add (untracked): `docs/superpowers/research/2026-08-28-block-c-capture-mining.md`,
  `docs/superpowers/research/2026-08-28-cag-and-the-librarian.md`,
  `docs/superpowers/research/2026-08-28-overnight-campaign-preregistration.md`,
  `docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md`
- Add (untracked): `docs/superpowers/research/experiment-manifest-editing-n20.tsv`,
  `docs/superpowers/research/experiment-manifest-editing-pluralfix.tsv`,
  `docs/superpowers/research/experiment-manifest-orchestrate-turn1800.tsv`,
  `docs/superpowers/research/experiment-manifest-orchestrate.tsv`,
  `docs/superpowers/research/experiment-results-editing-n20.tsv`,
  `docs/superpowers/research/experiment-results-editing-pluralfix.tsv`,
  `docs/superpowers/research/experiment-results-orchestrate-turn1800.tsv`,
  `docs/superpowers/research/experiment-results-orchestrate.tsv`
- **Explicitly excluded:** `Sources/swiftstar-agenttest/main.swift` (unrelated,
  pre-existing, not part of P26)

**Interfaces:**
- Consumes: nothing (this is a git operation, no code)
- Produces: a committed baseline that a `git worktree add` can branch from,
  containing everything Tasks 2 and 3 will modify

- [ ] **Step 1: Verify the exclusion list before staging**

```bash
git status --porcelain=v1
```

Expected: `Sources/swiftstar-agenttest/main.swift` shows as ` M` and is the
only file you do NOT stage.

- [ ] **Step 2: Stage exactly the P26 files**

```bash
git add ROADMAP.md \
        Tools/run-experiment.py \
        Tools/campaign-preflight.sh \
        Tools/campaign-report.py \
        Tools/directive-taxonomy.py \
        Tools/overnight-campaign.sh \
        Tools/run-orchestrate-campaign.py \
        docs/superpowers/research/2026-08-28-block-c-capture-mining.md \
        docs/superpowers/research/2026-08-28-cag-and-the-librarian.md \
        docs/superpowers/research/2026-08-28-overnight-campaign-preregistration.md \
        docs/superpowers/research/2026-08-29-block-b-negative-result-analysis.md \
        docs/superpowers/research/2026-08-29-eval-system-audit-and-later-work.md \
        docs/superpowers/plans/2026-08-29-p26-eval-system-hygiene.md \
        docs/superpowers/research/experiment-manifest-editing-n20.tsv \
        docs/superpowers/research/experiment-manifest-editing-pluralfix.tsv \
        docs/superpowers/research/experiment-manifest-orchestrate-turn1800.tsv \
        docs/superpowers/research/experiment-manifest-orchestrate.tsv \
        docs/superpowers/research/experiment-results-editing-n20.tsv \
        docs/superpowers/research/experiment-results-editing-pluralfix.tsv \
        docs/superpowers/research/experiment-results-orchestrate-turn1800.tsv \
        docs/superpowers/research/experiment-results-orchestrate.tsv
```

- [ ] **Step 3: Verify the staged diff excludes the unrelated file**

```bash
git status --porcelain=v1 | grep '^M ' 
git diff --cached --stat
```

Expected: `Sources/swiftstar-agenttest/main.swift` does not appear in either
output.

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
P26: commit pre-registered campaign evidence and eval-system audit docs

The overnight campaign's scripts, manifests, and results TSVs were sitting
untracked — pre-registered evidence one `git clean` from gone. Also lands
the P26 roadmap phase entry, the three corrections to the now-overturned
"flat depth profile" claim (line 33, P13 row, P17 row), and the Later
backlog entry pointing to the audit's non-gating recommendations.

No code changes; the runner de-duplication and grader-claim annotation
follow in the P26 worktree.
EOF
)"
```

- [ ] **Step 5: Verify**

```bash
git log -1 --stat
git status --porcelain=v1
```

Expected: the commit lists all 19 files from Step 2; `git status` shows only
`Sources/swiftstar-agenttest/main.swift` as modified.

---

## Task 2: Extract shared cell-classification logic into `campaign_common.py`

**Do this in the P26 worktree** (created after Task 1's commit).

**Files:**
- Create: `Tools/campaign_common.py`
- Create: `Tools/test_campaign_common.py`
- Modify: `Tools/run-experiment.py`
- Modify: `Tools/run-orchestrate-campaign.py`
- Modify: `Tools/campaign-report.py`

**Interfaces:**
- Produces (from `campaign_common.py`, imported by all three modified files
  as `import campaign_common` — all four files live in `Tools/`, so Python's
  script-directory-on-`sys.path` behavior makes this a plain same-directory
  import, no path manipulation needed):
  - `is_closed(row: list[str]) -> bool`
  - `done_cells(results_path: str, key_width: int) -> set[tuple[str, ...]]`
  - `ensure_header(results_path: str, header: list[str]) -> None`
  - `append_row(results_path: str, fields: list[str]) -> None`
  - `family_key(header: list[str]) -> str`
- Consumes: nothing new (stdlib `csv`, `os` only)

- [ ] **Step 1: Write the failing test**

Create `Tools/test_campaign_common.py`:

```python
#!/usr/bin/env python3
"""Unit tests for campaign_common — no subprocess, no engine, no network.

Run directly: python3 Tools/test_campaign_common.py
"""
import os
import tempfile

import campaign_common as cc


def test_is_closed():
    assert cc.is_closed(['d2', '1', '3', 'pass', '13/13', 'cap']) is True
    assert cc.is_closed(['d2', '1', '3', 'fail', 'detail', 'cap']) is True
    assert cc.is_closed(['d2', '1', '3', 'harness-void', 'V5', 'cap']) is False
    assert cc.is_closed(['d2', '1', '3', 'timeout', '', '', '']) is False
    assert cc.is_closed(['d2', '1', '3']) is False  # too short to have outcome


def test_done_cells_missing_file():
    assert cc.done_cells('/nonexistent/path.tsv', 3) == set()


def test_done_cells_skips_header_and_open_cells():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'results.tsv')
        with open(path, 'w') as fh:
            fh.write('fixture\trounds\tseed\toutcome\tdetail\tcapture\n')
            fh.write('depth-2\t1\t3\tpass\t13/13\tcap-a\n')
            fh.write('depth-2\t1\t4\tharness-void\tV5 stale binary\tcap-b\n')
            fh.write('depth-2\t1\t5\tfail\ttimeout\tcap-c\n')
        got = cc.done_cells(path, 3)
        assert got == {('depth-2', '1', '3'), ('depth-2', '1', '5')}, got


def test_ensure_header_does_not_overwrite():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'results.tsv')
        cc.ensure_header(path, ['a', 'b'])
        with open(path, 'a') as fh:
            fh.write('1\t2\n')
        cc.ensure_header(path, ['a', 'b'])  # must be a no-op now
        with open(path) as fh:
            lines = fh.readlines()
        assert lines == ['a\tb\n', '1\t2\n'], lines


def test_append_row():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'results.tsv')
        cc.append_row(path, ['x', 'y'])
        cc.append_row(path, ['1', '2'])
        with open(path) as fh:
            assert fh.readlines() == ['x\ty\n', '1\t2\n']


def test_family_key():
    assert cc.family_key(['fixture', 'rounds', 'seed', 'outcome']) == 'fixture'
    assert cc.family_key(['spec', 'think', 'seed', 'outcome']) == 'spec'
    try:
        cc.family_key(['unknown', 'columns'])
        assert False, 'expected ValueError'
    except ValueError:
        pass


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
        print(f'ok  {t.__name__}')
    print(f'{len(tests)} passed')


if __name__ == '__main__':
    main()
```

- [ ] **Step 2: Run it to verify it fails on import**

```bash
cd Tools && python3 test_campaign_common.py; cd ..
```

Expected: `ModuleNotFoundError: No module named 'campaign_common'`

- [ ] **Step 3: Write `campaign_common.py`**

```python
#!/usr/bin/env python3
"""Shared cell-classification helpers for the campaign runners.

Both `run-experiment.py` (Block B, --fixture) and
`run-orchestrate-campaign.py` (Block A, --directive) independently
re-implemented "is this cell closed" and "append one result row" with
subtly different rules — flagged by the 2026-08-29 eval-system audit as
exactly the kind of drift that makes results incomparable. This module is
the single implementation both import.

Deliberately does NOT unify the two runners' column sets: Block A's
`dispatches`/`acceptance_exit`/`seconds` describe an orchestrate cell and
have no fixture-mode analogue, so forcing one physical header would mean
placeholder blanks in whichever mode doesn't use a column. What is unified
is the *closure rule* and the *append mechanics* — the actual place the
drift was a bug, not a legitimate schema difference.
"""
import csv
import os

HEADER_ROWS = ('fixture', 'spec')  # first column value on a header line


def is_closed(row: list) -> bool:
    """True iff `row` is a GRADED cell. A `harness-void` or `timeout` row
    records a run the harness could not use and must stay re-runnable, or
    one broken engine permanently fixes n at whatever ran before the
    breakage — this is the resume-safety rule both runners already state in
    their own docstrings; this is just the one implementation of it."""
    return len(row) > 3 and row[3] in ('pass', 'fail')


def done_cells(results_path: str, key_width: int) -> set:
    """The set of closed cell keys already recorded in `results_path`, keyed
    on the first `key_width` columns (e.g. fixture/rounds/seed, or
    spec/think/seed)."""
    if not os.path.exists(results_path):
        return set()
    with open(results_path) as fh:
        return {tuple(r[:key_width]) for r in csv.reader(fh, delimiter='\t')
                if r and r[0] not in HEADER_ROWS and is_closed(r)}


def ensure_header(results_path: str, header: list) -> None:
    """Write `header` as the first line iff `results_path` doesn't exist
    yet. Never rewrites an existing file's header — historical rows are
    append-only, never modified."""
    if not os.path.exists(results_path):
        with open(results_path, 'w') as fh:
            fh.write('\t'.join(header) + '\n')


def append_row(results_path: str, fields: list) -> None:
    with open(results_path, 'a') as fh:
        fh.write('\t'.join(fields) + '\n')


# The column name campaign-report.py groups rows by, chosen from the row's
# own header rather than inferred from which keys happen to be present.
_FAMILY_KEY_BY_PREFIX = {
    ('fixture', 'rounds', 'seed'): 'fixture',
    ('spec', 'think', 'seed'): 'spec',
}


def family_key(header: list) -> str:
    prefix = tuple(header[:3])
    if prefix in _FAMILY_KEY_BY_PREFIX:
        return _FAMILY_KEY_BY_PREFIX[prefix]
    raise ValueError(f'unrecognized results header prefix: {prefix!r}')
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd Tools && python3 test_campaign_common.py; cd ..
```

Expected: `6 passed` (or the current count), all lines prefixed `ok`.

- [ ] **Step 5: Refactor `run-experiment.py` to use it**

In `Tools/run-experiment.py`:

Replace:
```python
def done():
    if not os.path.exists(RESULTS):
        return set()
    # Only a GRADED cell is closed. A `harness-void` row records a run the
    # harness could not use, so its cell must stay re-runnable — otherwise one
    # broken engine voids every remaining cell in seconds and permanently fixes
    # n at whatever ran before the breakage. (2026-08-28: a stale engine binary
    # did exactly that to a dry run; the classification was right and the
    # resume semantics would have made it permanent.)
    return {tuple(r[:3]) for r in csv.reader(open(RESULTS), delimiter='\t')
            if r and r[0] != 'fixture' and len(r) > 3 and r[3] in ('pass', 'fail')}
```

With:
```python
def done():
    # See campaign_common.done_cells' docstring for the resume-safety rule:
    # a `harness-void` row stays re-runnable, or one broken engine
    # permanently fixes n at whatever ran before the breakage.
    return campaign_common.done_cells(RESULTS, 3)
```

Add `import campaign_common` to the top-of-file imports (alongside the
existing `import csv, glob, json, os, re, subprocess, sys`).

Replace, in `main()`:
```python
    if not os.path.exists(RESULTS):
        with open(RESULTS, 'w') as fh:
            fh.write('fixture\trounds\tseed\toutcome\tdetail\tcapture\n')
```
With:
```python
    campaign_common.ensure_header(
        RESULTS, ['fixture', 'rounds', 'seed', 'outcome', 'detail', 'capture'])
```

Replace, in `main()`:
```python
        with open(RESULTS, 'a') as fh:
            fh.write(f'{fixture}\t{rnd}\t{seed}\t{outcome}\t{detail}\t{os.path.basename(cell)}\n')
```
With:
```python
        campaign_common.append_row(
            RESULTS, [fixture, rnd, seed, outcome, detail, os.path.basename(cell)])
```

- [ ] **Step 6: Refactor `run-orchestrate-campaign.py` to use it**

In `Tools/run-orchestrate-campaign.py`, add `import campaign_common` to the
top-of-file imports.

Replace:
```python
def done():
    """Cells that are CLOSED — i.e. graded. Deliberately not "cells that have a
    row": a `timeout` or `harness-void` row records a run the harness could not
    grade, and treating it as closed would permanently burn that seed. The
    realistic bad night is an orphaned engine voiding cells 4-30 in seconds;
    tomorrow's resume must re-run them, not accept n=3 forever."""
    if not os.path.exists(RESULTS):
        return set()
    closed = set()
    with open(RESULTS) as fh:
        for r in csv.reader(fh, delimiter='\t'):
            if not r or r[0] == 'spec' or len(r) < 4:
                continue
            if r[3] in ('pass', 'fail'):
                closed.add((r[0], r[1], r[2]))
    return closed
```
With:
```python
def done():
    """Cells that are CLOSED — i.e. graded. Deliberately not "cells that have
    a row": a `timeout` or `harness-void` row records a run the harness could
    not grade, and treating it as closed would permanently burn that seed.
    The realistic bad night is an orphaned engine voiding cells 4-30 in
    seconds; tomorrow's resume must re-run them, not accept n=3 forever.
    See campaign_common.done_cells' docstring — same rule, shared code."""
    return campaign_common.done_cells(RESULTS, 3)
```

Replace, in `main()`:
```python
    if not os.path.exists(RESULTS):
        with open(RESULTS, 'w') as fh:
            fh.write('\t'.join(HEADER) + '\n')
```
With:
```python
    campaign_common.ensure_header(RESULTS, HEADER)
```

Replace, in `main()`:
```python
        with open(RESULTS, 'a') as fh:
            fh.write('\t'.join(r[k] for k in HEADER) + '\n')
```
With:
```python
        campaign_common.append_row(RESULTS, [r[k] for k in HEADER])
```

- [ ] **Step 7: Refactor `campaign-report.py` to use `family_key`**

In `Tools/campaign-report.py`, add `import campaign_common` to the imports.

Replace:
```python
    # Block B keys on fixture; Block A is one family keyed on spec.
    key = 'fixture' if 'fixture' in rows[0] else 'spec'
```
With:
```python
    # The row's own header determines the family key — no sniffing which
    # dict keys happen to be present. See campaign_common.family_key.
    key = campaign_common.family_key(list(rows[0].keys()))
```

- [ ] **Step 8: Re-run the unit test**

```bash
cd Tools && python3 test_campaign_common.py; cd ..
```

Expected: still all passing (this refactor doesn't change `campaign_common.py`
itself, but confirms nothing else in `Tools/` broke the import).

- [ ] **Step 9: Verify the three refactored files parse and the report tool
      still runs against the already-committed results files (read-only,
      no engine)**

```bash
python3 -c "import ast; [ast.parse(open(f).read(), f) for f in [
    'Tools/run-experiment.py',
    'Tools/run-orchestrate-campaign.py',
    'Tools/campaign-report.py',
    'Tools/campaign_common.py',
]]" && echo "all parse OK"
python3 Tools/campaign-report.py \
    docs/superpowers/research/experiment-results-editing-n20.tsv \
    docs/superpowers/research/experiment-results-orchestrate.tsv
```

Expected: `all parse OK`, then a report identical in shape to what
`campaign-report.py` produced before the refactor (same pass/fail counts —
this step only changed how the family key is *derived*, not the data). **Do
not** run `run-experiment.py` or `run-orchestrate-campaign.py` themselves —
that would start a second engine-driving process while the pluralfix arm is
live.

- [ ] **Step 10: Commit**

```bash
git add Tools/campaign_common.py Tools/test_campaign_common.py \
        Tools/run-experiment.py Tools/run-orchestrate-campaign.py \
        Tools/campaign-report.py
git commit -m "$(cat <<'EOF'
P26: de-duplicate cell-classification logic across the campaign runners

run-experiment.py and run-orchestrate-campaign.py each reimplemented
"is this cell closed" and "append one result row" with subtly different
rules (len(r) > 3 vs len(r) < 4, a set of tuples built two different ways).
campaign_common.py is now the one implementation both import; campaign-
report.py's family-key detection is now explicit (from the header) rather
than sniffed from which dict keys happen to be present.

No behavior change to either runner's column schema or process-babysitting
logic (timeout, process-group kill, lock file) — those stay runner-specific
because they answer genuinely different questions (fixture-mode has no
dispatch/orchestrator-turn concept). Verified with a standalone unit test
and a read-only run of campaign-report.py against already-committed
results; the real runners were not invoked (a live campaign is using the
engine).
EOF
)"
```

---

## Task 3: Annotate the uncalibrated-grader acceptance claim

**Do this in the P26 worktree, in parallel with Task 2** (different file —
`ROADMAP.md`'s P22 row — so no merge conflict with Task 2's `Tools/*.py`
changes).

**Files:**
- Modify: `ROADMAP.md` (P22 row)

**Interfaces:** none — documentation only.

- [ ] **Step 1: Locate the claim**

```bash
grep -n "GLM 5.3 APPROVE" ROADMAP.md
```

Expected: one match, inside the P22 row, immediately after `agentclinic
roadmap passed via DS4_AGENT_TOOL_NUDGE=2 (13/13, verdict good),
roadmap-user-story passed on defaults (13/13, verdict good); 614 declared
tests on that branch (main: 552, of which 82 are integration-tier and do not
run in the fast tier); GLM 5.3 APPROVE.`

- [ ] **Step 2: Insert the annotation**

Find this exact substring in `ROADMAP.md` (still inside the P22 row):

```
614 declared tests on that branch (main: 552, of which 82 are integration-tier and do not run in the fast tier); GLM 5.3 APPROVE.
```

Replace it with:

```
614 declared tests on that branch (main: 552, of which 82 are integration-tier and do not run in the fast tier); GLM 5.3 APPROVE. **Flagged 2026-08-29:** the "verdict good" calls are `DeepSeekGrader`, an uncalibrated LLM judge with no calibration set in this repo — treat this acceptance claim as advisory pending calibration or an n≥3 rerun against the 13-test acceptance oracle (see the P26 Later backlog entry), not as a reliability figure.
```

- [ ] **Step 3: Verify the edit didn't break the table**

```bash
awk -F'|' 'NR>1 && /^\| P/ {print NF, $2}' ROADMAP.md | sort | uniq -c | sort -rn | head -5
```

Expected: the P22 row still has the same pipe-count profile as other phase
rows (a single long row can have more `|` than a short one only if it
contains literal `|` characters — this edit adds none, so the count for the
P22 row should be unchanged from before the edit).

- [ ] **Step 4: Commit**

```bash
git add ROADMAP.md
git commit -m "$(cat <<'EOF'
P26: flag P22's grader-backed acceptance claims as advisory

DeepSeekGrader backs the "verdict good"/"GLM 5.3 APPROVE" acceptance
language with a single live run per spec and no calibration set anywhere
in the repo. Not fixing the grader here (that's Later work) — just making
sure nobody builds on an uncalibrated n=1 LLM judgment as if it were a
reliability figure in the meantime.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** all four P26 "Now" items from the ROADMAP row are
  covered — commit untracked evidence (Task 1), freeze the shared
  classification schema (Task 2), annotate the grader claim (Task 3). The
  fourth item, "correct the stale flat-depth-profile claim," was already
  done directly in `ROADMAP.md` before this plan was written and is
  captured by Task 1's commit rather than a separate task.
- **No placeholders:** every step has literal code/commands, not descriptions.
- **Type/name consistency:** `campaign_common`'s five function names are used
  identically across Task 2's Steps 3, 5, 6, 7.
- **Engine safety:** Step 9 of Task 2 is deliberately read-only against
  already-committed results files; nowhere in this plan does any step invoke
  the real `run-experiment.py` or `run-orchestrate-campaign.py` binaries.
