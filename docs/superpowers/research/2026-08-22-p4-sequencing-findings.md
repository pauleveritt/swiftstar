# P4 sequencing findings (2026-08-22)

Research note: where Phase P4 ("It shows what the machine is doing") gets its
data, and whether its place in `ROADMAP.md` is sound. Research, not design —
the design spec for P4 is a later artifact. **This note was reviewed by GLM 5.2
and corrected; the retraction is recorded below, not edited away.**

## The finding

P4 leads with **absolute `ctx_used` and prefill throughput**, per the roadmap's
own direction and the telemetry harvest. Those two numbers exist only on the
`ds4-agent --json-events` wire, which the app does not yet drive (that is P7).
So the phase that leads with `ctx_used` is scheduled before the process that
emits it.

## Verified facts

**F1 — the telemetry already exists, on the agent wire.** The `ds4-agent
--json-events` `status` event carries `state`, `prefill_done`, `prefill_total`,
`prefill_tps`, `generated`, `gen_tps`, `ctx_used`, `ctx_size`, `power`, `error`
— throttled to at most once per 200 ms, emitted immediately on state change,
exact-repeat deduped. The `ready` event carries the session memory budget
(`kv_bytes`, `scratch_bytes`, `model_bytes`, `planned_bytes`). Both landed in
the fork at P1 (fork-ledger divergences #4 and #5). Source:
`external/ds4/docs/json-events.md`.

**F2 — the chat wire carries none of it.** The `ds4-server` SSE wire (what the
app drives from P2) carries only `id`, `created`, `model`, and
`role`/`reasoning_content`/`content`/`finish_reason`. No `ctx_used`, no tps, no
memory/GPU/CPU/power. `SSEParser.swift` confirms it handles nothing else.
Source: `fixtures/server/golden.sse` + `Sources/SwiftStarKit/SSEParser.swift`.

**F3 — the rate dial needs no client-side timing.** The engine computes and
carries `prefill_tps`/`gen_tps` in the `status` event. The "never both
non-zero, ratchet the last value" wire fact is about those carried values, not
about values derived from receive times. (Contrast the chat wire, where rate
must be derived from the `created` epoch field.)

**F4 — P4's fixture source already exists, and it carries the telemetry.**
`fixtures/agent/golden.ndjson` (committed at P1) is a verbatim capture of
`ds4-agent --json-events` stdout containing **1053 `status` events and 7
`ready` events** — `ctx_used`, `prefill_tps`, `gen_tps`, `ctx_size`, `power`,
and the memory budget. *Retraction: an earlier draft of this note claimed "the
only committed fixtures are chat SSE with no telemetry." That was wrong — the
agent capture was committed alongside the SSE captures at P1 and carries
exactly the telemetry P4 leads with. Corrected 2026-08-22 after GLM 5.2
review, verified by counting event types in the fixture.*

**F5 — the predecessor proved the pattern.** `ds4-control`'s headless capture
driver composed the production types against real `ds4-agent --json-events`
and produced genuine telemetry. It was a throwaway test file that was lost
twice. The harvested lesson is that this capability must be a committed
production component. Source: `docs/harvest/capture-driver.md`.

## Conclusion (corrected)

P4 has a **fixture source today** (`golden.ndjson`). What it lacks is a
**live** data source: the app's engine process is `ds4-server` (chat SSE, no
telemetry), and the telemetry-emitting `ds4-agent` is P7 — a tool-executing
agent whose safety surface (workspace grant, shell toggle) lands in P7, and
which cannot run beside `ds4-server` (two ~48 GiB model loads). P4 therefore
ships **fixture-driven** — parser and widgets built and tested against
`golden.ndjson` — with live wiring deferred to P7's `ds4-agent` migration. The
original claim that P4 was unschedulable was withdrawn: it rested on the
incorrect F4.

## Recommended sequencing (corrected)

1. **Keep the phase order.** P4 stays where it is; no re-sequencing is needed.
2. **P4's scope**: the NDJSON `status`/`ready` parser plus the metrics widgets,
   built and tested against `fixtures/agent/golden.ndjson` in the fast tier —
   no engine, no model, no subprocess. The live engine stays `ds4-server` for
   chat.
3. **P4 must not spawn `ds4-agent` live.** That would enable a tool-executing
   agent before its safety guards (P7's workspace grant, shell toggle) exist,
   and it would rewrite the chat path from SSE to NDJSON while also losing the
   chat wire's `created` timing field.
4. **P7 owns the live wiring.** The `ds4-agent` migration lands there; the
   metrics tab lights up from the live `status`/`ready` stream, behind a
   telemetry-provider seam so the fixture-driven path (P4) is a drop-in for
   the live path (P7) rather than a rewrite. How the shipped app presents
   fixture-replayed vs. live numbers (and avoids presenting recorded values as
   live) is an open P4-spec question.

## Withdrawn: the three-move re-sequencing

The original recommendation was a three-move re-sequencing — re-anchor P4 to
the agent wire (kept), pull P5's capture program and P7's NDJSON-parser slice
ahead of P4, and migrate the app's single engine to `ds4-agent --json-events`
before P4. The migration move is withdrawn: it was motivated by the false
belief that P4 had no fixture (F4 as originally written), and it would have
enabled a tool-executing agent before its safety guards exist, at the cost of
rewriting the chat path. The capture-program pull is also dropped — the fixture
already exists, so P4 needs no new capture. The only surviving piece is the
correct, narrow point that P4's data model should be the agent `status`/`ready`
wire (not chat SSE), which the parser can already be built against today.

## GLM 5.2 review (recorded)

Two rounds, via OpenRouter `z-ai/glm-5.2`. Round 1 was an adversarial review of
the original finding against the wire-format spec and the roadmap; it caught
the F4 error (the P1 NDJSON capture exists) and challenged the engine
migration as over-reach with a safety cost. Round 2 delivered the verdict on
the corrected facts.

**Verdict: reject as-is; accept with amendments.**

1. **Strike F4.** The claim that "the only committed fixtures are chat SSE with
   no telemetry" is factually wrong. `fixtures/agent/golden.ndjson` is the
   canonical P4 telemetry source. *(Verified against the repo: 1053 `status`,
   7 `ready`, plus `text`/`think`/`tool`.)*
2. **Amend P4's objective** from "wire to live telemetry" to "telemetry UI and
   state management driven by fixture replay."
3. **Add a safety constraint:** P4 must not instantiate the live `ds4-agent`
   engine — doing so bypasses P7's workspace grant and shell toggle.
4. **Update the dependency mapping:** live `ds4-agent` telemetry wiring is
   strictly a P7 dependency.

GLM's suggested shape — a telemetry-provider seam (fixture replay in P4, a live
`ds4-agent` provider swapped in at P7) — is recorded as the recommended
direction, not as a committed interface; the naming is P4 spec material.

All four amendments are accepted. The only point not carried verbatim is the
"splice replayed telemetry into the live app alongside `ds4-server` chat"
detail — whether the shipped app shows replayed numbers at all is left as an
open P4-spec question, because presenting recorded values as live would
mislead.
