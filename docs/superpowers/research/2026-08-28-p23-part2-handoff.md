# P23 part 2 — handoff at the Task 10 boundary

**2026-08-28.** Tasks 1–9 of the
[part-2 plan](../plans/archive/2026-08-28-p23-wire-level-control-part2.md) are done on
branch `worktree-p23-part2`. **Task 10 — the golden recapture, fork-ledger row
#14, the submodule bump, and phase closure — is deliberately not done**: it is
the phase's one live-model gate, and every comparable gate in this repo (P25
cycle 5, P22's 16 GB acceptance) was explicitly reserved for a human.

## State

| Thing | State |
|---|---|
| Branch `worktree-p23-part2` | 9 commits on top of `20048f1` (part 1 merged) |
| Fast tier | **780 green** (baseline 751) |
| Integration tier | **780 green**, 26.9 s |
| Engine self-tests | green except 2 **pre-existing** `[upto]` failures |
| Submodule `external/ds4` | 2 commits, **pushed** to `origin/p20-dispatch-schema` (`5fa6ee0`) |
| Parent gitlink | **deliberately NOT bumped** — still `1091a39` |
| `git status` | shows `M external/ds4` — expected, see below |

**Why the gitlink is unbumped.** The plan's own constraint: *"the app must never
pass a flag the pinned engine does not know."* `--per-turn-think` enters
`AgentCommand.argv` in Task 10, in the same change as the bump, after the
recapture. Until then the app sends overrides only when the cap is advertised —
which the pinned engine never does — so the shipping app is unaffected by the
engine work sitting ahead of the pin.

The submodule commits were pushed anyway, for durability: part 1 found that
unpushed divergences make the pin unresolvable from a clean clone. Nothing
consumes them yet, because the pin is a SHA rather than the branch tip.

## What shipped (cycle 5, Swift)

- **`TurnThinkPolicy`** — the pure decision authority. `(requested, family,
  capAdvertised) → useDefault | override | refused`.
- **`PoolPrompt`** carries `think` and `ctx`, emitted only when non-nil, so the
  absent-field encoding is byte-identical to pre-P23.
- **`/quick`** — one no-think turn, routed on the `/chat` pattern, refused
  visibly without the cap.
- **`optionalCaps`** — the handshake's advertisement recorded, and cleared per
  spawn.
- **`TurnOutcome.sampler`** records the effort actually used, retiring the
  `"engine-defaults"` literal that was wrong at four sites.
- **`WorkerContextPolicy`** — clamp `[4096, parent]`, default 8,192.
- **Dispatch threading** — the worker's think comes from its packet's declared
  `SamplingPolicy.think` at last, and its ctx is clamped; both cap-gated.

## What shipped (cycles 6–7, engine divergence #14)

`--per-turn-think` gates the whole feature. `hello` advertises
`think_override`; the envelope's `think` and `ctx` keys are parsed and threaded
through the prompt queue into the turn; JSON envelopes parse at N=1 (without
that the feature was silently dead in the app's single-agent configuration);
per-turn think is refused loudly on prefix-busting families; the worker's
session is re-created at the requested ctx under `pool_mu` while idle; and the
sysprompt checkpoint is `sysprompt-<ctx>.kv`.

**Live-verified:** the cap appears only with the flag and the off-arm's `caps`
is byte-identical to pre-P23; an envelope asking `think=none` produced zero
think events; the N=1 parse is visible in the prefill accounting (61 tokens for
the extracted question vs 74 for the whole envelope as literal); and on a
2-worker pool the wire showed worker 0 at `ctx_size` 32768 with worker 1 at
8192, with `sysprompt-32768.kv` and `sysprompt-8192.kv` side by side.

## Three defects found in the plan, and how they were resolved

1. **`ThinkEffort.none` was an Optional collision.** `decide` takes a
   `ThinkEffort?`, and inside an Optional `.none` resolves to `Optional.none` —
   nil — silently. As written, `/quick` would have sent no override at all and
   been a no-op that still passed its own tests. The case is named **`off`**;
   the wire value stays `"none"`. A regression test pins both halves.
2. **The plan's Task 9 integration tests cannot compile.** They construct
   `AgentController`, but `SwiftStarIntegrationTests` depends only on
   `SwiftStarKit`/`SwiftStarAppKit` and `SwiftStar` is an `executableTarget`.
   Replaced with source-level assertions, the pattern part 1 established for
   exactly this constraint, each shown to fail by breaking the gate it pins.
3. **`TurnOutcomeBuilder(think:)` was used a task before it existed**, and the
   plan's `refused(reason:)` declaration disagreed with its own call sites.
   Both reconciled in favour of the documented interface.

## What Task 10 still needs

1. **Decide D11** (expose `ds4_session_common_prefix` as a wire query) *before*
   the recapture — adding it later costs a second one.
2. **Capture** a `think-override` fixture exercising the flag, and **re-capture
   `golden`** against the rebuilt binary (the standing rule: this bump changes
   engine code). Copy to `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}`.
3. **Fork-ledger row #14**, then bump the parent gitlink.
4. **Add `--per-turn-think` to `AgentCommand.argv`** in that same change, and
   the `CAPTURE_PER_TURN_THINK` knob to `swiftstar-drive`.
5. **Close the phase**: ROADMAP P23 row, and stamp the spec `implemented`
   (four recent specs are stuck at `proposed`; this should not become the
   fifth).

## Known unrelated issue

`serverErrorFailsCleanly` in `DownloadIntegrationTests` is flaky in full-suite
runs: it assumes the port below its test server's is closed so it gets
connection-refused, and another test's server can occupy it. It passed in the
final run here. Diagnosed in part 1 and already filed as a separate task; it
touches nothing in P23.
