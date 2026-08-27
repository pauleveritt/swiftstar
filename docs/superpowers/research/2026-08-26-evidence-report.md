# Roadmap evidence report (2026-08-26)

*Which roadmap/backlog "big ideas" now have support, from the live telemetry
collected this session: the heavy-session capture
([`2026-08-26-heavy-session-telemetry-findings.md`](2026-08-26-heavy-session-telemetry-findings.md)),
the spike shell-on run
([`2026-08-26-spike-shell-on-findings.md`](2026-08-26-spike-shell-on-findings.md)),
and the P11 engine-constraints doc.*

## Strong live evidence

- **"Deterministic work first" / specialized tool subagents — the strongest
  new evidence.** The Backlog claims `ruff --fix` beats the model typing the
  same edit ~500×. The shell-off session is the negative confirmation: with
  `bash` excluded from the schema, "count swift files" took 23+ reasoning
  rounds instead of one deterministic command. The shell-on spike then showed
  the positive: git/grep/build became possible. Deterministic routing is a
  *performance* rule, confirmed from both sides.
- **The context tax / isolation hypothesis (P11).** Effective prefill fell
  231 → 134 tok/s as context grew 12k → 27k, with 85–95% KV-cache hits every
  round — the measured curve the pool's 4.2× ceiling is built on.
- **Compaction is the cliff.** Two compactions at 89% of 32k, each discarding
  ~24k tokens of learned context — the grow-then-reset pattern the ctx-50k
  change and the dispatch-preference rule both target.
- **The dispatch decision's "thinking requirement" (axis 2).** The spike
  prompt is exactly the non-delegable task the entry describes (fuzzy
  acceptance, unbounded exploration, no exact writable set) — and
  `/orchestrate` failed it precisely because the writable set couldn't be
  exact. The rule now has a concrete failure case.

## Documented but unmeasured (unchanged)

- **Specialized-subagent economics** (the 500× / 178s→9s figures) — from
  `docs/harvest/telemetry-findings.md`, not re-measured live. The mechanism is
  confirmed; the magnitude isn't.
- **House style as a compiled artifact** — the Backlog says "nothing here is
  measured"; still true.

## New findings this session

- **The severity thresholds are dead at small ctx.** `DialLogic` warning=37.5k
  / critical=75k is anchored at a 150k context. At 32k the context ring never
  fired — even at 89% full (29k < 37.5k). At 50k, warning fires at 73% but
  critical (75k) is unreachable. Re-anchor per the P11 discipline.
- **Shell posture is the cheapest lever in the system.** A Settings toggle;
  the deny posture is *why* the read/search loops happen. Zero code to flip.
- **The wire already emits `power` but the parser drops it** — the first step
  toward the energy-pacing question (which stays in the Backlog until the
  sustained draw of the prefill spikes is measured).

## Evidence for the P19–P23 phases

- P19 (one surface) — landed, verified (552 tests, selftest, real-engine pool
  protocol test).
- P20 (delegation) — the pool protocol is engine-verified (worker prompt →
  `pong`); the dispatch-preference rule is unbuilt but directly targets the
  measured 73-round pattern.
- P21 (measurement) — capture works; golden recapture + re-anchored thresholds
  + the eval remain.
- P22 (Laguna XS + model switching) — the unmerged branch exists with its own
  spec; XS is the natural small-ctx worker line.
- P23 (wire-level think control) — unbuilt; the 1,232-think-events budget
  split is the evidence it should exist.
