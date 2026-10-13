# Agent instructions for this repository

This project runs spec-driven development, sized to the change. See
[`docs/sdd.md`](docs/sdd.md) for the cycle and [`BRIEF.md`](BRIEF.md) for the
settled design, and read both before planning non-trivial work here.

## Finishing a branch

Before finishing work that closes a cycle, including through
`superpowers:finishing-a-development-branch`, do `docs/sdd.md`'s close step:
- update [`ROADMAP.md`](ROADMAP.md)
- pass `just lint-docs`

The pre-commit hook can be skipped, so don't rely on it.

## UI work

A change to anything under `Sources/SwiftStarUI/` is not done until every
`#Preview` it touches has been rendered with Xcode's `RenderPreview` tool and
the image looked at, and both test tiers (`just test`, `just integration`) are
green. The project skill `ui-loop` (`.claude/skills/ui-loop/SKILL.md`) has the
scheme, paths, fixture rules and known limits; load it before UI work.
