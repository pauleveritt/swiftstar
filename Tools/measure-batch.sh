#!/usr/bin/env bash
# P16 /goal measure batch: mellum-only, 2 seeds x 2 path styles, think=off.
# Deliberately NOT the full matrix -- the loop's contract forbids that.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$HERE/.build/arm64-apple-macosx/debug/swiftstar-agenttest"
LOG="${MEASURE_LOG:-/tmp/measure-batch.log}"
MANIFEST="${MEASURE_MANIFEST:-/tmp/measure-manifest.tsv}"
STOP_FILE="${STOP_FILE:-/tmp/measure-stop}"

cd "$HERE" || exit 2
[ -x "$BIN" ] || { echo "[measure] binary missing: $BIN" >&2; exit 2; }

echo "[measure] start $(date '+%F %T') head=$(git rev-parse --short HEAD)" >> "$LOG"
printf 'model\tpath\tthink\tseed\texit\tcapture\n' > "$MANIFEST"

for seed in 1 2; do
  for path in relative absolute; do
    [ -f "$STOP_FILE" ] && { echo "[measure] stop file present; aborting" >> "$LOG"; exit 0; }
    envs=(AGENTTEST_SEED="$seed")
    [ "$path" = "absolute" ] && envs+=(AGENTTEST_PATH_STYLE=absolute)
    echo "[measure] $(date '+%H:%M:%S') mellum/$path/off seed=$seed start" >> "$LOG"
    out="$(env "${envs[@]}" "$BIN" --spec roadmap --batch 1 --variant mellum-2.1 2>&1)"; rc=$?
    cap="$(printf '%s\n' "$out" | sed -n 's/.*capture=//p' | head -1)"
    printf 'mellum\t%s\toff\t%s\t%s\t%s\n' "$path" "$seed" "$rc" "$cap" >> "$MANIFEST"
    echo "[measure] $(date '+%H:%M:%S') mellum/$path/off seed=$seed done rc=$rc capture=$cap" >> "$LOG"
    printf '%s\n' "$out" | tail -10 >> "$LOG"
  done
done

echo "[measure] done $(date '+%F %T')" >> "$LOG"
