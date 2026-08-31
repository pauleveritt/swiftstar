---
phase: P24
cycle: P24.3-run-digest-family
lifecycle: active
---

# P24.3 run+digest family implementation plan

## Goal

Ship deterministic host-owned `test`, `lint`, and digested `bash` tools. The
host derives commands, runs them, archives full output, and gives the model a
bounded deterministic digest. The model never supplies a command string.

## Constraints

- Digesters are total pure functions over `CommandOutput` and produce bounded
  `ToolDigest` values.
- Test failures are clustered into actionable representatives; Ruff findings
  are grouped by rule and file; arbitrary shell output is never unbounded.
- Tool consent, command derivation, selector validation, artifacts, and
  `outputDigest` remain host-owned.
- Engine schemas are advertised only under `--host-tools`.
- Red-first tests, a fork-ledger row, one golden recapture, and a paired live
  measurement are required before closure.

## Tasks

### 1. Value types

Create `CommandOutput` and `ToolDigest` in `Sources/SwiftStarKit/`, with fast
tests in `Tests/SwiftStarKitTests/ToolDigestTests.swift`.

### 2. Project command resolution

Create `ProjectCommandResolver` and tests. Resolve Swift/Python project
markers, derive `test`/`lint`, and validate selectors without shell syntax.

### 3. Bash digest

Create `BashDigest` and tests. Preserve small output, bound large output, and
always retain the artifact pointer and stdout digest.

### 4–5. Test digest

Create the XCTest parser, clustering core, pytest JSON parser, and their tests
in `Sources/SwiftStarKit/TestDigest.swift` and
`Tests/SwiftStarKitTests/TestDigestTests.swift`. Non-JSON output must fall back
honestly and never crash.

### 6. Ruff digest

Create `RuffDigest` and tests, and add the minimal Ruff development
configuration to `pyproject.toml`.

### 7. Consent and callback admission

Update `Sources/SwiftStarKit/ToolCallbackResponder.swift` and its tests with a
`deterministicTools` consent set and the new tool branches.

### 8. Host runner

Create `CommandToolRunner` in `Sources/SwiftStarAppKit/` with integration tests
for run, archive, assemble, timeout, and refusal behavior.

### 9. Executor wiring

Update `Sources/SwiftStarAppKit/HostToolExecutor.swift` and integration tests
to run `test`/`lint`, digest `bash`, and preserve the existing app seam.

### 10. Engine contract

Update `external/ds4/ds4_agent.c`, its C tests, and the fork ledger to advertise
the schemas under `--host-tools`; preserve the existing DSML/DeepSeek block.

### 11. Fixture recapture

Build the engine, recapture the agent fixtures, copy bundled resources, and
record provenance in `fixtures/agent/provenance.md`.

### 12. Measurement and close

Commit the preregistered paired-bill protocol, run control and treatment arms,
answer the digest falsifier, add the research record, update `ROADMAP.md`, and
then add this plan's `## Result` section.

## Verification commands

Use focused fast tests during Tasks 1–7, integration tests for Tasks 8–9, the
engine test target for Task 10, `just integration` after recapture, and
`swiftstar-analyze diff` for the paired bill. No live measurement belongs in
CI.
