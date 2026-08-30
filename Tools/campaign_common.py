#!/usr/bin/env python3
"""Shared cell-classification helpers for the campaign runners.

`run-experiment.py` (fixture-tier) and `run-orchestrate-campaign.py`
(directive-tier) each reimplemented "is this cell closed" and "append one
result row" independently, and drifted: by 2026-08-29 `run-experiment.py`
had grown a 4th manifest column (`arm`, for interleaved prompt-wording
arms) and keyed closure on a 4-tuple with a legacy-row fallback, while
`run-orchestrate-campaign.py` still keyed on a plain 3-tuple prefix. This
module is the one implementation both import — general enough to describe
either runner's key shape, so a future column addition changes a call site,
not a second parallel implementation.

Deliberately does NOT unify the two runners' column sets or process-
babysitting logic (timeout, process-group kill, lock file) — those answer
genuinely different questions (fixture-mode has no dispatch/orchestrator-
turn concept, directive-mode has no prompt-arm concept). What is unified is
closure detection and append mechanics — the actual place the drift caused
divergent, hand-rolled logic.
"""
import csv
import os

HEADER_ROWS = ('fixture', 'spec')  # first column value on a header line


def is_closed(row: list) -> bool:
    """True iff `row` is a GRADED cell. A `harness-void` or `timeout` row
    records a run the harness could not use and must stay re-runnable, or
    one broken engine permanently fixes n at whatever ran before the
    breakage — the resume-safety rule both runners' own docstrings state;
    this is the one implementation of it."""
    return len(row) > 3 and row[3] in ('pass', 'fail')


def done_cells(results_path: str, key_columns: list) -> set:
    """The set of closed cell keys already recorded in `results_path`.

    `key_columns` is a list of `(index, default)` pairs describing which
    columns make up a cell's identity. `default` is used when a row is too
    short to have that column — a run-experiment.py row predating the `arm`
    column, for example, is read under `arm`'s documented default rather
    than raising or silently mis-keying. A plain positional prefix (no
    trailing/optional columns) is just `[(0, None), (1, None), (2, None)]`.
    """
    if not os.path.exists(results_path):
        return set()
    closed = set()
    with open(results_path) as fh:
        for r in csv.reader(fh, delimiter='\t'):
            if not r or r[0] in HEADER_ROWS or not is_closed(r):
                continue
            closed.add(tuple(r[i] if i < len(r) else default
                              for i, default in key_columns))
    return closed


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
