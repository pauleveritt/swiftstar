#!/usr/bin/env bash
# Preflight gate for an unattended measurement campaign.
#
# WHY THIS EXISTS: on 2026-08-28 a Block B dry run returned
# "harness-void: no capture produced" in 3 seconds for every cell. Cause:
# `external/ds4/ds4-agent` on disk predated the P23 divergence-#14 pin bump,
# so it rejected the `--per-turn-think` that `AgentCommand.argv` now emits.
# Nothing in the harness or the runner notices this — `run-experiment.py`
# faithfully records 60 harness-void rows and exits 0. An overnight campaign
# launched in that state burns the night and produces no measurement.
#
# So: fail LOUDLY here, before any cell runs. Exit non-zero = do not launch.
#
# Env: SKIP_SMOKE=1 to skip the live fixture cell (checks 1-5 only).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || { echo "[preflight] cannot cd to $HERE" >&2; exit 2; }

BIN="$HERE/.build/arm64-apple-macosx/debug/swiftstar-agenttest"
ANALYZER="${ANALYZER_BIN:-$HERE/.build/arm64-apple-macosx/debug/swiftstar-eval}"
ENGINE="$HERE/external/ds4/ds4-agent"
fail=0
note() { printf '[preflight] %-7s %s\n' "$1" "$2"; }
bad()  { note FAIL "$1"; fail=1; }
ok()   { note ok "$1"; }

# ---- 1. submodule checked out at the pinned SHA -----------------------------
pin="$(git ls-tree HEAD external/ds4 | awk '{print $3}')"
head="$(git -C external/ds4 rev-parse HEAD 2>/dev/null)"
if [ -z "$head" ]; then
  bad "external/ds4 not checked out (run: just engine)"
elif [ "$pin" != "$head" ]; then
  bad "ds4 SHA drift: pin=${pin:0:9} head=${head:0:9} (run: just engine)"
else
  ok "ds4 at pinned SHA ${head:0:9}"
fi

# ---- 2. engine binary newer than every engine source ------------------------
# The failure above was exactly this: a correct SHA with a stale binary.
if [ ! -x "$ENGINE" ]; then
  bad "engine binary missing: $ENGINE (run: just engine)"
else
  stale="$(find external/ds4 -maxdepth 1 \( -name '*.c' -o -name '*.h' -o -name 'Makefile' \) \
            -newer "$ENGINE" 2>/dev/null | head -5)"
  if [ -n "$stale" ]; then
    bad "engine binary older than sources (run: just engine):"
    printf '           %s\n' $stale
  else
    ok "engine binary newer than engine sources"
  fi
fi

# ---- 3. harness binary newer than every Swift source ------------------------
if [ ! -x "$BIN" ]; then
  bad "harness binary missing: $BIN (run: swift build)"
else
  stale="$(find Sources -name '*.swift' -newer "$BIN" 2>/dev/null | head -5)"
  if [ -n "$stale" ]; then
    bad "harness binary older than Sources (run: swift build):"
    printf '           %s\n' $stale
  else
    ok "harness binary newer than Sources"
  fi
fi

# The fixture runner invokes the analyzer after every capture to classify V5/V6.
# Treat it as a first-class build artifact so a missing or stale analyzer cannot
# turn an otherwise valid campaign into a stream of harness-void rows.
if [ ! -x "$ANALYZER" ]; then
  bad "analyzer binary missing: $ANALYZER (run: swift build --product swiftstar-eval)"
else
  stale="$(find Sources -name '*.swift' -newer "$ANALYZER" 2>/dev/null | head -5)"
  if [ -n "$stale" ]; then
    bad "analyzer binary older than Sources (run: swift build --product swiftstar-eval):"
    printf '           %s\n' $stale
  else
    ok "analyzer binary newer than Swift sources"
  fi
fi

# ---- 4. the engine accepts the argv the harness actually emits --------------
# Cheap and direct: hand the engine each flag AgentCommand can emit and check
# it does not answer "unknown option". This is the check that would have caught
# the 2026-08-28 failure in one second.
if [ -x "$ENGINE" ]; then
  unknown=""
  for flag in --per-turn-think --host-tools --subagent-pool --json-events \
              --non-interactive --seed --metal --shell --think-budget --trace; do
    if "$ENGINE" "$flag" --help 2>&1 | grep -q "unknown option: $flag"; then
      unknown="$unknown $flag"
    fi
  done
  if [ -n "$unknown" ]; then
    bad "engine rejects flags the harness emits:$unknown (run: just engine)"
  else
    ok "engine accepts the harness's argv flags"
  fi
  # Negative control: a flag that cannot exist MUST be reported unknown. Without
  # this, a change to the engine's error string makes the check above a
  # permanent silent pass — which is the exact class of failure it exists to catch.
  if ! "$ENGINE" --swiftstar-preflight-canary --help 2>&1 \
        | grep -q "unknown option: --swiftstar-preflight-canary"; then
    bad "flag probe is broken (canary not rejected) — the argv check is a false pass"
  else
    ok "flag probe negative control passes"
  fi
fi

# ---- 5. no engine already holding the instance lock -------------------------
# ds4 takes a global lock: a second process dies with "another ds4 process is
# already running (pid N); refusing to start" in about a second. If one is
# resident at launch, every cell of the night voids. Observed 2026-08-28 when a
# killed driver orphaned its engine.
if pgrep -f 'ds4-agent' > /dev/null 2>&1; then
  bad "a ds4-agent is already running — it holds the instance lock:"
  pgrep -fl 'ds4-agent' | cut -c1-110 | sed 's/^/           /'
  echo "           (the app? a stale orphan? campaign engines match:"
  echo "            pkill -f 'ds4-agent.*(agenttest-directive|agenttest-fixture)')"
else
  ok "no ds4-agent holding the instance lock"
fi

# ---- 5b. sweep leaked temp worktrees ----------------------------------------
# The harness's `exit(1)` on a FAIL skips its `defer`, so `WorktreeDispatcher`
# never discards the throwaway repo. Nothing sweeps the fixture and batch tiers
# (only the Block A driver sweeps, and only between its own cells), so they
# accumulate: a sweep on 2026-08-29 found 240 dating back to 2026-08-23. Small
# individually — 11.3 MiB in total — so this is housekeeping, never a failure.
# The 10-minute age guard keeps a concurrently running harness's live worktree.
leaked="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'agenttest-*' -mmin +10 2>/dev/null | wc -l | tr -d ' ')"
if [ "${leaked:-0}" -gt 0 ]; then
  find "${TMPDIR:-/tmp}" -maxdepth 1 -type d -name 'agenttest-*' -mmin +10 -exec rm -rf {} + 2>/dev/null
  ok "swept ${leaked} leaked temp worktree(s)"
else
  ok "no leaked temp worktrees"
fi

# ---- 6. resources ------------------------------------------------------------
freegib="$(df -g "$HERE" | awk 'NR==2 {print $4}')"
if [ "${freegib:-0}" -lt 20 ]; then
  bad "only ${freegib}GiB free on the volume; want >=20GiB for a night of captures"
else
  ok "${freegib}GiB free disk"
fi

# ---- 7. one real fixture cell end-to-end ------------------------------------
# The only check that proves the whole path (spawn -> tools -> grade -> capture).
# Uses seed 97, deliberately OUTSIDE every pre-registered manifest, so a
# preflight never consumes or contaminates a measured cell.
if [ -n "${SKIP_SMOKE:-}" ]; then
  note skip "smoke cell (SKIP_SMOKE set)"
elif [ "$fail" = 0 ]; then
  tmp="$(mktemp -d)"
  printf 'fixture\trounds\tseed\nplausible-wrong-fix\t2\t97\n' > "$tmp/manifest.tsv"
  note run "smoke cell: plausible-wrong-fix/rounds=2/seed=97 (off-manifest)"
  EXP_MANIFEST="$tmp/manifest.tsv" EXP_RESULTS="$tmp/results.tsv" \
    python3 Tools/run-experiment.py > "$tmp/out.txt" 2>&1
  outcome="$(awk -F'\t' 'NR==2 {print $4}' "$tmp/results.tsv" 2>/dev/null)"
  detail="$(awk -F'\t' 'NR==2 {print $5}' "$tmp/results.tsv" 2>/dev/null)"
  case "$outcome" in
    pass|fail)
      # Either is fine — the model may legitimately fail a cell. What matters
      # is that the harness produced a graded capture at all.
      ok "smoke cell graded: $outcome ($detail)" ;;
    *)
      bad "smoke cell did not grade: ${outcome:-<none>} ${detail:-}"
      tail -15 "$tmp/out.txt" ;;
  esac
  rm -rf "$tmp"
else
  note skip "smoke cell (earlier checks already failed)"
fi

echo
if [ "$fail" = 0 ]; then
  echo "[preflight] READY — safe to launch the campaign."
  exit 0
fi
echo "[preflight] NOT READY — fix the FAILs above before launching. Nothing was run."
exit 1
