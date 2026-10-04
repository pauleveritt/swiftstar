# Xcode 27's coding assistant and Claude Agent: setup, project config, tools

> Research for SU.4 (Xcode-first UI loop) and SU.5 (cleanup and test
> modernisation), gathered 2026-10-04 by a research agent from Apple and Anthropic docs and read-only inspection of the local Xcode 27.0 install. Kept as
> written, apart from this header, and with a snapshot of this Mac's expiring MCP permission grants replaced by a pointer to `xcrun mcp-server status`. Each finding carries its own confidence tag; treat
> **UNCONFIRMED** items as leads, not facts, and re-check before building on
> them. Related: [`2026-10-04-su4-handoff-brief.md`](2026-10-04-su4-handoff-brief.md).

Confidence tags: [CONFIRMED] = stated by an Apple/Anthropic source; [LOCAL] = observed on this Mac
(Xcode 27.0 / 27A266a, CLI `--help`, files under ~/Library/Developer/Xcode, and the user's own two
Xcode-agent session logs in this repo from 2026-10-03); [BLOG] = third-party writeup; [UNCONFIRMED].

Sources (short names used below)
- A1 https://developer.apple.com/documentation/xcode/setting-up-coding-intelligence
- A2 https://developer.apple.com/documentation/xcode/extending-and-customizing-agents
- A3 https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode
- A4 Xcode 27 release notes https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes
  (page is JS-rendered; I read it via https://developer.apple.com/tutorials/data/documentation/xcode-release-notes/xcode-27-release-notes.json)
- AN https://anthropic.com/news/apple-xcode-claude-agent-sdk (written for Xcode 26.3, the first Claude Agent release)
- L = local inspection (paths given inline)

---------------------------------------------------------------------------------------------
## 1. How the Claude Agent is integrated

1. It is Claude Code itself (Agent SDK harness), not a re-implementation. [CONFIRMED: AN: "the same
   underlying harness that powers Claude Code... subagents, background tasks, and plugins"]
   [LOCAL: Xcode downloads a signed Claude Code binary, version 2.1.280, to
   ~/Library/Developer/Xcode/CodingAssistant/Agents/claude/2.1.280/claude (Info.plist url points at
   Anthropic's claude-code-releases bucket; codesign identifier com.anthropic.claude-code, team Q6L2SF6YDW).
   Your terminal Claude Code is 2.1.198, a separate install.]
2. Setup: Xcode > Settings > Intelligence > Agents > "Get" next to Claude Agent > Install; then the
   Account row "..." button to sign in (claude.ai account or Anthropic API key per Apple/Anthropic
   docs); a Model row picks the model. Xcode auto-updates the downloaded agents. [CONFIRMED: A1]
   (The "API key or claude.ai account" wording came from a search snippet of A1/AN-era docs, not the current A1 page.) [partly BLOG]
3. Launch recipe (this is exactly how Xcode starts it): `xcrun mcpbridge run-agent --dry-run claude`
   prints it. [LOCAL] Environment: ANTHROPIC_MODEL=best, CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1,
   CLAUDE_CODE_FORWARD_SUBAGENT_TEXT=1, CLAUDE_AFK_TIMEOUT_MS=max,
   CLAUDE_CONFIG_DIR=~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig, MCP_XCODE_PID=<Xcode pid>.
   Args: `--verbose --mcp-config <temp json> --settings '{"env":{"CLAUDE_CODE_ENABLE_TELEMETRY":"0",
   "DISABLE_TELEMETRY":"1"},"hasCompletedOnboarding":true}'`. `xcrun mcpbridge run-agent claude ...`
   also launches that same Xcode-configured Claude from a terminal (extra args pass through,
   e.g. `--model opus -p "..."`). [LOCAL: `xcrun mcpbridge --help`]
4. Auth is separate from your terminal Claude Code: Xcode keeps its own `.claude.json` (oauth state) in
   ClaudeAgentConfig (mode 600; I did not read secrets). [LOCAL]
5. Model: Xcode's agent session logs show claude-sonnet-5 (marketing "Sonnet 5") and the cache lists
   claude-opus-5-5 and claude-fable-5-1[1m] as options; ANTHROPIC_MODEL=best is the default env. Model is a
   picker in Intelligence settings / the conversation. [LOCAL; exact default per-account is UNCONFIRMED]
   Other agents in 27: Codex, Gemini, Google Antigravity, plus any ACP agent ("Add an Agent"). [CONFIRMED: A1, A4]
6. Permissions: Intelligence settings > Agents > "Permissions" row lists Allowed Commands (shell commands,
   add with +) and Allowed Tools. [CONFIRMED: A2]. Release notes add a "Security Layer": filesystem access
   monitoring/control for agents, configurable in Coding Intelligence settings (178289431). [CONFIRMED: A4]
   MDM key `CodingAssistantAllowExternalIntegrations=false` disables the coding assistant. [CONFIRMED: A1]
7. Xcode 27 UI extras: conversations are editors/tabs, plan mode (`/plan`, `/exit-plan`; plans are editable
   markdown artifacts), sidebar of conversations, inline diff/preview artifacts. [CONFIRMED: A2, A4]

---------------------------------------------------------------------------------------------
## 2. Project-level configuration honored

Key architectural fact: Xcode's Claude runs with CLAUDE_CONFIG_DIR pointed at its own dir, so your
~/.claude (settings.json, skills, plugins, agents, auth) is NOT its user-level config. Apple: "Place the
configuration files in agent-specific subfolders in ~/Library/Developer/Xcode/CodingAssistant... These
configurations only affect agents when you launch them in Xcode." (set default model, add MCP servers,
create your own skills) -> ClaudeAgentConfig, codex, gemini. [CONFIRMED: A2]

Observed from the user's Oct 3 Xcode sessions in this repo (init attachments in
ClaudeAgentConfig/projects/-Users-pauleveritt-projects-pauleveritt-swiftstar/*.jsonl): [LOCAL]
- CLAUDE.md: LOADED. Instruction files listed: <repo>/CLAUDE.md, plus /Users/pauleveritt/.claude/CLAUDE.md
  and ~/.claude/rules/context7.md (typed "Project" -> picked up as ancestor-directory memory of the repo
  path, standard Claude Code behavior, not as the user config dir). So repo CLAUDE.md works; "@RTK.md" imports
  from the home file work too. AGENTS.md: not seen in this repo (none exists); Apple's A3 says hints go in
  "AGENTS.md or CLAUDE.md ... in the location that the external agent uses". For Claude Agent use CLAUDE.md
  (Claude Code reads CLAUDE.md, not AGENTS.md, unless you `@AGENTS.md` import from it). [AGENTS.md-for-Claude UNCONFIRMED]
- Project slash commands/skills: the skill list in Xcode's session included "goal (retired 2026-08-26)" tagged
  "(project)" -> project-scoped commands/skills ARE read (repo `.claude/commands/` existed then; it is empty
  now). [LOCAL; inferred]
- ~/.claude/skills and plugins (superpowers, python, uv, etc.): NOT present in Xcode's skill list. The list was
  only: goal, 15 `xcode-integration:*`, and Claude Code built-ins (dataviz, update-config, code-review, simplify,
  loop, schedule, claude-api, run, init, security-review...). So your superpowers skills do not load in Xcode's
  agent unless installed into ClaudeAgentConfig (or the project's .claude). [LOCAL]
- ~/.claude/settings.json: not applied (different CLAUDE_CONFIG_DIR); project .claude/settings.json should still
  be read as project scope (standard Claude Code) but UNCONFIRMED here (repo has no .claude/settings.json).
- Project `.mcp.json`: none in repo; whether Xcode's agent honors it is UNCONFIRMED. Xcode's own MCP
  config is `~/Library/Developer/Xcode/CodingAssistant/mcp-servers.json` (currently `{"mcpServers":{}}`);
  the Xcode tools server is injected via `--mcp-config` temp file and appears as MCP server `xcode-tools`. [LOCAL]
- Project `.claude/agents/`: UNCONFIRMED in Xcode. Built-in agent types seen: claude, Explore, general-purpose,
  Plan, statusline-setup. [LOCAL]
- Plug-ins: Intelligence settings > Agents > Plug-ins > Add Plug-in (from URL etc.); bundles subagents, MCP
  servers, skills. Release notes: "Agent Plugins: skills invokable as slash commands with completion; MCP
  servers and ACP agent configurations" (178289210). Plugin JSON can set MCP tool icons/titles via `_meta`
  (`ideToolIconPath`, `ideToolTitles`). [CONFIRMED: A2, A4]. Xcode's own plugin is named `xcode-integration`
  (inline), usageCount tracked in .claude.json. [LOCAL]

Apple-built specialists / skills:
- 15 skills ship as plugin `xcode-integration` (slash-invocable as `/xcode-integration:<name>`): accessibility-
  dynamic-type-specialist, accessibility-sufficient-contrast-specialist, accessibility-voiceover-specialist,
  adopt-c-bounds-safety, app-intents-specialist, app-intents-whats-new-27, audit-xcode-security-settings,
  building-document-based-swiftui-applications, device-interaction, modernize-tests, swiftui-specialist,
  swiftui-whats-new-27, translation, uikit-app-modernization (+ translation-coordinator subagent). [LOCAL:
  ClaudeAgentConfig skill_listing + SlashCommandCache/claude-code.json]. Release notes: "Apple-Built Specialists"
  for localization, UIKit resizing, accessibility (178289150). [CONFIRMED: A4]
- On disk in the Xcode bundle: /Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/
  Versions/A/Resources/{swiftui-specialist,app-intents-specialist,audit-xcode-security-settings}.
  idechatprompttemplate (+ many `swiftui-specialist-ref-*.md.packaged` reference files), and
  .../IDEXCStringsSupport.framework/Versions/A/Resources/Skills/{translation,translation-coordinator}/
  SKILL.md.packaged. [LOCAL]
- Format = standard Agent Skills: SKILL.md with YAML frontmatter (`name:`, `description:` with "Use when:" /
  "SKIP:" clauses) then markdown, plus `references/*.md`. Example: audit-xcode-security-settings frontmatter
  `name: audit-xcode-security-settings`, `description: > Audit and enable security-oriented Xcode build
  settings...`. Skill bodies tell the agent to prefer Xcode MCP tools (XcodeGlob/Grep/Read/LS/Update) over
  Bash for project files. [LOCAL]
- Export to disk: `xcrun agent skills export <dir>` (also reachable as `xcrun mcpbridge run-agent skills export`;
  `--replace-existing`; `xcrun agent plugin path --plugin-format <name>` prints packaged plugin path).
  [LOCAL: help text; BLOG: https://bleepingswift.com/blog/xcode-27-agent-skills-claude-code lists 7 exported
  skills (swiftui-specialist, swiftui-whats-new-27, test-modernizer, uikit-app-modernization, c-bounds-safety,
  device-interaction, audit-xcode-security-settings) to ~/.agents/skills or ~/.claude/skills;
  https://www.avanderlee.com/ai-development/using-xcode-27s-agent-skills-in-claude-codex-and-cursor/ same.]
  Portability: knowledge skills work anywhere; device-interaction and audit-xcode-security-settings need
  Xcode MCP tools. [BLOG]
- Can projects add their own? Apple says users can "create your own skills" in ClaudeAgentConfig and install
  plug-ins [CONFIRMED: A2]; project `.claude/skills/` is standard Claude Code and project commands were seen
  working [LOCAL, inferred]. Apple's specialists themselves are shipped read-only in the bundle and cannot be
  edited in place. Note skills with the same name from an export + the built-in plugin could duplicate. [UNCONFIRMED]

---------------------------------------------------------------------------------------------
## 3. Xcode tools given to the agent; previews in the loop; SwiftPM guidance

Tool list (MCP server `xcode-tools`, seen as deferred tools in the session; Claude loads them via ToolSearch
on demand, which keeps context small) [LOCAL]:
- Project/files: XcodeRead, XcodeWrite, XcodeUpdate, XcodeGlob, XcodeGrep, XcodeLS, XcodeMV, XcodeRM,
  XcodeMakeDir, XcodeListTargets, XcodeNewTarget, XcodeListTemplates
- Build/run/test: BuildProject, GetBuildLog, XcodeListNavigatorIssues, XcodeRefreshCodeIssuesInFile, RunProject,
  StopProject, RunAllTests, RunSomeTests, GetTestList, XcodeListTestPlans, XcodeSwitchTestPlan, RunCodeSnippet,
  GetConsoleOutput, InvokeDebuggerCommand
- Schemes/destinations: XcodeListSchemes, XcodeSwitchScheme, XcodeListRunDestinations, XcodeSwitchRunDestination
- Settings: GetTargetBuildSettings, UpdateTargetBuildSetting, AddEntitlement, AddInfoPlist, Get/UpdateFileCompilerFlags
- Preview/visual: RenderPreview; device/simulator: DeviceInteractionStartSession/StartWorkspaceSession/
  InstallAndRun/Synthesize/EndSession
- Docs: DocumentationSearch (semantic Apple docs). Localization: LocalizationPlanner, StringCatalogRead/Context/Edit.
- Insights: GetTopCrashIssues, GetCrashIssueLogs, GetTopFieldPerformanceIssues, GetFieldPerformanceIssueLogs.
Release notes (A4) confirm: expanded MCP server (debugger, scheme/destination switching, build settings),
simulator control, String Catalog tools, project insights. [CONFIRMED]

RenderPreview: "Builds and renders a Preview and waits until a snapshot of the resulting UI is available."
Inputs (per BLOG https://cuteios.dev/2026/07/14/previews-and-mcp/): tabIdentifier (external MCP clients),
sourceFilePath (Xcode project-organization path, e.g. `swiftstar/Sources/SwiftStarUI/Foo.swift`),
previewDefinitionIndexInFile (0-based `#Preview`, default 0), timeout (default 120s), variant/localization
overrides; success returns a PNG path, failure returns errors with no snapshot path. Xcode 27 adds light/dark/
orientation/type-size variants, preview groups, widgets timelines, returns display name + line number
(181040291, 182215198, 172961797, 174692209). [CONFIRMED: A4 for features; BLOG for params]
Agent loop: edit with XcodeUpdate -> RenderPreview (or BuildProject first for diagnostics) -> agent looks at PNG
-> iterate; previews are rendered headlessly without opening the Canvas. [BLOG/AN: "Claude can capture Xcode
Previews to evaluate SwiftUI interfaces... iterate automatically"]

SwiftPM-specific (this repo; first-hand evidence from the user's Oct 3 Xcode agent session) [LOCAL]:
- Bare package opens as workspace "swiftstar"; Xcode synthesizes schemes: SwiftStar-Package (default, the
  all-targets scheme), SwiftStarKit, SwiftStar (executable), FastTierGuardTool, etc.
- RenderPreview on a view inside the executable target failed with: "DebugDylibNotEnabled: The executable
  target 'SwiftStar' needs ENABLE_DEBUG_DYLIB=YES ... Either set ENABLE_DEBUG_DYLIB to YES for this target, or
  break out your preview code into a separate framework with its own scheme." The agent then tried
  UpdateTargetBuildSetting (error: "Target names must be unique within an Xcode project"; XcodeListTargets
  returns 0 targets for a package workspace), so build-setting tools do not work on bare packages.
- Therefore previews need views in a LIBRARY target that has a scheme. Package.swift already does this
  (library product SwiftStarUI "exists so Xcode generates a SwiftStarUI scheme"; views in SwiftStarUI target).
  Switch the active scheme to SwiftStarUI before RenderPreview / canvas. [LOCAL; the "switch scheme" step is an
  inference, but XcodeSwitchScheme was used by the agent in-session and the tool schema (per a 27.2 beta
  excerpt in search results) says not to switch the user's scheme unprompted. UNCONFIRMED wording.]
- Path convention in Xcode* tools: workspace-relative paths, prefixed by the workspace root name ("swiftstar/..."),
  not the git root or absolute paths. [LOCAL: audit skill text + tool use]
- Compiler flags like Package.swift `swiftLanguageMode` etc. cannot be changed via UpdateTargetBuildSetting;
  edit Package.swift instead. [inferred from above]

---------------------------------------------------------------------------------------------
## 4. Making terminal Claude Code use Xcode's MCP tools

Documented way [CONFIRMED: A3]:
1. Xcode > Settings > Intelligence > Model Context Protocol: turn on "Allow external agents to use Xcode tools".
2. `claude mcp add --transport stdio xcode -- xcrun mcpbridge`  (Codex: `codex mcp add xcode -- xcrun mcpbridge`)
   Verify: `claude mcp list`. Optionally put Xcode/project hints in CLAUDE.md/AGENTS.md.
3. Open the project in Xcode first ("Before prompting an external agent, be sure to open your project in
   Xcode"); Xcode shows an alert when the external agent connects/is active.
   Per-project sharing variant [BLOG: artemnovichkov.com headless post]: `claude mcp add --scope project xcode --
   xcrun mcpbridge` writes `<repo>/.mcp.json` (add env DEVELOPER_DIR for multiple Xcodes).
   At the time of writing this repo had no .mcp.json. [LOCAL]
4. `xcrun mcpbridge` = stdio<->XPC bridge to Xcode's tool service. Env: MCP_XCODE_PID picks a specific Xcode
   (default: the xcode-select one), MCP_XCODE_SESSION_ID (UUID). [LOCAL help] The tools take a `tabIdentifier`
   to pick the workspace tab (get it via the workspace/tab listing tool). [BLOG]
5. Approval flow: first connection from a new agent triggers an Xcode permission prompt naming the agent;
   approving covers the directory containing the project, recursively; choose Always Allow or Allow for 24 Hours.
   Menu-bar Xcode icon shows connected projects/activity. [BLOG: artemnovichkov.com; wendyliga.com] 
   Note: CLI `claude` is codesign-identified; the unsigned-agent case (e.g. python) is listed as "unsigned".

Headless mode ("MCP server without an open workspace") [CONFIRMED: A4 item 181836944 "MCP Server Headless Mode
Preview": run without an open Xcode workspace; code-signed agent permissions; `sudo xcrun mcp-server enable`,
`xcrun mcp-server status`; unattended: `sudo xcrun mcp-server enable --unsafe-always-allow-all-agents`]
Local `xcrun mcp-server --help` [LOCAL] commands: open <paths...> (launch + open workspaces/projects, no sudo),
stop, enable / disable (sudo), approve <id> [--always|--for-24-hours] (sudo), allow-folder <path> [--always|
--for-24-hours] (sudo), deny <id>, clear-permissions, reset-all, status [--format json], show-logs.
- Typical flow for this repo: `sudo xcrun mcp-server enable` (once), `sudo xcrun mcp-server allow-folder
  /Users/pauleveritt/projects/pauleveritt/swiftstar --always`, then `xcrun mcp-server open <repo path>` (or the
  agent triggers it); register `claude mcp add --transport stdio xcode -- xcrun mcpbridge`.
- Machine state (grants, expiries, pending approvals) changes; check it with `xcrun mcp-server status`
  rather than trusting a snapshot. [LOCAL]
- `--unsafe-always-allow-all-agents` trusts every process under your user; avoid. [CONFIRMED A4; BLOG]
- Beta-5-specific introduction of headless: not independently confirmed; feature is present in 27.0 GM-ish
  build 27A266a. [UNCONFIRMED version history]
Coexistence note: Xcode's embedded Claude uses its own ClaudeAgentConfig dir; terminal Claude Code uses
~/.claude. Both read the same repo CLAUDE.md. They can run concurrently on the same checkout (no lock), but
both editing the same files at once will race; Xcode editing via XcodeUpdate goes through Xcode's buffers.

---------------------------------------------------------------------------------------------
## 5. Official docs / best practices on "Claude in Xcode"

- Anthropic: "Apple's Xcode now supports the Claude Agent SDK" (AN, Xcode 26.3 era): full Claude Code harness
  in Xcode, subagents/background tasks/plugins; visual verification by capturing Previews and iterating;
  autonomy "until the task is complete or it needs user input". [CONFIRMED]
- Apple docs A1-A3 (above) are the official setup/extension/external-agent references. Apple also says you
  control "which commands, tools, and skills agents use". [CONFIRMED]
- Project instructions: Apple points to CLAUDE.md/AGENTS.md for hints about Xcode and the project (A3).
- Keep context small: Xcode already defers all ~60 xcode-tools MCP schemas (agent loads via ToolSearch), and
  skills are loaded on demand via `description:` triggers; keep CLAUDE.md short and push detail into skills/
  docs. [LOCAL observation + general Claude Code guidance; no Apple-specific "context budget" doc found]
- Previews as verification: preview-render-in-loop is the endorsed verification path (AN, A4 preview features);
  prefer small `#Preview`s per view and RenderPreview variants (dark/light, type sizes) over full app runs.
- Not found: any official Apple/Anthropic page stating that Xcode's Claude reads `.claude/settings.json`,
  `.claude/skills`, `.claude/agents`, or `.mcp.json`; WWDC 2026 session transcripts were not retrieved.
  Third-party posts consulted: wendyliga.com/blog/how-to-use-xcode-27-mcp-server, blakecrosley.com/blog/
  xcode-27-coding-agents (says only that AGENTS.md is a shared convention), cuteios.dev previews-and-mcp.

---------------------------------------------------------------------------------------------
## Practical implications for swiftstar (derived)
- Put instructions in repo CLAUDE.md (already read by both). Add an Xcode-specific short section: "previews:
  switch to the SwiftStarUI scheme; RenderPreview with sourceFilePath `swiftstar/Sources/SwiftStarUI/...`;
  SwiftStarKit/Engine have no previews; UpdateTargetBuildSetting does not work on a bare package".
- Superpowers skills will NOT appear in Xcode's agent; either install them in
  ~/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig (skills/ or plugin via Intelligence settings) or
  accept that Xcode's agent is the "quick preview loop" and the terminal handles the SDD cycle.
- Terminal Claude: `claude mcp add --transport stdio xcode -- xcrun mcpbridge` (user scope) after enabling
  "Allow external agents..." and opening the folder in Xcode, or use headless (`allow-folder`, sudo).
- Optional: `xcrun agent skills export <dir>` to bring swiftui-specialist etc. into terminal Claude (project or
  user skills dir). Not required for Xcode itself (it bundles them).
