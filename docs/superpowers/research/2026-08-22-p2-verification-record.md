# P2 verification record (2026-08-22)

Durable record for Phase P2 ("It launches and answers"). Executed on branch
`p2-it-launches-and-answers` (worktree `.worktrees/p2-it-launches-and-answers`),
spec-driven per `docs/sdd.md`.

## Test evidence

- **Fast tier** (`just test`): 35 tests in 7 suites, green in ~0.3s — no model,
  no network, no subprocess (tripwire-guarded).
- **Integration tier** (`just integration`): same 35 tests plus the 3
  env-gated `FakeServerIntegrationTests` green in ~3.5s. The fake engine was
  **compiled from `fixtures/server/golden.sse`** with `swiftc`, spawned with
  strict argv, streamed over TCP; the parsed event sequence matched the
  capture exactly (`fakeReplaysCaptureEventsEquivalently`). Wrong argv refused
  with exit≠0 and an "argv mismatch" stderr line. The fake announces
  `listening on http://…` on stderr (supervisor ready detection).
- **App bundle** (`just app`): `.build/SwiftStar.app` with executable,
  `AppIcon.icns` (generated star icon), and `Info.plist`.
- **Live smoke** (manual, real engine): the app auto-started the real
  `ds4-server` from the P1 submodule build with a probed free port (51392);
  the engine booted (Metal, 46.51 GiB planned) and announced
  `ds4-server: listening on http://127.0.0.1:51392`; all stderr was streamed
  to `SWIFTSTAR_LOG`. A full chat turn through the UI remains a manual step
  (the SSE streaming path itself is pinned by the integration tier against the
  identical wire shape).

## Shown-fail / break-and-restore records (binding rule 2)

| Behavior pinned | Break | Observed failure | Restored green |
|---|---|---|---|
| Tripwire (T2) | fast test referencing `Process(` | build failed: `FAST-TIER TRIPWIRE … TripwireProbeTests.swift:6: Process(` | yes |
| SSE `.ignored` refusal (T3) | wrong expected payload | `malformedDataIsIgnoredNotRefused` failed | yes |
| Supervisor `.stopping→.exit→.stopped` (T4) | transition removed | `stopFromReadyGoesToStoppingThenStopped` failed — this caught an accidental broken commit, amended | yes |
| Fake generator refusal (T6) | malformed-line guard removed | `refusesMalformedCapture` failed (2 issues) | yes |
| Integration transport fidelity (T7) | generator dropped every 2nd line | `fakeReplaysCaptureEventsEquivalently` failed (fake ≠ capture) | yes |

## Real bugs found by the live tier (fake tier could not catch them)

1. **argv contract**: `ServerCommand.argv` included the binary path, but
   `Process` prepends argv[0] itself — the real engine got its own path as an
   unknown option. The fake validated the same wrong contract
   self-consistently (a hand-authored-style belief about the wire); the real
   binary was the tie-breaker. Fixed: `argv` excludes the binary path;
   `ServerCommand.binaryPath` supplies it. Spec D5 amended with a retraction.
2. **Metal sources / CWD**: the engine resolves `metal/*.metal` relative to
   CWD; the app inherited the launcher's CWD. Fixed: spawn with
   `currentDirectoryURL = engineDir` (the P1-documented "run from inside
   external/ds4" behavior).
3. **Auto-start**: the engine only started on a button click; the done-when
   says the app starts the server, so Chat auto-starts when stopped (a failed
   state stays visible for deliberate retry).

## Scope compliance

No agent mode (P7), no metrics (P4), no diagnostics (P6), no downloads (P3),
no `swiftstar-drive` (P5), no NDJSON parser (P7), no wire handshake (P5). No
source-text assertions; refusal tests have sibling success tests. No submodule
bump; `external/ds4` untouched.

## Concept budget

Definitions landed in the plan glossary: **seam**, **wire**, **capture**,
**fixture**.
