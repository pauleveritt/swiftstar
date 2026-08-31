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

   **Plans — local rule, overriding `superpowers:writing-plans`.** A plan
   names per task: files touched (`path:line` for modifications), interfaces
   produced (signatures only), and the test that proves it (test name + the
   assertion, one line each). It does not paste bodies. That skill's "No
   Placeholders" section requires full code blocks; it serves a stateless
   subagent executor and is **not in force here** — a test name plus its
   assertion is not a placeholder. Ceiling: under 400 lines, under 25%
   fenced. Over either, split the phase. Plans written before this local rule
   are retained in `docs/superpowers/plans/archive/` as legacy records; they
   are not rewritten by automation. Current plans stay directly under
   `docs/superpowers/plans/` and must carry the rule's metadata.
4. **Execute** the plan, test-first.
5. **Review**, then close the phase in `ROADMAP.md`.

   **Close the plan.** At phase close the plan gains a `## Result` section
   (commits, what diverged, what descoped), and every fence over 15 lines is
   replaced by a `path:line` reference to what shipped. "Kept as it was
   written," below, governs the *decision* record (`specs/`, `research/`). A
   plan is a build instruction; its history is in git.

   **Closing a phase (or a branch that closes one) is not done until
   `ROADMAP.md` is updated and `just lint-docs` is green.** Both are part of
   the close, not optional follow-up — a phase whose row is stale, or whose
   cell blew the cap, is not closed. This is a standing rule regardless of
   which skill or workflow drives the finish (see "Standing rules" below).

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

## The phase table

`ROADMAP.md`'s Status column is a status: state, date, key facts, links.
Direction stays one sentence. A Direction cell exceeding 900 characters, or
a Status cell exceeding 1,000, means a verdict doc is owed — move the
narrative to `docs/superpowers/research/`, link it, and let the cell shrink
back down. Applies at every update, not just at close: a cell growing
mid-phase is the signal a verdict doc is owed *now*, not at the next
milestone.

These caps are calibrated against this project's own post-cleanup ROADMAP,
not chosen in the abstract — the first version used a uniform 300-character
cap on every cell, which nobody checked before writing it down: even P20's
row, the cited example of "already short," failed it by roughly 7x. If
`just lint-docs` starts failing pervasively again, recalibrate against real
content before assuming every row regressed.

Enforced mechanically by `just lint-docs`, checking phase-table cell length
and current-scope plan metadata, fenced-code fraction, fence length, and line
count. A written convention that nothing checks gets ignored under deadline
pressure — this project has already proven that twice on two different rules
(see `ROADMAP.md`'s Backlog, "eval-system consolidation" and the P26
schema-freeze note) — so the gate exists precisely because prose alone did
not hold. The 2026-08-29 policy change deliberately left earlier plans
untouched; this scope rule makes that decision explicit instead of printing
historical debt as if it were a current-plan regression. The archive index
explains the retained legacy records and points readers to current authority.

Plans in the current lint scope carry YAML front matter with `phase`, `cycle`,
and `lifecycle` (`active`, `closed`, or `superseded`). Closed and superseded
plans must have `## Result`; active plans must not claim a result in advance.

**A phase with more than one feature cycle (P12, P24, …) uses a numbered
list inside the relevant cell(s)** — Phase, Direction, and/or Status — one
item per cycle, each linking its own spec/plan/research docs and carrying its
own one-line status. This keeps the phase as one table row (no nested
sub-table) while still giving each cycle a distinct, linkable status instead
of one run-on paragraph. The cell-length caps above still apply to the whole
cell — a cycle whose item is still too long owes the same verdict-doc move.

**`## Now` is a pointer, not a narrative.** It names what is currently in
flight, what is parked and why (one line each), and links to the phase row
or Backlog entry that carries the actual detail. It must never re-narrate a
decision that already has a home in the phase table or the Backlog — that is
how it grew into a second, undated history of the project the first time.
Update it when what's in flight changes; if an item needs more than a
sentence, that sentence belongs in the phase row or Backlog entry it points
to, not in `Now` itself.

## Standing rules

Every rule in `BRIEF.md`'s "Binding rules" applies to every phase. The two
easiest to forget:

- **Every new test must be shown to fail** when the behavior it pins is broken.
  Break it, watch it fail, restore it.
- **Every submodule bump owes a golden-fixture recapture** against the real
  binary. A rebase can apply cleanly and still be semantically wrong.
- **Finishing a branch that closes a phase or feature cycle updates
  `ROADMAP.md` and passes `just lint-docs`, before the branch is considered
  done** — merged, PR'd, or otherwise handed off. This is enforced two ways,
  not left to memory: a git hook runs `just lint-docs` on commit, and the
  project's `CLAUDE.md` states the same rule for the agent driving the finish.
  A closed phase with a stale row is not closed.
