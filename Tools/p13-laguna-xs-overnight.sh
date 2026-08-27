#!/usr/bin/env bash
# P13 Laguna XS overnight spike — bring laguna-xs-2.1 up to parity with
# Laguna S by passing the two agentclinic evals (roadmap = basic, then
# roadmap-user-story) on the real engine.
#
# XS at its Q3_K quant may struggle to initiate/pass, so this is an ORDERED
# SEARCH, not a single shot: for each spec it walks a lever escalation
# (default → nudge → absolute → combos → repair depth → seed sweep) and stops
# at the first PASS. Levers are the ones built for Laguna S (B8/C1: absolute
# paths + DS4_AGENT_TOOL_NUDGE; C18: --think-budget; P16: repair rounds).
#
# Pass signal: the harness prints "[agenttest] acceptance exit=0" (initial
# grade) or "[agenttest] repair: passed" (repair reached exit 0).
#
# Env:  STOP_FILE (touch to abort before the next cell), P13_XS_LOG,
#       RUN_CAP (per-run wall-clock seconds, default 1800).
set -u

LOG="${P13_XS_LOG:-/tmp/p13-laguna-xs-overnight.log}"
exec >> "$LOG" 2>&1
echo "=== P13 Laguna XS overnight spike $(date '+%F %T') ==="

ENGINE_DIR=/Users/pauleveritt/projects/pauleveritt/swiftstar/external/ds4
ARTIFACT=/Users/pauleveritt/projects/ds4/gguf/laguna-xs-2.1-RoutedQ3_K-biased.gguf
WORKTREE=/Users/pauleveritt/projects/pauleveritt/swiftstar/.worktrees/p13-laguna-xs-variant
MANIFEST="${P13_XS_MANIFEST:-/tmp/p13-xs-manifest.tsv}"
STOP_FILE="${STOP_FILE:-/tmp/p13-xs-stop}"
RUN_CAP="${RUN_CAP:-1800}"

# ---- 1. Build the pinned engine (proves XS21 still compiles: GLM 5.2 caveat)
echo "=== [1/3] build engine ==="
cd "$ENGINE_DIR" || { echo "engine dir missing"; exit 2; }
echo "engine HEAD: $(git rev-parse HEAD)"
make ds4-server ds4-agent
echo "build exit: $?"

# ---- 2. Smoke: load the XS21 artifact with --ssd-streaming and answer one prompt
echo "=== [2/3] smoke: load XS21 + one prompt ==="
SMOKE=/tmp/p13-xs-smoke.out
rm -f "$SMOKE"
(
  sleep 60                                   # allow the 15 GiB SSD-streaming load
  printf '%s\n' '{"t":"prompt","s":"Say hello in one word."}'
  sleep 45
) | "$ENGINE_DIR/ds4-agent" -m "$ARTIFACT" -c 32768 --metal \
      --ssd-streaming --ssd-streaming-cache-experts 3200 --prefill-chunk 4096 \
      --non-interactive --json-events --shell off --workspace /tmp --nothink -n 16 \
      > "$SMOKE" 2>&1 &
SMOKE_PID=$!
SMOKE_WAITED=0
while kill -0 "$SMOKE_PID" 2>/dev/null && [ "$SMOKE_WAITED" -lt 240 ]; do
  sleep 10; SMOKE_WAITED=$((SMOKE_WAITED + 10))
done
if kill -0 "$SMOKE_PID" 2>/dev/null; then
  kill "$SMOKE_PID" 2>/dev/null; sleep 2; kill -9 "$SMOKE_PID" 2>/dev/null
fi
wait "$SMOKE_PID" 2>/dev/null
if grep -qE '"ready"|"text"|planned_bytes' "$SMOKE" 2>/dev/null \
   && ! grep -qiE 'ds4: |refus|segmentation|panic|fatal' "$SMOKE" 2>/dev/null; then
  echo "[smoke] LOADED + generated"
else
  echo "[smoke] FAILED to load/generate — aborting before the eval loop"
  tail -25 "$SMOKE"
  exit 3
fi
tail -8 "$SMOKE"

# ---- 3. Ordered search over the two specs
echo "=== [3/3] eval loop (roadmap, then roadmap-user-story) ==="
cd "$WORKTREE" || { echo "worktree missing"; exit 2; }
echo "worktree HEAD: $(git rev-parse HEAD)"
printf 'spec\tconfig\trc\tresult\n' > "$MANIFEST"

bounded_run() {
  local cap="$1"; shift
  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$cap" ]; do
    sleep 15; waited=$((waited + 15))
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "[bounded] still running after ${cap}s; killing"
    kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null
  fi
  wait "$pid" 2>/dev/null
}

run_cell() {
  local spec="$1" config="$2"; shift 2
  [ -f "$STOP_FILE" ] && { echo "[loop] STOP_FILE present; aborting"; exit 0; }
  local out="/tmp/p13-xs-${spec}-${config}.out"
  local -a envs=(SWIFTSTAR_LAGUNA_XS_MODEL="$ARTIFACT" DS4_DIR="$ENGINE_DIR" AGENTTEST_TURN_TIMEOUT=1800)
  envs+=("$@")
  echo "[loop] $(date '+%H:%M:%S') $spec/$config start"
  bounded_run "$RUN_CAP" env "${envs[@]}" \
    swift run swiftstar-agenttest --variant laguna-xs-2.1 --spec "$spec" > "$out" 2>&1
  local rc=$?
  local result="FAIL"
  if grep -qE '\[agenttest\] (acceptance exit=0|repair: passed)' "$out" 2>/dev/null; then
    result="PASS"
  fi
  printf '%s\t%s\t%s\t%s\n' "$spec" "$config" "$rc" "$result" >> "$MANIFEST"
  echo "[loop] $(date '+%H:%M:%S') $spec/$config -> $result (rc=$rc)"
  grep -E 'acceptance exit=|repair:|grader verdict|elapsed|stopped|failed|infeasible|refus' "$out" 2>/dev/null | tail -6
  [ "$result" = "PASS" ]
}

for spec in roadmap roadmap-user-story; do
  passed=0
  # Escalation order: baseline first (Laguna S's best cell), then the
  # initiation levers (nudge, absolute paths), then thinking/repair depth.
  for config in default nudge abs abs-nudge abs-think abs-think-budget abs-repair4; do
    case "$config" in
      default)          run_cell "$spec" "$config" && { passed=1; break; } ;;
      nudge)            run_cell "$spec" "$config" DS4_AGENT_TOOL_NUDGE=2 && { passed=1; break; } ;;
      abs)              run_cell "$spec" "$config" AGENTTEST_PATH_STYLE=absolute && { passed=1; break; } ;;
      abs-nudge)        run_cell "$spec" "$config" AGENTTEST_PATH_STYLE=absolute DS4_AGENT_TOOL_NUDGE=2 && { passed=1; break; } ;;
      abs-think)        run_cell "$spec" "$config" AGENTTEST_PATH_STYLE=absolute AGENTTEST_THINK=1 && { passed=1; break; } ;;
      abs-think-budget) run_cell "$spec" "$config" AGENTTEST_PATH_STYLE=absolute AGENTTEST_THINK=1 AGENTTEST_THINK_BUDGET=2048 && { passed=1; break; } ;;
      abs-repair4)      run_cell "$spec" "$config" AGENTTEST_PATH_STYLE=absolute AGENTTEST_REPAIR_ROUNDS=4 && { passed=1; break; } ;;
    esac
  done
  if [ "$passed" = 0 ]; then
    for seed in 1 2 3 4 5 6; do
      run_cell "$spec" "abs-seed${seed}" AGENTTEST_PATH_STYLE=absolute AGENTTEST_SEED="$seed" \
        && { passed=1; break; }
    done
  fi
  echo "[loop] $spec passed=$passed"
done

echo "=== manifest ==="
cat "$MANIFEST"
echo "=== done $(date '+%F %T') ==="
