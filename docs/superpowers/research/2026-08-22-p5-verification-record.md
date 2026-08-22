# P5 verification record (2026-08-22)

Durable record for Phase P5 ("Capture is a program, not a lost file"). Executed on
branch `p5-capture-is-a-program`, spec-driven per `docs/sdd.md`.
Spec: `docs/superpowers/specs/2026-08-22-p5-capture-is-a-program-design.md`.

## Test evidence

- **Fast tier** (`just test`): 83 tests green, 12 integration-gated tests skipped —
  no model, no network, no subprocess (tripwire-guarded). New: handshake
  enforcement (`helloParsesHandshake`, `firstNonBlankLineMustBeHandshake`,
  `unknownVersionRefuses`, `missingRequiredCapRefuses`, `malformedFirstLineRefuses`)
  and `statusCarriesTs`; every existing parser test now feeds the handshake first.
- **Integration tier** (`just integration`): 95 tests green across 17 suites.
  New: `CaptureWriterTests` (2 — byte-verbatim files + provenance; missing-dir
  creation).
- **Live tier** (`just capture`, manual, never CI): a one-shot smoke confirmed the
  patched `ds4-agent` emits `{"t":"hello","v":1,"caps":[…],"ts":…}` first and `ts`
  on every event. The recapture produced `golden.ndjson` (43 lines: 1 hello, 19
  status, 3 ready, all with `ts`), `golden.trace` (1187 lines), `golden.stderr`
  (9 lines).

## Shown-fail records (binding rule 2)

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| CaptureWriter verbatim files (T2) | write the wire bytes into `wire.stderr` | `writesVerbatimFilesAndProvenance` failed | yes |
| handshake version check (T4) | `v == 1` → `v == 2` | `helloParsesHandshake` and `goldenNdjsonParsesWithoutRefusing` failed | yes |

## Real bugs found during P5 (by the live tier, not review)

1. **The driver hung after the last turn.** The final `drainStdout(until: { false })`
   blocked forever in `FileHandle.availableData`: the idle engine emits no more
   stdout, so the blocking read never returned and the deadline was only checked
   *between* reads. Fixed by replacing blocking reads with `readabilityHandler`
   callbacks (stdout parsed + tee'd, stderr tee'd) and a main loop that polls the
   ready-count — no blocking reads at all.
2. **The driver wiped the engine's environment.** `process.environment =
   ["DS4_LOCK_FILE": …]` replaced (not merged) the parent environment, dropping
   `HOME`; the engine then wrote `./.ds4/kvcache` into the submodule checkout
   instead of `$HOME/.ds4`. Fixed by inheriting
   `ProcessInfo.processInfo.environment` and overriding only `DS4_LOCK_FILE`.

## The fixture carries the scratch under-report verbatim

`golden.ndjson`'s `ready` events still carry `scratch_bytes: 784752` (the
estimator's single-row figure), while the same session's `golden.stderr` carries
`ds4: Laguna GPU graph: ctx=32768, prefill=16384, KV 1.57 GiB, scratch 5862.21 MiB`
— the ~6.1 GB per-session under-report documented in
`docs/superpowers/research/2026-08-22-p11-engine-constraints-and-corrections.md`.
`fixtures/agent/provenance.md` records this so the fixture is not misread. The
engine-side fix (the estimator's Laguna branch multiplying by `prefill_cap` rows)
is upstream-bound and **deferred** — see the "engine-side memory-plan / tokenize
CLI" backlog entry.

## GLM 5.2 implementation review (applied post-implementation)

The committed implementation was reviewed by GLM 5.2 (OpenRouter `z-ai/glm-5.2`);
accepted findings applied (commit `865178e`):

1. **`ts` was documented as "since engine start" but is monotonic-since-boot.**
   `clock_gettime(CLOCK_MONOTONIC)` returns boot-relative time; the comment, the
   Swift doc, the provenance render, and the spec all claimed "since engine
   start", and the prose promised wall-clock correlation that is unfulfillable
   without recording the monotonic start. Fixed the wording everywhere (only
   deltas are meaningful; the provenance records wall-clock start for anchoring)
   rather than adding a start-delta that would force another recapture.
2. **The driver ignored a refused handshake.** `DriveState.onStdoutData` only
   counted `.ready`; a wrong-build engine (no `hello`) would capture silently,
   violating binding rule 7. Added a `refusal` flag; the driver aborts with
   `FATAL: wire handshake refused: …`.
3. **Trailing bytes could be lost after exit.** `readabilityHandler = nil` after
   `waitUntilExit` without a final drain. Added `readDataToEndOfFile()` on both
   pipes after exit.
4. **Hardcoded `DS4_LOCK_FILE`** became pid-unique so a stale/concurrent capture
   cannot collide.

Dismissed after verification: "handshake missing outside non-interactive" —
`--json-events` requires `--non-interactive` (a startup error otherwise), so
`run_agent_non_interactive` is the only valid entry point.

## Concept budget

**handshake** and **trace** are now defined (see ROADMAP); **capture** is re-worded
to drop the retired timestamp sidecar (timestamps are on the wire now).

## Scope compliance

No telemetry-to-disk capture (deferred; P6's diagnostics do not need it), no
`ds4-server` capture, no CI automation of the live tier. The scratch-bytes
estimator fix was deferred to the backlog rather than absorbed into P5.
