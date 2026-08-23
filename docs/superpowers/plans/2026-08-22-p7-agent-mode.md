# P7 — Agent Mode: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Agent tab real: spawn a live `ds4-agent` on the NDJSON wire, render the stream as a transcript with tool cards, enforce the spawn-time consent model (`--workspace` grant + `--shell` toggle), support interruptible turns via an ETX byte, and produce the roadmap's capture-grade turn/tool outcome records (D12).

**Architecture:** A new `AgentWireParser` (NDJSON `hello`/`text`/`think`/`tool`/`status`/`ready`/`queued`, the `ready` carrying the D12 turn-outcome fields) feeds a pure `AgentTranscript` reducer that reconstructs tool cards from the phase stream, and a pure `TurnOutcomeBuilder` produces the per-turn outcome records; `AgentCommand` owns the one argv contract (including the consent flags); a `FakeAgentSource` generates a fake `ds4-agent` from the committed tool capture for the integration tier. The engine fork gains `--workspace DIR` (cwd + fail-closed file-tool confinement) and `--shell on|off` (bash gating in schema + dispatch) as fork divergence #8, plus turn-outcome fields on the turn-end `ready` event as divergence #9. The app's `AgentController` spawns the child, drains stdout through the parser, writes one `0x03` byte to interrupt, infers turn end from `status.state → idle`, and writes each turn's `TurnOutcome` to the `SWIFTSTAR_LOG` trail. Metrics and Diagnostics stay fixture-driven (D9).

**Tech Stack:** Swift 6.3, SwiftPM, swift-testing (fast + integration tiers); C (`ds4_agent.c`) + the fork's `DS4_AGENT_TEST` harness + `make test` (engine tier); `swiftstar-drive` + the real engine and weights (live tier, never CI).

**Spec:** `docs/superpowers/specs/2026-08-22-p7-agent-mode-design.md`

## Global Constraints

- **Fast tier** (`just test`): no model, no network, no subprocess (tripwire-guarded). Fixture reads by `#filePath`-relative path are allowed (that is how `WireEventParserTests` reads `golden.ndjson`).
- **Binding rule 2** — every new test shown to fail first (in a compiled language, "fail" = the test target does not compile, or the assertion fails).
- **Binding rule 3** — no source-text assertions: tests assert on typed `AgentEvent`/`AgentTranscriptRow`/`ToolCard` values, never on reconstructed prose strings.
- **Binding rule 6** — evidence floor: `AgentWireParser` accepts both `golden.ndjson` and `golden-tools.ndjson` (naming the fixtures) and refuses a non-handshake first line; the fake agent is generated from the real tool capture, never hand-authored.
- **Binding rule 7** — the first non-blank wire line must be a v1 `hello` whose `caps ⊇ {text, tool, status, ts}`; a mismatch refuses loudly.
- **D1/D2** — consent is spawn-time and engine-enforced: `--workspace` confines (fail closed), `--shell off` removes the bash family from schema *and* dispatch; engine defaults preserve the bare CLI (no `--shell` = on, no `--workspace` = no confinement); the *app* always passes both flags with shell defaulting to `off`.
- **Standing rule** — every submodule bump owes a golden-fixture recapture against the real binary; P7 recaptures `golden.ndjson` at the new SHA.
- **No new SwiftPM targets** — all new files live in existing targets (`SwiftStarKit`, `SwiftStar`, `SwiftStarKitTests`, `SwiftStarIntegrationTests`), so `Package.swift` is untouched.
- **D11** — only the bash family is gated; `google_search`/`visit_page` keep the engine's existing terminal-UI approval (a P9/wire concern, out of scope).
- **D9** — Metrics and Diagnostics are not re-wired to the live agent in P7; they stay fixture-driven (the deviation from the roadmap's P4 bullet is recorded in the spec's D9 and amended in the roadmap at close).
- **D12 / outcome telemetry (roadmap `0ee5f6c`)** — every turn yields a `TurnOutcome` identifying model/build/sampler and task, token and context use, stop reason (EOS, limit, interrupt, timeout, or context-full — timeout app-side by definition), and each tool lifecycle transition (emitted, parsed, rejected, executed). The stop reason comes from the turn-end `ready` event's new fields; the tool lifecycle and token/context figures come off the wire; the identification and task text are app-known.

## File Structure

**Engine (submodule `external/ds4`, committed on `swiftstar-integration`):**
- `ds4_agent.c` — `agent_config` gains `workspace_path`/`shell_allowed`; `--workspace`/`--shell` arg parsing; `agent_confine_path()` helper applied in `read`/`more`/`write`/`list`/`edit`/`search`; `agent_schemas_for()` gating bash in the tools prompt (line-bounded matcher); bash refusal in `agent_execute_tool_call()`; the turn-stop classification + `agent_emit_ready_event` outcome fields (D12); `DS4_AGENT_TEST` unit tests registered in `ds4_agent_unit_tests_run()`.
- `docs/fork-ledger.md` — divergence rows #8 (consent flags) and #9 (turn-outcome `ready` fields).
- `docs/json-events.md` — a short addendum: the two new flags (no event kind or ordering change) and the `ready` event's optional turn-outcome fields.

**SwiftStarKit (pure, fast-tier):**
- `Sources/SwiftStarKit/AgentWireParser.swift` — `AgentToolPhase`, `AgentToolEvent`, `AgentEvent` (ready carries the outcome fields), `AgentWireParser` (handshake-enforced).
- `Sources/SwiftStarKit/AgentTranscript.swift` — `ToolParam`, `ToolCard`, `AgentTranscriptRow`, `AgentTranscript` (tool-card reducer + leading-newline quirk).
- `Sources/SwiftStarKit/TurnOutcome.swift` — `TurnStopReason`, `ToolLifecycle`, `ToolCallOutcome`, `TurnOutcome`, `TurnOutcomeBuilder` (D12).
- `Sources/SwiftStarKit/AgentCommand.swift` — `AgentSettings`, `AgentCommand.argv`/`binaryPath`.
- `Sources/SwiftStarKit/FakeAgentSource.swift` — fake `ds4-agent` generator from a committed NDJSON capture.

**SwiftStar (app):**
- `Sources/SwiftStar/AgentController.swift` — spawn, drain, parser→transcript, turn state, ETX interrupt, consent flags, per-turn `TurnOutcome` records to the `SWIFTSTAR_LOG` trail.
- `Sources/SwiftStar/AgentView.swift` — status bar, transcript with tool cards, composer, interrupt button, consent controls.
- `Sources/SwiftStar/MainView.swift` — replace the Agent placeholder with `AgentView`.

**Tests:**
- `Tests/SwiftStarKitTests/AgentWireParserTests.swift`, `TurnOutcomeTests.swift`, `AgentTranscriptTests.swift`, `AgentCommandTests.swift`, `FakeAgentSourceTests.swift`.
- `Tests/SwiftStarIntegrationTests/FakeAgentHarness.swift`, `FakeAgentIntegrationTests.swift`.

**Fixtures (committed):**
- `fixtures/agent/golden-tools.ndjson` (+ `.stderr`, `.trace`, `provenance.md`), `golden.ndjson` recaptured.
- `Tools/p7-tool-capture-prompts.txt` — the committed prompts that induced the tool capture.

**Tooling:** `Sources/swiftstar-drive/main.swift` gains `CAPTURE_WORKSPACE` / `CAPTURE_SHELL` env knobs.

**Docs:** `ROADMAP.md` (P7 complete, concept budget), `docs/superpowers/research/2026-08-22-p7-verification-record.md`.

---

### Task 1: Engine — `--shell on|off` (bash gating)

**Files:**
- Modify: `external/ds4/ds4_agent.c` (config struct, arg parse, schema builders, dispatch, unit tests)

**Interfaces:**
- Produces: `agent_config.shell_allowed: bool` (default true = the bare CLI keeps bash, D2); arg `--shell on|off`; `static size_t agent_schemas_for(char *out, size_t outlen, bool shell_allowed)`; `agent_execute_tool_call` refuses the bash family when `!w->cfg->shell_allowed`.

- [ ] **Step 1: Write the failing engine unit tests**

In `external/ds4/ds4_agent.c`, inside the existing `#ifdef DS4_AGENT_TEST` block (near the other `test_agent_*` functions, before `ds4_agent_unit_tests_run()`):

```c
static void test_agent_schemas_gate_bash_when_shell_off(void) {
    char buf[16384];
    agent_schemas_for(buf, sizeof(buf), false);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash\"") == NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash_status\"") == NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash_stop\"") == NULL);
    // D11: only the bash family is gated. google_search and visit_page come
    // BEFORE the bash lines in agent_glm_tool_schemas — these two assertions
    // are what catches an unbounded matcher (deep review 2026-08-22).
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"google_search\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"visit_page\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"read\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"write\"") != NULL);
    agent_schemas_for(buf, sizeof(buf), true);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash_status\"") != NULL);
    AGENT_TEST_ASSERT(strstr(buf, "\"name\":\"bash_stop\"") != NULL);
}

static void test_agent_execute_tool_call_refuses_bash_when_shell_off(void) {
    /* Mirror the harness setup of test_agent_execute_tool_call_unknown_tool
     * (~:8882): the mutex and the wake fd must be initialized or the real
     * dispatch path (shell-on branch) is UB. */
    agent_worker w = {0};
    pthread_mutex_init(&w.mu, NULL);
    w.wake_fd[1] = -1; /* agent_wake_locked() writes here; -1 is a safe no-op fd. */
    agent_config cfg = {0};
    cfg.shell_allowed = false;
    w.cfg = &cfg;
    /* agent_tool_call.args is a POINTER (ds4_agent.c ~:249) — the calls the
     * parser produces own their array; a hand-built call must too, or
     * call.args[0] is a NULL deref (found during implementation). */
    agent_tool_arg args[1] = {0};
    agent_tool_call call = {0};
    call.name = "bash";
    call.argc = 1;
    call.args = args;
    call.args[0].name = "command";
    call.args[0].value = "echo hi";
    char *result = agent_execute_tool_call(&w, &call, 0);
    AGENT_TEST_ASSERT(result && strstr(result, "shell is disabled") != NULL);
    free(result);

    cfg.shell_allowed = true;
    /* With the shell on, dispatch proceeds past the gate — this runs a real
     * `echo hi` through the bash tool (the engine test tier already runs
     * heavier things); the result must NOT be the consent refusal. */
    result = agent_execute_tool_call(&w, &call, 0);
    AGENT_TEST_ASSERT(result && strstr(result, "shell is disabled") == NULL);
    free(result);
}
```

Register both in `ds4_agent_unit_tests_run()` (alphabetical-ish, near the other json-events tests):

```c
    test_agent_schemas_gate_bash_when_shell_off();
    test_agent_execute_tool_call_refuses_bash_when_shell_off();
```

- [ ] **Step 2: Run to verify the failure**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: FAIL — `agent_schemas_for` is undefined (link/compile error), and once the helper exists as a stub the assertions fail.

- [ ] **Step 3: Implement the config field + arg parsing**

In `agent_config` (near `json_events`):

```c
    bool non_interactive;
    bool edit_upto;
    bool json_events;
    /* Consent flags (fork divergence #8, P7). shell_allowed defaults true in
     * parse_options (D2: the bare CLI keeps bash); the app always passes
     * --shell. workspace_path arrives in Task 2. */
    bool shell_allowed;
```

In the arg-parsing chain (near `--json-events`):

```c
        } else if (!strcmp(arg, "--shell")) {
            const char *v = need_arg(&i, argc, argv, arg);
            if (!strcmp(v, "on")) {
                c.shell_allowed = true;
            } else if (!strcmp(v, "off")) {
                c.shell_allowed = false;
            } else {
                fprintf(stderr, "ds4-agent: --shell expects on or off, got \"%s\"\n", v);
                exit(2);
            }
```

At the config init site — `static agent_config parse_options(int argc, char **argv)` (ds4_agent.c ~:660), where `agent_config c = { ... }` is a **designated initializer** (there is no `agent_config c = {0};` in `main`; `main` calls `parse_options` at ~:15021, and the unlisted bool fields zero-default). Add the default to the initializer list (D2: absent `--shell` keeps the bare CLI's bash):

```c
    agent_config c = {
        .engine = {
            .model_path = "ds4flash.gguf",
            .backend = default_backend(),
            .mtp_draft_tokens = 1,
            .dflash_draft_tokens = 0,
            .mtp_margin = 3.0f,
        },
        .gen = {
            .system = "You are a helpful coding assistant running inside ds4-agent.",
            .n_predict = 50000,
            .ctx_size = 100000,
            .temperature = DS4_DEFAULT_TEMPERATURE,
            .top_p = DS4_DEFAULT_TOP_P,
            .min_p = DS4_DEFAULT_MIN_P,
            .think_mode = DS4_THINK_HIGH,
        },
        .shell_allowed = true,  /* D2: absent --shell keeps the bare CLI's bash */
    };
```

- [ ] **Step 4: Implement `agent_schemas_for` and gate the tools prompt**

Add (near `agent_build_glm_tools_prompt`). **The matcher must be line-bounded** (deep review 2026-08-22): a bare `strstr(p, …)` searches past the current line's newline into later lines, and `google_search`/`visit_page` come **before** the bash entries in `agent_glm_tool_schemas` — an unbounded search would drop the web tools too, violating D11:

```c
/* Line-bounded check: does this one schema line (length len) declare one of
 * the bash-family tools? NOT strstr(p, ...) — that searches past the line's
 * newline and matches later lines' names (google_search and visit_page
 * precede the bash entries in agent_glm_tool_schemas). */
static bool agent_schema_line_is_bash(const char *p, size_t len) {
    static const char *const names[] = {
        "\"name\":\"bash\"",
        "\"name\":\"bash_status\"",
        "\"name\":\"bash_stop\"",
    };
    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]); n++) {
        size_t needle = strlen(names[n]);
        if (len < needle) continue;
        for (size_t i = 0; i + needle <= len; i++) {
            if (memcmp(p + i, names[n], needle) == 0) return true;
        }
    }
    return false;
}

/* The three bash tools are removed from the advertised schema when the shell
 * is off (D1/D11: only the bash family is gated; web tools keep the engine's
 * existing terminal approval). agent_glm_tool_schemas is a line-oriented JSON
 * blob; walk it line by line and drop the bash lines. Writes at most outlen-1
 * bytes (NUL-terminated) and returns the length written. */
static size_t agent_schemas_for(char *out, size_t outlen, bool shell_allowed) {
    const char *src = agent_glm_tool_schemas;
    size_t o = 0;
    const char *p = src;
    while (*p && o + 1 < outlen) {
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - p) : strlen(p);
        bool bash_line = !shell_allowed && agent_schema_line_is_bash(p, len);
        if (!bash_line) {
            if (o + len + 2 > outlen) break;
            memcpy(out + o, p, len);
            o += len;
            if (nl) out[o++] = '\n';
        }
        if (!nl) break;
        p = nl + 1;
    }
    out[o] = '\0';
    return o;
}
```

Rewrite the two builders with the exact allocation math. `agent_schemas_for` writes into a fixed stack buffer first, so the size is known before `xmalloc` (a dry-run mode is unnecessary):

```c
static char *agent_build_glm_tools_prompt(bool shell_allowed) {
    size_t a = strlen(agent_glm_tools_prompt_intro);
    size_t h = strlen(agent_glm_after_schemas_head);
    size_t t = strlen(agent_glm_after_schemas_tail);
    char schemas[16384];  /* agent_glm_tool_schemas is ~2.3 KB; ample headroom */
    size_t b = agent_schemas_for(schemas, sizeof(schemas), shell_allowed);
    size_t d = shell_allowed ? strlen(agent_bash_jobs_rule) : 0;
    char *out = xmalloc(a + b + h + d + t + 1);
    memcpy(out, agent_glm_tools_prompt_intro, a);
    memcpy(out + a, schemas, b);
    memcpy(out + a + b, agent_glm_after_schemas_head, h);
    if (d) memcpy(out + a + b + h, agent_bash_jobs_rule, d);
    memcpy(out + a + b + h + d, agent_glm_after_schemas_tail, t);
    out[a + b + h + d + t] = '\0';
    return out;
}
```

```c
static char *agent_build_laguna_tools_prompt(bool shell_allowed) {
    size_t a = strlen(agent_laguna_tools_prompt_intro);
    size_t h = strlen(agent_laguna_after_schemas_head);
    size_t t = strlen(agent_laguna_after_schemas_tail);
    char schemas[16384];
    size_t b = agent_schemas_for(schemas, sizeof(schemas), shell_allowed);
    size_t d = shell_allowed ? strlen(agent_bash_jobs_rule) : 0;
    char *out = xmalloc(a + b + h + d + t + 1);
    memcpy(out, agent_laguna_tools_prompt_intro, a);
    memcpy(out + a, schemas, b);
    memcpy(out + a + b, agent_laguna_after_schemas_head, h);
    if (d) memcpy(out + a + b + h, agent_bash_jobs_rule, d);
    memcpy(out + a + b + h + d, agent_laguna_after_schemas_tail, t);
    out[a + b + h + d + t] = '\0';
    return out;
}
```

The bash-jobs advisory line (deep review 2026-08-22: the line is **second-to-last** in both constants, not final — `- Preserve the current system configuration…` is the last line in both, at `ds4_agent.c` ~:1199–1200 for GLM and ~:1249–1250 for Laguna). Split each `agent_*_tools_prompt_after_schemas` constant at the bash line, keeping the original text byte-for-byte:

- `static const char agent_glm_after_schemas_head[]` — everything up to (not including) the `- For long bash jobs…` line;
- `static const char agent_bash_jobs_rule[] = "- For long bash jobs, pass refresh_sec and then poll with bash_status or stop with bash_stop.\n";` — shared (the line is identical in both constants);
- `static const char agent_glm_after_schemas_tail[] = "- Preserve the current system configuration unless the user explicitly asks otherwise.\n";` (and the laguna equivalents).

The builders insert `agent_bash_jobs_rule` between head and tail only when `shell_allowed` — advice about a tool the model can no longer call — so the **shell-on prompt stays byte-identical to today's** (`test_agent_glm_tools_prompt_is_native` pins that; the head+rule+tail concatenation guarantees it). Then thread the bool through: `agent_build_tools_prompt(ds4_engine *engine, bool shell_allowed)` passing it to both branches, and update BOTH call sites (ds4_agent.c :1373 in `agent_build_system_prompt_reminder` and :1390 in `agent_append_system_prompt` — the plan's earlier "single call site" was wrong, found during implementation) to pass `w->cfg->shell_allowed`.

- [ ] **Step 5: Implement the dispatch gate**

At the top of `agent_execute_tool_call`, right after the `call->name` check:

```c
    bool bash_tool = !strcmp(call->name, "bash") ||
                     !strcmp(call->name, "bash_status") ||
                     !strcmp(call->name, "bash_stop");
    if (bash_tool && !w->cfg->shell_allowed) {
        return xstrdup("Tool error: shell is disabled (--shell off); bash tools are not available\n");
    }
```

- [ ] **Step 6: Run the engine tests to verify they pass**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: PASS — `ds4-agent tests: ok`. The two new tests fail with the old code and pass with the gate; the rest of the suite stays green (the schema filter must keep every non-bash line byte-identical when the shell is on — the `agent_glm_tools_prompt_is_native` test pins that).

- [ ] **Step 7: Commit (in the submodule)**

```bash
git -C external/ds4 add ds4_agent.c
git -C external/ds4 commit -m "agent: add --shell on|off consent flag (bash gating in schema + dispatch)"
```

---

### Task 2: Engine — `--workspace DIR` (file-tool confinement)

**Files:**
- Modify: `external/ds4/ds4_agent.c` (config struct, arg parse, confinement helper, file tools, unit tests)

**Interfaces:**
- Produces: `agent_config.workspace_path: const char *`; arg `--workspace DIR` (also implies the chdir when `--chdir` is not given); `static char *agent_confine_path(agent_config *cfg, const char *path, bool allow_missing)` returning a malloc'd confined absolute path or NULL on refusal; `agent_tool_read`/`agent_tool_write`/`agent_tool_list`/`agent_tool_edit`/`agent_tool_search` confine their `path` argument first. `more` needs no change: `w->more_path` was confined by the preceding `read`.

- [ ] **Step 1: Write the failing engine unit tests**

In the `DS4_AGENT_TEST` block:

```c
static void test_agent_confine_path_allows_inside(void) {
    char tmp[PATH_MAX];
    char oldcwd[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "/tmp/swiftstar-confine-%ld", (long)getpid());
    if (mkdir(tmp, 0700) != 0 && errno != EEXIST) return;  /* env problem, not the assertion */
    AGENT_TEST_ASSERT(getcwd(oldcwd, sizeof(oldcwd)) != NULL);
    AGENT_TEST_ASSERT(chdir(tmp) == 0);
    agent_config cfg = {0};
    cfg.workspace_path = tmp;
    char *out = agent_confine_path(&cfg, "a.txt", true);
    chdir(oldcwd);
    AGENT_TEST_ASSERT(out != NULL);
    if (out) {
        AGENT_TEST_ASSERT(strncmp(out, tmp, strlen(tmp)) == 0);
        AGENT_TEST_ASSERT(out[strlen(tmp)] == '/');
        free(out);
    }
    rmdir(tmp);
}

static void test_agent_confine_path_refuses_escape(void) {
    char tmp[PATH_MAX];
    char oldcwd[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "/tmp/swiftstar-confine-%ld", (long)getpid());
    if (mkdir(tmp, 0700) != 0 && errno != EEXIST) return;
    AGENT_TEST_ASSERT(getcwd(oldcwd, sizeof(oldcwd)) != NULL);
    AGENT_TEST_ASSERT(chdir(tmp) == 0);
    agent_config cfg = {0};
    cfg.workspace_path = tmp;
    char *out = agent_confine_path(&cfg, "../escape.txt", true);
    chdir(oldcwd);
    AGENT_TEST_ASSERT(out == NULL);
    rmdir(tmp);
}

static void test_agent_confine_path_refuses_missing_read_target(void) {
    char tmp[PATH_MAX];
    char oldcwd[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "/tmp/swiftstar-confine-%ld", (long)getpid());
    if (mkdir(tmp, 0700) != 0 && errno != EEXIST) return;
    AGENT_TEST_ASSERT(getcwd(oldcwd, sizeof(oldcwd)) != NULL);
    AGENT_TEST_ASSERT(chdir(tmp) == 0);
    agent_config cfg = {0};
    cfg.workspace_path = tmp;
    /* allow_missing=false (a read target): an unresolvable path must refuse. */
    char *out = agent_confine_path(&cfg, "no/such/file.txt", false);
    chdir(oldcwd);
    AGENT_TEST_ASSERT(out == NULL);
    rmdir(tmp);
}
```

Register the three in `ds4_agent_unit_tests_run()`.

- [ ] **Step 2: Run to verify the failure**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: FAIL — `agent_confine_path` undefined.

- [ ] **Step 3: Implement the config field + arg parsing**

In `agent_config`:

```c
    bool shell_allowed;
    /* Consent flags (fork divergence #8, P7): the workspace grant. */
    const char *workspace_path;
```

In the arg-parsing chain (near `--chdir`):

```c
        } else if (!strcmp(arg, "--workspace")) {
            c.workspace_path = need_arg(&i, argc, argv, arg);
            /* D1: the workspace sets the agent's cwd (reuse the existing
             * --chdir site at :15022) unless --chdir was given explicitly. */
            if (!c.chdir_path) c.chdir_path = c.workspace_path;
```

- [ ] **Step 4: Implement `agent_confine_path`**

Add (near the file-tool functions, before `agent_tool_read`):

```c
/* Fail-closed confinement for file tools (D1). Resolves `path` against cwd
 * (which is the workspace when one is set) and refuses when the resolved path
 * escapes the workspace root. allow_missing is true for write targets, whose
 * file may not exist yet: resolve the parent directory instead and check that.
 * Returns a malloc'd confined absolute path, or NULL on refusal. */
static char *agent_confine_path(agent_config *cfg, const char *path, bool allow_missing) {
    if (!cfg->workspace_path) return xstrdup(path);
    char root[PATH_MAX];
    if (!realpath(cfg->workspace_path, root)) return NULL;
    size_t root_len = strlen(root);
    if (root_len == 0 || root_len >= PATH_MAX - 2) return NULL;

    char resolved[PATH_MAX];
    if (!realpath(path, resolved)) {
        if (!allow_missing) return NULL;
        char parent[PATH_MAX];
        snprintf(parent, sizeof(parent), "%s", path);
        char *slash = strrchr(parent, '/');
        const char *leaf;
        if (slash) {
            *slash = '\0';
            leaf = slash + 1;
        } else {
            snprintf(parent, sizeof(parent), ".");
            leaf = path;
        }
        if (!leaf[0] || !realpath(parent, resolved)) return NULL;
        size_t plen = strlen(resolved);
        if (plen + strlen(leaf) + 2 > PATH_MAX) return NULL;
        if (resolved[plen - 1] != '/') resolved[plen++] = '/';
        memcpy(resolved + plen, leaf, strlen(leaf) + 1);
    }
    if (strncmp(resolved, root, root_len) != 0) return NULL;
    if (resolved[root_len] != '\0' && resolved[root_len] != '/') return NULL;
    return xstrdup(resolved);
}
```

- [ ] **Step 5: Apply confinement in the file tools**

Every confinement call is `agent_confine_path(w->cfg, path, allow_missing)`; a NULL result is the fail-closed refusal. `agent_tool_search` already takes `agent_worker *w` (and currently marks it `(void)w` — drop that). `agent_tool_list` does **not** take `w`, so its signature must change (see below) — without this the confinement cannot compile.

**`agent_tool_read`** (replace `agent_read_range(w, path, …)`; the tool currently returns it directly):

```c
static char *agent_tool_read(agent_worker *w, const agent_tool_call *call) {
    const char *path = agent_tool_arg_value(call, "path");
    char *confined = agent_confine_path(w->cfg, path, false);
    if (!confined) {
        return xstrdup("Tool error: path is outside the workspace grant (--workspace)\n");
    }
    bool whole = agent_parse_bool_default(agent_tool_arg_value(call, "whole"), false);
    int start = agent_parse_int_default(agent_tool_arg_value(call, "start_line"),
                                        1, 1, INT_MAX);
    int count = agent_parse_int_default(agent_tool_arg_value(call, "max_lines"),
                                        agent_read_default_lines(w), 1, INT_MAX);
    bool raw = agent_parse_bool_default(agent_tool_arg_value(call, "raw"), false);
    char *result = agent_read_range(w, confined, start, count, whole, raw, true);
    free(confined);
    return result;
}
```

**`agent_tool_write`** (`allow_missing=true` — the file may not exist yet; free on every return path):

```c
static char *agent_tool_write(agent_worker *w, const agent_tool_call *call) {
    const char *path = agent_tool_arg_value(call, "path");
    const char *content = agent_tool_arg_value(call, "content");
    if (!path || !path[0]) return xstrdup("Tool error: write requires path\n");
    if (!content) return xstrdup("Tool error: write requires content\n");
    char *confined = agent_confine_path(w->cfg, path, true);
    if (!confined) {
        return xstrdup("Tool error: path is outside the workspace grant (--workspace)\n");
    }
    FILE *fp = fopen(confined, "wb");
    if (!fp) {
        agent_buf b = {0};
        agent_buf_puts(&b, "Tool error: open for write failed: ");
        agent_buf_puts(&b, strerror(errno));
        agent_buf_puts(&b, "\n");
        free(confined);
        return agent_buf_take(&b);
    }
    size_t len = strlen(content);
    size_t wr = fwrite(content, 1, len, fp);
    int close_rc = fclose(fp);
    if (wr != len || close_rc != 0) {
        agent_buf b = {0};
        agent_buf_puts(&b, "Tool error: write failed: ");
        agent_buf_puts(&b, strerror(errno));
        agent_buf_puts(&b, "\n");
        free(confined);
        return agent_buf_take(&b);
    }
    char msg[PATH_MAX + 160];
    snprintf(msg, sizeof(msg), "Wrote %zu bytes to %s\n", len, confined);
    free(confined);
    return xstrdup(msg);
}
```

**`agent_tool_list` — signature change is mandatory.** The function currently takes only `const agent_tool_call *call` (ds4_agent.c :7268), so it cannot reach `w->cfg`. Change it to take `agent_worker *w`, update the dispatch call site (:11300, `return agent_tool_list(call);` → `return agent_tool_list(w, call);`), and confine after the `.` defaulting (the default must be confined too):

```c
static char *agent_tool_list(agent_worker *w, const agent_tool_call *call) {
    const char *path = agent_tool_arg_value(call, "path");
    if (!path || !path[0]) path = ".";
    char *confined = agent_confine_path(w->cfg, path, false);
    if (!confined) {
        return xstrdup("Tool error: path is outside the workspace grant (--workspace)\n");
    }
    DIR *dir = opendir(confined);
    if (!dir) {
        agent_buf b = {0};
        agent_buf_puts(&b, "Tool error: opendir failed: ");
        agent_buf_puts(&b, strerror(errno));
        agent_buf_puts(&b, "\n");
        free(confined);
        return agent_buf_take(&b);
    }
    agent_buf out = {0};
    char hdr[PATH_MAX + 64];
    snprintf(hdr, sizeof(hdr), "%s:\n", confined);
    agent_buf_puts(&out, hdr);
    /* body unchanged: readdir loop builds `full` from `confined` instead of
     * `path` (`snprintf(full, sizeof(full), "%s/%s", confined, de->d_name)`),
     * lstat(full), etc. */
    if (de) agent_buf_puts(&out, "... more entries omitted ...\n");
    closedir(dir);
    free(confined);
    return agent_buf_take(&out);
}
```

**`agent_tool_search`** (already has `w`; drop `(void)w;`; confine after the `.` defaulting — the default is confined too):

```c
static char *agent_tool_search(agent_worker *w, const agent_tool_call *call) {
    const char *query = agent_tool_arg_value(call, "query");
    if (!query || !query[0]) return xstrdup("Tool error: search requires query\n");
    const char *path = agent_tool_arg_value(call, "path");
    if (!path || !path[0]) path = ".";
    char *confined = agent_confine_path(w->cfg, path, false);
    if (!confined) {
        return xstrdup("Tool error: path is outside the workspace grant (--workspace)\n");
    }
    /* ctx construction unchanged; every early return after this point must
     * free(confined) first (the regex-compile error path included). */
    agent_search_path(&ctx, confined, 0);
    free(confined);
    /* rest unchanged */
}
```

**`agent_tool_edit`** (has `w`; drop `(void)w;`): confine once after the `path` non-empty check, then use `confined` for every file operation (`agent_read_file_bytes(confined, …)`, `agent_write_file_bytes(confined, …)`, and the apply), freeing before each of the tool's several returns. The streaming-time preflight runs on a different path from dispatch: add the same confine block at the top of `agent_preflight_edit_old` (ds4_agent.c :10285 — it already takes `agent_worker *w` and is called from the renderer at :4115), refusing with the same message; without it, the preflight would `fopen`/read the escaping path before dispatch ever refuses.

`more` needs no change (its `w->more_path` was confined by the preceding read). `google_search`/`visit_page` are untouched (D11).

- [ ] **Step 6: Run the engine tests to verify they pass**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: PASS — `ds4-agent tests: ok`.

- [ ] **Step 7: Commit (in the submodule)**

```bash
git -C external/ds4 add ds4_agent.c
git -C external/ds4 commit -m "agent: add --workspace consent flag (fail-closed file-tool confinement)"
```

---

### Task 3: Engine — turn-end stop reason on the `ready` event

**Files:**
- Modify: `external/ds4/ds4_agent.c` (turn-stop classification, worker state, `agent_emit_ready_event`, unit tests)

**Interfaces:**
- Produces: `typedef enum { AGENT_TURN_STOP_NONE=0, AGENT_TURN_STOP_EOS, AGENT_TURN_STOP_LIMIT, AGENT_TURN_STOP_INTERRUPT, AGENT_TURN_STOP_CONTEXT_FULL } agent_turn_stop_reason;` + `static const char *agent_turn_stop_reason_name(agent_turn_stop_reason)` (returns NULL for NONE); worker fields `last_turn_stop_reason` / `last_turn_generated` / `last_turn_ctx_used` snapshotted where the turn actually ends; `agent_emit_ready_event` appends `,"stop_reason":"…","generated":N,"ctx_used":M` after the memory-plan fields when `last_turn_stop_reason != AGENT_TURN_STOP_NONE` (startup `ready` stays bare — the fields repeat on later readys like the memory-plan fields, so a consumer that drops a line recovers).

Why `ready`: it fires exactly once per turn end in the persistent piped-stdin loop (the P5 driver counts it for exactly that), so the outcome lands at the turn-end moment without a new event kind (D12). The generation loop knows the reason at its exit (`ds4_agent.c` ~:12135–12260: the stop token → EOS, `generated >= max_tokens` → limit, the latched interrupt, `room <= 1` forcing `max_tokens = 0` → context-full); a turn is multiple generation rounds (tool rounds resume generation), so classify only where the round ends **without** a tool block — that exit is the turn's end.

- [ ] **Step 1: Write the failing engine unit tests**

In the `DS4_AGENT_TEST` block (mirror the setup of `test_agent_emit_ready_event_carries_memory_plan` at ~:9023 — `agent_worker w = {0}; pthread_mutex_init(&w.mu, NULL); w.wake_fd[1] = -1; agent_config cfg = { .json_events = true }; w.cfg = &cfg;` — and reset `w.out`/`w.out_len`/`w.out_cap` between emissions):

```c
static void test_agent_turn_stop_reason_names(void) {
    AGENT_TEST_ASSERT(!strcmp(agent_turn_stop_reason_name(AGENT_TURN_STOP_EOS), "eos"));
    AGENT_TEST_ASSERT(!strcmp(agent_turn_stop_reason_name(AGENT_TURN_STOP_LIMIT), "limit"));
    AGENT_TEST_ASSERT(!strcmp(agent_turn_stop_reason_name(AGENT_TURN_STOP_INTERRUPT), "interrupt"));
    AGENT_TEST_ASSERT(!strcmp(agent_turn_stop_reason_name(AGENT_TURN_STOP_CONTEXT_FULL), "context_full"));
    AGENT_TEST_ASSERT(agent_turn_stop_reason_name(AGENT_TURN_STOP_NONE) == NULL);
}

static void test_agent_ready_event_carries_turn_outcome(void) {
    agent_worker w = {0};
    pthread_mutex_init(&w.mu, NULL);
    w.wake_fd[1] = -1;
    agent_config cfg = { .json_events = true };
    w.cfg = &cfg;

    /* Startup ready: no turn has ended, so no outcome fields. */
    w.last_turn_stop_reason = AGENT_TURN_STOP_NONE;
    agent_emit_ready_event(&w, NULL);
    AGENT_TEST_ASSERT(w.out != NULL);
    if (w.out) AGENT_TEST_ASSERT(strstr(w.out, "stop_reason") == NULL);
    free(w.out); w.out = NULL; w.out_len = 0; w.out_cap = 0;

    /* After a turn: the ready event carries the outcome snapshot. */
    w.last_turn_stop_reason = AGENT_TURN_STOP_INTERRUPT;
    w.last_turn_generated = 42;
    w.last_turn_ctx_used = 1024;
    agent_emit_ready_event(&w, NULL);
    AGENT_TEST_ASSERT(w.out != NULL);
    if (w.out) {
        AGENT_TEST_ASSERT(strstr(w.out, "\"stop_reason\":\"interrupt\"") != NULL);
        AGENT_TEST_ASSERT(strstr(w.out, "\"generated\":42") != NULL);
        AGENT_TEST_ASSERT(strstr(w.out, "\"ctx_used\":1024") != NULL);
    }
    free(w.out); w.out = NULL; w.out_len = 0; w.out_cap = 0;
}
```

Register both in `ds4_agent_unit_tests_run()`.

- [ ] **Step 2: Run to verify the failure**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: FAIL — the enum and worker fields do not exist (compile error).

- [ ] **Step 3: Implement the classification, worker state, and emitter fields**

1. Add the enum and name function (near `agent_worker_state`):

```c
/* Why a turn ended (D12, roadmap 0ee5f6c). NONE = no turn has ended yet. */
typedef enum {
    AGENT_TURN_STOP_NONE = 0,
    AGENT_TURN_STOP_EOS,
    AGENT_TURN_STOP_LIMIT,
    AGENT_TURN_STOP_INTERRUPT,
    AGENT_TURN_STOP_CONTEXT_FULL,
} agent_turn_stop_reason;

static const char *agent_turn_stop_reason_name(agent_turn_stop_reason r) {
    switch (r) {
    case AGENT_TURN_STOP_EOS:          return "eos";
    case AGENT_TURN_STOP_LIMIT:        return "limit";
    case AGENT_TURN_STOP_INTERRUPT:    return "interrupt";
    case AGENT_TURN_STOP_CONTEXT_FULL: return "context_full";
    case AGENT_TURN_STOP_NONE:         return NULL;
    }
    return NULL;
}
```

2. Add the snapshot fields to `agent_worker` (near `status`):

```c
    /* Turn-outcome snapshot (D12): set where the turn actually ends (the
     * final generation round's non-tool exit), read by the ready emitter.
     * Dedicated fields, not status: status may be reset at idle. */
    agent_turn_stop_reason last_turn_stop_reason;
    int last_turn_generated;
    int last_turn_ctx_used;
```

3. Classify at the turn-end exit. In the worker's turn function, the generation loop (~:12135–12260) exits for: the latched interrupt (`worker_should_interrupt`), the stop token (`ds4_token_is_stop_for_think_mode` / `stop_from_speculation`), the token limit (`generated >= max_tokens`), and tool-round terminations (`got_tool` → dispatch and generate again — **not** a turn end). After the loop, where the code handles the non-tool exits and returns the worker to idle, set the snapshot (the exact site is wherever the turn ends without `got_tool`; if the loop structure makes the limit/context-full distinction awkward there, compute it before the loop: `room <= 1` → `AGENT_TURN_STOP_CONTEXT_FULL`, else the limit applies):

```c
    w->last_turn_stop_reason = worker_should_interrupt(w) ? AGENT_TURN_STOP_INTERRUPT
                            : <token-limit exit>          ? AGENT_TURN_STOP_LIMIT
                            :                               AGENT_TURN_STOP_EOS;
    w->last_turn_generated = <generated>;
    w->last_turn_ctx_used = ds4_session_pos(w->session);
```

   Also set `AGENT_TURN_STOP_INTERRUPT` on the interrupt path that ends a prefill (`DS4_SESSION_SYNC_INTERRUPTED`, ~:12077, which already calls `agent_worker_append_assistant_turn_end`) — a turn can be cut short before generation starts. The `turn_fail`/error path may leave `last_turn_stop_reason` at its previous value; record what the source shows in the verification notes rather than guessing.

4. Extend `agent_emit_ready_event` (after the memory-plan block, before the `ts`):

```c
    if (w->last_turn_stop_reason != AGENT_TURN_STOP_NONE) {
        const char *reason = agent_turn_stop_reason_name(w->last_turn_stop_reason);
        char outcome[96];
        snprintf(outcome, sizeof(outcome),
                 ",\"stop_reason\":\"%s\",\"generated\":%d,\"ctx_used\":%d",
                 reason ? reason : "eos", w->last_turn_generated,
                 w->last_turn_ctx_used);
        agent_buf_puts(&b, outcome);
    }
```

- [ ] **Step 4: Run the engine tests to verify they pass**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: PASS — the new tests fail without the emitter fields and pass with them; `test_agent_emit_ready_event_carries_memory_plan` still passes (its worker is zero-initialized, so `last_turn_stop_reason == NONE` and the plan-only line is unchanged).

- [ ] **Step 5: Commit (in the submodule)**

```bash
git -C external/ds4 add ds4_agent.c
git -C external/ds4 commit -m "agent: carry turn-outcome fields (stop_reason/generated/ctx_used) on the ready event"
```

---

### Task 4: Fork ledger rows + rebuild + submodule bump

**Files:**
- Modify: `external/ds4/docs/fork-ledger.md`; parent repo gitlink `external/ds4`

- [ ] **Step 1: Add fork-ledger divergence #8**

Append two rows to the fork-ledger table and the SHA mapping (three commits from Tasks 1–3 — get their SHAs from `git -C external/ds4 log --oneline -3`):

| # | Divergence | Commits (orig → new) | Why it exists | What retires it |
|---|---|---|---|---|
| 8 | consent flags (`--workspace`, `--shell`) | (Task 1 sha)→(Task 2 sha) | the app's consent model is spawn-time and engine-enforced: `--workspace DIR` confines the file tools (fail closed) and sets the cwd; `--shell off` removes the bash family from schema and dispatch. Without it a "grant"/"toggle" in the app would be cosmetic — the file tools `fopen(path)` with no confinement | upstream lands a wire-level tool-authorization protocol; the flags then become one implementation of it (retires with the P9 wire round-trip) |
| 9 | turn-outcome fields on `ready` | (Task 3 sha) | binding the roadmap's outcome-telemetry requirement (main `0ee5f6c`): the turn-end `ready` event carries `stop_reason`/`generated`/`ctx_used` — the wire previously had no stop reason at all (turn end was only inferable from `status.state → idle`), so a capture-grade turn outcome could not distinguish EOS from limit from context-full | upstream lands a structured events mode with turn-end semantics (flagship proposal #1); retires with #4 |

Also update the json-events.md addendum to document **both** changes: the two consent flags (and that they change no event kind or ordering guarantee), and the `ready` event's optional turn-outcome fields (`stop_reason`/`generated`/`ctx_used` — absent at startup, repeated on later readys like the memory-plan fields).

- [ ] **Step 2: Rebuild the engine**

Run: `just engine`
Expected: `ds4-agent`/`ds4-server` build from the new submodule tip; no errors. The build now carries three P7 engine commits (consent flags ×2 + turn-outcome fields).

- [ ] **Step 3: Run the full engine test suite**

Run: `make -C external/ds4 test`
Expected: PASS — includes `ds4_agent_test` with the new tests.

- [ ] **Step 4: Commit the ledger doc (submodule) and bump the gitlink (parent)**

```bash
git -C external/ds4 add docs/fork-ledger.md docs/json-events.md
git -C external/ds4 commit -m "docs: fork-ledger divergences #8/#9 (consent flags, turn-outcome ready fields) + json-events addendum"
git add external/ds4
git commit -m "P7: bump submodule — consent flags + turn-outcome ready fields (divergences #8/#9)"
```

- [ ] **Step 5: Verify the gitlink**

Run: `git submodule status`
Expected: `+<newsha> external/ds4` (the `+` marks the staged/working-tree change — normal between the bump commit and the next `just engine` in the CI checkout).

---

### Task 5: Live recapture — `golden-tools.ndjson` + recaptured `golden.ndjson`

**Files:**
- Modify: `Sources/swiftstar-drive/main.swift`, `fixtures/agent/provenance.md`
- Create: `Tools/p7-tool-capture-prompts.txt`, `fixtures/agent/golden-tools.ndjson`, `fixtures/agent/golden-tools.stderr`, `fixtures/agent/golden-tools.trace`, `fixtures/agent/golden-tools.provenance.md`
- Replace: `fixtures/agent/golden.ndjson`, `fixtures/agent/golden.stderr`, `fixtures/agent/golden.trace` (recapture at the new SHA)

> Live tier: real engine, real weights (~48 GiB model), minutes to run. Never CI. The executor runs this once; the committed result is what every other tier consumes.

- [ ] **Step 1: Add the consent knobs to `swiftstar-drive`**

In `Sources/swiftstar-drive/main.swift`, read two optional env knobs and append them to the spawned argv (after `--json-events`):

```swift
let workspace = env["CAPTURE_WORKSPACE"]  // nil = no --workspace (P5 shape)
let shell = env["CAPTURE_SHELL"]          // nil = no --shell
```

```swift
process.arguments = [
    "-m", ggufPath,
    "-c", "\(ctx)",
    "--metal",
    "--non-interactive",
    "--json-events",
    "--trace", tracePath.path,
]
if let workspace {
    process.arguments?.append(contentsOf: ["--workspace", workspace])
}
if let shell {
    process.arguments?.append(contentsOf: ["--shell", shell])
}
```

`CaptureManifest.commandLine` already records `process.arguments`, so the provenance carries the consent flags verbatim.

- [ ] **Step 2: Commit the tool-capture prompts file**

`Tools/p7-tool-capture-prompts.txt` (one prompt per line; each is a single-line instruction chosen to induce a tool call with machine-independent paths/outputs):

```
Write a file named seed.txt in the current directory with content exactly: hello from golden-tools
Read the file seed.txt
Edit seed.txt: replace the text "hello" with "hi"
List the current directory
Run the command: echo hello-world
```

Stability rationale (recorded in the fixture provenance): the workspace is the engine's cwd, so every tool path is relative (`seed.txt`, `.`); `write`/`edit` output echoes the relative path; `echo hello-world` output is literal. No absolute paths, no `pwd`/`ls /tmp`, so the fixture is reproducible on any machine.

- [ ] **Step 3: Capture `golden-tools`**

```bash
mkdir -p /tmp/swiftstar-p7-workspace && rm -f /tmp/swiftstar-p7-workspace/seed.txt
CAPTURE_GGUF="$HOME/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf" \
CAPTURE_WORKSPACE=/tmp/swiftstar-p7-workspace \
CAPTURE_SHELL=on \
CAPTURE_PROMPTS_FILE=Tools/p7-tool-capture-prompts.txt \
just capture
```

- [ ] **Step 4: Verify the capture actually contains tool events**

Run:
```bash
grep -c '"phase":"tool"' captures/*/wire.ndjson   # >= 1 (a call announcement)
grep -c '"phase":"output"' captures/*/wire.ndjson # >= 1 (the bash echo)
grep -c '"phase":"finish"' captures/*/wire.ndjson # >= 1
```
Expected: each >= 1. If the model declined a tool call for a prompt, rephrase that prompt (the capture must prove the wire carries read/write/edit/list *and* a bash `output` event) and re-run Step 3. Also confirm `seed.txt` was created inside the workspace (proves the write ran under confinement, not refused) and that `grep '"phase":"start"'` shows a block open before the tool events.

Also verify the D12 wire addition against the real binary (the fixture proves it — Task 7's outcome tests depend on it):

```bash
grep -c '"stop_reason"' captures/*/wire.ndjson  # >= number of prompts: every turn's end
```

Expected: each turn's ending `ready` carries a stop reason (`eos` for these simple prompts). If the fields are absent, the engine patch did not land — fix before installing the fixture.

- [ ] **Step 5: Install the fixture**

Copy the newest capture dir (`captures/<ts>-<model>/`): `wire.ndjson` → `fixtures/agent/golden-tools.ndjson`, `wire.stderr` → `fixtures/agent/golden-tools.stderr`, `wire.trace` → `fixtures/agent/golden-tools.trace`. Write `fixtures/agent/golden-tools.provenance.md` in the P5 `provenance.md` style (submodule SHA, command line with `--workspace`/`--shell on`, model file, workspace setup, prompts file path, date, and the verification numbers from Step 4).

- [ ] **Step 6: Recapture `golden.ndjson` at the new SHA (standing rule)**

With the same two P5 prompts (default `swiftstar-drive` prompts) and **no** `CAPTURE_WORKSPACE`/`CAPTURE_SHELL`:

```bash
CAPTURE_GGUF="$HOME/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf" just capture
```
Copy the result over `fixtures/agent/golden.ndjson` / `golden.stderr` / `golden.trace` and update `fixtures/agent/provenance.md` (new submodule SHA, new `ts` anchor, date). Then verify the recaptured `golden.ndjson` is still **text-only** (Task 6's test asserts no tool events): `grep -c '"phase"' fixtures/agent/golden.ndjson` must be 0 — if the model emitted a tool call for one of the simple prompts, re-run the capture rather than adjusting the test.

- [ ] **Step 7: Re-run the fast tier and fix any golden-value drift**

Run: `just test`
Expected: green. The P6 assertions on `golden` are count/band-based (`golden.trace` has 2 prefill syncs for the same two prompts; the analyzer's healthy verdict holds), so they should stay green; if any test hard-codes an exact golden-derived number, update the assertion to the recaptured value — bands and counts must not change, only exact `ts`/`tps`/`ctx_used` figures.

- [ ] **Step 8: Commit**

```bash
git add Tools/p7-tool-capture-prompts.txt fixtures/agent/golden-tools.ndjson fixtures/agent/golden-tools.stderr fixtures/agent/golden-tools.trace fixtures/agent/golden-tools.provenance.md fixtures/agent/golden.ndjson fixtures/agent/golden.stderr fixtures/agent/golden.trace fixtures/agent/provenance.md Sources/swiftstar-drive/main.swift
git commit -m "P7: recapture golden at new SHA + capture golden-tools fixture (tool events + stop reasons)"
```

---

### Task 6: `AgentEvent` + `AgentWireParser` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/AgentWireParser.swift`
- Test: `Tests/SwiftStarKitTests/AgentWireParserTests.swift`

**Interfaces:**
- Consumes: `StatusSnapshot` (already in `WireEventParser.swift` — the shared telemetry snapshot, D3).
- Produces:
  - `public enum AgentToolPhase: String, Equatable, Sendable` — `.start, .tool, .paramBegin = "param_begin", .paramValue = "param_value", .paramEnd = "param_end", .output, .finish`.
  - `public struct AgentToolEvent: Equatable, Sendable` — `phase: AgentToolPhase`, `idx: Int`, `name: String?`, `paramKind: String?`, `paramName: String?`, `value: String?`, `status: String?`, `calls: Int?`.
  - `public enum AgentEvent: Equatable, Sendable` — `.hello(version: Int, capabilities: [String])`, `.status(StatusSnapshot)`, `.ready(plannedBytes: Int64?, stopReason: String?, generated: Int?, ctxUsed: Int?)` (the D12 turn-outcome fields, all optional), `.queued`, `.text(String)`, `.think(String)`, `.tool(AgentToolEvent)`, `.ignored(String)`, `.refused(String)`.
  - `public struct AgentWireParser: Sendable { public init(); public mutating func feed(_ line: String) -> AgentEvent? }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/AgentWireParserTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct AgentWireParserTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private static let helloLine = #"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":100}"#

    private mutating func feedAll(_ parser: inout AgentWireParser, _ text: String) -> [AgentEvent] {
        var out: [AgentEvent] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let e = parser.feed(s) { out.append(e) }
        }
        return out
    }

    @Test func handshakeParses() {
        var p = AgentWireParser()
        let events = feedAll(&p, Self.helloLine)
        #expect(events == [.hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"])])
    }

    @Test func firstNonBlankLineMustBeHandshake() {
        var p = AgentWireParser()
        let refused = p.feed(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#)
        #expect(refused == .refused(#"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#))
    }

    @Test func missingRequiredCapRefuses() {
        var p = AgentWireParser()
        // caps lacks "tool" — the transcript cannot be built; refuse loudly.
        let line = #"{"t":"hello","v":1,"caps":["status","ready","text","ts"],"ts":1}"#
        #expect(p.feed(line) == .refused(line))
    }

    @Test func unknownVersionRefuses() {
        var p = AgentWireParser()
        let line = #"{"t":"hello","v":2,"caps":["status","ready","text","think","tool","queued","ts"],"ts":1}"#
        #expect(p.feed(line) == .refused(line))
    }

    @Test func parsesToolBlockPhases() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let start = p.feed(#"{"t":"tool","phase":"start","idx":0,"ts":10}"#)
        #expect(start == .tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let tool = p.feed(#"{"t":"tool","phase":"tool","idx":0,"name":"read","ts":11}"#)
        #expect(tool == .tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let pb = p.feed(#"{"t":"tool","phase":"param_begin","idx":0,"kind":"path","name":"path","ts":12}"#)
        #expect(pb == .tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        let pv = p.feed(#"{"t":"tool","phase":"param_value","idx":0,"s":"seed.txt","ts":13}"#)
        #expect(pv == .tool(AgentToolEvent(phase: .paramValue, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "seed.txt", status: nil, calls: nil)))
        let pe = p.feed(#"{"t":"tool","phase":"param_end","idx":0,"ts":14}"#)
        #expect(pe == .tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        let finish = p.feed(#"{"t":"tool","phase":"finish","idx":0,"calls":1,"ts":15}"#)
        #expect(finish == .tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        let output = p.feed(#"{"t":"tool","phase":"output","idx":0,"s":"1 hello from golden-tools\n","ts":16}"#)
        #expect(output == .tool(AgentToolEvent(phase: .output, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "1 hello from golden-tools\n", status: nil, calls: nil)))
    }

    @Test func finishCarriesInterruptedStatus() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"tool","phase":"finish","idx":0,"calls":1,"status":"[tool call interrupted]\n","ts":20}"#
        #expect(p.feed(line) == .tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: "[tool call interrupted]\n", calls: 1)))
    }

    @Test func textAndThinkParse() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        #expect(p.feed(#"{"t":"text","s":"hello","ts":1}"#) == .text("hello"))
        #expect(p.feed(#"{"t":"think","s":"hmm","ts":2}"#) == .think("hmm"))
    }

    @Test func statusCarriesState() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // The shared StatusSnapshot carries the wire's state string: D6's turn
        // end is inferred from state → idle, and the controller needs it.
        let line = #"{"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":5}"#
        #expect(p.feed(line) == .status(StatusSnapshot(ctxUsed: 0, ctxSize: 32768, prefillTPS: 0.0, genTPS: 0.0, ts: 5, state: "idle")))
    }

    @Test func queuedAndReadyParse() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        #expect(p.feed(#"{"t":"queued","ts":1}"#) == .queued)
        #expect(p.feed(#"{"t":"ready","kv_bytes":1,"scratch_bytes":2,"model_bytes":3,"planned_bytes":4,"ts":2}"#) == .ready(plannedBytes: 4, stopReason: nil, generated: nil, ctxUsed: nil))
        #expect(p.feed(#"{"t":"ready","ts":3}"#) == .ready(plannedBytes: nil, stopReason: nil, generated: nil, ctxUsed: nil))  // ctx_size <= 0 sessions omit the plan
    }

    @Test func readyCarriesTurnOutcomeFields() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        // D12: the turn-end ready carries the stop reason and final figures.
        #expect(p.feed(#"{"t":"ready","stop_reason":"context_full","generated":7,"ctx_used":32768,"ts":4}"#) == .ready(plannedBytes: nil, stopReason: "context_full", generated: 7, ctxUsed: 32768))
        // And the fields coexist with the memory plan.
        #expect(p.feed(#"{"t":"ready","kv_bytes":1,"planned_bytes":4,"stop_reason":"eos","generated":9,"ctx_used":100,"ts":5}"#) == .ready(plannedBytes: 4, stopReason: "eos", generated: 9, ctxUsed: 100))
    }

    @Test func unknownLinesIgnored() {
        var p = AgentWireParser()
        _ = p.feed(Self.helloLine)
        let line = #"{"t":"future_event","x":1,"ts":1}"#
        #expect(p.feed(line) == .ignored(line))
    }

    @Test func goldenNdjsonParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = AgentWireParser()
        let events = feedAll(&p, text)
        #expect(events.first == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"]))
        #expect(events.allSatisfy { if case .refused = $0 { return false } else { return true } })
        // 43-line text-only capture: 1 hello, 3 ready, 19 status, no tool events.
        #expect(events.filter { if case .tool = $0 { return true } else { return false } }.isEmpty)
    }

    @Test func goldenToolsNdjsonParsesWithoutRefusing() throws {
        let url = Self.fixturesRoot.appendingPathComponent("golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var p = AgentWireParser()
        let events = feedAll(&p, text)
        #expect(events.first == .hello(version: 1, capabilities: ["status", "ready", "text", "think", "tool", "queued", "ts"]))
        #expect(events.allSatisfy { if case .refused = $0 { return false } else { return true } })
        // The tool capture must actually carry tool events (evidence floor).
        let toolEvents = events.compactMap { if case .tool(let te) = $0 { return te } else { return nil } }
        #expect(toolEvents.contains { $0.phase == .start })
        #expect(toolEvents.contains { $0.phase == .output })
        #expect(toolEvents.contains { $0.phase == .finish })
        // D12 (evidence floor): the capture's turn-end readys carry the stop reason.
        let readyReasons = events.compactMap { if case .ready(_, let stop, _, _) = $0 { return stop } else { return nil } }
        #expect(readyReasons.contains { $0 != nil })
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `AgentWireParserTests.swift` does not compile (`AgentWireParser`/`AgentEvent`/`AgentToolEvent` undefined, and `StatusSnapshot` has no `state` field).

- [ ] **Step 3: Extend `StatusSnapshot` with the wire's `state` string**

The controller infers turn end from `status.state → idle` (D6), but the shared `StatusSnapshot` (D3) currently drops `state`. Add it — an additive field; Metrics/Diagnostics ignore it. The wire always carries `state` (json-events.md `status` table), so there is no default value: every construction site passes it explicitly.

`Sources/SwiftStarKit/WireEventParser.swift` — add the field to the struct:

```swift
public struct StatusSnapshot: Equatable, Sendable {
    public let ctxUsed: Int
    public let ctxSize: Int
    public let prefillTPS: Double
    public let genTPS: Double
    public let ts: UInt64
    /// The wire's `status.state` string (`idle`, `prefill`, `generating`, …).
    /// Added in P7: the agent controller infers turn end from the `idle`
    /// transition (D6). Metrics and Diagnostics read only the numeric fields.
    public let state: String
}
```

And parse it in the existing `status` case:

```swift
        case "status":
            return .status(StatusSnapshot(
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
                ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
                prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
                genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0,
                ts: (object["ts"] as? NSNumber)?.uint64Value ?? 0,
                state: (object["state"] as? String) ?? ""
            ))
```

Update the existing construction sites (all mechanical, add `state:`): `Tests/SwiftStarKitTests/WireEventParserTests.swift:50`, `MetricsReducerTests.swift` (5 sites), `DiagnosticsAnalyzerTests.swift:5`, `DiagnosticsLogicTests.swift:5`. Then run `just test` and confirm the only failures are the expected compile failures from Steps 1–2 (binding rule 2: the new `statusCarriesState` test also fails here — `state` does not exist yet).

- [ ] **Step 4: Implement `AgentEvent` + `AgentWireParser`**

`Sources/SwiftStarKit/AgentWireParser.swift`:

```swift
import Foundation

/// One phase of a tool event on the NDJSON agent wire (json-events.md). The
/// raw `phase` string maps 1:1; `param_begin`/`param_value`/`param_end` use
/// the underscored wire spellings.
public enum AgentToolPhase: String, Equatable, Sendable {
    case start
    case tool
    case paramBegin = "param_begin"
    case paramValue = "param_value"
    case paramEnd = "param_end"
    case output
    case finish
}

/// The structured payload of one `tool` event line. Which fields are present
/// depends on the phase (json-events.md "tool" table): `tool` carries `name`;
/// `param_begin` carries `kind`+`name`; `param_value`/`output` carry `s`;
/// `finish` carries optional `status` + always `calls`.
public struct AgentToolEvent: Equatable, Sendable {
    public let phase: AgentToolPhase
    public let idx: Int
    public let name: String?
    public let paramKind: String?
    public let paramName: String?
    public let value: String?
    public let status: String?
    public let calls: Int?
}

/// One modelled event from the NDJSON agent wire. `.ignored` carries the raw
/// line for anything not modelled — the wire can grow and this parser will not
/// refuse it. `.refused` is the binding-rule-7 loud failure: a first line that
/// is not a v1 handshake with the required capabilities.
public enum AgentEvent: Equatable, Sendable {
    case hello(version: Int, capabilities: [String])
    case status(StatusSnapshot)
    case ready(plannedBytes: Int64?, stopReason: String?, generated: Int?, ctxUsed: Int?)
    case queued
    case text(String)
    case think(String)
    case tool(AgentToolEvent)
    case ignored(String)
    case refused(String)
}

/// Streaming NDJSON consumer for the `ds4-agent` wire (`--json-events`),
/// shaped like `WireEventParser` and `SSEParser`: feed one wire line at a time;
/// it returns an event or nil. The first non-blank line must be the v1 `hello`
/// handshake whose caps include `text`, `tool`, `status` and `ts` (binding
/// rule 7). Deliberately a sibling of `WireEventParser`, not an extension of
/// it: the telemetry consumers (`MetricsReducer`, `DiagnosticsAnalyzer`) switch
/// exhaustively over `WireEvent`, and the transcript needs `text`/`think`/
/// `tool`/`queued` with different required caps (D3). The one shared type is
/// `StatusSnapshot`.
public struct AgentWireParser: Sendable {
    private var sawHandshake = false
    private static let requiredCaps: Set<String> = ["text", "tool", "status", "ts"]

    public init() {}

    public mutating func feed(_ line: String) -> AgentEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let t = object["t"] as? String
        else {
            if !sawHandshake { sawHandshake = true; return .refused(trimmed) }
            return .ignored(trimmed)
        }

        if !sawHandshake {
            sawHandshake = true
            if t == "hello",
               let v = (object["v"] as? NSNumber)?.intValue, v == 1,
               let caps = object["caps"] as? [String],
               Self.requiredCaps.isSubset(of: Set(caps)) {
                return .hello(version: v, capabilities: caps)
            }
            return .refused(trimmed)
        }

        switch t {
        case "hello":
            return .ignored(trimmed)  // a second handshake is not an error, just unmodelled
        case "status":
            return .status(StatusSnapshot(
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
                ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
                prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
                genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0,
                ts: (object["ts"] as? NSNumber)?.uint64Value ?? 0,
                state: (object["state"] as? String) ?? ""
            ))
        case "ready":
            return .ready(
                plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value,
                stopReason: object["stop_reason"] as? String,
                generated: (object["generated"] as? NSNumber)?.intValue,
                ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue
            )
        case "queued":
            return .queued
        case "text":
            return .text(object["s"] as? String ?? "")
        case "think":
            return .think(object["s"] as? String ?? "")
        case "tool":
            if let toolEvent = parseTool(object) { return .tool(toolEvent) }
            return .ignored(trimmed)
        default:
            return .ignored(trimmed)
        }
    }

    /// `name` is overloaded on the wire: the `tool` phase carries the tool
    /// name, `param_begin` carries the parameter name. Read it per-phase, and
    /// return nil for an unknown phase so `feed` can ignore the line.
    private func parseTool(_ object: [String: Any]) -> AgentToolEvent? {
        guard let rawPhase = object["phase"] as? String,
              let phase = AgentToolPhase(rawValue: rawPhase) else { return nil }
        let idx = (object["idx"] as? NSNumber)?.intValue ?? 0
        switch phase {
        case .tool:
            return AgentToolEvent(phase: phase, idx: idx, name: object["name"] as? String,
                                  paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)
        case .paramBegin:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: object["kind"] as? String, paramName: object["name"] as? String,
                                  value: nil, status: nil, calls: nil)
        case .paramValue, .output:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: object["s"] as? String,
                                  status: nil, calls: nil)
        case .finish:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: nil,
                                  status: object["status"] as? String,
                                  calls: (object["calls"] as? NSNumber)?.intValue)
        case .start, .paramEnd:
            return AgentToolEvent(phase: phase, idx: idx, name: nil,
                                  paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)
        }
    }
}
```

- [ ] **Step 5: Run to verify the tests pass**

Run: `just test`
Expected: PASS — all `AgentWireParserTests` green (including `statusCarriesState` and both fixture parses — the evidence floor, binding rule 6), and the pre-existing WireEventParser/Metrics/Diagnostics suites stay green with the updated `StatusSnapshot` construction sites.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/AgentWireParser.swift Tests/SwiftStarKitTests/AgentWireParserTests.swift
git commit -m "P7: AgentWireParser — NDJSON agent wire, handshake-enforced"
```

---

### Task 7: `TurnOutcome` + `TurnOutcomeBuilder` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/TurnOutcome.swift`
- Test: `Tests/SwiftStarKitTests/TurnOutcomeTests.swift`

**Interfaces:**
- Consumes: `AgentEvent`, `AgentToolEvent`, `AgentToolPhase` (Task 6 — including the `ready` outcome fields).
- Produces:
  - `public enum ToolLifecycle: String, Equatable, Sendable, CaseIterable` — `.emitted, .parsed, .rejected, .executed`.
  - `public struct ToolCallOutcome: Equatable, Sendable { public let name: String; public let transitions: [ToolLifecycle] }`.
  - `public enum TurnStopReason: String, Equatable, Sendable, CaseIterable` — `.eos, .limit, .interrupt, .timeout, .contextFull = "context_full"`.
  - `public struct TurnOutcome: Equatable, Sendable` — `model: String, build: String, sampler: String, task: String, generatedTokens: Int, ctxUsed: Int, stopReason: TurnStopReason, toolCalls: [ToolCallOutcome]`, `CustomStringConvertible` (one compact line for the log trail).
  - `public struct TurnOutcomeBuilder` — `init(model: String, build: String, sampler: String, task: String)`, `mutating func apply(_ event: AgentEvent)`, `func finish(appStopReason: TurnStopReason? = nil) -> TurnOutcome`.

Semantics (D12): a `tool` phase → `.emitted`; a clean block `finish` (no `status`) closes **every call in the block** with `.parsed` + `.executed` (dispatch is synchronous — a clean finish means the calls ran); a `finish` with a `status` closes every call with `.rejected` (invalid, interrupted, or failed — the four-word vocabulary has no finer case); an `output` adds `.executed` to that call (bash only; idempotent). `ready` carries the wire's stop reason and final token/context figures. `finish` resolves the stop reason as: the app's override (interrupt/timeout — the app knows what it did) ?? the wire's `stop_reason` ?? `.eos` (a wire predating D12 ends turns with no reason; a turn that simply ended is the least-wrong default).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/TurnOutcomeTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct TurnOutcomeTests {
    private static let hello = AgentEvent.hello(version: 1, capabilities: ["text", "tool", "status", "ts"])

    private func tool(_ phase: AgentToolPhase, idx: Int = 0, name: String? = nil,
                      status: String? = nil, calls: Int? = nil, value: String? = nil) -> AgentEvent {
        .tool(AgentToolEvent(phase: phase, idx: idx, name: name, paramKind: nil,
                             paramName: nil, value: value, status: status, calls: calls))
    }

    @Test func cleanReadCallIsEmittedParsedExecuted() {
        var b = TurnOutcomeBuilder(model: "m.gguf", build: "abc123", sampler: "engine-defaults", task: "read it")
        for e in [Self.hello, tool(.start), tool(.tool, name: "read"), tool(.paramBegin),
                  tool(.paramValue, value: "seed.txt"), tool(.paramEnd), tool(.finish, calls: 1),
                  .ready(plannedBytes: nil, stopReason: "eos", generated: 12, ctxUsed: 120)] {
            b.apply(e)
        }
        let outcome = b.finish()
        #expect(outcome.toolCalls == [ToolCallOutcome(name: "read", transitions: [.emitted, .parsed, .executed])])
        #expect(outcome.stopReason == .eos)
        #expect(outcome.generatedTokens == 12)
        #expect(outcome.ctxUsed == 120)
        #expect(outcome.model == "m.gguf")
        #expect(outcome.build == "abc123")
        #expect(outcome.sampler == "engine-defaults")
        #expect(outcome.task == "read it")
    }

    @Test func bashOutputExecutesOnce() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        for e in [tool(.start), tool(.tool, name: "bash"), tool(.finish, calls: 1),
                  tool(.output, value: "hello-world\n"),
                  .ready(plannedBytes: nil, stopReason: "eos", generated: 3, ctxUsed: 9)] {
            b.apply(e)
        }
        // .executed arrives twice (output + clean finish) but records once.
        #expect(b.finish().toolCalls == [ToolCallOutcome(name: "bash", transitions: [.emitted, .parsed, .executed])])
    }

    @Test func interruptedFinishRejectsEveryCallInTheBlock() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        for e in [tool(.start), tool(.tool, idx: 0, name: "read"), tool(.tool, idx: 1, name: "bash"),
                  tool(.finish, idx: 1, status: "[tool call interrupted]\n", calls: 2),
                  .ready(plannedBytes: nil, stopReason: "interrupt", generated: 5, ctxUsed: 20)] {
            b.apply(e)
        }
        let outcome = b.finish()
        #expect(outcome.toolCalls == [
            ToolCallOutcome(name: "read", transitions: [.emitted, .rejected]),
            ToolCallOutcome(name: "bash", transitions: [.emitted, .rejected]),
        ])
        #expect(outcome.stopReason == .interrupt)
    }

    @Test func multipleBlocksAccumulateWithinATurn() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        for e in [tool(.start), tool(.tool, name: "read"), tool(.finish, calls: 1),
                  tool(.start), tool(.tool, name: "edit"), tool(.finish, calls: 1),
                  .ready(plannedBytes: nil, stopReason: "limit", generated: 99, ctxUsed: 32768)] {
            b.apply(e)
        }
        #expect(b.finish().toolCalls.map(\.name) == ["read", "edit"])
        #expect(b.finish().stopReason == .limit)
    }

    @Test func appOverrideBeatsWireReason() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "eos", generated: 1, ctxUsed: 2))
        // The app sent ETX; the wire may have already reported a stale reason.
        #expect(b.finish(appStopReason: .interrupt).stopReason == .interrupt)
        // Timeout is app-side only — the vocabulary case exists so the record
        // is complete (no controller policy in P7).
        #expect(b.finish(appStopReason: .timeout).stopReason == .timeout)
    }

    @Test func wireWithoutStopReasonDefaultsToEOS() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        b.apply(.ready(plannedBytes: 4, stopReason: nil, generated: nil, ctxUsed: nil))
        #expect(b.finish().stopReason == .eos)
    }

    @Test func contextFullMapsFromWire() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "context_full", generated: 0, ctxUsed: 32768))
        #expect(b.finish().stopReason == .contextFull)
    }

    @Test func goldenToolsYieldsFullLifecycleOutcomes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var b = TurnOutcomeBuilder(model: "m", build: "b", sampler: "s", task: "whole capture")
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = parser.feed(String(line)) { b.apply(e) }
        }
        let outcome = b.finish()
        // Evidence floor (binding rule 6): the real tool capture yields calls
        // with the full lifecycle — every call emitted, the bash call executed
        // — and a wire stop reason off its turn-end readys.
        #expect(!outcome.toolCalls.isEmpty)
        #expect(outcome.toolCalls.allSatisfy { $0.transitions.first == .emitted })
        #expect(outcome.toolCalls.contains { $0.name == "bash" && $0.transitions.contains(.executed) })
        #expect(outcome.toolCalls.contains { $0.name == "read" && $0.transitions.contains(.parsed) })
        #expect(outcome.stopReason == .eos || outcome.stopReason == .limit || outcome.stopReason == .interrupt || outcome.stopReason == .contextFull)
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `TurnOutcomeTests.swift` does not compile (`TurnOutcome`/`TurnOutcomeBuilder`/`ToolCallOutcome`/`ToolLifecycle` undefined).

- [ ] **Step 3: Implement `TurnOutcome` + `TurnOutcomeBuilder`**

`Sources/SwiftStarKit/TurnOutcome.swift`:

```swift
import Foundation

/// The outcome-telemetry vocabulary for one tool call (D12, roadmap 0ee5f6c):
/// emitted (announced on the wire), parsed (its block closed cleanly),
/// rejected (the block closed with a status — invalid, interrupted, or
/// failed; the vocabulary has no finer case), executed (dispatch ran; bash
/// additionally shows it via `output`).
public enum ToolLifecycle: String, Equatable, Sendable, CaseIterable {
    case emitted, parsed, rejected, executed
}

public struct ToolCallOutcome: Equatable, Sendable {
    public let name: String
    public let transitions: [ToolLifecycle]
}

/// Why a turn ended. `timeout` is app-side by definition — the app's own turn
/// budget — and exists so the record's vocabulary is complete; P7's controller
/// imposes no timeout policy (D12).
public enum TurnStopReason: String, Equatable, Sendable, CaseIterable {
    case eos
    case limit
    case interrupt
    case timeout
    case contextFull = "context_full"
}

/// One turn's capture-grade outcome record (D12): the spawn-time
/// identification the wire cannot carry (model/build/sampler), the task text,
/// final token/context figures, the stop reason, and every tool call's
/// lifecycle. P10's handoff packets consume these facts rather than inferring
/// success from the transcript.
public struct TurnOutcome: Equatable, Sendable {
    public let model: String
    public let build: String
    public let sampler: String
    public let task: String
    public let generatedTokens: Int
    public let ctxUsed: Int
    public let stopReason: TurnStopReason
    public let toolCalls: [ToolCallOutcome]

    public init(model: String, build: String, sampler: String, task: String,
                generatedTokens: Int, ctxUsed: Int, stopReason: TurnStopReason,
                toolCalls: [ToolCallOutcome]) {
        self.model = model
        self.build = build
        self.sampler = sampler
        self.task = task
        self.generatedTokens = generatedTokens
        self.ctxUsed = ctxUsed
        self.stopReason = stopReason
        self.toolCalls = toolCalls
    }
}

extension TurnOutcome: CustomStringConvertible {
    /// One compact line for the SWIFTSTAR_LOG trail.
    public var description: String {
        let tools = toolCalls.map { "\($0.name)[\($0.transitions.map(\.rawValue).joined(separator: "+"))]" }
            .joined(separator: " ")
        return "turn model=\(model) build=\(build) sampler=\(sampler) tokens=\(generatedTokens) ctx=\(ctxUsed) stop=\(stopReason.rawValue) tools=[\(tools)] task=\(task.prefix(80))"
    }
}

/// Builds one `TurnOutcome` from a turn's wire events plus the app-known facts
/// the wire cannot carry (D12). Pure; the controller opens one builder per
/// turn and finishes it at the turn end. Tool state is keyed by `idx` within
/// the current block (the same idx contract as `AgentTranscript`); a block's
/// `finish` closes every call in it, and completed blocks accumulate within
/// the turn.
public struct TurnOutcomeBuilder {
    private let model: String
    private let build: String
    private let sampler: String
    private let task: String
    private var calls: [Int: (name: String, transitions: [ToolLifecycle])] = [:]
    private var order: [Int] = []
    private var completed: [ToolCallOutcome] = []
    private var wireStopReason: TurnStopReason?
    private var generated = 0
    private var ctxUsed = 0

    public init(model: String, build: String, sampler: String, task: String) {
        self.model = model
        self.build = build
        self.sampler = sampler
        self.task = task
    }

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .tool(let te):
            applyTool(te)
        case .ready(_, let stopReason, let generated, let ctxUsed):
            if let stopReason { wireStopReason = TurnStopReason(rawValue: stopReason) }
            if let generated { self.generated = generated }
            if let ctxUsed { self.ctxUsed = ctxUsed }
        case .hello, .status, .queued, .text, .think, .ignored, .refused:
            break
        }
    }

    /// The app override (interrupt/timeout — the app knows what it did) beats
    /// the wire's reason; a wire predating the D12 fields ends turns with no
    /// reason, so a turn that simply ended defaults to `.eos`.
    public func finish(appStopReason: TurnStopReason? = nil) -> TurnOutcome {
        var all = completed
        for idx in order {
            if let c = calls[idx] {
                all.append(ToolCallOutcome(name: c.name, transitions: c.transitions))
            }
        }
        return TurnOutcome(
            model: model, build: build, sampler: sampler, task: task,
            generatedTokens: generated, ctxUsed: ctxUsed,
            stopReason: appStopReason ?? wireStopReason ?? .eos,
            toolCalls: all
        )
    }

    private mutating func applyTool(_ te: AgentToolEvent) {
        switch te.phase {
        case .start:
            flushBlock()
        case .tool:
            calls[te.idx] = (name: te.name ?? "", transitions: [.emitted])
            order.append(te.idx)
        case .paramBegin, .paramValue, .paramEnd:
            break  // the lifecycle vocabulary has no finer granularity
        case .output:
            if var c = calls[te.idx], !c.transitions.contains(.executed) {
                c.transitions.append(.executed)
                calls[te.idx] = c
            }
        case .finish:
            // One finish per block: it closes every call in it. A clean
            // finish (no status) means the calls parsed and — dispatch being
            // synchronous — executed; a status means the block closed badly,
            // which the vocabulary records as rejected.
            for idx in order {
                guard var c = calls[idx] else { continue }
                if te.status == nil {
                    if !c.transitions.contains(.parsed) { c.transitions.append(.parsed) }
                    if !c.transitions.contains(.executed) { c.transitions.append(.executed) }
                } else if !c.transitions.contains(.rejected) {
                    c.transitions.append(.rejected)
                }
                calls[idx] = c
            }
        }
    }

    private mutating func flushBlock() {
        for idx in order {
            if let c = calls[idx] {
                completed.append(ToolCallOutcome(name: c.name, transitions: c.transitions))
            }
        }
        calls = [:]
        order = []
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS — all `TurnOutcomeTests` green, including the `golden-tools` evidence-floor test.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/TurnOutcome.swift Tests/SwiftStarKitTests/TurnOutcomeTests.swift
git commit -m "P7: TurnOutcome — capture-grade turn/tool outcome records (D12)"
```

---

### Task 8: `AgentTranscript` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/AgentTranscript.swift`
- Test: `Tests/SwiftStarKitTests/AgentTranscriptTests.swift`

**Interfaces:**
- Consumes: `AgentEvent`, `AgentToolEvent`, `AgentToolPhase` (Task 6).
- Produces:
  - `public struct ToolParam: Equatable, Sendable { public let name: String; public var value: String }`
  - `public struct ToolCard: Equatable, Sendable { public let name: String; public var params: [ToolParam]; public var output: String?; public var status: String? }`
  - `public enum AgentTranscriptRow: Equatable, Sendable` — `.thinking(String)`, `.content(String)`, `.tool(ToolCard)`, `.system(String)`.
  - `public struct AgentTranscript: Equatable, Sendable { public private(set) var rows: [AgentTranscriptRow]; public init(); public mutating func apply(_ event: AgentEvent); public mutating func appendSystem(_ message: String) }`.

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/AgentTranscriptTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct AgentTranscriptTests {
    private static let hello = AgentEvent.hello(version: 1, capabilities: ["text", "tool", "status", "ts"])

    @Test func contentCoalesces() {
        var t = AgentTranscript()
        t.apply(.text("Hello "))
        t.apply(.text("world"))
        #expect(t.rows == [.content("Hello world")])
    }

    @Test func thinkingCoalescesSeparately() {
        var t = AgentTranscript()
        t.apply(.think("hmm"))
        t.apply(.think(" more"))
        t.apply(.text("answer"))
        #expect(t.rows == [.thinking("hmm more"), .content("answer")])
    }

    @Test func leadingNewlineQuirkStripsOnce() {
        // json-events.md quirk: the first text after a </think> starts with
        // leading newlines (one or two from the renderer, more possible from
        // the model). Strip all leading whitespace on exactly that chunk.
        var t = AgentTranscript()
        t.apply(.think("done"))
        t.apply(.text("\n\n\nThe answer"))
        t.apply(.text(" and more"))  // a later chunk is not stripped
        #expect(t.rows == [.thinking("done"), .content("The answer and more")])
    }

    @Test func singleCallBlockBuildsCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramValue, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "seed.txt", status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [ToolParam(name: "path", value: "seed.txt")], output: nil, status: nil))])
    }

    @Test func emptyParamValueStillAddsParam() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "write", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        // An empty-string parameter value emits no param_value event (json-events.md).
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "path", paramName: "path", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 0, name: nil, paramKind: "content", paramName: "content", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "write", params: [ToolParam(name: "path", value: ""), ToolParam(name: "content", value: "")], output: nil, status: nil))])
    }

    @Test func outputAttributedToSameBlockAfterFinish() {
        // json-events.md ordering guarantee: a block's output events land
        // after its finish but before the next block's start.
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "bash", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        t.apply(.tool(AgentToolEvent(phase: .output, idx: 0, name: nil, paramKind: nil, paramName: nil, value: "hello-world\n", status: nil, calls: nil)))
        #expect(t.rows == [.tool(ToolCard(name: "bash", params: [], output: "hello-world\n", status: nil))])
    }

    @Test func interruptedFinishSetsStatusOnCard() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: "[tool call interrupted]\n", calls: 1)))
        #expect(t.rows == [.tool(ToolCard(name: "read", params: [], output: nil, status: "[tool call interrupted]\n"))])
    }

    @Test func multiCallBlockKeysCardsByIdx() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "list", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 1, name: "bash", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramBegin, idx: 1, name: nil, paramKind: "bash_command", paramName: "command", value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramValue, idx: 1, name: nil, paramKind: nil, paramName: nil, value: "pwd", status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .paramEnd, idx: 1, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 1, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 2)))
        #expect(t.rows == [
            .tool(ToolCard(name: "list", params: [], output: nil, status: nil)),
            .tool(ToolCard(name: "bash", params: [ToolParam(name: "command", value: "pwd")], output: nil, status: nil)),
        ])
    }

    @Test func blockStartClearsPriorBlockCards() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "read", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 1)))
        // A new block restarts idx at 0: the card map is cleared at `start`, so
        // the new block's idx-0 card is a fresh row, never the old block's card.
        // (A stale `output` arriving after the new `start` is a wire violation
        // — json-events.md guarantees a block's outputs land before the next
        // start — and the reducer does not defend against it: once the new
        // block's `tool` phase re-keys idx 0, a late output attaches to that
        // card. That case is undefined per D4; this test pins the defined one.)
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "edit", paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        #expect(t.rows.count == 2)
        #expect(t.rows[0] == .tool(ToolCard(name: "read", params: [], output: nil, status: nil)))
        #expect(t.rows[1] == .tool(ToolCard(name: "edit", params: [], output: nil, status: nil)))
    }

    @Test func zeroCallFinishIsIgnored() {
        var t = AgentTranscript()
        t.apply(.tool(AgentToolEvent(phase: .start, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: nil)))
        t.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil, paramKind: nil, paramName: nil, value: nil, status: nil, calls: 0)))
        #expect(t.rows.isEmpty)
    }

    @Test func systemRowAppends() {
        var t = AgentTranscript()
        t.appendSystem("> hello")
        #expect(t.rows == [.system("> hello")])
    }

    @Test func goldenToolsTranscriptBuildsToolCards() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var t = AgentTranscript()
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            if let e = parser.feed(s) { t.apply(e) }
        }
        let cards = t.rows.compactMap { if case .tool(let card) = $0 { return card } else { return nil } }
        #expect(!cards.isEmpty)
        #expect(cards.contains { $0.name == "bash" && $0.output != nil })  // the echo output surfaced on its card
        #expect(cards.contains { $0.name == "read" })
        #expect(cards.contains { $0.name == "write" || $0.name == "edit" })
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `AgentTranscriptTests.swift` does not compile (`AgentTranscript`/`ToolCard`/`ToolParam`/`AgentTranscriptRow` undefined).

- [ ] **Step 3: Implement `AgentTranscript`**

`Sources/SwiftStarKit/AgentTranscript.swift`:

```swift
import Foundation

/// One parameter of a tool call, reconstructed from the phase stream.
public struct ToolParam: Equatable, Sendable {
    public let name: String
    public var value: String
}

/// A tool card: one tool call's rendered state, rebuilt from the wire's
/// `tool`/`param_begin`/`param_value`/`param_end`/`output`/`finish` phases
/// (D4). Only the bash family ever carries `output` (json-events.md); `status`
/// is non-nil when the block did not close cleanly (interrupt, parse error,
/// hard failure).
public struct ToolCard: Equatable, Sendable {
    public let name: String
    public var params: [ToolParam]
    public var output: String?
    public var status: String?
}

/// One display row of the agent transcript.
public enum AgentTranscriptRow: Equatable, Sendable {
    case thinking(String)
    case content(String)
    case tool(ToolCard)
    case system(String)
}

/// Reduces `AgentEvent`s to display rows. Consecutive `.content` and
/// `.thinking` deltas coalesce into one row each (like `ChatTranscript`);
/// tool phases mutate the currently-open card in place, keyed by `idx` within
/// the current block (D4, json-events.md "The idx contract"). The card key map
/// is cleared at each block `start`, so a late `output` can never be
/// attributed to a same-`idx` call in the following block. The leading-newline
/// quirk (json-events.md "Known quirks": the first `text` after a `</think>`
/// starts with leading newlines) is stripped here, exactly once.
public struct AgentTranscript: Equatable, Sendable {
    public private(set) var rows: [AgentTranscriptRow] = []
    /// Card row index per `idx`, scoped to the current tool block.
    private var cardRows: [Int: Int] = [:]
    /// True while the last content event was `think`, so the next `text`
    /// strips leading whitespace exactly once.
    private var sawThink = false

    public init() {}

    public mutating func apply(_ event: AgentEvent) {
        switch event {
        case .text(let s):
            var text = s
            if sawThink {
                text = String(text.drop(while: { $0.isWhitespace }))
                sawThink = false
            }
            if case .content(let existing)? = rows.last {
                rows[rows.count - 1] = .content(existing + text)
            } else {
                rows.append(.content(text))
            }
        case .think(let s):
            sawThink = true
            if case .thinking(let existing)? = rows.last {
                rows[rows.count - 1] = .thinking(existing + s)
            } else {
                rows.append(.thinking(s))
            }
        case .tool(let te):
            applyTool(te)
        case .hello, .status, .ready, .queued, .ignored, .refused:
            break
        }
    }

    /// Non-wire sibling: user prompts and engine status lines are not NDJSON
    /// events, so they enter through a separate mutator (like ChatTranscript).
    public mutating func appendSystem(_ message: String) {
        rows.append(.system(message))
    }

    private mutating func applyTool(_ te: AgentToolEvent) {
        switch te.phase {
        case .start:
            cardRows = [:]
        case .tool:
            let card = ToolCard(name: te.name ?? "", params: [], output: nil, status: nil)
            rows.append(.tool(card))
            cardRows[te.idx] = rows.count - 1
        case .paramBegin:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.params.append(ToolParam(name: te.paramName ?? "", value: ""))
            rows[row] = .tool(card)
        case .paramValue:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row],
                  !card.params.isEmpty else { return }
            card.params[card.params.count - 1].value += te.value ?? ""
            rows[row] = .tool(card)
        case .paramEnd:
            break  // the param is already tracked by param_begin/param_value
        case .output:
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.output = (card.output ?? "") + (te.value ?? "")
            rows[row] = .tool(card)
        case .finish:
            // `finish` carries the last real call's idx; a zero-call block
            // (calls == 0, idx == 0) has no card and is a no-op here.
            guard let row = cardRows[te.idx], case .tool(var card) = rows[row] else { return }
            card.status = te.status
            rows[row] = .tool(card)
        }
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS — all `AgentTranscriptTests` green, including the fixture-driven `goldenToolsTranscriptBuildsToolCards`.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/AgentTranscript.swift Tests/SwiftStarKitTests/AgentTranscriptTests.swift
git commit -m "P7: AgentTranscript — tool-card reducer + leading-newline quirk"
```

---

### Task 9: `AgentCommand` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/AgentCommand.swift`
- Test: `Tests/SwiftStarKitTests/AgentCommandTests.swift`

**Interfaces:**
- Produces:
  - `public struct AgentSettings: Equatable, Sendable { public var engineDir: URL; public var modelPath: URL; public var contextSize: Int; public var workspace: URL; public var shellAllowed: Bool; public init(engineDir: URL, modelPath: URL, contextSize: Int = 32768, workspace: URL, shellAllowed: Bool = false) }`
  - `public enum AgentCommand { public static func argv(settings: AgentSettings) -> [String]; public static func binaryPath(settings: AgentSettings) -> URL }`

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/AgentCommandTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct AgentCommandTests {
    private func makeSettings(workspace: URL, shellAllowed: Bool = false) -> AgentSettings {
        AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 16384,
            workspace: workspace,
            shellAllowed: shellAllowed
        )
    }

    @Test func argvCarriesConsentFlagsByDefault() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        // The app always passes both flags explicitly (D2), shell defaulting to off.
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
        ])
    }

    @Test func argvAllowsShell() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws, shellAllowed: true))
        #expect(argv.contains("--shell"))
        #expect(argv[argv.firstIndex(of: "--shell")! + 1] == "on")
    }

    @Test func binaryPathIsDs4Agent() {
        let settings = makeSettings(workspace: URL(fileURLWithPath: "/tmp/ws"))
        #expect(AgentCommand.binaryPath(settings: settings) == URL(fileURLWithPath: "/tmp/fake-engine/ds4-agent"))
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `AgentCommandTests.swift` does not compile (`AgentCommand`/`AgentSettings` undefined).

- [ ] **Step 3: Implement `AgentCommand`**

`Sources/SwiftStarKit/AgentCommand.swift`:

```swift
import Foundation

/// The agent launch settings. Pure value type; defaults live in the app.
public struct AgentSettings: Equatable, Sendable {
    public var engineDir: URL
    public var modelPath: URL
    public var contextSize: Int
    /// The workspace grant (D1): the agent's cwd and the file tools'
    /// confinement root. The app always passes it (D2).
    public var workspace: URL
    /// The shell toggle (D1/D2): false = `--shell off` (bash removed from
    /// schema and refused in dispatch). The app's default posture is deny.
    public var shellAllowed: Bool

    public init(
        engineDir: URL,
        modelPath: URL,
        contextSize: Int = 32768,
        workspace: URL,
        shellAllowed: Bool = false
    ) {
        self.engineDir = engineDir
        self.modelPath = modelPath
        self.contextSize = contextSize
        self.workspace = workspace
        self.shellAllowed = shellAllowed
    }
}

/// The one argv contract: what the app spawns (as `Process.arguments`, after
/// `Process` prepends the executable path as argv[0]) and what the fake agent
/// validates. The binary path itself is NOT part of the returned array.
public enum AgentCommand {
    public static func argv(settings: AgentSettings) -> [String] {
        [
            "-m", settings.modelPath.path,
            "-c", String(settings.contextSize),
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", settings.workspace.path,
            "--shell", settings.shellAllowed ? "on" : "off",
        ]
    }

    /// The executable to spawn for these settings.
    public static func binaryPath(settings: AgentSettings) -> URL {
        settings.engineDir.appendingPathComponent("ds4-agent")
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/AgentCommand.swift Tests/SwiftStarKitTests/AgentCommandTests.swift
git commit -m "P7: AgentCommand — the agent argv contract (workspace grant + shell toggle)"
```

---

### Task 10: `FakeAgentSource` (SwiftStarKit)

**Files:**
- Create: `Sources/SwiftStarKit/FakeAgentSource.swift`
- Test: `Tests/SwiftStarKitTests/FakeAgentSourceTests.swift`

**Interfaces:**
- Consumes: `FakeServerSource.swiftStringLiteral` (reuse the existing public escaper).
- Produces: `public enum FakeAgentError: Error, Equatable, Sendable { case invalidUTF8, malformedCaptureLine(line: Int, content: String) }`; `public enum FakeAgentSource { public static func generate(capture: Data, engineArgv: [String]) throws -> String }`.

The generated fake (D8) validates its argv strictly (including `--workspace`/`--shell`), reads prompt lines from stdin (one turn per line), replays the capture's NDJSON to stdout once per turn with `ts`-derived delays, and honors an ETX byte (0x03) on stdin as an interrupt — emitting the documented interrupted `finish` (when a tool block is open), then `status idle`, then `ready`. Env knobs: `FAKE_SPEED` (multiplier, 0 = no delay), `FAKE_MIN_LINE_DELAY` (seconds floor, for the deterministic interrupt test).

- [ ] **Step 1: Write the failing tests**

`Tests/SwiftStarKitTests/FakeAgentSourceTests.swift`:

```swift
import Testing
import Foundation
@testable import SwiftStarKit

struct FakeAgentSourceTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("fixtures/agent")
    }

    private func load(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesRoot.appendingPathComponent(name))
    }

    private func makeArgv() -> [String] {
        ["-m", "/tmp/model.gguf", "-c", "32768", "--metal", "--non-interactive",
         "--json-events", "--workspace", "/tmp/ws", "--shell", "off"]
    }

    @Test func generatesFromRealToolCapture() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        // The fake embeds the expected argv (including the consent flags) and
        // the replay lines from the real capture.
        #expect(source.contains("\"-m\", \"/tmp/model.gguf\""))
        #expect(source.contains("\"--workspace\", \"/tmp/ws\""))
        #expect(source.contains("\"--shell\", \"off\""))
        #expect(source.contains("\"phase\":\"start\""))
        #expect(source.contains("argv mismatch"))
    }

    @Test func rejectsInvalidUTF8() {
        let bad = Data([0xFF, 0xFE, 0x00, 0x01])  // torn/invalid UTF-8
        #expect(throws: FakeAgentError.invalidUTF8) {
            _ = try FakeAgentSource.generate(capture: bad, engineArgv: makeArgv())
        }
    }

    @Test func determinism() throws {
        let a = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        let b = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        #expect(a == b)
    }

    @Test func delaysDeriveFromTsDeltas() throws {
        let source = try FakeAgentSource.generate(capture: load("golden-tools.ndjson"), engineArgv: makeArgv())
        // The first replay line (hello) carries delay 0; every line's delay is
        // derived from consecutive ts deltas (fork divergence #7), so the fake
        // needs no sidecar file.
        #expect(source.contains("(0, "))
    }
}
```

- [ ] **Step 2: Run to verify the failure**

Run: `just test`
Expected: FAIL — `FakeAgentSourceTests.swift` does not compile (`FakeAgentSource` undefined).

- [ ] **Step 3: Implement `FakeAgentSource`**

`Sources/SwiftStarKit/FakeAgentSource.swift`:

```swift
import Foundation

public enum FakeAgentError: Error, Equatable, Sendable {
    case invalidUTF8
    case malformedCaptureLine(line: Int, content: String)
}

/// Generates the complete Swift source of a fake `ds4-agent` from a committed
/// NDJSON capture (mirrors `FakeServerSource` for the agent wire). The fake
/// validates its argv strictly (including `--workspace` and `--shell`), reads
/// one prompt line per turn from stdin, replays the capture to stdout with
/// `ts`-derived delays, and honors an ETX byte (0x03) on stdin as an
/// interrupt: it emits the documented interrupted `finish` when a tool block
/// is open, then `status idle`, then `ready`, and stops the turn. `FAKE_SPEED`
/// (0 = no delay) keeps the equivalence test fast; `FAKE_MIN_LINE_DELAY`
/// (seconds floor) gives the interrupt test a deterministic window.
public enum FakeAgentSource {

    public static func generate(capture: Data, engineArgv: [String]) throws -> String {
        guard
            let captureText = String(data: capture, encoding: .utf8)?
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        else {
            throw FakeAgentError.invalidUTF8
        }

        var captureLines = captureText.split(separator: "\n", omittingEmptySubsequences: false)
        if captureLines.last == "" { captureLines.removeLast() }

        // Every event carries a monotonic `ts` (fork divergence #7); derive
        // per-line delays from consecutive deltas — no sidecar file needed.
        // The first line's delay is 0 (no wait before hello), mirroring
        // FakeServerSource's `lastStamp = stamps.first ?? 0`.
        var replay: [(Int, String)] = []
        var lastTS: Int?
        for (index, line) in captureLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let ts = extractTS(from: trimmed) else {
                throw FakeAgentError.malformedCaptureLine(line: index + 1, content: trimmed)
            }
            let delay = lastTS.map { max(0, ts - $0) } ?? 0
            lastTS = ts
            replay.append((delay, String(line)))
        }
        guard !replay.isEmpty else {
            throw FakeAgentError.malformedCaptureLine(line: 0, content: "<empty capture>")
        }

        let argvLiteral = engineArgv.map(FakeServerSource.swiftStringLiteral).joined(separator: ", ")
        let replayLiteral = replay
            .map { "    (\($0.0), \(FakeServerSource.swiftStringLiteral($0.1)))" }
            .joined(separator: ",\n")

        // Raw string template: `\(...)` inside is literal for the generated
        // file; only __ARGV__ / __REPLAY__ are filled.
        let template = #"""
import Foundation
import Darwin

// GENERATED by SwiftStarKit.FakeAgentSource — do not hand-edit.
// Regenerate from the committed capture; a drift test pins this.

let expectedArgv: [String] = [__ARGV__]
let replay: [(Int, String)] = [
__REPLAY__
]

func validateArgv() -> Bool {
    let actual = Array(CommandLine.arguments.dropFirst())
    return actual == expectedArgv
}

if !validateArgv() {
    FileHandle.standardError.write(Data("fake ds4-agent: argv mismatch; expected \(expectedArgv) got \(Array(CommandLine.arguments.dropFirst()))\n".utf8))
    exit(1)
}

let speed = Double(ProcessInfo.processInfo.environment["FAKE_SPEED"] ?? "1.0") ?? 1.0
let minDelay = Double(ProcessInfo.processInfo.environment["FAKE_MIN_LINE_DELAY"] ?? "0") ?? 0

func lineDelay(_ micros: Int) -> TimeInterval {
    max(minDelay, Double(micros) / 1_000_000 / max(speed, 0.0001))
}

func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

// Non-blocking probe: is an ETX (0x03) byte pending on stdin?
func etXPending() -> Bool {
    var p = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    guard poll(&p, 1, 0) > 0 else { return false }
    var b: UInt8 = 0
    return read(STDIN_FILENO, &b, 1) == 1 && b == 0x03
}

// Blocking read of one stdin line (raw bytes; stdio buffering would hide an
// ETX written right after the prompt's newline).
func readPromptLine() -> String? {
    var line = [UInt8]()
    while true {
        var p = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&p, 1, -1) > 0 else { return nil }
        var b: UInt8 = 0
        guard read(STDIN_FILENO, &b, 1) == 1 else { return nil }
        if b == 0x0A { break }
        line.append(b)
    }
    return String(decoding: line, as: UTF8.self)
}

var blockOpen = false

// The engine's documented ETX behavior (json-events.md / divergence #2) plus
// the D12 turn-outcome fields: interrupted finish when mid-block, then
// idle, then a turn-end ready carrying the interrupt stop reason.
func emitInterrupt() {
    if blockOpen {
        emit("{\"t\":\"tool\",\"phase\":\"finish\",\"idx\":0,\"calls\":1,\"status\":\"[tool call interrupted]\\n\",\"ts\":0}")
    }
    emit("{\"t\":\"status\",\"state\":\"idle\",\"prefill_done\":0,\"prefill_total\":0,\"prefill_tps\":0.0,\"generated\":0,\"gen_tps\":0.0,\"ctx_used\":0,\"ctx_size\":0,\"power\":100,\"error\":\"\",\"ts\":0}")
    emit("{\"t\":\"ready\",\"stop_reason\":\"interrupt\",\"generated\":0,\"ctx_used\":0,\"ts\":0}")
}

func replayOnce() {
    for (micros, line) in replay {
        Thread.sleep(forTimeInterval: lineDelay(micros))
        if etXPending() { emitInterrupt(); return }
        emit(line)
        if line.contains("\"phase\":\"start\"") { blockOpen = true }
        if line.contains("\"phase\":\"finish\"") { blockOpen = false }
    }
}

while readPromptLine() != nil {
    replayOnce()
}
"""#

        return template
            .replacingOccurrences(of: "__ARGV__", with: argvLiteral)
            .replacingOccurrences(of: "__REPLAY__", with: replayLiteral)
    }

    /// Extracts the monotonic µs `ts` from a wire line. `ts` is the last field
    /// on every event, and the JSON escaper escapes quotes inside string
    /// bodies, so a bare `"ts":<digits>` occurs only as the real field.
    private static func extractTS(from line: String) -> Int? {
        guard let range = line.range(of: #""ts":(\d+)""#, options: .regularExpression) else { return nil }
        let digits = line[range].dropFirst(5)  // drop `"ts":`
        return Int(digits)
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just test`
Expected: PASS. (If `golden-tools.ndjson` contains a line whose `ts` extraction fails — e.g. a hypothetical capture violation — the `malformedCaptureLine` failure is the evidence; the fixture was verified in Task 5.)

- [ ] **Step 5: Commit**

```bash
git add Sources/SwiftStarKit/FakeAgentSource.swift Tests/SwiftStarKitTests/FakeAgentSourceTests.swift
git commit -m "P7: FakeAgentSource — fake ds4-agent generated from the real tool capture"
```

---

### Task 11: Integration tier — fake `ds4-agent` harness

**Files:**
- Create: `Tests/SwiftStarIntegrationTests/FakeAgentHarness.swift`, `Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift`

**Interfaces:**
- Consumes: `FakeAgentSource.generate(capture:engineArgv:)`, `AgentCommand.argv`/`binaryPath`, `AgentWireParser`, `AgentTranscript`, `TurnOutcome` (Tasks 6–10); `FakeServerHarness.resolveSwiftc()` (reuse the compiler resolution).
- Produces: `struct FakeAgentProcess { process: Process; stdout: Pipe; stderr: Pipe; stdin: Pipe }` (the server harness's `FakeProcess` has no stdin pipe, which the agent fake needs for prompts and the ETX byte); `enum FakeAgentHarness` with `static func fixture(_ name: String) throws -> URL`, `static func compileFake(source: String, into dir: URL) throws -> URL`, `static func spawnAgent(_ binary: URL, arguments: [String], env: [String: String]) throws -> FakeAgentProcess`, and `static func readAgentEvents(_ fake: FakeAgentProcess, parser: inout AgentWireParser, until: @escaping ([AgentEvent]) -> Bool, timeout: TimeInterval = 30) throws -> [AgentEvent]`. The parser is caller-owned: a test spanning multiple read calls (the interrupt test) continues one parse session instead of re-parsing a mid-stream first line as a handshake violation.

- [ ] **Step 1: Write the failing harness + tests**

`Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift`:

```swift
import Testing
import Foundation
import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FakeAgentIntegrationTests {

    private func makeSettings(workspace: URL, shellAllowed: Bool = false) -> AgentSettings {
        AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 32768,
            workspace: workspace,
            shellAllowed: shellAllowed
        )
    }

    private func buildFake(fixture: String, settings: AgentSettings) throws -> (URL, [String]) {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("\(fixture).ndjson"))
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p7-fake-agent-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        return (binary, argv)
    }

    /// Parses the fixture directly for the expected event sequence.
    private func expectedEvents(_ fixture: String) throws -> [AgentEvent] {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("\(fixture).ndjson"))
        var parser = AgentWireParser()
        var out: [AgentEvent] = []
        for line in String(decoding: capture, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if let e = parser.feed(String(line)) { out.append(e) }
        }
        return out
    }

    @Test func fakeReplaysCaptureEventsEquivalently() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = makeSettings(workspace: ws, shellAllowed: true)
        let (binary, argv) = try buildFake(fixture: "golden-tools", settings: settings)

        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: ["FAKE_SPEED": "0"])
        defer {
            fake.process.terminate()
            fake.process.waitUntilExit()
        }
        let expected = try expectedEvents("golden-tools")
        var parser = AgentWireParser()
        FakeAgentHarness.writePrompt(fake, "run your tools")
        let actual = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { $0.count >= expected.count })
        #expect(actual == expected, "fake replay must produce the same events as the capture")
    }

    @Test func fakeRefusesWrongArgv() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = makeSettings(workspace: ws, shellAllowed: false)
        let (binary, _) = try buildFake(fixture: "golden-tools", settings: settings)

        // Wrong argv: workspace differs from what the fake was generated with.
        var wrong = settings
        wrong.workspace = URL(fileURLWithPath: "/tmp/other")
        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: AgentCommand.argv(settings: wrong), env: [:])
        fake.process.waitUntilExit()
        let stderr = String(data: fake.stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(fake.process.terminationStatus != 0)
        #expect(stderr.contains("argv mismatch"))
    }

    @Test func fakeHonorsETXAsInterrupt() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = makeSettings(workspace: ws, shellAllowed: true)
        let (binary, argv) = try buildFake(fixture: "golden-tools", settings: settings)

        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv,
                                                   env: ["FAKE_SPEED": "1", "FAKE_MIN_LINE_DELAY": "0.2"])
        defer {
            fake.process.terminate()
            fake.process.waitUntilExit()
        }
        // One parse session across both reads: the second call starts mid-stream
        // (after the `start` event), so a fresh parser would refuse the first
        // line it sees as a non-handshake.
        var parser = AgentWireParser()
        FakeAgentHarness.writePrompt(fake, "run your tools")
        // Read until a tool block opens, then interrupt mid-replay.
        let sawStart = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { events in
            events.contains {
                if case .tool(let te) = $0, te.phase == .start { return true } else { return false }
            }
        })
        #expect(sawStart.contains { if case .tool(let te) = $0, te.phase == .start { return true } else { return false } })
        FakeAgentHarness.writeETX(fake)
        let interrupted = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { events in
            events.contains {
                if case .tool(let te) = $0, te.phase == .finish, te.status?.contains("interrupted") == true { return true } else { return false }
            }
        }, timeout: 10)
        #expect(interrupted.contains {
            if case .tool(let te) = $0, te.phase == .finish, te.status?.contains("interrupted") == true { return true } else { return false }
        })
        #expect(interrupted.contains { if case .status(let s) = $0, s.ctxUsed == 0 { return true } else { return false } })
        // The fake returns to waiting on stdin (ready), the turn is over, and
        // the D12 fields ride the turn-end ready: the interrupt is the stop reason.
        #expect(interrupted.contains {
            if case .ready(_, let stopReason, _, _) = $0, stopReason == "interrupt" { return true } else { return false }
        })
    }
}
```

Note on the interrupt test's determinism: `FAKE_MIN_LINE_DELAY=0.2` floors every line at 200ms; the fake checks `etXPending()` *after* sleeping and *before* emitting each line. The harness reads until the `start` event (block open), then writes ETX while the fake is sleeping before its next line — the next check finds the ETX and interrupts. The `golden-tools` capture has its tool block mid-stream, so this window exists.

- [ ] **Step 2: Run to verify the failure**

Run: `just integration`
Expected: FAIL — `FakeAgentIntegrationTests.swift` does not compile (`FakeAgentHarness`/`FakeAgentProcess` undefined).

- [ ] **Step 3: Implement the harness**

`Tests/SwiftStarIntegrationTests/FakeAgentHarness.swift`:

```swift
import Foundation
import Darwin
import SwiftStarKit

enum FakeAgentHarnessError: LocalizedError {
    case compileFailed(status: Int32, output: String)
    case timeout(eventCount: Int)
    case unexpectedEOF
    case readFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .compileFailed(let status, let output):
            return "swiftc failed (exit \(status)): \(output)"
        case .timeout(let count):
            return "timed out reading agent events; got \(count)"
        case .unexpectedEOF:
            return "unexpected EOF reading agent events"
        case .readFailed(let code):
            return "read failed: \(String(cString: strerror(code)))"
        }
    }
}

/// The agent fake's process handles. A separate struct from the server
/// harness's `FakeProcess` because the agent wire is stdin/stdout pipes (no
/// socket), and the fake needs the stdin pipe to write prompts and the ETX
/// interrupt byte.
struct FakeAgentProcess {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
    let stdin: Pipe
}

enum FakeAgentHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> URL {
        repoRoot.appendingPathComponent("fixtures/agent").appendingPathComponent(name)
    }

    static func compileFake(source: String, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mainFile = dir.appendingPathComponent("main.swift")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = try FakeServerHarness.resolveSwiftc()
        process.arguments = [mainFile.path, "-o", dir.appendingPathComponent("fake-ds4-agent").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FakeAgentHarnessError.compileFailed(status: process.terminationStatus, output: output)
        }
        return dir.appendingPathComponent("fake-ds4-agent")
    }

    static func spawnAgent(_ binary: URL, arguments: [String], env: [String: String]) throws -> FakeAgentProcess {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        let inp = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = inp
        try process.run()
        return FakeAgentProcess(process: process, stdout: out, stderr: err, stdin: inp)
    }

    static func writePrompt(_ fake: FakeAgentProcess, _ prompt: String) {
        fake.stdin.fileHandleForWriting.write(Data((prompt + "\n").utf8))
    }

    static func writeETX(_ fake: FakeAgentProcess) {
        fake.stdin.fileHandleForWriting.write(Data([0x03]))
    }

    static func closeStdin(_ fake: FakeAgentProcess) {
        try? fake.stdin.fileHandleForWriting.close()
    }

    /// Reads the fake's stdout, feeding `AgentWireParser`, until `until`
    /// returns true or the timeout elapses. The fake stays alive between
    /// prompts, so completion is a predicate, not EOF. Uses a blocking
    /// `Darwin.read` loop (the same shape as `FakeServerHarness.readEvents`):
    /// `FileHandle.availableData` blocks with no way to honour the deadline,
    /// and conflates "quiet" with "EOF" — a slow fake would hang the test or
    /// fail it spuriously. Reading raw bytes keeps the deadline real. The
    /// parser is caller-owned and shared across calls (see the interrupt
    /// test): a fresh parser on a second call would refuse the first
    /// mid-stream line as a non-handshake.
    static func readAgentEvents(_ fake: FakeAgentProcess,
                                parser: inout AgentWireParser,
                                until: @escaping ([AgentEvent]) -> Bool,
                                timeout: TimeInterval = 30) throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        let fd = fake.stdout.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n == 0 { throw FakeAgentHarnessError.unexpectedEOF }
            if n < 0 {
                if errno == EINTR { continue }
                throw FakeAgentHarnessError.readFailed(errno: errno)
            }
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let event = parser.feed(line) {
                    events.append(event)
                    if until(events) { return events }
                }
            }
        }
        throw FakeAgentHarnessError.timeout(eventCount: events.count)
    }
}
```

- [ ] **Step 4: Run to verify the tests pass**

Run: `just integration`
Expected: PASS — all three `FakeAgentIntegrationTests` green (replay equivalence, argv refusal incl. `--workspace`/`--shell`, ETX interrupt).

- [ ] **Step 5: Commit**

```bash
git add Tests/SwiftStarIntegrationTests/FakeAgentHarness.swift Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift
git commit -m "P7: integration — fake ds4-agent replay, argv validation, ETX interrupt"
```

---

### Task 12: App — `AgentController` + `AgentView` + `MainView`

**Files:**
- Create: `Sources/SwiftStar/AgentController.swift`, `Sources/SwiftStar/AgentView.swift`
- Modify: `Sources/SwiftStar/MainView.swift` (replace the Agent placeholder)

**Interfaces:**
- Consumes: `AgentCommand`, `AgentSettings`, `AgentWireParser`, `AgentEvent`, `AgentTranscript`, `AgentTranscriptRow`, `ToolCard`, `ToolParam`, `TurnOutcome`, `TurnOutcomeBuilder`, `TurnStopReason` (Tasks 6–9).
- Produces: `@MainActor @Observable final class AgentController` with `state: AgentState`, `transcript: AgentTranscript`, `stderrTail: [String]`, `lastTurnOutcome: TurnOutcome?` (D12 — the full trail goes to `SWIFTSTAR_LOG`), `settings: AgentSettings`, `func startIfNeeded()/startAgent()/send(_:)/interrupt()/stopAgent()`, `var canSend: Bool`, `var isGenerating: Bool`; `struct AgentView: View`.

The controller is app glue (like `EngineController`): deliberately thin, every decision it consumes lives in Kit and is fast/integration-tested. D9: it does **not** re-wire Metrics/Diagnostics; D10: it passes no `--think` flag and offers no think control; D5: interrupt = one `0x03` byte on stdin; D6: turn end inferred from `status.state → idle`.

- [ ] **Step 1: Implement `AgentController`**

`Sources/SwiftStar/AgentController.swift`:

```swift
import Foundation
import Observation
import SwiftStarKit

/// The agent child's lifecycle + turn state. Unlike the server's `Supervisor`
/// state machine, the agent wire carries no explicit turn-end event: turn end
/// is inferred from `status.state → idle` (D6).
@MainActor
@Observable
final class AgentController {
    enum AgentState: Equatable {
        case stopped
        case starting
        case ready       // handshake seen, idle (waiting for or between turns)
        case generating  // a turn is in flight
        case stopping
        case failed(String)
    }

    private(set) var state: AgentState = .stopped
    private(set) var transcript = AgentTranscript()
    private(set) var stderrTail: [String] = []
    /// The last completed turn's outcome record (D12); the full trail goes to
    /// the SWIFTSTAR_LOG file. Persistence beyond that is P9/P10 work.
    private(set) var lastTurnOutcome: TurnOutcome?
    var settings: AgentSettings

    nonisolated(unsafe) private var process: Process?
    private var parser = AgentWireParser()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var startupTimeoutTask: Task<Void, Never>?
    private var generation = 0
    // D12 turn-outcome state.
    private var outcomeBuilder: TurnOutcomeBuilder?
    private var sentInterrupt = false
    private var buildSHA = "unknown"
    nonisolated(unsafe) private let logHandle: FileHandle?

    init(settings: AgentSettings = AgentController.defaultSettings()) {
        self.settings = settings
        if let logPath = ProcessInfo.processInfo.environment["SWIFTSTAR_LOG"] {
            let url = URL(fileURLWithPath: logPath)
            if !FileManager.default.fileExists(atPath: logPath) {
                FileManager.default.createFile(atPath: logPath, contents: nil)
            }
            self.logHandle = try? FileHandle(forWritingTo: url)
        } else {
            self.logHandle = nil
        }
    }

    deinit {
        process?.terminate()
        try? logHandle?.close()
    }

    var canSend: Bool { state == .ready }
    var isGenerating: Bool { state == .generating }

    static func defaultSettings() -> AgentSettings {
        let defaults = UserDefaults.standard
        let engineDir: URL
        if let dir = defaults.string(forKey: "engineDir"), !dir.isEmpty {
            engineDir = URL(fileURLWithPath: dir)
        } else if let dir = ProcessInfo.processInfo.environment["DS4_DIR"] {
            engineDir = URL(fileURLWithPath: dir)
        } else {
            engineDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("external/ds4")
        }
        let modelPath: URL
        if let path = defaults.string(forKey: "modelPath"), !path.isEmpty {
            modelPath = URL(fileURLWithPath: path)
        } else if let env = ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"], !env.isEmpty {
            modelPath = URL(fileURLWithPath: env)
        } else {
            modelPath = URL(fileURLWithPath: "/Users/pauleveritt/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf")
        }
        let contextSize = defaults.object(forKey: "contextSize") as? Int ?? 32768
        let workspace: URL
        if let dir = defaults.string(forKey: "agentWorkspace"), !dir.isEmpty {
            workspace = URL(fileURLWithPath: dir)
        } else {
            workspace = FileManager.default.homeDirectoryForCurrentUser
        }
        // D2: the app's default posture is deny — shell off until granted.
        let shellAllowed = defaults.bool(forKey: "agentShellAllowed")
        return AgentSettings(
            engineDir: engineDir,
            modelPath: modelPath,
            contextSize: contextSize,
            workspace: workspace,
            shellAllowed: shellAllowed
        )
    }

    func startIfNeeded() {
        if state == .stopped { startAgent() }
    }

    func startAgent() {
        switch state {
        case .stopped, .failed: break
        default: return
        }
        let binary = AgentCommand.binaryPath(settings: settings)
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = .failed("agent binary missing at \(binary.path)")
            return
        }
        state = .starting
        generation += 1
        let gen = generation
        // A restart is a fresh wire: the handshake state must reset or the new
        // session's hello is misread as a second handshake (stuck in
        // .starting forever). The transcript is deliberately kept (history,
        // like EngineController); stderrTail is reset so a failure message
        // never pairs a new session with a stale tail.
        parser = AgentWireParser()
        stderrTail = []
        outcomeBuilder = nil
        sentInterrupt = false
        // D12: the build identification is resolved once per spawn (the
        // submodule SHA — the same fact the capture provenance records).
        buildSHA = AgentController.submoduleSHA(settings.engineDir)

        let process = Process()
        process.executableURL = binary
        process.arguments = AgentCommand.argv(settings: settings)
        process.currentDirectoryURL = settings.engineDir  // metal/*.metal resolve relative to CWD
        process.environment = ProcessInfo.processInfo.environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                // The engine's failure mode is exiting (stderr boot lines are
                // normal — the memory plan lives there); a mid-start or
                // mid-turn exit is a failure carrying the stderr tail.
                if self.state == .starting || self.state == .generating {
                    self.state = .failed("agent exited (\(p.terminationStatus)): \(self.stderrTail.joined(separator: "\n"))")
                } else if self.state != .stopped {
                    self.state = .stopped
                }
            }
        }
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            state = .failed("spawn failed: \(error)")
            return
        }

        stdoutTask?.cancel()
        stdoutTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }  // EOF: the child closed stdout
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeWire(line, generation: gen)
                }
            }
        }

        stderrTask?.cancel()
        stderrTask = Task.detached(priority: .utility) { [weak self] in
            let handle = stderrPipe.fileHandleForReading
            var buffer = Data()
            while !Task.isCancelled {
                let data = handle.availableData
                if data.isEmpty { break }
                buffer.append(data)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer[buffer.startIndex..<nl]
                    buffer.removeSubrange(buffer.startIndex...nl)
                    let line = String(decoding: lineData, as: UTF8.self)
                    await self?.consumeStderr(line, generation: gen)
                }
            }
        }

        startupTimeoutTask?.cancel()
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled else { return }
            if self.state == .starting {
                self.state = .failed("agent did not handshake within 60s")
                self.process?.terminate()
            }
        }
    }

    private func consumeWire(_ line: String, generation: Int) {
        guard generation == self.generation else { return }
        guard let event = parser.feed(line) else { return }
        // Every event feeds the outcome builder (it ignores what it does not
        // need); the record spans the whole turn, not just tool events.
        outcomeBuilder?.apply(event)
        switch event {
        case .hello:
            if state == .starting { state = .ready }
        case .status(let s):
            // D6: turn end is inferred from the idle state transition (state
            // changes bypass the 200ms status throttle, so this is reliable).
            if state == .generating && s.state == "idle" {
                state = .ready
            }
        case .ready(_, let stopReason, _, _):
            if state == .starting { state = .ready }
            // D12: the turn-end ready carries the stop reason — finish the
            // record. The app's own interrupt beats the wire's word for it.
            if stopReason != nil, let builder = outcomeBuilder {
                let outcome = builder.finish(appStopReason: sentInterrupt ? .interrupt : nil)
                outcomeBuilder = nil
                lastTurnOutcome = outcome
                log("turn outcome: \(outcome)")
            }
        case .text, .think, .tool:
            transcript.apply(event)
        case .queued, .ignored:
            break
        case .refused(let line):
            state = .failed("wire handshake refused: \(line)")
            process?.terminate()
        }
    }

    private func log(_ s: String) {
        guard let logHandle else { return }
        var data = Data((s + "\n").utf8)
        try? logHandle.seekToEnd()
        try? logHandle.write(contentsOf: data)
    }

    /// The engine build identification (D12): the submodule SHA, resolved
    /// once per spawn — the same fact the capture provenance records.
    private static func submoduleSHA(_ engineDir: URL) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", engineDir.path, "rev-parse", "HEAD"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }

    private func consumeStderr(_ line: String, generation: Int) {
        guard generation == self.generation else { return }
        stderrTail.append(line)
        if stderrTail.count > 20 { stderrTail.removeFirst(stderrTail.count - 20) }
    }

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !trimmed.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return }
        transcript.appendSystem("> \(trimmed)")
        state = .generating
        sentInterrupt = false
        // D12: open the turn's outcome record with the app-known facts the
        // wire cannot carry. sampler is "engine-defaults": the app passes no
        // sampler flags (D10's think default is the engine's too).
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            sampler: "engine-defaults",
            task: trimmed
        )
        pipe.fileHandleForWriting.write(Data((trimmed + "\n").utf8))
    }

    /// D5: interrupt = write one ETX byte (0x03) to the child's stdin. The
    /// engine latches it, emits an interrupted `finish` when mid-block, and
    /// returns to idle; the controller reflects that via the wire.
    func interrupt() {
        guard isGenerating, let process,
              let pipe = process.standardInput as? Pipe else { return }
        sentInterrupt = true
        pipe.fileHandleForWriting.write(Data([0x03]))
    }

    func stopAgent() {
        guard state != .stopped else { return }
        state = .stopping
        stdoutTask?.cancel()
        stderrTask?.cancel()
        startupTimeoutTask?.cancel()
        // EOF on stdin first (the same clean-exit shape as swiftstar-drive):
        // the engine's non-interactive loop exits on EOF rather than relying
        // on SIGTERM alone.
        (process?.standardInput as? Pipe)?.fileHandleForWriting.close()
        process?.terminate()
        // The termination handler lands on .stopped (its guard passes: state
        // is .stopping, not .stopped) after recording the exit.
    }
}
```

- [ ] **Step 2: Implement `AgentView` + wire `MainView`**

`Sources/SwiftStar/AgentView.swift`:

```swift
import SwiftUI
import SwiftStarKit

/// One tool card: name, params, bash output, and a status line when the block
/// did not close cleanly (interrupt / parse error / hard failure).
struct ToolCardView: View {
    let card: ToolCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                Text(card.name).font(.callout).bold()
                Spacer()
            }
            ForEach(Array(card.params.enumerated()), id: \.offset) { _, param in
                Text("\(param.name): \(param.value)")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let output = card.output {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if let status = card.status {
                Text(status).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct AgentView: View {
    @Bindable var controller: AgentController
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcriptView
            Divider()
            consentControls
            Divider()
            composer
        }
        .navigationTitle("Agent")
        .task { controller.startIfNeeded() }
    }

    private var statusBar: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.caption)
            Spacer()
            if controller.isGenerating {
                Button("Interrupt") { controller.interrupt() }
            } else {
                agentButton
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var agentButton: some View {
        switch controller.state {
        case .ready, .generating, .starting:
            Button("Stop Agent") { controller.stopAgent() }
        case .stopped, .failed:
            Button("Start Agent") { controller.startAgent() }
        case .stopping:
            Button("Start Agent") { controller.startAgent() }.disabled(true)
        }
    }

    private var statusText: String {
        switch controller.state {
        case .stopped: return "Agent stopped"
        case .starting: return "Starting agent…"
        case .ready: return "Agent ready"
        case .generating: return "Working…"
        case .stopping: return "Stopping…"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .stopped: return .gray
        case .starting, .stopping: return .yellow
        case .ready: return .green
        case .generating: return .blue
        case .failed: return .red
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.transcript.rows.count) { _, _ in
                let last = controller.transcript.rows.count - 1
                guard last >= 0 else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: AgentTranscriptRow) -> some View {
        switch row {
        case .thinking(let text):
            Text(text).font(.callout).foregroundStyle(.secondary).italic()
        case .content(let text):
            Text(text).font(.body).textSelection(.enabled)
        case .tool(let card):
            ToolCardView(card: card)
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// Spawn-time consent (D2): the workspace grant and the shell toggle apply
    /// when the agent next starts; changing them never mutates a live child.
    private var consentControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workspace").font(.caption).foregroundStyle(.secondary)
                TextField("Workspace directory", text: Binding(
                    get: { controller.settings.workspace.path },
                    set: { controller.settings.workspace = URL(fileURLWithPath: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            Toggle("Allow shell commands", isOn: Binding(
                get: { controller.settings.shellAllowed },
                set: { controller.settings.shellAllowed = $0 }
            ))
            .font(.caption)
            Text("Applied when the agent starts.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    private var composer: some View {
        HStack {
            TextField("Message the agent", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .disabled(!controller.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
    }

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard controller.canSend, !message.isEmpty else { return }
        input = ""
        controller.send(message)
    }
}
```

`Sources/SwiftStar/MainView.swift` — replace the Agent placeholder:

```swift
            AgentView(controller: agentController)
                .tabItem { Label("Agent", systemImage: "person.crop.circle") }
```

and add the controller to the view state (next to the other `@State` models):

```swift
    @State private var agentController = AgentController()
```

- [ ] **Step 3: Verify the app target compiles**

Run: `swift build`
Expected: builds. (`just test` covers the Kit/AppKit/test targets; the app executable needs an explicit `swift build` — this is where a SwiftUI/AppKit compile error would surface, exactly as P2's argv/CWD bugs surfaced in the live tier, not the fast tier.)

- [ ] **Step 4: Commit**

```bash
git add Sources/SwiftStar/AgentController.swift Sources/SwiftStar/AgentView.swift Sources/SwiftStar/MainView.swift
git commit -m "P7: Agent tab — controller, tool-card transcript view, consent controls"
```


---

### Task 13: Close — roadmap, concept budget, verification record

**Files:**
- Modify: `ROADMAP.md`, `docs/superpowers/research/2026-08-22-p7-verification-record.md` (create)

- [ ] **Step 1: Verify the full suite**

Run: `just test` then `just integration` then `make -C external/ds4 test`.
Expected: all green.

- [ ] **Step 2: Write the verification record** (`docs/superpowers/research/2026-08-22-p7-verification-record.md`) in the P5 record's style: test evidence per tier (fast counts, integration counts, live recapture results incl. the golden-tools verification numbers and the stop-reason greps), the outcome-telemetry evidence (D12: golden-tools turn outcomes with full tool lifecycles and stop reasons), shown-fail records (binding rule 2 table), real bugs found, scope compliance.

- [ ] **Step 3: Update the roadmap**

- `## Now`: P7 complete → P8 next ("Next up; not started").
- Phases table: P7 row → `complete (2026-08-22)`.
- Add the P7 summary under Prior work (mirror the P6 entry; cite the spec path).
- Concept budget: define the terms P7 earns — **workspace** (the confinement root + cwd the app grants at spawn; the file tools fail closed outside it), **tool card** (the transcript's per-call reconstruction of one tool invocation from the wire's phase stream), and **turn outcome** (the capture-grade per-turn record — model/build/sampler and task, token and context use, stop reason, tool lifecycles — that P10's handoff packets consume instead of trusting the transcript). Check the existing seed terms: **handoff packet** (unrelated, stays), **candidate ref** (unrelated).
- **Amend the P4 sequencing bullet with a dated correction** (the same way P6 corrected the P11 bullet): the live metrics wiring did **not** land with P7 — the phase row never included it, and P7's plate carried the consent patch, the outcome wire, two fixtures, and a new tab; Metrics/Diagnostics stay fixture-driven until a later phase (the spec's D9 records the deviation).

- [ ] **Step 4: Commit**

```bash
git add ROADMAP.md docs/superpowers/research/2026-08-22-p7-verification-record.md
git commit -m "P7: close — roadmap, concept budget, verification record"
```

- [ ] **Step 5: Phase close review**

Self-review against the spec's "Testing" section: evidence floor (rule 6) met in Tasks 6/7/10/11; binding rule 2 recorded in Task 13 Step 2; every component from the spec's Components section exists with a test in the tier the spec assigned. Then the branch is ready for the phase review and merge per `docs/sdd.md` step 5.

---

## Self-Review

(For the plan author, run before handoff.)

**1. Spec coverage.** Every D decision and component maps to a task: D1/D2 → Tasks 1–2 (engine) + 9 (argv) + 12 (app defaults); D3 → Task 6; D4 → Task 8; D5 → Tasks 10–11 (fake honors ETX) + 12 (controller writes ETX); D6 → Task 6 (StatusSnapshot.state) + 12; D7 → Task 5; D8 → Tasks 10–11; D9 → Task 12 (explicit non-goal + the recorded P4-bullet deviation); D10 → Task 8 (think handled) + 12 (no think control); D11 → Task 1 (only bash gated); D12 → Task 3 (engine stop reason) + 6 (ready fields) + 7 (TurnOutcome) + 12 (controller wiring) + 5 (fixture proves it). Fixtures → Task 5; engine → Tasks 1–4; Kit → 6–10; integration → 11; app → 12; close → 13.

**2. Placeholder scan.** Every task has real code in the failing-test and implementation steps; no "add error handling", no "similar to Task N" (the harness/template code is repeated where needed), no undefined type references (AgentEvent/AgentToolEvent/AgentToolPhase/ready-fields defined in Task 6 before Tasks 7/8/11/12 use them; FakeAgentProcess defined in Task 11; StatusSnapshot.state added in Task 6; TurnOutcome/Builder defined in Task 7 before Task 12 uses them).

**3. Type consistency.** `AgentToolPhase` cases match the wire spellings everywhere (paramBegin/paramValue/paramEnd via raw values); `AgentToolEvent` field names consistent across Tasks 6, 7, 8, 11; `AgentTranscript`/`ToolCard`/`ToolParam` consistent across Tasks 8, 12; `TurnOutcome`/`TurnStopReason`/`ToolCallOutcome`/`ToolLifecycle` and the `ready(plannedBytes:stopReason:generated:ctxUsed:)` shape consistent across Tasks 6, 7, 11, 12; `AgentSettings`/`AgentCommand.argv` consistent across Tasks 9, 11, 12 (including `--workspace`/`--shell` ordering — the fake validates the exact array). `FakeServerSource.swiftStringLiteral` is reused (public, already exists) so the escaper stays single-sourced.

**Cross-cutting note for the executor:** Task 6 adds `state: String` to the shared `StatusSnapshot` (the controller needs it for D6 turn-end inference). That is an additive change to one existing file (`WireEventParser.swift`) and mechanical updates to the P6 tests that construct `StatusSnapshot`; Metrics/Diagnostics logic ignores the new field. Shown-fail discipline applies to the affected tests too.

---

## GLM 5.2 review (2026-08-22)

*(Task numbers in this section refer to the pre-deep-review numbering — before the
outcome-telemetry tasks (3 and 7) were inserted and the tasks renumbered. The trail
is kept as it was written; the deep review below records what changed since.)*

Reviewed by GLM 5.2 (OpenRouter `z-ai/glm-5.2`) with the plan, the design spec,
`external/ds4/docs/json-events.md`, and the real sources it names. The review
was delivered in two calls (the first was truncated at the token limit; the
second completed with reasoning disabled). Findings were verified against the
codebase before applying — the two that contradicted the code were dismissed:

### Accepted and applied

| Finding | Applied as |
|---|---|
| `AgentController` never resets the wire parser on restart; `sawHandshake` persists, so a second session's `hello` is read as a second handshake and the tab sticks in `.starting` | Task 10 Step 1: `startAgent` resets `parser = AgentWireParser()` and `stderrTail = []` |
| `agent_tool_list` takes no `agent_worker *w`, so the plan's `w->cfg` confinement cannot compile | Task 2 Step 5: signature gains `agent_worker *w`; dispatch call site (`:11300`) updated; exact per-tool code for read/write/list/search/edit, incl. `agent_preflight_edit_old` |
| `blockStartClearsPriorBlockCards` asserted a stale post-`start` output is not attached, but the reducer re-keys `cardRows[0]` when the new block's `tool` phase arrives, so it is; the scenario is a wire violation D4 does not defend against | Task 6 test rewritten to pin the defined behavior (two same-`idx` blocks → two distinct cards) and document the undefined case |
| `FakeAgentSource.generate` initialized `lastTS = 0`, so the first line's delay was `ts` (nonzero), failing `delaysDeriveFromTsDeltas`'s `(0, ` assertion and sleeping before `hello`; `FakeServerSource` seeds from the first stamp | Task 8: `lastTS` is `Int?`, first delay 0 |
| `FakeAgentHarness.readAgentEvents` used `FileHandle.availableData` in a deadline loop: it blocks (no deadline honouring) and conflates "quiet" with "EOF"; a second call with a fresh parser would refuse the first mid-stream line | Task 9: `Darwin.read` loop with a real deadline (same shape as `FakeServerHarness.readEvents`); `readFailed` error; parser is caller-owned and shared across the interrupt test's two reads |
| Config default location: the plan said "the `agent_config c = {0};` line in `main`"; the config is a designated initializer in `parse_options` (`:660`) and `main` calls `parse_options` (`:15021`) | Task 1 Step 3: default added to the real initializer |
| "recompute sizes" in the prompt-builder change was too vague for a zero-context executor | Task 1 Step 4: exact rewritten `agent_build_glm_tools_prompt` / `agent_build_laguna_tools_prompt` with `agent_schemas_for` into a stack buffer and conditional `agent_bash_jobs_rule` append |
| `stopAgent` did not close stdin (swiftstar-drive closes it for a clean EOF exit) | Task 10: stdin closed before `terminate()` |
| `send`/`interrupt` silently no-op'd if `standardInput` was not a `Pipe` | Task 10: explicit `guard let pipe = process.standardInput as? Pipe` |

### Dismissed after verification

- **`Task.detached` captures non-Sendable `Pipe` (flagged MAJOR).** The existing
  `EngineController` (`Sources/SwiftStar/EngineController.swift:214,234`) uses
  the identical pattern and ships; `Package.swift` is swift-tools 6.2 with
  default (minimal) concurrency checking. The plan mirrors proven code.
- **Hardcoded default model path (flagged MINOR).** Identical to the existing
  `EngineController.defaultSettings()` default; consistent with the codebase.
- **`availableData` "returns empty immediately" (part of the harness finding).**
  The P5 verification record documents the opposite — a blocking read that hung
  the capture driver. The real defects were the un-honoured deadline and the
  fresh-parser-on-second-read, both fixed above.

---

## Deep review (2026-08-22)

Adversarial review of the spec and plan together — the spec against the settled
design (`BRIEF.md`, `ROADMAP.md` at main's tip, `json-events.md`), the plan against
the real sources — with every finding verified against the codebase before a fix.
Findings and dispositions:

### Accepted and fixed

| Finding | Verification | Fix |
|---|---|---|
| **BLOCKING (spec):** the branch forked before main's `0ee5f6c` ("require outcome telemetry before handoff packets"), so the spec was written against a roadmap that did not yet demand "capture-grade turn/tool outcomes" of P7 — model/build/sampler + task, token/context use, stop reason (EOS, limit, interrupt, timeout, context-full), and tool lifecycle transitions (emitted, parsed, rejected, executed). Neither spec nor plan delivered a turn-outcome record; the wire carries no stop reason at all. | `git log` on the branch vs main; the phase row and dependency bullet in the rebased ROADMAP. | Branch rebased onto main; spec gains **D12** (with options weighed: app-side-only rejected — 3 of 5 stop reasons unknowable; new event kind rejected; **stop reason on the turn-end `ready`** chosen); plan gains Task 3 (engine), the `ready` fields in Task 6, Task 7 (`TurnOutcome`/`TurnOutcomeBuilder`), the fixture checks in Task 5, the fake/integration assertions in Tasks 10–11, the controller wiring in Task 12, and the close-task concept-budget term (**turn outcome**). |
| **MAJOR (spec):** D9 defers the live metrics wiring that the roadmap's P4 bullet says "lands with P7's `ds4-agent` migration" — silently contradicting the roadmap. | The P4 sequencing bullet (ROADMAP, "P4's telemetry data lives on the agent wire"). | The spec's D9 now records the deviation explicitly (dated); Task 13 amends the P4 bullet with a dated correction at close — the same way P6 corrected the P11 bullet. |
| **BLOCKING (plan):** `agent_schemas_for` used bare `strstr(p, …)` per line — but `strstr` searches past the line's newline into later lines, and `google_search`/`visit_page` come *before* the bash entries in `agent_glm_tool_schemas`, so `--shell off` would silently drop the web tools too (violating D11) — and the unit test didn't check for it. | `agent_glm_tool_schemas` line order (google_search, visit_page, bash, bash_status, bash_stop, read, …). | Line-bounded matcher `agent_schema_line_is_bash` (memcmp within the line); the Task 1 test now asserts google_search/visit_page survive shell-off — the sibling that catches an unbounded matcher. |
| **MAJOR (plan):** the bash-jobs prompt split claimed the bash line is the *final* line of both `after_schemas` constants; it is second-to-last (`- Preserve the current system configuration…` is last), and appending the rule after the constant would reorder the prompt — while `test_agent_glm_tools_prompt_is_native` pins the shell-on prompt. | `ds4_agent.c` ~:1196–1200 (GLM) and ~:1249–1251 (Laguna): both constants end "…bash jobs…\n- Preserve…\n"; both bash lines are byte-identical. | Each `after_schemas` splits into head + tail at the bash line; the builders insert the shared `agent_bash_jobs_rule` between head and tail only when the shell is on — byte-identical shell-on prompts. |
| **MAJOR (plan):** Task 1's dispatch unit test constructed `agent_worker w = {0}` without the mutex/wake-fd setup the existing harness tests use — the shell-on branch runs the real bash dispatch path, so it would be UB. | `test_agent_execute_tool_call_unknown_tool_trims_torn_utf8_name` (~:8882) initializes `pthread_mutex_init(&w.mu, NULL)` and `w.wake_fd[1] = -1`. | The test now mirrors that setup verbatim. |
| **MINOR (plan):** the golden recapture had no tool-free check, but Task 6's test asserts the fixture carries no tool events — a stray tool call would surface as a confusing fast-tier failure later. | Task 6's `goldenNdjsonParsesWithoutRefusing` asserts `.tool` events are absent. | Task 5 Step 6 greps the recaptured `golden.ndjson` for `"phase"` (must be 0) and re-runs the capture if the model emitted a tool call. |
| **MINOR (plan):** the fake's `emitInterrupt` emitted a bare `ready` — the real engine now emits the turn-end `ready` with `stop_reason` (D12), so the fake modeled less than the engine does. | D12's wire addition. | The fake's interrupt `ready` carries `stop_reason: interrupt` (+ generated/ctx_used); the integration interrupt test asserts it. |

### Dismissed after verification

- **The `--shell off` schema would still advertise bash via the prompt intro.**
  The intros list tools only in the `<available_tools>` schemas block; the rules
  prose is advice, now gated with the bash-jobs rule split. Nothing else names bash.
- **Two `~48 GiB` engine loads (Chat's server + Agent's agent) when both tabs run.**
  Real, but the settled design sanctions it (`BRIEF.md`: Chat and Agent are different
  wires and different products); the per-engine feasibility gate (P3) covers each
  load. The P4-bullet amendment at close records the deferral conversation honestly
  rather than smuggling a Chat-to-agent migration into P7.

The GLM 5.2 review's findings (above) all remain applied; none were reverted by this
pass.
