# P11 addendum — the canonical agent test: live run (2026-08-23)

**Status:** first live run, n=1, easy + hard spec, real engine (Laguna S 2.1).
The canonical agent test is now the project's reproducible headless proof that
the subagent machinery works end to end.

## Command

```bash
SWIFTSTAR_MODEL=<laguna-s-2.1 gguf> DS4_DIR=$PWD/external/ds4 \
  swift run swiftstar-agenttest --spec roadmap            # easy (imperative)
SWIFTSTAR_MODEL=<laguna-s-2.1 gguf> DS4_DIR=$PWD/external/ds4 \
  swift run swiftstar-agenttest --spec roadmap-user-story  # hard (user-story)
```

The harness decomposes the roadmap into its 3 phases, runs each as a subagent in
a chained-worktree transaction (`--subagent-pool 2`, one worker slot), and grades
the final candidate with the cumulative acceptance suite (`uv run pytest`).

## Result — easy (`roadmap.md`)

Three phases, each a candidate; the acceptance suite passed.

| Phase | Outcome | Mutations | Tokens |
|---|---|---|---|
| 1 (home page) | candidate | 5 | 486 |
| 2 (complaints board) | candidate | 4 | 287 |
| 3 (add complaint) | candidate | 4 | 309 |
| **Final** | candidate | — | — |
| **Acceptance** | **exit 0** (13 tests) | — | — |

## Result — hard (`roadmap-user-story.md`)

Phase 1 produced a candidate; Phase 2 returned a **`noChanges` receipt** — the
transaction stopped. This reproduces the recorded user-story finding: the
outcome-only spec does not trigger building, so the model declines to act.

| Phase | Outcome |
|---|---|
| 1 (welcoming front door) | candidate (6 mutations) |
| 2 (board where complaints are heard) | **receipt noChanges** |

## What this establishes (n=1)

- The harness drives the whole P11 path headlessly: decompose → handoff packet →
  chained worktrees → subagent turn → candidate ref → acceptance grade.
- The **easy** spec is winnable by the implementer model (3 phases, acceptance
  green) — the test is not a ceiling.
- The **hard** spec discriminates: it stops on the "no agency" failure, exactly
  the signal the local-ai-pi `user-story-arms.md` record predicted.

## What it does not establish

n=1, one model, no variance, no statistical claim. The DeepSeek qualitative
read ("does the code look good vs the spec") is wired as `GraderVerdict` but its
live invocation over the harness's *own* output is the next pass — this run's
deterministic acceptance suite is the grade.

## DeepSeek grader — demonstration

The grader prompt (rubric = `roadmap.md` + `mission.md` + `tech-stack.md`, plus
the generated code) was run against the **reference** implementation (known-good)
as a sanity check. `deepseek/deepseek-chat` returned:

```json
{"verdict":"good","reasons":["Correctly uses FastAPI as specified in the rubric",
  "Implements all three phases of the spec including home page, complaints board,
  and complaint submission", "Includes all required templates with proper Jinja2
  inheritance", "Properly handles form submission with redirect", "Includes seed
  complaints with the required 'Scope creep never ends.' text", ...]}
```

The grader parses into `GraderVerdict.parse(...) == .good`. Wiring this same
prompt over the harness's *own* output (via the code-dump the harness will write
before `discardFinal`) is the remaining grader step.
