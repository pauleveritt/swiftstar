#!/usr/bin/env bash
# Overnight R3.5 prompt-shape ablation — seed-swept, both models.
# Matrix: {laguna,mellum} x {relative,absolute} x {off,on} x seeds 1..NSEEDS
#   = 80 runs at NSEEDS=10.
#
# Env:  NSEEDS (default 10), CHAIN_ONESHOT=1 (smoke test: first cell only),
#       CHAIN_LOG, CHAIN_MANIFEST, STOP_FILE, LAGUNA_GGUF.
# Abort at any time: touch "$STOP_FILE"  (checked before each run)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HERE/.build/arm64-apple-macosx/debug/swiftstar-agenttest"
SPEC="roadmap"
LAGUNA_GGUF="${LAGUNA_GGUF:-/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf}"
NSEEDS="${NSEEDS:-10}"
LOG="${CHAIN_LOG:-/tmp/overnight-chain.log}"
MANIFEST="${CHAIN_MANIFEST:-/tmp/overnight-manifest.tsv}"
STOP_FILE="${STOP_FILE:-/tmp/overnight-stop}"

cd "$HERE" || { echo "[chain] cannot cd to $HERE" >&2; exit 2; }
[ -x "$BIN" ] || { echo "[chain] binary missing: $BIN" >&2; exit 2; }
[ -f "$LAGUNA_GGUF" ] || { echo "[chain] laguna weights missing: $LAGUNA_GGUF" >&2; exit 2; }

echo "[chain] start $(date '+%F %T') spec=$SPEC models=laguna,mellum paths=relative,absolute think=off,on seeds=1..$NSEEDS" >> "$LOG"
printf 'model\tpath\tthink\tseed\texit\tcapture\n' > "$MANIFEST"

run_cell() {
  local model="$1" path="$2" think="$3" seed="$4"
  [ -f "$STOP_FILE" ] && { echo "[chain] stop file present; aborting" >> "$LOG"; exit 0; }
  local -a envs=(AGENTTEST_SEED="$seed")
  local -a argv=(--spec "$SPEC" --batch 1)
  if [ "$model" = "mellum" ]; then
    argv+=(--variant mellum-2.1)
  else
    envs+=(SWIFTSTAR_MODEL="$LAGUNA_GGUF")
  fi
  [ "$path" = "absolute" ] && envs+=(AGENTTEST_PATH_STYLE=absolute)
  [ "$think" = "on" ] && envs+=(AGENTTEST_THINK=1)
  echo "[chain] $(date '+%H:%M:%S') $model/$path/$think seed=$seed start" >> "$LOG"
  local out rc cap
  out="$(env "${envs[@]}" "$BIN" "${argv[@]}" 2>&1)"; rc=$?
  cap="$(printf '%s\n' "$out" | sed -n 's/.*capture=//p' | head -1)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$model" "$path" "$think" "$seed" "$rc" "$cap" >> "$MANIFEST"
  echo "[chain] $(date '+%H:%M:%S') $model/$path/$think seed=$seed done rc=$rc capture=$cap" >> "$LOG"
  printf '%s\n' "$out" | tail -8 >> "$LOG"
}

for model in laguna mellum; do
  for path in relative absolute; do
    for think in off on; do
      for seed in $(seq 1 "$NSEEDS"); do
        run_cell "$model" "$path" "$think" "$seed"
        [ -n "${CHAIN_ONESHOT:-}" ] && break 4
      done
    done
  done
done

echo "[chain] done $(date '+%F %T')" >> "$LOG"
