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
    assert cc.done_cells('/nonexistent/path.tsv', [(0, None), (1, None), (2, None)]) == set()


def test_done_cells_plain_prefix_key():
    """run-orchestrate-campaign.py's shape: a plain 3-column prefix key,
    no optional trailing column."""
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'results.tsv')
        with open(path, 'w') as fh:
            fh.write('spec\tthink\tseed\toutcome\tdispatches\trounds\tacceptance_exit\tseconds\tcapture\tdetail\n')
            fh.write('roadmap\t1500\t3\tpass\t1\t2\t0\t695\tcap-a\t\n')
            fh.write('roadmap\t1500\t4\tharness-void\t\t\t\t\tcap-b\tno summary\n')
            fh.write('roadmap\t1500\t5\tfail\t0\t1\t1\t900\tcap-c\ttimeout\n')
        got = cc.done_cells(path, [(0, None), (1, None), (2, None)])
        assert got == {('roadmap', '1500', '3'), ('roadmap', '1500', '5')}, got


def test_done_cells_trailing_optional_column_with_default():
    """run-experiment.py's shape: a 4th `arm` column at a non-adjacent
    index, with a documented default for legacy rows that predate it."""
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'results.tsv')
        with open(path, 'w') as fh:
            fh.write('fixture\trounds\tseed\toutcome\tdetail\tcapture\tarm\n')
            fh.write('depth-2\t1\t3\tpass\t13/13\tcap-a\tsingular\n')
            fh.write('depth-2\t1\t3\tpass\t13/13\tcap-a\n')  # legacy row, no arm column
            fh.write('depth-2\t1\t4\tharness-void\tV5 stale binary\tcap-b\tplural\n')
        got = cc.done_cells(path, [(0, None), (1, None), (2, None), (6, 'plural')])
        assert got == {('depth-2', '1', '3', 'singular'),
                        ('depth-2', '1', '3', 'plural')}, got


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


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith('test_')]
    for t in tests:
        t()
        print(f'ok  {t.__name__}')
    print(f'{len(tests)} passed')


if __name__ == '__main__':
    main()
