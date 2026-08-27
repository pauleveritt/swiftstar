# Pi harness: Context7 and Superpowers integration (2026-08-27)

**Single record for the session that researched how Context7 is installed and
invoked in the Pi coding agent, how Superpowers was translated into Pi, and
what the real context cost of each is.** This concerns the team's *development
harness* (the Pi agent we do our own work in), not the swiftstar app — it is
the "how we work" layer, parked next to the app's own research because this
repo is where that layer lives.

**One-line findings:**

- **Context7 on Pi is already the right shape:** two natively registered tools
  (`resolve-library-id`, `query-docs`) plus a progressive-disclosure skill. It
  is *lazy* — it costs ~160 tokens of description in the system prompt and
  nothing else until a library question matches. No bootstrap, no forced load.
- **Superpowers on Pi is the outlier:** `.pi/extensions/superpowers.ts`
  force-injects a ~1.1k-token bootstrap into the first agent run of every
  session (and again after each compaction). That is redundant with its own
  discoverable skill description, and it is the only expensive, non-Pi-native
  piece.
- **Measured always-on cost:** ~700 tokens of skill descriptions in the system
  prompt, every prompt. The bootstrap is *transient* (never persisted —
  verified against all 40 stored session files), so it is **not** paid on every
  prompt, only at session start / post-compaction.
- **The Pi-native move is "lazy Superpowers":** drop the bootstrap, trim the
  skill surface, and specialize via per-project package filtering — not
  multi-session "specialist agents."

---

## 1. How Context7 is installed and invoked on Pi

### Install

```bash
pi install npm:@upstash/context7-pi
```

Writes `"npm:@upstash/context7-pi"` into the `packages` array of
`~/.pi/agent/settings.json`; the package lands in
`~/.pi/agent/npm/node_modules/@upstash/context7-pi/`.

### Package manifest (`package.json`)

```json
"pi": {
  "extensions": ["./extensions"],
  "skills": ["./skills"],
  "prompts": ["./prompts"]
}
```

Peer deps `@earendil-works/pi-coding-agent` and `typebox` (both bundled by Pi).

### What each piece does

| Path | Role |
|------|------|
| `extensions/context7.ts` | 3-line entry point: `pi.registerTool(resolveLibraryIdTool); pi.registerTool(queryDocsTool)`. **No event hooks, no injection.** |
| `lib/tools/resolve-library-id.ts` | Tool 1: name → Context7 library ID (`/org/project`). TypeBox schema. |
| `lib/tools/query-docs.ts` | Tool 2: fetch docs for a library ID. TypeBox schema. |
| `lib/api.ts` | Plain `fetch` against `https://context7.com/api/v2/libs/search` and `/v2/context`; auth via `CONTEXT7_API_KEY` env (optional — IP-based rate limit without it). Adapted from `@upstash/context7-mcp`, kept minimal (no proxy/CA handling). |
| `lib/prompts.ts` | Tool + parameter descriptions — **copied verbatim from `@upstash/context7-mcp`** so pi and MCP clients give the LLM identical instructions. |
| `lib/format.ts`, `lib/types.ts` | Copied verbatim from MCP to keep wire format/output identical. |
| `lib/result.ts` | Adapts text output to Pi's `AgentToolResult` (`{ content: [{type:"text",text}], details: undefined }`). |
| `skills/context7-docs/SKILL.md` | The "when to use it" instruction layer. Frontmatter `description` is always in the system prompt; the body (resolve→query→answer workflow, ≤3 calls, no secrets in queries) loads on demand. |
| `prompts/c7-docs.md` | Registers `/c7-docs <library> <question>` — one-shot resolve+query. |

### How it actually gets used (it is not magic)

1. The two tools are registered and always callable; the skill's `description`
   is always in the system prompt ("Use whenever the user asks about a specific
   library… Use even when you think you know the answer…").
2. On a matching question, the agent reads `SKILL.md`, then calls
   `resolve-library-id` → `query-docs`. This is the intended "automatic" path.
3. Explicit overrides: `/skill:context7-docs`, `/c7-docs <lib> <question>`, or
   saying "use Context7" in prose.
4. It will **not** fire for questions that mention no library, and the model
   can still answer from training data despite the description's persuasion —
   descriptions bias, they don't enforce.

Key contrast: Context7 has **no `context`-event injection** (the file is three
lines of `registerTool`). It is lazy by design — Pi's native skill model
(progressive disclosure: descriptions always, bodies on demand) is exactly what
Context7 relies on.

### How OpenCode does it (for contrast)

Not MCP, not the Pi extension: the **`ctx7` CLI**, driven by an AGENTS.md skill
instruction at `~/.config/opencode-thursday/AGENTS.md`:

```
1. npx ctx7@latest library <name> "<user's question>"
2. npx ctx7@latest docs <libraryId> "<user's question>"
```

No MCP server or plugin entry exists in `~/.config/opencode/opencode.jsonc`.
The canonical MCP server (`@upstash/context7-mcp`) is the reference the Pi
package copies its lib from; OpenCode *could* consume it via its native MCP
support, but the machine's OpenCode config does not — it shells out to `ctx7`.

---

## 2. How Superpowers was translated into Pi (the reference pattern)

### Install

```bash
pi install git:github.com/obra/superpowers
```

Cloned to `~/.pi/agent/git/github.com/obra/superpowers/` (settings entry:
`git:github.com/obra/superpowers`). Manifest:

```json
"pi": {
  "extensions": ["./.pi/extensions/superpowers.ts"],
  "skills": ["./skills"]
}
```

### The translation glue (`.pi/extensions/superpowers.ts`)

Three mechanisms, all harness-specific:

1. **`resources_discover`** → returns `{ skillPaths: [skillsDir] }` so Pi
   discovers the 14 skills.
2. **`context` event** → injects the `using-superpowers` skill body (frontmatter
   stripped) + a "Pi tool mapping" section as a **user message** wrapped in
   `<EXTREMELY_IMPORTANT>`, once per session. Flag lifecycle: `true` on
   `session_start` and `session_compact`, `false` on `agent_end`; a
   marker-dedupe guard prevents double injection.
3. **Tool mapping** — because skills speak in tool-agnostic verbs, the injected
   text maps Claude Code tools → Pi tools (no `Skill` tool → `read`
   SKILL.md or `/skill:name`; no subagent tool → inline; `TodoWrite` → plan
   files / `TODO.md`).

The same core skills ship per-harness adapters: `.claude-plugin/plugin.json` +
`marketplace.json`, `.codex-plugin/plugin.json`, `.opencode/plugins/superpowers.js`
(config hook to register the skills dir + message-transform to inject the
bootstrap + OpenCode tool mapping). The skills themselves are harness-agnostic
(Agent Skills standard); only the glue and the tool mapping differ.

---

## 3. Measured context cost

Measured from the real files and from all stored Pi sessions on this machine.

### Always-on: skill descriptions in the system prompt (~700 tokens, every prompt)

| Component | chars | ~tokens |
|---|---|---|
| 14 Superpowers skill descriptions | 1,861 | ~465 |
| context7-docs description | ~640 | ~160 |
| XML / formatting overhead | ~300 | ~80 |
| **Total** | | **~700** |

This is the progressive-disclosure metadata. It scales with **count** of
skills, not size of bodies. (Note: some Superpowers descriptions are verbose —
`receiving-code-review` 234 chars, `verification-before-completion` 225,
`brainstorming` 198, `using-git-worktrees` 196 — and trim easily.)

### Session-start: the bootstrap (~1,100 tokens, first run only)

| Piece | chars | ~tokens |
|---|---|---|
| `using-superpowers` SKILL.md body | 2,878 | ~720 |
| Pi tool mapping section | 1,146 | ~290 |
| wrapper | ~100 | ~100 |
| **Total** | | **~1,100** |

**Persistence verified:** the bootstrap is injected via the `context` event,
which per Pi docs modifies messages *non-destructively* (not persisted). Search
of all 40 session files under `~/.pi/agent/sessions/` for the bootstrap marker
(`superpowers:using-superpowers bootstrap` / `EXTREMELY_IMPORTANT`) found the
marker in **zero** of them (the only hit was this session's own quotes of the
extension source). So it is transient per-LLM-call, present while
`injectBootstrap` is true — i.e. during the **first agent run** of a session
and again **after each compaction**, not on every prompt.

### On-demand: skill bodies (zero unless read)

`brainstorming` (15 KB), `subagent-driven-development` (32 KB),
`writing-skills` (26 KB), etc. are loaded via `read` only when relevant.

### What that means on small windows

| Window | Descriptions (always) | + Bootstrap (first run only) |
|---|---|---|
| 32K | ~2.2% | ~5.6% peak |
| 16K | ~4.4% | ~11% peak |
| 8K | ~8.8% | ~22% peak |

On 32K+ it is noise; at 8–16K it is a real tax — and the bootstrap is
**redundant**, because `using-superpowers` is already in the skill list with
its description, so the model can find and read it on demand. The bootstrap
exists to force-feed a Claude-Code-ism ("methodology always loaded"); Context7
deliberately does not do this, and it works.

---

## 4. Options, Pi-first

1. **Drop the bootstrap — make Superpowers lazy, the Pi way.** Remove the
   `context` injection from the extension. Cost: −~1,100 tokens in the first
   run; Superpowers becomes "available methodology" (description → read on
   demand) instead of "always-on methodology." The only loss is the forced
   "brainstorm first" push on turn 1. This is the Context7 pattern.
2. **Trim the skill surface (~300–400 tokens, risk-free).** Delete unused
   skills from the package (`writing-skills`, `dispatching-parallel-agents`,
   `using-git-worktrees` if inapplicable) and shorten verbose descriptions.
3. **`disable-model-invocation: true` for human-gated skills.** Removes them
   from the system prompt entirely (no description cost, no auto-trigger);
   load only via `/skill:name`. Caveat: editing the cloned git package is
   fragile — `pi update` resets/cleans git-package clones on ref reconcile,
   so this belongs in a fork or a local wrapper package.
4. **Specialist *environments* via package filtering + project settings — the
   most Pi-integrated "specialist agents," no code.** Pi scopes which skills a
   package loads via the settings object form:

   ```json
   { "source": "git:github.com/obra/superpowers",
     "skills": ["skills/writing-plans", "skills/brainstorming"] }
   ```

   Combined with project-local `.pi/settings.json`, this yields per-project
   specialist surfaces: a "planner" project loads only planning skills, a
   "coding" project only TDD/debugging. Each project becomes a small-context
   specialist.
5. **True sub-contexts — `pi-subagents` (only if parallelism/isolation is
   needed).** Pi has **no native sub-agent** (no built-in tool; only the
   `subagent/` example extension and the external `pi-subagents` package, which
   Superpowers' own tool mapping assumes). A sub-agent runs with a fresh tight
   context and stops conversation growth — but it still carries the same
   system prompt + all skill descriptions, so it does not fix the metadata tax
   by itself.

---

## 5. Recommendation

For small-context targets:

1. **Kill the bootstrap** (option 1) — the expensive, non-Pi-native piece,
   redundant with the skill description that remains.
2. **Keep but trim** the ~700-token description surface (option 2).
3. Use **per-project package filtering** (option 4) as the "specialist agents"
   mechanism — harness-integrated, zero runtime cost.
4. Reach for **`pi-subagents`** only when genuinely isolated parallel
   sub-contexts are needed (option 5).

Backlog entry: see ROADMAP.md Backlog ("Agent harness (Pi) tooling…").
