# P1 done-when verification record (2026-08-22)

Durable record of the Task 8 verification for Phase P1 ("The fork,
consolidated"). The plan said the verification is "recorded in the session log
and (optionally) the roadmap"; this file makes the fork-state sign-off durable
in the repo (recommended by the post-completion deep review). ROADMAP.md marks
P1 complete (2026-08-22).

## Fork state (checked via gh + git ls-remote)

- `pauleveritt/ds4` is a fork of `antirez/ds4`; default branch `main`
  (`gh repo view pauleveritt/ds4 --json parent,defaultBranchRef`).
- `main` is pristine: fork main SHA `84cc882352757baf628a1776badf7cc54d584e28`
  == antirez main SHA `84cc882352757baf628a1776badf7cc54d584e28` (exact match,
  fast-forward mirror, never edited).

## Integration branch

- `swiftstar-integration` carries the 22 app-required commits
  (status marker ×2, turn-interrupt ×1, stale-interrupt latch ×1,
  `--json-events` ×16, startup memory plan ×2) on the `laguna-s2.1` model line:
  40 commits above `main` = 17 laguna-s2.1 + 22 app + 1 docs commit
  (`git log --oneline origin/main..origin/swiftstar-integration | wc -l`).
- `patch-set` exists on the fork (tip `53dd1a4`); `main` is not touched.
- No scope leaks: no Swift, no app, no Mellum on the integration,
  no `--subagent-pool`, no upstream PRs (`docs/upstream-proposals.md` states
  nothing has been filed).

## Submodule pin + one-command build

- Captures were taken at `b3d2b5e0d4b15f223d333921797b4a6fd018aeae` (the
  gitlink == local HEAD == remote `swiftstar-integration` tip at capture time).
- After the deep-review fix, the pin moved to `0b3f0c7` — a docs-only fork
  commit (REBASING.md + fork-ledger.md); the engine tree is byte-identical to
  `b3d2b5e`, so per the standing rule's docs-only exception (written into
  REBASING.md) no recapture was required. The golden captures remain valid at
  `b3d2b5e`.
- `just engine` builds both binaries: `git submodule update --init external/ds4`
  + `make -C external/ds4 ds4-server ds4-agent` — clean, both binaries present.

## Fork docs (on `swiftstar-integration`, absent from pristine `main`)

- `REBASING.md`: standing recapture rule present; harness method now
  cross-references `fixtures/{agent,server}/provenance.md`.
- `docs/fork-ledger.md`: 6 divergence rows (status marker, turn-interrupt,
  stale-interrupt latch, `--json-events`, startup memory plan, integration
  structure), each with a retirement condition, plus the orig→new SHA mapping.
- `docs/upstream-proposals.md`: present; flagship = structured-events mode for
  non-interactive agents; explicitly not filed upstream.

## Golden captures committed (SwiftStar, main)

- `fixtures/agent/golden.ndjson` + `.sidecar` + `provenance.md`
  (NDJSON recapture from `ds4-agent`; 2136 wire lines == 2136 sidecar lines;
  every line valid JSON; 7 `ready` events byte-identical with the four memory
  fields matching the `ds4: memory:` boot line; one interrupted `finish` with
  `"status":"[tool call interrupted]\n"`).
- `fixtures/server/golden.sse` + `.sidecar` + `provenance.md` (first SSE capture
  from `ds4-server`; canonical = house-puzzle request, 6312 lines, 3155 data
  chunks all valid JSON, ends `data: [DONE]`) and
  `golden.short.sse` + `.sidecar` (the "sky is blue" request, 674 lines).

## Harness notes for the record

- A hung external `ds4 --mellum-resident-profile` (from an unrelated
  `decode_sweep.sh` on this machine) held `/tmp/ds4.lock`; the captures used a
  distinct `DS4_LOCK_FILE` and never touched that process.
- The capture runs needed all 21 `DS4_METAL_*_SOURCE` env vars (absolute)
  because `--chdir` defeats the in-submodule `cd` for Metal shader resolution —
  see the retraction recorded at plan Task 6 Step 3 and
  `fixtures/agent/provenance.md` gotcha #1.

## Post-completion deep review fixes (applied 2026-08-22)

1. `fixtures/server/provenance.md`: corrected `id` (per-request increment:
   `chatcmpl-2` in the canonical capture) and `created` (per-chunk emit second,
   57 distinct values over 56 s — not a constant request epoch).
2. `.gitignore`: comment pointed at `Tests/`; now `fixtures/`.
3. Plan Task 6 Step 3: retraction recorded (the literal command fails under
   `--chdir`); `REBASING.md` + `fork-ledger.md` updated on the fork (0b3f0c7).
4. ROADMAP.md: completion date corrected to 2026-08-22.
