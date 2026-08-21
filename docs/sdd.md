# How work happens here

Spec-driven development, one phase at a time.

## The cycle

1. **Brainstorm** the phase, treating `BRIEF.md` and the phase list as settled.
   Brainstorm *within* a phase; do not reopen the architecture.
2. **Spec** — a design document committed to
   `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
3. **Plan** — an implementation plan committed to
   `docs/superpowers/plans/YYYY-MM-DD-<topic>.md`, task by task, each task
   naming the files it touches and the test that proves it.
4. **Execute** the plan, test-first.
5. **Review**, then close the phase in `ROADMAP.md`.

Research that informs a decision but is not itself a design goes in
`docs/superpowers/research/`.

## What the record is for

The trail is kept **as it was written**, including withdrawn framings and
corrected numbers. A retraction is recorded next to what it retracts, not
edited away. Both predecessor projects did this and both found it was the part
that paid off later — a decision you can see being reversed is one you do not
re-litigate from scratch.

## Test tiers

- **Fast** (`just test`) — `SwiftStarKit` against fixtures. No model, no
  network, no subprocess, enforced by a tripwire that fails the build.
- **Integration** — real processes and files against fake engine binaries
  generated from committed captures.
- **Live** (`just capture`) — the real engine and real weights. Minutes to run,
  never in CI.

## Standing rules

Every rule in `BRIEF.md`'s "Binding rules" applies to every phase. The two
easiest to forget:

- **Every new test must be shown to fail** when the behavior it pins is broken.
  Break it, watch it fail, restore it.
- **Every submodule bump owes a golden-fixture recapture** against the real
  binary. A rebase can apply cleanly and still be semantically wrong.
