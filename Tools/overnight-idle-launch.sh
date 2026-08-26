#!/usr/bin/env bash
# Idle-gated delayed launch: sleep, then wait for the machine to sit untouched,
# then launch the overnight chain. Meant to be run detached: nohup ... & .
#
# Env:  WAIT_SECONDS (default 12600 = 3.5 h), IDLE_MIN (default 600 = 10 min),
#       POLL_SECONDS (600), MAX_EXTRA_WAIT (21600 = give up after +6 h),
#       RAM_MIN_GIB (8), LAUNCH_LOG, STOP_FILE.
# Abort at any time: touch "$STOP_FILE"
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAIT_SECONDS="${WAIT_SECONDS:-12600}"
IDLE_MIN="${IDLE_MIN:-600}"
POLL_SECONDS="${POLL_SECONDS:-600}"
MAX_EXTRA_WAIT="${MAX_EXTRA_WAIT:-21600}"
RAM_MIN_GIB="${RAM_MIN_GIB:-60}"
LOG="${LAUNCH_LOG:-/tmp/overnight-idle-launch.log}"
STOP_FILE="${STOP_FILE:-/tmp/overnight-stop}"

echo "[launch] $(date '+%F %T') armed wait=${WAIT_SECONDS}s idle>=${IDLE_MIN}s poll=${POLL_SECONDS}s maxExtra=${MAX_EXTRA_WAIT}s ramMin=${RAM_MIN_GIB}GiB" >> "$LOG"
sleep "$WAIT_SECONDS"

extra=0
while :; do
  [ -f "$STOP_FILE" ] && { echo "[launch] $(date '+%F %T') stop file present; aborted" >> "$LOG"; exit 0; }
  idle="$(ioreg -c IOHIDSystem -r -d 1 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}')"
  idle="${idle:-0}"
  ramline="$(python3 -c "
import subprocess, re
out = subprocess.check_output(['vm_stat']).decode()
ps = int(re.search(r'page size of (\d+)', out).group(1))
def pages(name):
    m = re.search(r'Pages %s:\s+(\d+)' % name, out)
    return int(m.group(1)) if m else 0
avail = (pages('free') + pages('inactive') + pages('speculative')) * ps / 1073741824
print(f'{avail:.1f} ok' if avail >= $RAM_MIN_GIB else f'{avail:.1f} low')
" 2>/dev/null)" || ramline="? ok"
  freegib="${ramline% *}"; ramstate="${ramline##* }"
  echo "[launch] $(date '+%F %T') idle=${idle}s avail=${freegib}GiB ram=${ramstate}" >> "$LOG"
  if [ "$idle" -ge "$IDLE_MIN" ] && [ "$ramstate" = "ok" ]; then break; fi
  extra=$((extra + POLL_SECONDS))
  if [ "$extra" -ge "$MAX_EXTRA_WAIT" ]; then
    echo "[launch] $(date '+%F %T') gave up: still not idle after ${extra}s extra" >> "$LOG"
    exit 0
  fi
  sleep "$POLL_SECONDS"
done

echo "[launch] $(date '+%F %T') idle confirmed (${idle}s, ${freegib}GiB avail); starting chain" >> "$LOG"
bash "$HERE/Tools/overnight-chain.sh" >> "$LOG" 2>&1
echo "[launch] $(date '+%F %T') chain finished rc=$?" >> "$LOG"
