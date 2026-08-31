# SwiftStar P24.3 design: the deterministic run+digest family

**Date:** 2026-08-30
**Status:** proposed
**Phase:** P24 — Digested first-class tools (feature cycle 3)

P24's thesis is **deterministic, host-owned tools — no model in the loop**. A
**tool** is deterministic host code (run one command, digest the output); a
**subagent** has a model in the loop (out of scope here). This cycle ships the
first rung of the ladder: the **run+digest family** — `test`, `lint`, and a
digested `bash`. The ladder's later rungs are not this cycle: `scout` (its own
cycle), the **policy gate** and **model-asks-human** (the "for the novel"
escalation, a later cycle together).

## Evidence — one observed session

[`captures/live/20260830-155556`](../../../captures/live/20260830-155556) is
one observed session. It justifies design *constraints*, not measured claims.

1. **`test` — the model cannot be trusted to name the verification command.**
   A dispatch packet's task text literally said "Build and test the SwiftStar
   project" and then ran `swift build`, with `validationCommand` also `swift
   build`. The failure was the translation from *intent* to *command*, not
   motivation. A `test` rung parameterized by a model-supplied command string
   reproduces this bug with more ceremony. **The rung runs the project's test
   command; the model gets no say in what it is.**

2. **`scout` — default the corpus to the repo, never silently drop `Tests/`.**
   All five searches in the session were `path: "Sources"`; `TranscriptFontScale`
   was a good query but the scope was the bug. `TranscriptFontScaleTests` appears
   zero times in the 542 KB wire. A symbol scout reporting "1 definition in
   Sources, 5 uses in Tests" makes an invariant's second home structurally
   visible. *(Constraint recorded here for the scout cycle to inherit.)*

3. **Validation contracts are a separate hole from the ladder.** That dispatch
   had `writableFiles: ""` (correct for verification) and a validation command
   that passes whether or not the change is right. P12's "real validation" is
   only as strong as the command. A host-side check — task text says "test",
   validation must invoke the test runner — is itself deterministic and testable.
   *(Flagged here; its own item, not folded into this cycle — see Out of scope.)*

Not carried over, deliberately:

- The **dispatch dead-lettered** (zero worker events) and was not diagnosed.
  That is a possible pool bug, independent of the ladder — its own chip, not
  P24.3.
- **"Completed turn" is not a proxy for real work.** `--latest` flagged 249 of
  500 captures because sessions killed mid-turn and pooled captures with work on
  worker 1 both look empty by that measure. `SwiftStarKit/CaptureUsability.swift`
  (`recordsWork`) is the corrected predicate; capture selection uses it, never
  the old proxy.

## Scope

**In this cycle:**

- `test` — run the project's host-resolved test command, digest the failures.
- `lint` — run the host-resolved `ruff` command, digest the diagnostics.
- digested `bash` — re-scope the existing `bash` tool's *result*: the model
  never sees unbounded raw output; the result is a `BashDigest` summary.
- The `ProjectCommandResolver` that derives these commands from the workspace.
- One engine patch adding the `test`/`lint` schemas and the `bash` description
  tweak (one fork-ledger row, one golden recapture).
- The paired-bill measurement at close.

**Out of this cycle (each its own later work):**

- `scout` and its deterministic files+symbols index (next cycle; inherits the
  constraint above).
- The **policy gate** and **model-asks-human** — the ladder's "for the novel"
  end. The policy is designed *with* its escalation; a gate with no human path
  is a half-ladder. `bash` keeps its existing `shellAllowed` consent unchanged.
- The **validation-contract check** (task says "test" → validation invokes the
  test runner) — a distinct deterministic item on the dispatch path, not a
  model-facing tool.
- **Sphinx** and "roadmap admin" — deferred; one digester each under this
  machinery when a consumer exists (P14 docs site is still planned).
- **pyrefly** — same `RuffDigest` shape, different command, added behind a param
  later; `lint` ships ruff-first.
- **swiftlint** — not named in the P24 row; a possible follow-on under the same
  host-owned-command principle.
- Artifact **cleanup** beyond the in-cycle prune (see Data flow).

## Components

The repo splits pure logic (`SwiftStarKit`) from side-effecting glue
(`SwiftStarAppKit`). This cycle follows it.

**In `SwiftStarKit` (pure, no I/O, red-first unit-tested):**

- `CommandOutput` — `{stdout, stderr, exit, timedOut}`. Needed because
  `SubprocessRunner.Result` lives in AppKit and the pure digesters cannot depend
  on it.
- `ToolDigest` — the digesters' product:
  `{summary: String, command: String, artifactPath: String, outputDigest: String}`.
- Three pure digesters, each
  `static func digest(_ out: CommandOutput, command: String, artifactPath: String) -> ToolDigest`:
  - `TestDigest` — cluster test failures by (file, error signature); a pluggable
    parser for XCTest text (`swift test`) and pytest JSON (`--json-report`), one
    shared clustering core.
  - `RuffDigest` — group ruff JSON diagnostics by (rule, file).
  - `BashDigest` — arbitrary text: bounded structured summary, never a raw dump.
- `ProjectCommandResolver` — derive the test/lint commands from the workspace.
- `ToolCallbackResponder.deterministicTools` — the new consent set (`test`,
  `lint`).

**In `SwiftStarAppKit` (side-effecting, thin glue):**

- `CommandToolRunner` — one method per tool (`runTest`, `runLint`, `runBash`):
  run the fixed command via `SubprocessRunner`, write full stdout+stderr to the
  artifact, call the pure digester, assemble the `ToolExecutionResult`.
- `HostToolExecutor` gains `test`/`lint` cases; its `bashResult` is re-scoped to
  call `BashDigest` instead of returning raw combined stdout.

## Digest contract

Every digest shares one frame, ≤8000 bytes so `ToolResultCondenser` is a no-op:

1. **Status header** — what ran and the verdict (`exit N` / `timed out after
   300s`) plus a count.
2. **Command echo** — the exact command the *host* ran (transparency +
   re-runnability; never a model string).
3. **Digest body** — the clustered/grouped/summarized content.
4. **Artifact pointer** — `full output: .swiftstar/runs/<tool>-<sha>.<ext>`.

**"Lossless-for-the-decision" is a checkable property, not a slogan:** the
clustering key is chosen so every failure in one cluster maps to the *same
edit*; the representative carries everything needed to make it (`file:line` +
message + sibling count); the only thing dropped is redundancy *within* a
cluster, never anything that distinguishes one cluster from another; the count +
artifact pointer make the dropped items recoverable. **This is the hypothesis
the paired-bill measurement validates** — the fast tier pins determinism,
boundedness, and totality, not decision-completeness.

**`TestDigest`** — key = (test file, error signature); representative = one
test identifier + source location + assertion, with sibling count. Example:

```
pytest: 12 passed, 7 failed (exit 1)          # or: swift test: 7 failed (exit 1)
Ran: <host-resolved command>
2 clusters (7 failures):
[1] tests/test_api.py — 4 failures
    tests/test_api.py::test_create_user
    AssertionError: expected 201, got 500   (src/api.py:42)
[2] tests/test_db.py — 3 failures
    tests/test_db.py::test_migration
    OperationalError: no such table   (src/db.py:17)
full output: .swiftstar/runs/test-<sha>.log
```

More than 2 clusters → show the 2 largest + "and N more clusters (see full
output)".

**`RuffDigest`** — key = (rule code, file); representative = one `file:line:col`
+ message, with counts:

```
ruff: 18 diagnostics, 4 files (exit 1)
Ran: <host-resolved ruff command>
2 rule groups (4 total):
[1] F401 unused-import — 6 in 3 files
    src/app.py:12:1 'os' imported but unused
[2] E501 line-too-long — 9 in 2 files
    src/util.py:88:1 line too long (92 > 88)
full output: .swiftstar/runs/lint-<sha>.json
```

**`BashDigest`** — arbitrary text, no clustering; "never raw" means never an
unbounded dump:

```
bash: exit 0 (Ran: <cmd>)
<full output if ≤ 4000 bytes, else head/tail + artifact pointer>
```

Today's `bash` returns raw stdout+stderr and lets the blind 8000-byte condenser
truncate the middle with no pointer; `BashDigest` makes the truncation
deliberate and recoverable.

**Total, never crash:** non-JSON output from `test`/`lint` (a crashed runner, a
traceback on stdout) or a missing command (exit 127) falls back to a
`BashDigest`-style bounded summary. A digest is a total function over
`CommandOutput`.

## Consent and params

- `test` — admitted via `deterministicTools`, **no shell toggle**. Host-owned
  command; the model supplies only an optional typed `selector` (a path/test-name
  filter, appended to the host command), never a command string.
- `lint` — admitted the same way; **no params**.
- `bash` — unchanged consent (`shellAllowed` gate); only its result is re-scoped.

The tool/bash distinction: a tool runs a fixed, host-assembled command, so the
model cannot inject arbitrary shell; `bash` runs arbitrary commands and keeps
its gate.

**`ok` semantics (deliberate difference from `bash`):** for `test`/`lint`, `ok`
means *the runner executed and produced a digest* — failing tests or diagnostics
are a successful run (the failures live in the digest + `exitStatus`). `ok:false`
is reserved for "could not run" (not installed / timeout / no project). `bash`
keeps its existing `ok` = command success; the difference is documented, not
silently changed.

## Data flow (`test` end-to-end)

1. Model calls `test` with `{selector: "FontScaleTests"}` (or `{}`).
2. `ToolCallbackResponder.consent` admits it (`deterministicTools` → `.proceed`).
3. `HostToolExecutor` routes to `CommandToolRunner.runTest`.
4. `ProjectCommandResolver` picks the command — `Package.swift` → `swift test`;
   `pyproject.toml` → `uv run pytest`; Swift wins in mixed repos. The selector is
   charset-validated (`[A-Za-z0-9_./-]`, reject everything else) and appended.
5. `SubprocessRunner.run`; timeout 300s.
6. Full stdout+stderr written to `.swiftstar/runs/test-<sha256>.log` (the artifact is
   always `.log` — it is the raw combined output, not a JSON document).
7. `CommandOutput` → pure `TestDigest.digest` → `ToolDigest`.
8. Assemble `ToolExecutionResult{text: summary, exitStatus, outputDigest:
   sha256(stdout), validationRan: true}`.
9. Responder condenses (no-op ≤8000) → `tool_result` → KV.

**Error handling — the digester is total:**

- command not installed (exit 127) → "could not run: <stderr head>", `ok:false`;
- timeout → "timed out after 300s; partial output at <path>";
- non-JSON stdout → text parser / bounded-summary fallback;
- no recognized project → deterministic refusal
  "no `Package.swift` or `pyproject.toml` in workspace";
- artifact write fails → digest still returned, without the artifact pointer;
- selector fails the charset whitelist → refusal, not silent execution.

**Artifact growth:** names are content-addressed; prune to the last 20 runs per
tool at write time (deterministic, cheap).

## Engine patch

One fork-ledger row:

- Add `test` + `lint` schema constants and append them in `agent_schemas_for`
  under `--host-tools`, following the `dispatch` precedent exactly (fork
  divergence #12). The DSML/DeepSeek block is **untouched** — the same way
  `dispatch` itself is handled; DeepSeek visibility is a separate decision,
  flagged here and not decided.
- Tweak the `bash` schema description to say output is digested.
- Golden recapture + provenance note (standing rule: every submodule bump owes a
  recapture).
- A schema-presence assertion: under `--host-tools` the engine advertises both.

## Cycles

| # | Cycle | Gate | Risk |
|---|---|---|---|
| 1 | Pure core: `CommandOutput`, `ToolDigest`, `ProjectCommandResolver`, `TestDigest` (XCTest + pytest parsers), `RuffDigest`, `BashDigest`, `ToolCallbackResponder.deterministicTools` | fast tier green, **red first** | none |
| 2 | Wiring: `CommandToolRunner` (run/archive/assemble), `HostToolExecutor` `test`/`lint` cases + `bash` → `BashDigest` | integration tests green; artifact, timeout, not-installed, consent pins | low |
| 3 | Engine patch: `test`/`lint` schema constants + `agent_schemas_for` append (dispatch precedent; DSML untouched) + `bash` description, fork-ledger row, golden recapture, schema-presence assertion | recapture clean; schema assertion green | medium (engine change) |
| 4 | Measurement: paired-bill `swiftstar-analyze diff` replay vs control arm, pre-registered falsifier, research note | note committed with the falsifier answered either way | the cycle's one live step |

## Tests

**Fast tier (pure, no model, no subprocess):**

- `TestDigest` parsers against committed fixtures: XCTest text → expected
  clusters; pytest JSON → same shape; pytest text fallback → bounded summary.
  Refusal-adjacent cases get a sibling success (rule 3).
- `RuffDigest`: JSON fixture → rule groups + counts; 0 diagnostics → "0
  diagnostics"; unparseable → fallback.
- `BashDigest`: ≤4000 bytes shown whole; large → head/tail + artifact pointer;
  pins "never raw".
- **Condense-no-op pin:** for a pathological 1000-failure run,
  `ToolResultCondenser.condense(summary) == summary`.
- **Determinism pin:** same `CommandOutput` → byte-identical `ToolDigest`.
- `ProjectCommandResolver`: `Package.swift` → `swift test`; `pyproject.toml` →
  pytest; mixed → Swift precedence; neither → refusal.
- Selector validation: `[A-Za-z0-9_./-]` passes; `; rm -rf`, `$(...)`, backticks
  → refusal + sibling success.

**Integration tier (real files, fake engine, seconds):**

- `CommandToolRunner` against a tiny fixture project: artifact written to
  `.swiftstar/runs/`; digest carries correct sha + command echo + artifact path;
  artifact contains the full output.
- `HostToolExecutor`: `test`/`lint` admitted without the shell toggle; unknown
  tool still refused; `bash` returns `BashDigest` (pin: "bash result is digested,
  never raw").
- Timeout → "timed out"; bogus binary → "could not run".

## Measurement (the close gate)

Paired-bill `swiftstar-analyze diff`: replay the observed session (the one that
ran `swift build` instead of `swift test`) with the tools available, against a
control arm without them. **Pre-registered falsifier:** the digest drops nothing
decision-relevant. No self-reported savings — measure Σsuffix. Capture selection
uses `CaptureUsability.recordsWork`, never "completed turn".

## Out of scope

`scout` (next cycle; inherits the corpus/Tests constraint); the policy gate +
model-asks-human (later, together); the validation-contract check (its own
deterministic item on the dispatch path); sphinx + roadmap admin (deferred);
pyrefly (same shape, later param); swiftlint (unnamed in the P24 row); artifact
cleanup beyond the 20-per-tool prune.

## Note on status

Stamped `proposed` until the cycles ship, then `implemented` (per the P23/P24.1
specs: do not leave a shipped spec mis-stamped).

## Documents this spec invalidates

Correct these when cycle 3 lands:

1. The **P24 row** in [`ROADMAP.md`](../../../ROADMAP.md), description cell —
   "`test` (pytest → ~2 clustered representatives…)" narrows `test` to pytest;
   this spec generalizes it to **the project's host-resolved test command**
   (`swift test` / pytest). Update the parenthetical when the engine patch lands.
2. [`docs/glossary.md`](../../glossary.md) — the `tool` entry ("later P24's
   `test`/`scout`/`lint`") stays accurate; no change, but check it at phase end.
