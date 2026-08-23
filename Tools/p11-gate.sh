#!/bin/bash
# P11 full measurement gate — the D11 envelope (canonical arm). Measures the
# realized context-curve win: one deep 131k prefill vs 8 sequential 16k prefills,
# versus the analytic 4.2x ceiling (research note).
#
# Wall-clock (the wire's `ts` span) is the primary metric — it includes generate
# and load overhead, which is the honest "does the pool win" number. Per-worker
# prefill wall-clock is reported as a secondary figure.
#
# This is the spec's hard exit criterion — the phase does not close until the
# canonical arm (and, in a later pass, the sensitivity envelope) is measured.
#
# Run: bash Tools/p11-gate.sh
# Env: SWIFTSTAR_MODEL, DEEP_CTX (131072), POOL_CTX (16384), WORKERS (8).
set -u
GGUF="${SWIFTSTAR_MODEL:-/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf}"
DEEP_CTX="${DEEP_CTX:-131072}"
POOL_CTX="${POOL_CTX:-16384}"
WORKERS="${WORKERS:-8}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$HERE/external/ds4/ds4-agent"
cd "$HERE/external/ds4"

[ -x "$ENGINE" ] || { echo "gate: engine missing at $ENGINE" >&2; exit 2; }
[ -f "$GGUF" ] || { echo "gate: weights missing at $GGUF" >&2; exit 2; }

# Deterministic corpus: ~500KB of repeated prose (~116k tokens at ~4.3 chars/tok).
CORPUS=/tmp/p11-corpus.txt
python3 - <<'EOF'
para = ("The quick brown fox jumps over the lazy dog while the cat watches from the windowsill, "
        "and the sky above turns a deep shade of blue as the afternoon wears on. ")
with open('/tmp/p11-corpus.txt', 'w') as f:
    while f.tell() < 500000:
        f.write(para)
EOF
CORPUS_BYTES=$(wc -c < "$CORPUS" | tr -d ' ')
echo "[gate] corpus: $CORPUS_BYTES bytes (~116k tokens)"

span() {  # wire-file ts span in seconds
  python3 - "$1" <<'EOF'
import json, sys
ts = [int(json.loads(l)["ts"]) for l in open(sys.argv[1]) if l.strip()]
print(f"{(ts[-1]-ts[0])/1e6:.1f}")
EOF
}

# Deep baseline: the whole corpus as one prompt, filling the deep ctx.
echo "[gate] deep (ctx $DEEP_CTX)..."
( sleep 25; cat "$CORPUS"; printf '\n'; sleep 120 ) \
  | "$ENGINE" -m "$GGUF" -c "$DEEP_CTX" --metal --non-interactive --json-events --host-tools \
    > /tmp/p11-deep.ndjson 2> /tmp/p11-deep.stderr
DEEP=$(span /tmp/p11-deep.ndjson)
echo "[gate] deep wall-clock: ${DEEP}s"

# Pool: WORKERS workers (sessions = WORKERS + 1, counting the orchestrator),
# each prefilling 1/WORKERS of the corpus, one at a time.
echo "[gate] pool (ctx $POOL_CTX, $WORKERS workers)..."
mkdir -p /tmp/p11-chunks
python3 - "$CORPUS" "$WORKERS" <<'EOF'
import json, sys
corpus = open(sys.argv[1]).read(); n = int(sys.argv[2]); chunk = len(corpus) // n
for i in range(n):
    body = corpus[i*chunk:(i+1)*chunk]
    with open(f'/tmp/p11-chunks/w{i+1}.prompt', 'w') as f:
        f.write(json.dumps({"t":"prompt","worker":i+1,"s":body}, sort_keys=True, separators=(',',':')))
EOF
( sleep 25
  for i in $(seq 1 "$WORKERS"); do cat "/tmp/p11-chunks/w$i.prompt"; echo; sleep 1; done
  sleep $((WORKERS * 80 + 30))
) | "$ENGINE" -m "$GGUF" -c "$POOL_CTX" --metal --non-interactive --json-events --host-tools \
      --subagent-pool $((WORKERS + 1)) > /tmp/p11-pool.ndjson 2> /tmp/p11-pool.stderr
POOL=$(span /tmp/p11-pool.ndjson)
echo "[gate] pool wall-clock: ${POOL}s"

# Report the realized win vs the 4.2x ceiling.
python3 - "$DEEP" "$POOL" <<'EOF'
import sys
deep = float(sys.argv[1]); pool = float(sys.argv[2])
win = deep / pool if pool else 0.0
print(f"[gate] RESULT: deep {deep:.1f}s / pool {pool:.1f}s = {win:.2f}x realized win "
      f"(ceiling 4.2x; overhead ratio {win/4.2:.2f})")
EOF
echo "[gate] done"
