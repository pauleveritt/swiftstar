# Agent instructions for this repository

This project runs spec-driven development — see [`docs/sdd.md`](docs/sdd.md)
for the full cycle (brainstorm → spec → plan → execute → review/close) and
[`BRIEF.md`](BRIEF.md) for the settled design. Read both before planning
non-trivial work here.

## Session telemetry

When asked what happened in a session (model used, timing, tokens, tool
calls), read `.claude/skills/telemetry/SKILL.md` first — it documents the
`swiftstar-analyze` CLI and the `captures/` layout. Do not go hunting
elsewhere for a "telemetry" tool.

## Finishing a branch

When using `superpowers:finishing-a-development-branch` (or otherwise
concluding work that closes a phase or feature cycle) in this repository,
**before presenting the finish menu**:

1. Update [`ROADMAP.md`](ROADMAP.md) — the phase's Status cell (and Direction,
   if it changed), the `## Now` pointer if what's in flight changed, and any
   Backlog entry the work resolves or reopens.
2. Run `just lint-docs` and fix any violation before proceeding. A phase
   whose row is stale, or whose cell exceeds the caps in `docs/sdd.md`, is not
   closed. This is also enforced by a pre-commit hook (`just install-hooks`
   wires it up once per clone); do not rely on the hook alone — it runs
   `set -e` and expects `just` on `PATH`, and `--no-verify` bypasses it
   silently.

This is a standing rule, not a suggestion the human partner has to repeat
each time — see `docs/sdd.md`'s "Standing rules" section.
