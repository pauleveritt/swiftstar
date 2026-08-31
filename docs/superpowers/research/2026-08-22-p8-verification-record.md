# P8 verification record (2026-08-22)

Durable record for Phase P8 ("Skills"). Executed on branch `p8-skills`,
spec-driven per [`docs/sdd.md`](../../sdd.md).
Spec: [`docs/superpowers/specs/2026-08-22-p8-skills-design.md`](../specs/2026-08-22-p8-skills-design.md).
Plan: [`docs/superpowers/plans/archive/2026-08-22-p8-skills.md`](../plans/archive/2026-08-22-p8-skills.md).

## Test evidence

- **Fast tier** (`just test`): **178 tests in 30 suites passed**, 0 failures
  (0.283 s). The seven integration-gated suites (`CaptureWriterTests`,
  `DownloadIntegrationTests`, `FakeAgentIntegrationTests`,
  `FakeServerIntegrationTests`, `FixtureReplayTests`,
  `ProcessStatsCollectorTests`, `SkillStagerTests`) are skipped — no model, no
  network, no subprocess (tripwire-guarded). New P8 fast suite:
  `SuperpowersBootstrapTests` (9 — the deterministic build: 14-skill sort,
  header + generic disclosure, unquoted brainstorming description,
  byte-identical re-build, missing/empty/no-`SKILL.md` degrade, dir-name
  fallback, the small sorted fixture). `AgentCommandTests` extended by 2
  (`argvAppendsSystemPromptAfterShell`, `argvOmitsSystemPromptWhenNil`).
- **Integration tier** (`just integration`): **178 tests in 30 suites passed**,
  0 failures (3.384 s) — the seven gated suites now run. New P8 integration:
  `SkillStagerTests` (4 — recursive copy + returned destination, supporting
  siblings ship, idempotent replace, missing-dir throws and leaves no root) and
  `FakeAgentIntegrationTests` extended by 1 (`fakeArgvCarriesSysAndBootstrap` —
  the built argv carries `-sys` + the deterministic bootstrap the app passes).
- **Engine tier** (`make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`):
  build clean (`cc … -o ds4_agent_test … -lm -pthread -framework Foundation -framework Metal`,
  exit 0); `ds4-agent tests: ok` (exit 0). P8 touches no engine code (D4 —
  `sysprompt.kv` already rebuilds on mismatch), so the engine tier is a
  regression guard, not a P8 exercise: the binary builds and its agent tests
  are green at the pinned submodule SHA `b91401d`.
- **Live tier**: none this phase. P8 ships no new capture and no engine patch;
  `sysprompt.kv`'s rebuild-on-mismatch is the engine's existing behavior, so
  the bootstrap is prefilled once without a live run.

## Shown-fail records (binding rule 2)

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| bootstrap determinism (T1) | no `SuperpowersBootstrap` | `cannot find 'SuperpowersBootstrap' in scope` (9 sites) — RED | yes |
| `-sys` after `--shell` (T2) | omit `systemPrompt` from `AgentSettings` | `extra argument 'systemPrompt' in call` — RED | yes |
| `SkillStager` copy (T3) | no `SkillStager` | `cannot find 'SkillStager' in scope` — RED | yes |
| fake argv carries the bootstrap (T4) | `makeSettings` without `systemPrompt` | `fakeArgvCarriesSysAndBootstrap` — `(sysIndex → nil) != nil` (argv must carry `-sys`) | yes |

## Real findings during P8

Findings the tests, the implementer, or review caught (recorded, not hidden):

1. **The spec and the brief describe the index line differently.** The spec
   (D1) describes the index line as `- <name>: <trigger> — <SKILL.md path>`
   (a per-skill path trailing the description). The task brief — the authority
   for the task's interface — renders `- <name>: <description>` with a generic
   disclosure path (`.swiftstar/skills/<name>/SKILL.md`) on a separate line.
   Implemented the brief's shape (the description on the index line, the path
   in the generic disclosure); the spec's `— <SKILL.md path>` variant would
   re-open the index format and is a separate concern. Deferred, not hidden.
   [Task 1]
2. **`URL.==` stat-stamps `hasDirectoryPath` (a trailing-slash quirk).** The
   `SkillStager` integration test asserted `dest == expected` where `dest` was
   built *before* `.swiftstar/skills` existed and `expected` *after* `stage()`
   created it; `URL.appendingPathComponent` records `hasDirectoryPath` at
   build time, so the two URLs differ under `==` despite identical `.path`.
   Confirmed in isolation (`dest.path == expected.path` true; `dest == expected`
   false). Fixed by asserting on `.path` (the filesystem location the test
   cares about), not `URL.==`. [Task 3 — environmental, a Foundation quirk]
3. **A missing skills dir is non-fatal, not blocking.** `SkillStager.stage`
   throws `missingSkillsDir`; the controller logs and proceeds (D3). The
   bootstrap then degrades to "No skills available in this workspace." but is
   still passed via `-sys` — the agent starts with an index naming skills it
   cannot `read`, and the confined `read` refuses the missing file, so no
   dispatch is fabricated (D5). Wired explicitly; the degrade path is tested
   (`stageThrowsOnMissingSkillsDirAndLeavesNoRoot`,
   `missingDirDegradesToNoSkills`). [Tasks 1, 3, 4]

## Scope compliance

The `/tmp` → `/private/tmp` `realpath` canonicalization is **P7's** finding (P7
verification record, "Real bugs found during P7," #4), not P8's — recorded
here so it is not re-counted. P8's `URL.==` quirk (finding #2 above) is a
*different* Foundation behavior (stat-stamped `hasDirectoryPath`, not
`realpath`), caught at the Swift layer not the C layer, and is not the same
bug.

P8 shipped what the spec's Components section lists and nothing the
Out-of-scope section defers. In: `SuperpowersBootstrap` (deterministic index),
`AgentCommand`'s `systemPrompt` → `-sys`, `SkillStager` (recursive workspace
copy), and the `AgentController` wiring (resolve → stage non-fatal → bootstrap
→ `settings.systemPrompt` before the spawn argv is built). Out, and
deliberately deferred: skill *execution* (dispatch — P11), a
`recall`/session browser (backlog), and any engine change (D4 — none). No
`ds4-server` capture, no CI automation of a live tier, no new wire (the
bootstrap travels as one `-sys` argv element; `Process.arguments` is not a
shell, so no quoting issues — gardenable fact).

## Concept budget

**bootstrap** and **progressive disclosure** are now defined (see ROADMAP). The
seed terms **handoff packet** and **candidate ref** remain undefined until
P10.
