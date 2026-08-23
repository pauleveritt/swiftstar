# SwiftStar P8 design: Skills

**Date:** 2026-08-22
**Status:** accepted by delegation (autonomous run).
**Phase:** P8 — Skills.

This spec is the authority on *how* P8 is done. `BRIEF.md` and `ROADMAP.md` stay
settled.

## Problem

The Agent tab (P7) ships a `ds4-agent` that can use file/shell tools but has no
skills: the Superpowers discipline (brainstorm, plan, test-first, review,
verification) is not available to it. P8 bootstraps the Superpowers skills into
the agent through `-sys`, prefilled once into `sysprompt.kv`, with progressive
disclosure — the index in the system prompt, the full skill bodies read on
demand inside the workspace grant.

`ROADMAP.md`: "The Superpowers bootstrap through `-sys`, prefilled once into
`sysprompt.kv`, with progressive disclosure." The P8 dependency bullet:
"Superpowers skills carry fallback wording for a harness without subagent
dispatch, so P8 does not wait on P11 — but it must never fabricate a dispatch
call."

## Gardenable facts (verified against the source)

- `ds4-agent -sys`/`--system` takes the system-prompt **text inline as an argv
  string** (`c.gen.system = need_arg(...)`, `ds4_agent.c:750`); there is no
  `@file` convention. A multi-KB index travels fine as one argv element
  (`Process.arguments` is not a shell, so no quoting issues).
- `sysprompt.kv` is already the fixed bootstrap checkpoint (`ds4_agent.c:5226`):
  the rendered system/tool prompt is compared with the cached text and a
  mismatch rebuilds and overwrites the file. Passing `-sys` is therefore all
  that is needed; the "prefilled once" is the engine's existing behavior. **No
  engine patch.**
- The agent's `read` tool (P7) is confined to the workspace grant. For an agent
  to disclose a skill it must `read` a file **inside** the workspace.

## Decisions

- **D1 — the bootstrap is a deterministic Swift-built index, passed via `-sys`.**
  `SuperpowersBootstrap` (SwiftStarKit) renders a compact system prompt: a short
  header ("You have Superpowers skills. Load one before the work it covers."),
  then one line per skill (`- <name>: <trigger> — <SKILL.md path>`), then the
  disclosure protocol ("To load a skill, `read` its SKILL.md inside the
  workspace."). Deterministic order (sorted by name), no skill *bodies* inlined.
  `AgentCommand` gains `systemPrompt: String?` → emits `-sys <text>` when set.
- **D2 — progressive disclosure via the agent's own `read` tool.** Full skills
  are staged into the workspace at spawn under `.swiftstar/skills/<name>/` (the
  whole skill directory, not just SKILL.md, so skills with supporting `.md`
  siblings work). The index never carries skill bodies.
- **D3 — skill staging is a pure copy.** `SkillStager` (SwiftStarAppKit) copies
  the skills tree from the resolved skills dir into the workspace at spawn. The
  dir resolves from env `SUPERPOWERS_SKILLS_DIR`, else the default
  `~/.pi/agent/git/github.com/obra/superpowers/skills`. A missing dir is a
  non-fatal degrade: the agent starts with the bootstrap still passed (the
  index names skills the agent cannot load — the bootstrap says "load with
  `read`", and the `read` will refuse a missing file, so no fabrication).
- **D4 — no engine patch; no new wire.** `sysprompt.kv` already rebuilds on
  mismatch. The fake agent's strict-argv validation must include `-sys` in the
  expected argv (the app always passes the bootstrap).
- **D5 — never fabricate a dispatch call.** The bootstrap text reflects the
  skills' fallback wording ("run this in your current session", never "spawn a
  subagent"); Swift emits no subagent-dispatch surface. Progressive disclosure
  is `read`, which the workspace grant already admits.

## Components

**SwiftStarKit:** `SuperpowersBootstrap.swift` — builds the index prompt from a
skills dir (pure, deterministic). `AgentCommand.swift` — `AgentSettings` gains
`systemPrompt: String?`; argv emits `-sys <text>` after `--shell`.

**SwiftStarAppKit:** `SkillStager.swift` — copies the skills tree into
`<workspace>/.swiftstar/skills/` (recursive, plain `FileManager` copy).

**SwiftStar:** `AgentController` — resolves the skills dir, stages into the
workspace at spawn, passes `SuperpowersBootstrap` via `-sys` in settings. The
fake agent template (P7) already validates the exact argv, so its integration
tests regenerate the same bootstrap text.

## Testing

- **Fast tier:** `SuperpowersBootstrap` deterministic (same input → same text);
  index contains all expected skill names; `AgentCommand.argv` includes
  `-sys` + the text when `systemPrompt` set, and the ordering is pinned.
- **Integration tier:** `SkillStager` copies the tree into a temp workspace
  (SKILL.md files present, readable); the fake agent is generated with the
  bootstrap in its expected argv and validates it.
- **Evidence floor:** the bootstrap names every skill; the staged workspace
  contains the skills the index points at.

## Out of scope

Skill *execution* (dispatch) — P11. A `recall`/session browser — backlog.
Anything requiring an engine change — D4 says none.
