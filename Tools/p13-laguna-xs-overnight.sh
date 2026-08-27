#!/usr/bin/env bash
# P13 Laguna XS overnight verification — build the pinned engine, smoke-test
# that XS21 loads with --ssd-streaming, then run the live headless acceptance
# test (`swiftstar-agenttest --variant laguna-xs-2.1 --spec roadmap`).
#
# Run detached (see Tools/overnight-chain.sh for the pattern). Logs to
# /tmp/p13-laguna-xs-overnight.log.
set -u

LOG="${P13_XS_LOG:-/tmp/p13-laguna-xs-overnight.log}"
exec >> "$LOG" 2>&1
echo "=== P13 Laguna XS overnight spike $(date '+%F %T') ==="

ENGINE_DIR=/Users/pauleveritt/projects/pauleveritt/swiftstar/external/ds4
ARTIFACT=/Users/pauleveritt/projects/ds4/gguf/laguna-xs-2.1-RoutedQ3_K-biased.gguf
WORKTREE=/Users/pauleveritt/projects/pauleveritt/swiftstar/.worktrees/p13-laguna-xs-variant

# 1. Build the engine from the pinned fork (proves XS21 still compiles in the
#    integration line — GLM 5.2's "merged ≠ verified-merged" caveat).
echo "=== [1/3] build engine ==="
cd "$ENGINE_DIR" || { echo "engine dir missing"; exit 2; }
echo "engine HEAD: $(git rev-parse HEAD)"
make ds4-server ds4-agent
echo "build exit: $?"

# 2. Smoke test: does ds4-agent load the XS21 artifact with --ssd-streaming?
#    Success signal: a `ready`/`planned_bytes` event (the startup memory plan).
echo "=== [2/3] smoke: load XS21 with --ssd-streaming ==="
SMOKE=/tmp/p13-xs-smoke.out
rm -f "$SMOKE"
"$ENGINE_DIR/ds4-agent" -m "$ARTIFACT" -c 32768 --metal \
  --ssd-streaming --ssd-streaming-cache-experts 3200 --prefill-chunk 4096 \
  --non-interactive --json-events --shell off --workspace /tmp --nothink -n 16 \
  < /dev/null > "$SMOKE" 2>&1 &
SMOKE_PID=$!
SMOKE_RESULT="timeout (no load signal in 240s)"
for _ in $(seq 1 240); do
  if grep -q "planned_bytes\|'ready'\|\"ready\"" "$SMOKE" 2>/dev/null; then
    SMOKE_RESULT="LOADED (ready/planned_bytes emitted)"; break
  fi
  if grep -qiE 'ds4: |refus|die|abort|panic|segmentation|error' "$SMOKE" 2>/dev/null; then
    SMOKE_RESULT="FAILED"; break
  fi
  if ! kill -0 "$SMOKE_PID" 2>/dev/null; then SMOKE_RESULT="EXITED EARLY"; break; fi
  sleep 1
done
kill "$SMOKE_PID" 2>/dev/null; sleep 1; kill -9 "$SMOKE_PID" 2>/dev/null
echo "[smoke] result: $SMOKE_RESULT"
tail -20 "$SMOKE"

# 3. Live headless acceptance test (the canonical headless test).
echo "=== [3/3] live headless test: swiftstar-agenttest --variant laguna-xs-2.1 --spec roadmap ==="
cd "$WORKTREE" || { echo "worktree missing"; exit 2; }
echo "worktree HEAD: $(git rev-parse HEAD)"
LIVE=/tmp/p13-xs-live.out
rm -f "$LIVE"
SWIFTSTAR_LAGUNA_XS_MODEL="$ARTIFACT" \
DS4_DIR="$ENGINE_DIR" \
AGENTTEST_TURN_TIMEOUT="${AGENTTEST_TURN_TIMEOUT:-3600}" \
  swift run swiftstar-agenttest --variant laguna-xs-2.1 --spec roadmap > "$LIVE" 2>&1 &
LIVE_PID=$!
LIVE_MAX="${P13_XS_LIVE_MAX:-14400}"   # 4h wall-clock cap
LIVE_WAITED=0
while kill -0 "$LIVE_PID" 2>/dev/null && [ "$LIVE_WAITED" -lt "$LIVE_MAX" ]; do
  sleep 30; LIVE_WAITED=$((LIVE_WAITED + 30))
done
if kill -0 "$LIVE_PID" 2>/dev/null; then
  echo "[live] still running after ${LIVE_WAITED}s; killing"
  kill "$LIVE_PID" 2>/dev/null; sleep 5; kill -9 "$LIVE_PID" 2>/dev/null
fi
wait "$LIVE_PID" 2>/dev/null
LIVE_EXIT=$?
echo "[live] exit=$LIVE_EXIT (wall ${LIVE_WAITED}s)"
echo "--- live output tail ---"
tail -80 "$LIVE"

echo "=== done $(date '+%F %T') ==="
