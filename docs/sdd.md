# How work happens here

Spec-driven development, one cycle at a time, with the paperwork sized to
the change.

## The cycle

1. **Brainstorm** within a phase. `BRIEF.md` is settled; don't reopen the
   architecture inside a cycle.
2. **Write it down, sized to the change.**
   - **A small cycle** changes under about 200 code lines and needs no
     decision from the owner. It gets one doc,
     `docs/superpowers/plans/YYYY-MM-DD-<cycle>.md`, with `## Decisions`,
     `## Tasks` and `## Result`.
   - **A larger or decision-bearing cycle** gets a spec the owner accepts,
     `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`, and then a plan.

   **What a plan contains.** Per task: the files it touches (`path:line`
   for changes), the interfaces it produces (signatures only), and the test
   that proves it (the test's name and its assertion, one line each). It
   doesn't paste bodies. This overrides `superpowers:writing-plans`' "No
   Placeholders" rule: a test name plus its assertion is not a placeholder.
   A plan stays under 400 lines; split the cycle if it won't.
3. **Execute** test-first.
4. **Close.** The plan gains `## Result`: its commits, what diverged and
   what was descoped. The ROADMAP row shrinks to one line, anything a user
   would notice gets a short line in [`CHANGELOG.md`](../CHANGELOG.md)
   under Unreleased, and `just lint-docs` passes. Fold all of that into the last task's commit.
   There are no separate "Task N done" or "close" commits.

**Research docs are optional.** An audit or investigation is an appendix to
the spec it serves. It gets its own file in `docs/superpowers/research/`
only when it spans cycles.

## What the record is for

Decisions are kept as written. A retraction sits next to what it retracts,
as a dated `## Revision` section or a "Corrected" note; it is not edited
away. A decision you can see being reversed is one nobody re-litigates from
scratch.

The record lives in git, not all of it in the tree. `docs/history.md`
names the tags that hold docs removed from the tree.

## Test tiers

- **Fast** (`just test`): `SwiftStarKit` against fixtures. No model, no
  network, no subprocess. A grep in `just test` refuses `Process(`,
  `URLSession` and friends in `Tests/SwiftStarKitTests`.
- **Integration** (`just integration`): real processes and files, against
  the fake `ds4-dogfood` that replays committed `--ndjson` fixtures.
- **Live** (`just capture SCENARIO`): the real engine with real weights.
  Takes minutes.

There is no CI. Every tier is run by hand.

## The ROADMAP

- **`## Now` is a pointer.** One line each for what's next, what follows,
  and what's blocked, linking the row or Backlog entry that holds the
  detail. It never re-narrates a decision.
- **One table per named phase,** one row per cycle.
  - Direction is one sentence, at most 300 characters.
  - Status is state, date and links, at most 400 characters. A cell that
    wants more owes a doc it can link to.
  - A closed row shrinks to one line with links; the narrative is the
    plan's `## Result`.
- **New initiatives open a named phase** with a short mnemonic, numbered
  `<Name>.1`, `<Name>.2` and so on, matching ds4-engine's convention.
  - `EN` is the engine contract: one cycle per ds4-engine landing that
    SwiftStar catches up to.
  - `SU` is SwiftUI.
  - `AN` is Analyze: reading session telemetry, on its way into ds4-engine.
  - Phase `P` (P0–P32) is closed; see `docs/history.md`.

`just lint-docs` checks the cell caps and the plans' line limit. The
pre-commit hook runs it once `just install-hooks` has been run, once per
clone.

## Standing rules

Every rule in `BRIEF.md`'s "Binding rules" applies to every cycle. The three
easiest to forget:

- **Every new test must be shown to fail** when the behavior it pins is
  broken. Break it, watch it fail, restore it.
- **Every ds4-engine change that reaches the wire owes a fixture
  recapture.** That includes payload changes the relay forwards untouched:
  an unchanged relay file is not an unchanged wire (the 2026-10-13 audit,
  §1).
- **Closing a cycle updates `ROADMAP.md` and passes `just lint-docs`** before
  the work counts as done, whether merged, PR'd or handed off. This is the
  one home of that rule; `CLAUDE.md` points here.
