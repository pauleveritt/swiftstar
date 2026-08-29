#!/usr/bin/env bash
# Overnight measurement campaign — sequences the two engine-time blocks.
#
# Pre-registration: docs/superpowers/research/2026-08-28-overnight-campaign-preregistration.md
#
# Order is deliberate and NOT interchangeable:
#   Block B first — Mellum, fixture tier, ~60s/cell, 60 cells (~1-2h). Cheap,
#     and it finishes even on a short night.
#   Block A second — Laguna S (46 GB resident), ~695s/cell, 30 cells. Takes
#     whatever is left; resumable, so a partial night accumulates.
# They must not overlap: two resident models would contend for RAM and poison
# both measurements' timings.
#
# Env: STOP_FILE (touch to abort before the next cell — checked by both
#      blocks), RUN_CAP (Block A per-cell seconds), CAMPAIGN_LOG,
#      SKIP_BLOCK_B=1 / SKIP_BLOCK_A=1.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 2

LOG="${CAMPAIGN_LOG:-/tmp/overnight-campaign.log}"
STOP_FILE="${STOP_FILE:-/tmp/campaign-stop}"
export STOP_FILE

exec >> "$LOG" 2>&1
echo
echo "================================================================"
echo "=== overnight campaign $(date '+%F %T') ==="
echo "================================================================"

# ---- preflight: refuse to burn the night on a broken toolchain -------------
echo "=== preflight ==="
if ! bash Tools/campaign-preflight.sh; then
  echo "=== ABORTED: preflight failed. Nothing was run. $(date '+%F %T') ==="
  exit 1
fi

# Only ever consider engines this campaign could have started: their workspace
# is an agenttest temp dir. An engine the user launched by hand, or the app's
# own session, must never be touched by this script.
CAMPAIGN_ENGINE_PATTERN='ds4-agent.*(agenttest-directive|agenttest-fixture|/T/agenttest)'

engines_running() { pgrep -f "$CAMPAIGN_ENGINE_PATTERN" > /dev/null 2>&1; }

settle() {
  # Between blocks, make sure no engine from the previous block is still
  # resident — a 46 GB orphan would starve whatever runs next. A killed cell
  # (wall-clock cap, stop file) can leave one: the harness stops the engine
  # with SIGTERM only, and a SIGKILLed harness stops nothing at all.
  local waited=0
  while engines_running && [ "$waited" -lt 120 ]; do
    echo "[campaign] waiting for campaign ds4-agent to exit (${waited}s)"
    sleep 10; waited=$((waited + 10))
  done
  if engines_running; then
    echo "[campaign] campaign engine still resident after ${waited}s; reaping:"
    pgrep -fl "$CAMPAIGN_ENGINE_PATTERN" | head
    pkill -f "$CAMPAIGN_ENGINE_PATTERN"
    sleep 5
    pkill -9 -f "$CAMPAIGN_ENGINE_PATTERN" 2>/dev/null
    sleep 2
    if engines_running; then
      echo "[campaign] WARNING: could not reap; later cells may be starved"
    else
      echo "[campaign] reaped"
    fi
  else
    echo "[campaign] no campaign engine resident"
  fi
}

# ---- Block B: Mellum editing fixtures at n=20 ------------------------------
if [ -n "${SKIP_BLOCK_B:-}" ]; then
  echo "=== Block B skipped (SKIP_BLOCK_B) ==="
elif [ -f "$STOP_FILE" ]; then
  echo "=== Block B skipped: stop file present ==="
else
  echo "=== Block B start $(date '+%F %T') — editing fixtures, n=20, rounds=2 ==="
  # run-experiment.py has no timeout of its own and runs all 60 cells in one
  # process, so a single degenerate cell could consume the whole night. Bound
  # the block, not the cell: it records each cell as it finishes and skips
  # recorded cells on the next run, so a cut-off block simply resumes later.
  # Measured cost is ~60s/cell, so 3h is ~3x headroom over the expected 1h.
  BLOCK_B_CAP="${BLOCK_B_CAP:-10800}"
  EXP_MANIFEST="$HERE/docs/superpowers/research/experiment-manifest-editing-n20.tsv" \
  EXP_RESULTS="$HERE/docs/superpowers/research/experiment-results-editing-n20.tsv" \
    python3 Tools/run-experiment.py &
  b_pid=$!
  b_waited=0
  while kill -0 "$b_pid" 2>/dev/null && [ "$b_waited" -lt "$BLOCK_B_CAP" ]; do
    sleep 30; b_waited=$((b_waited + 30))
  done
  if kill -0 "$b_pid" 2>/dev/null; then
    echo "[campaign] Block B hit its ${BLOCK_B_CAP}s cap; stopping so Block A gets the night"
    kill "$b_pid" 2>/dev/null; sleep 5; kill -9 "$b_pid" 2>/dev/null
  fi
  wait "$b_pid" 2>/dev/null; b_rc=$?
  # $? must be captured BEFORE the command substitution in the echo resets it.
  echo "=== Block B done $(date '+%F %T') rc=$b_rc ==="
  settle
fi

# ---- Block A: orchestrate-loop pass rate -----------------------------------
if [ -n "${SKIP_BLOCK_A:-}" ]; then
  echo "=== Block A skipped (SKIP_BLOCK_A) ==="
elif [ -f "$STOP_FILE" ]; then
  echo "=== Block A skipped: stop file present ==="
else
  echo "=== Block A start $(date '+%F %T') — orchestrate loop, n=30 ==="
  # Python, not bash: the first bash driver hung in wait4 after its child had
  # already exited, recording nothing for a completed 695s cell. The Python
  # driver also runs each cell in its own process group, so a timeout kills the
  # engine grandchild instead of leaving 46 GB resident.
  python3 Tools/run-orchestrate-campaign.py; a_rc=$?
  echo "=== Block A done $(date '+%F %T') rc=$a_rc ==="
  settle
fi

echo "=== campaign finished $(date '+%F %T') ==="
echo "--- Block B results ---"
tail -5 docs/superpowers/research/experiment-results-editing-n20.tsv 2>/dev/null
echo "--- Block A results ---"
tail -5 docs/superpowers/research/experiment-results-orchestrate.tsv 2>/dev/null
