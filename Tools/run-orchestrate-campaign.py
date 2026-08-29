#!/usr/bin/env python3
"""Block A driver — /orchestrate coordination-loop pass rate at real n.

Pre-registration: docs/superpowers/research/2026-08-28-overnight-campaign-preregistration.md
Manifest:         docs/superpowers/research/experiment-manifest-orchestrate.tsv

Sibling of `run-experiment.py` and deliberately the same shape: read a
pre-registered manifest, run each unrecorded row once, append exactly one
outcome row. A recorded cell is NEVER re-run, so an interrupted night resumes
where it stopped.

This is Python rather than a shell script for one specific reason. The first
version was bash, polling `kill -0` and then calling `wait`; it hung in
`wait4` after its child had already exited, so a 695s cell sat forever and
recorded nothing. Bash job control is not reliable enough to leave running
unattended for eight hours. `subprocess` with a real timeout is.

The other thing this gets right that bash did not: the harness spawns the
engine as a *grandchild*, and killing the harness leaves a 46 GB `ds4-agent`
resident, which would starve every later cell. Each cell therefore runs in its
own process group and a timeout kills the whole group.

Env: CAMPAIGN_MANIFEST, CAMPAIGN_RESULTS, RUN_CAP (per-cell seconds, default
     1500), STOP_FILE (touch to abort before the next cell).
"""
import csv
import fcntl
import json
import os
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESEARCH = os.path.join(ROOT, 'docs/superpowers/research')
MANIFEST = os.environ.get('CAMPAIGN_MANIFEST',
                          os.path.join(RESEARCH, 'experiment-manifest-orchestrate.tsv'))
RESULTS = os.environ.get('CAMPAIGN_RESULTS',
                         os.path.join(RESEARCH, 'experiment-results-orchestrate.tsv'))
# CAMPAIGN_BIN exists so the driver's timeout and process-group kill can be
# tested against a stub, without loading a 46 GB model.
BIN = os.environ.get('CAMPAIGN_BIN',
                     os.path.join(ROOT, '.build/arm64-apple-macosx/debug/swiftstar-agenttest'))
RUN_CAP = int(os.environ.get('RUN_CAP', '3600'))
# Must stay well below RUN_CAP: the harness's own turn timeout unwinds
# cleanly (its defers stop the engine), the driver's kill does not.
TURN_TIMEOUT = os.environ.get('TURN_TIMEOUT', '900')
STOP_FILE = os.environ.get('STOP_FILE', '/tmp/campaign-stop')
CAPTURES = os.path.join(ROOT, 'captures/agenttest')

HEADER = ['spec', 'think', 'seed', 'outcome', 'dispatches', 'rounds',
          'acceptance_exit', 'seconds', 'capture', 'detail']

# "[agenttest] directive: PASS — 1 dispatch(es), 2 orchestrator turn(s), acceptance exit 0, 695s"
SUMMARY = re.compile(
    r'directive:\s+(PASS|FAIL)\s+.*?(\d+)\s+dispatch.*?(\d+)\s+orchestrator turn.*?'
    r'acceptance exit\s+(-?\d+)')


def rows():
    out = []
    for line in open(MANIFEST):
        line = line.rstrip('\n')
        if not line or line.startswith('#') or line.startswith('spec\t'):
            continue
        parts = line.split('\t')
        if len(parts) >= 3:
            out.append(parts[:3])
    return out


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


def newest_capture(spec: str, since: float) -> str:
    """The harness creates its capture dir at spawn and never prints the path,
    so find the newest matching dir created after this cell started."""
    best, best_t = '', 0.0
    suffix = f'-{spec}-directive'
    if not os.path.isdir(CAPTURES):
        return ''
    for name in os.listdir(CAPTURES):
        if not name.endswith(suffix):
            continue
        path = os.path.join(CAPTURES, name)
        try:
            t = os.stat(path).st_ctime
        except OSError:
            continue
        if t >= since - 5 and t > best_t:
            best, best_t = name, t
    return best


# Only ever match engines this campaign could have started — their workspace is
# an agenttest temp dir. An engine the user started by hand, or the app's own
# session, must never be touched.
ENGINE_PATTERN = r'ds4-agent.*(agenttest-directive|agenttest-fixture|/T/agenttest)'


def reap_orphan_engines() -> int:
    """Kill any campaign engine left over from a previous cell.

    The engine holds a global instance lock: `ds4: another ds4 process is
    already running (pid N); refusing to start`. A single orphan therefore
    fails every subsequent cell in about one second, which would silently void
    the rest of the night as `harness-void`. Observed for real on 2026-08-28,
    when a killed driver left its 46 GB engine resident.
    """
    def alive() -> list[str]:
        p = subprocess.run(['pgrep', '-f', ENGINE_PATTERN],
                           capture_output=True, text=True)
        return [x for x in p.stdout.split() if x]

    pids = alive()
    if not pids:
        return 0
    print(f'[blockA] reaping {len(pids)} orphaned engine(s): {" ".join(pids)}', flush=True)
    subprocess.run(['pkill', '-f', ENGINE_PATTERN], capture_output=True)
    time.sleep(5)
    if alive():
        subprocess.run(['pkill', '-9', '-f', ENGINE_PATTERN], capture_output=True)
        time.sleep(3)
    left = alive()
    if left:
        print(f'[blockA] WARNING: could not reap {" ".join(left)}; '
              f'later cells will fail on the instance lock', flush=True)
    return len(pids)


def sweep_temp_worktrees() -> int:
    """Remove throwaway directive repos the harness left behind.

    `main.swift:1317` calls `exit(1)` on a FAIL, and Swift's `exit` does not run
    `defer`, so `WorktreeDispatcher.discard` never fires. Each leak is a small
    git repo in $TMPDIR, but nothing sweeps them and a campaign makes 30.
    Only ever touches `agenttest-directive-*`, never anything else.
    """
    tmp = tempfile.gettempdir()
    removed = 0
    try:
        names = os.listdir(tmp)
    except OSError:
        return 0
    for name in names:
        if not name.startswith('agenttest-directive-'):
            continue
        path = os.path.join(tmp, name)
        try:
            shutil.rmtree(path)
            removed += 1
        except OSError:
            pass
    return removed


def run_cell(spec: str, think: str, seed: str) -> dict:
    env = dict(os.environ,
               AGENTTEST_SEED=seed,
               AGENTTEST_THINK_BUDGET=think,
               AGENTTEST_TURN_TIMEOUT=TURN_TIMEOUT)
    argv = [BIN, '--directive', '--spec', spec, '--variant', 'laguna-s-2.1']
    started = time.time()

    # start_new_session puts the harness AND the engine it spawns in one
    # process group, so a timeout can kill the engine too.
    proc = subprocess.Popen(argv, env=env, cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    timed_out = False
    try:
        out, _ = proc.communicate(timeout=RUN_CAP)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            out, _ = proc.communicate(timeout=30)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                pass
            out, _ = proc.communicate()
    elapsed = int(time.time() - started)
    out = out or ''

    capture = newest_capture(spec, started)
    m = None
    for line in out.splitlines():
        found = SUMMARY.search(line)
        if found:
            m = found

    detail = ''
    if timed_out:
        outcome, dispatches, turns, acc = 'timeout', '', '', ''
        detail = f'no summary within {RUN_CAP}s'
    elif m is None:
        # No graded summary line at all: the run died before the final grade.
        # That is a harness/engine failure, not a model result, and must not be
        # pooled with model failures — the 0/40 Mellum verdict was wrong for
        # exactly this reason.
        outcome, dispatches, turns, acc = 'harness-void', '', '', ''
        tail = [l.strip() for l in out.splitlines() if l.strip()]
        detail = tail[-1][:100] if tail else 'no output'
    else:
        verdict, dispatches, turns, acc = m.groups()
        outcome = 'pass' if verdict == 'PASS' else 'fail'

    if capture:
        cdir = os.path.join(CAPTURES, capture)
        # Directive mode writes no run-config.json, so without this the cell's
        # configuration would live only in the results row.
        with open(os.path.join(cdir, 'campaign.json'), 'w') as fh:
            json.dump({'block': 'A', 'spec': spec, 'variant': 'laguna-s-2.1',
                       'think_budget': int(think), 'seed': int(seed),
                       'outcome': outcome, 'seconds': elapsed, 'run_cap': RUN_CAP,
                       'prereg': '2026-08-28-overnight-campaign-preregistration.md'},
                      fh)
            fh.write('\n')
        with open(os.path.join(cdir, 'campaign-stdout.txt'), 'w') as fh:
            fh.write(out)

    return {'spec': spec, 'think': think, 'seed': seed, 'outcome': outcome,
            'dispatches': dispatches, 'rounds': turns, 'acceptance_exit': acc,
            'seconds': str(elapsed), 'capture': capture, 'detail': detail}


LOCK = '/tmp/swiftstar-campaign-blockA.lock'


def acquire_lock():
    """Refuse to run two Block A drivers at once.

    Not paranoia: `reap_orphan_engines` kills any campaign engine it finds, so a
    second driver silently destroys the first one's in-flight cell. That
    happened during development — a stub test reaped a live 12-minute cell.
    """
    fh = open(LOCK, 'w')
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        sys.exit(f'another Block A driver holds {LOCK}; refusing to start '
                 f'(it would reap the running cell\'s engine)')
    fh.write(f'{os.getpid()}\n')
    fh.flush()
    return fh  # keep the handle alive for the process lifetime


def main() -> None:
    if not os.path.exists(BIN):
        sys.exit(f'harness binary missing: {BIN}')
    _lock = acquire_lock()
    if not os.path.exists(RESULTS):
        with open(RESULTS, 'w') as fh:
            fh.write('\t'.join(HEADER) + '\n')

    have = done()
    for spec, think, seed in rows():
        if os.path.exists(STOP_FILE):
            print(f'[blockA] stop file present; aborting before seed={seed}', flush=True)
            break
        if (spec, think, seed) in have:
            print(f'[blockA] skip seed={seed} (already recorded)', flush=True)
            continue
        reap_orphan_engines()
        swept = sweep_temp_worktrees()
        if swept:
            print(f'[blockA] swept {swept} leaked worktree(s)', flush=True)
        print(f'[blockA] {time.strftime("%H:%M:%S")} seed={seed} think={think} start',
              flush=True)
        r = run_cell(spec, think, seed)
        with open(RESULTS, 'a') as fh:
            fh.write('\t'.join(r[k] for k in HEADER) + '\n')
        print(f'[blockA] {time.strftime("%H:%M:%S")} seed={seed} -> {r["outcome"]} '
              f'({r["seconds"]}s, dispatches={r["dispatches"] or "?"}, '
              f'acc={r["acceptance_exit"] or "?"}) capture={r["capture"]}'
              + (f' :: {r["detail"]}' if r["detail"] else ''), flush=True)

    print('[blockA] done', flush=True)


if __name__ == '__main__':
    main()
