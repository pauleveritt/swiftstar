#!/bin/bash
# P11 smoke gate: does the n=2 pool multiplex, route, and exit cleanly?
#
# NOT the measurement gate — the 4.2x context-curve ratio needs a 131k deep
# baseline vs 8x16k workers (the overnight full gate). This proves the pool
# machinery end-to-end against the real engine:
#   1. hello carries the "pool" cap
#   2. a bare prompt routes to worker 0 (events tagged worker:0)
#   3. a PoolPrompt routes to worker 1 (events tagged worker:1)
#   4. the engine exits 0 (no crash, no deadlock)
#
# Run: bash Tools/p11-smoke-gate.sh
# Env: SWIFTSTAR_MODEL (defaults to the laguna-s-2.1 gguf),
#      SMOKE_CTX (default 16384), SMOKE_SETTLE (default 25s for load + init).
set -u
GGUF="${SWIFTSTAR_MODEL:-/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf}"
CTX="${SMOKE_CTX:-16384}"
SETTLE="${SMOKE_SETTLE:-25}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$HERE/external/ds4/ds4-agent"
OUT="$(mktemp -t p11-smoke).ndjson"
ERR="$(mktemp -t p11-smoke).stderr"

if [ ! -x "$ENGINE" ]; then echo "smoke-gate: engine binary missing at $ENGINE" >&2; exit 2; fi
if [ ! -f "$GGUF" ]; then echo "smoke-gate: weights missing at $GGUF" >&2; exit 2; fi

echo "[smoke] spawn $ENGINE -c $CTX --subagent-pool 2"
cd "$HERE/external/ds4"   # Metal sources load cwd-relative (metal/*.metal)
(
  sleep "$SETTLE"
  echo "Explain the sky in one sentence."
  sleep 5
  echo '{"s":"List the first five prime numbers.","t":"prompt","worker":1}'
  sleep 15
) | "$ENGINE" -m "$GGUF" -c "$CTX" --metal --non-interactive --json-events \
      --host-tools --subagent-pool 2 > "$OUT" 2> "$ERR"
rc=$?

echo "[smoke] exit rc=$rc"
fail=0
check() {
  if eval "$2"; then echo "[smoke] $1: PASS"; else echo "[smoke] $1: FAIL"; fail=1; fi
}
check "pool cap advertised"        'grep -q '"'"'"pool"'"'"' "$OUT"'
check "worker 0 events present"    'grep -q '"'"'"worker":0'"'"' "$OUT"'
check "worker 1 events present"    'grep -q '"'"'"worker":1'"'"' "$OUT"'
check "worker 0 turn completed"    'grep -q '"'"'"t":"ready".*"stop_reason"'"'"' "$OUT"'
check "worker 1 turn completed"    'grep '"'"'"worker":1'"'"' "$OUT" | grep -q '"'"'"t":"ready"'"'"''
check "clean exit"                 '[ "$rc" = 0 ]'

echo "[smoke] worker 1 turn-end ready:"
grep '"worker":1' "$OUT" | grep '"t":"ready"' | tail -1

rm -f "$OUT" "$ERR"
exit "$fail"
