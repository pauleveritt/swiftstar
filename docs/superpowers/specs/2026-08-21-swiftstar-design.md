# SwiftStar: design

**Date:** 2026-08-21
**Status:** approved; supersedes nothing, initiates the project.

This spec records the design session that produced `BRIEF.md` and `ROADMAP.md`,
including the alternatives rejected and the adversarial review that corrected
two of them. `BRIEF.md` is the authority on the design; this document is the
authority on *why* it is that design.

## Problem

DS4 Control — a working macOS menu-bar control pane for a local DeepSeek V4 /
Laguna S 2.1 engine — has outgrown its shape in four ways at once: the surfaces
are window-sized rather than popup-sized; settings want a platform `Settings`
scene; the single target cannot be tested at its seams, which is why three of
its test files assert on source text; and a live measurement arrived that
reframes what the product is for.

## Decisions

Each decision names the alternatives and the reason.

### D1 — Engine integration: spawned child processes

**Chosen:** SwiftStar never links the engine. It spawns `ds4-server` (SSE) and
`ds4-agent` (NDJSON on stdout) and supervises them.

**Rejected:** embedding the engine in-process, as argued at length in
`SWIFTSTAR.md`. Reviewed adversarially; the capabilities embedding was to
unlock are reachable across the wire with additive C patches, and its
irreducible advantages — dynamic Swift-defined per-token logit masking,
zero-copy logits — are off the critical path. Embedding would additionally put
a Metal abort inside the GUI process and destroy per-pid memory attribution.

**Also rejected:** a phased "supervised now, embedded later behind a seam."
Rejected because the review showed the interesting capability question is not
the process boundary at all — see D2 — so the phased option would have
scheduled the wrong gate.

Full reasoning: [`docs/harvest/swiftstar-md.md`](../../harvest/swiftstar-md.md).

### D2 — Tool-execution ownership: bidirectional, scheduled at P9

**Chosen:** observation-only wire through P8; a tool-callback protocol at P9.

This was answered *silently* in the first draft, and the adversarial review is
what surfaced it. On an observation-only wire the C child executes tools and
inserts results into context before the app sees anything, which forecloses
condensation before KV entry, intra-turn tool parallelism, per-tool consent, and
both isolation items in the Backlog.

**Rejected:** observation-only permanently (deletes the best mitigation for the
measured 7x tax and two Backlog items requested the same day), and bidirectional
from phase one (a protocol design before there is an app to justify it).

**The cost that must not be discovered inside P9:** a bidirectional wire needs a
fake *app* side, not just a fake engine side.

### D3 — App shape: regular windowed app, no menu-bar presence

**Chosen:** dock icon, one main window with five tabs, a `Settings` scene.

**Rejected:** menu-bar-first (fights the Settings scene and keeps the
activation-policy hack), and regular-app-plus-menu-bar-extra (the glance is
genuinely useful, but the owner declined the surface).

Consequence: `WindowChrome`'s activation-policy switching has no analogue here.
It existed only to force windows into an `.accessory` app.

### D4 — Chat and Agent are separate tabs

Different wires, different consent models, different products. Merging them
would put two wire formats and two consent models in one view.

### D5 — Clean-room policy: gardened

Code does not cross; facts cross with a citation and a fresh test; tests do not
cross, because a transplanted test pins the old shape. The engine's own C work
is the exception, and it is not really one — it is the same codebase reached
through a submodule.

**Rejected:** strict clean-room (re-earns incidents), and gardened-plus-test-
transplant (drags the old API surface into a rewrite whose point is to change
it).

### D6 — Diagnostics computes deterministically; the model phrases

**Rejected:** model-authored analysis (a small local model doing quantitative
reasoning over its own instrumentation produces fluent, plausible,
unfalsifiable prose — and does it at exactly the moment the user is complaining
about speed), and deterministic-only (trustworthy, least useful).

Grounded in the recorded `local-ai-pi` result that facts work and rules of
conduct do not.

### D7 — Three targets

`SwiftStarKit` (framework-free), `SwiftStar` (the app), `swiftstar-drive` (a
committed capture executable). The rule that keeps it honest: a test that wants
to assert on source text is a report that a module boundary is missing.

### D8 — The fork: one shipped integration branch

**Corrected by review.** The first draft said both "per-model integration
branches" and "the submodule pins one SHA," which cannot both be true. Resolved
to: a patch set, one shipped integration branch that the submodule pins, and
per-model development branches the app never pins.

**Also corrected:** "strictly additive" was a description; it is a goal. The
patches instrument existing decode loops and emitters, so a rebase can apply
cleanly and be semantically wrong. Mandatory golden-fixture recapture on every
submodule bump is the mitigation.

### D9 — Testing: three tiers, mechanically enforced

Two wires means **two** golden captures at P1 — SSE from `ds4-server`, NDJSON
from `ds4-agent` — because an agent capture cannot generate a chat fake. P1's
captures are taken with a throwaway script since `swiftstar-drive` arrives at
P5; from P5 onward the drive executable is the only sanctioned fixture source.


Fast (no model/network/subprocess, tripwire-enforced), integration (real
processes, generated fakes), live (`swiftstar-drive`, never CI).

**Corrected by review:** fakes are generated from committed golden captures and
validate argv strictly, because a hand-authored fake and its parser drift
*together* when the emitter changes, with every test passing. An engine-side
`--null-model` mode is the honest fix and is Backlogged as upstream-bound.

### D10 — Wire hardening, binding from P5

A version/capability handshake as the first NDJSON line, and timestamps on the
wire. **Both require the engine patch that lands at P5**, so a parser written at
P2 must tolerate their absence; `BRIEF.md`'s binding rule 7 is annotated to say
so. Before P5 the wire is exactly what P1's captures contain. `DS4_DIR` lets the app be pointed at any engine build, and the parser's
forward-compatible ignore-unknown fallback means a skewed wire otherwise
degrades silently.

### D11 — Python for docs only

Sphinx + MyST + Furo through `uv`, scaffolded at P0, with the site itself as
P13. No Python runtime role. "Swift body, Python brain" is Backlogged with a
condition.

## The finding that shapes the product

See [`docs/harvest/telemetry-findings.md`](../../harvest/telemetry-findings.md).
Prefill throughput degrades ~7x with accumulated context, compute-bound at 98%
GPU utilization, distinct from a prefix cache that stays healthy. It makes
context the dial with a real cost curve, gives diagnostics a concrete first job,
and turns anything that keeps context small into a performance feature.

Its two limits travel with it: compaction was never observed at the everyday ctx
150,000 setting, and captures were taken on an idle machine over short sessions.

## Review

Reviewed adversarially by Fable on 2026-08-21 against the four grounding
documents and `SWIFTSTAR.md`. Verdict: keep the process seam. Three findings
were accepted and changed the design — D2 (tool-execution ownership was answered
silently), D8 (the fork scheme was incoherent as stated, and "strictly additive"
was false), and D9 (fake co-drift). Four were accepted as hardening: the version
handshake, wire timestamps, argv-strict fakes, and recapture tied to submodule
bumps.

One reviewer statement was incorrect and is recorded rather than quietly
dropped: the capture driver was described as committed. It is not, and never has
been — which is the reason
[`docs/harvest/capture-driver.md`](../../harvest/capture-driver.md) exists.

## Open questions, deliberately not answered here

- **P1's merge shape.** Absorbing `notatestuser`'s patches and the local
  `paul/laguna` work into one integration branch has real conflicts. The plan
  decides the order; this spec does not.
- **Where the `Variant` abstraction lives** once more than one model line ships.
  P12's problem.
- **What a capture fixture set must cover** to keep the analyzer honest, given
  that compaction at 150,000 ctx has never been observed. P5 and P6.
