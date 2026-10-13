# SU.6b: the Session card and an honest prefill average

A small cycle (`docs/sdd.md`): one doc, no spec. This is part of SU.6's
punch list. It covers the session-level, live view in the inspector.
Per-prompt analysis belongs to phase AN on the `session-last` branch, whose
report already has per-pause rates.

## Decisions

The owner made these on 2026-10-13.

**D1. Scope: the session's setup and its prefix cache.** Several items stay
on the punch list for a later part:
- start-up timings and the engine's stderr notices
- the "session avg" label, locale and units
- model sizes in the menu
- the loader's timing

**D2. A Session card at the top of the inspector** shows:
- **Model:** the model id.
- **DFlash:** "On" or "Off". The engine's reason sits under it, word for
  word, in secondary text: "plan 19.27 GiB <= budget 107.52 GiB", "no
  drafter" or "--no-dflash". When DFlash is on, the drafter's file name
  follows.
- **Prefix cache:**
  - a hit reads "hit · 944 tokens in 20 ms"
  - a miss reads "miss · 944 tokens filled in 3.9s"
  - any other outcome shows the engine's word, then the token count

Before the engine reports, each row shows "—".

**D3. Prefill avg leaves out a cache hit's tokens.** A hit's tokens are
loaded, not prefilled, but the engine counts them as prefilled. The
evidence is session `20261013-154825-session-last`:
- **The event:** `prefix_cache` reported a hit, 944 tokens loaded in 20 ms.
- **The checkpoint after it:** 1146 prefill tokens in 1084 ms.
- **Today's figure:** about 1,057 tok/s.
- **The honest figure:** (1146 − 944) / (1084 − 20) ms ≈ 190 tok/s.

When the correction applies:
- **Counters:** `checkpoint` counters accumulate over the whole engine
  process. Sessions `122106` and `123136` show they never reset at a prompt.
  So the correction lasts until the next `session` event, which only a new
  process sends.
- **A miss:** changes nothing, because those tokens really were prefilled.

The engine request in the ROADMAP Backlog stays open, with a note that the
app works around it.

## Facts this rests on

- **`session.dflash`** (`../ds4-engine/src/ds4_engine/dflash.py:40-47`)
  has these keys:
  - `on`, `label`, `reason`
  - `drafter`: a path or null
  - `plan_gib`, `gpu_budget_bytes`

  It may be missing: the engine's own TUI checks it with `if dflash:`.
- **`prefix_cache`** (`fixtures/engine/tool-read.ndjson`) has `outcome`,
  `prefix_tokens`, `load_ms` and `fill_ms`. It's sent once per process, on
  the first prompt.
- **Every recorded fixture is a miss.** The recorder starts with an empty
  state directory, so the hit numbers come from session `154825`, cited in
  the test.

**Corrected (final review, 2026-10-13).** Two claims above are wrong. D3's
"counters accumulate over the whole engine process" and the Facts' "sent once
per process" both fail in these cases:
- **After `/clear` or a compaction:** the engine fills the system prefix
  again and sends another `prefix_cache` (`operator.py:186-190`).
- **`prefill_tokens`:** it isn't a process counter. It's the conversation's
  transcript length minus its evals (`operator_telemetry.py:101-113`), so it
  collapses after `/clear`.
- **A resumed conversation:** it sends no `prefix_cache` and loads its KV
  instead. Session `160812`, resumed from `154825`, shows 41,949 tokens in
  393 ms, which reads as about 106,700 tok/s.

Sessions `122106` and `123136` contain no `/clear` or resume, so they
couldn't test the claim. The code stands:
- the hit correction is right for the case it targets
- after `/clear` it keeps the prior rate rather than showing about 0
- the resume inflation needs the engine (ROADMAP, Engine requests)

## Tasks

### Task 1: Kit decodes DFlash and the prefix cache; the honest prefill rate

**Files:**
- `Sources/SwiftStarKit/EngineEvent.swift`
  - `:177-185`: `EngineSessionInfo` gains `dflash`
  - `:187-`: `EngineEvent` gains `prefixCache`
- `Sources/SwiftStarKit/EngineWireParser.swift`
  - `:63-66`: the session case
  - a new `"prefix_cache"` case
- `Sources/SwiftStarKit/EngineMetrics.swift`: the state and the reducer
- `Sources/SwiftStarKit/MetricsFormatting.swift`: the prefix-cache line
- Tests:
  - `EngineWireParserTests`
  - `EngineMetricsTests`
  - `MetricsFormattingTests`

**Interfaces:**
- `public struct EngineDFlash: Equatable, Sendable`, with `on: Bool`,
  `reason: String` and `drafter: String?` (a path).
- `EngineSessionInfo.dflash: EngineDFlash?`. The init gains
  `dflash: EngineDFlash? = nil`, so existing call sites still compile.
- `public struct EnginePrefixCache: Equatable, Sendable`, with
  `outcome: String`, `tokens: Int?`, `loadMs: Double?` and `fillMs: Double?`.
- `EngineEvent.prefixCache(EnginePrefixCache)`.
- `EngineMetricsState.prefixCache: EnginePrefixCache?`.
- The reducer:
  - **`.prefixCache(p)`** stores `p`.
  - **`.session`** clears the stored value, because a new process means new
    counters.
  - **`.pause`:** when the stored outcome is `"hit"`, the prefill rate uses
    `prefillTokens − tokens` over `prefillMs − (loadMs ?? 0)`. Either
    difference must stay above 0; if it doesn't, keep the prior rate.
- `MetricsFormatting.prefixCacheLine(_ p: EnginePrefixCache) -> String`:
  - a hit gives "hit · N tokens in X ms"
  - a miss gives "miss · N tokens filled in" plus `duration(seconds:)`
  - any other outcome gives the engine's word and "· N tokens"
  - N goes through `number(_:)`, and X is milliseconds rounded

**Tests** (each shown to fail first):
- `toolReadFixtureDecodes` (extended): the `.session` event has
  `dflash.on == true`, a `reason` starting "plan 19.27 GiB", and a
  `drafter` ending `dflash-Qwen3.8-27B-Q4_0.gguf`. The fixture's
  `.prefixCache` has outcome "miss" and 944 tokens.
- A new `afterReady` row, `sessionWithoutDFlash`: a `session` line with no
  `dflash` key gives `EngineSessionInfo(..., dflash: nil)`.
- `prefixHitLeavesCachedTokensOut` (EngineMetricsTests), using session
  `154825`'s numbers:
  - hit, 944 tokens, `loadMs` 20
  - then a pause with prefill 1146 tokens in 1084 ms
  - expected: `prefillTPS` is about 189.8 (±0.5)
- `prefixMissKeepsTheRate`: the same pause after a miss gives about
  1057.2 (±0.5).
- `newSessionDropsTheCorrection`: after the hit, a `.session` event and the
  same pause give about 1057.2.
- `prefixCacheLine`, a table:
  - a hit gives "hit · 944 tokens in 20 ms"
  - a miss with `fillMs` 3880 gives "miss · 944 tokens filled in 3.9s"
  - outcome "error" gives "error · 944 tokens"

  It uses the en_US locale for the number.

Break check: drop the hit subtraction, and `prefixHitLeavesCachedTokensOut`
fails.

### Task 2: the Session card, the preview and the close

**Files:**
- `Sources/SwiftStarUI/Inspector/InspectorView.swift`: a "Session" card
  above "Context"
- `Sources/SwiftStarUI/PreviewSupport/PreviewFixtures.swift:31`: the
  running model's `.session` gains `dflash`, and a `.prefixCache` hit
  follows it
- `ROADMAP.md`:
  - SU.6's Status
  - the punch-list lines this resolves
  - the engine request's "worked around" note
- This doc's `## Result`

**What the card shows:**
- **Model:** `engine.transcript.session?.modelID ?? "—"`.
- **DFlash:**
  - "On" or "Off", or "—" with no session
  - the reason in `.secondary` text
  - when on and the drafter is set, the drafter's `lastPathComponent`
- **Prefix cache:** `engine.metrics.prefixCache.map(MetricsFormatting.prefixCacheLine) ?? "—"`.

It uses the existing `metricRow` and `inspectorCard()`.

**Checks:**
- Render the Inspector's "Running" preview and look at it. The card should
  show the model, "On" with the reason and the drafter file, and
  "hit · 944 tokens in 20 ms".
- Run `just test` and `just integration`; both must pass.
- Run `just lint-docs`.

## Result

**Commits:** `b94b481`..this one, on `main`. Suites: 98 fast and 39
integration, all passing.

**Break checks:** each new test failed against one broken line, then
passed once it was restored.
- Without the hit subtraction, `prefixHitLeavesCachedTokensOut` fails.
- Without the reset on `.session`, `newSessionDropsTheCorrection` fails.
- Decoding `dflash` from the wrong key fails `toolReadFixtureDecodes`.

**Previews:** these were rendered and looked at:
- Inspector "Running": the card shows the model, "On" with its reason, the
  drafter file, and "hit · 944 tokens in 20 ms"; Prefill avg is 189.8 tok/s
- StatusBar "Running" and "No GPU metrics"
- SessionView "Running"
- MainView "Running"

**Diverged:**
- `prefixCacheLine` takes a `locale:` parameter, defaulting to the current
  locale, so the test can pin en_US.
- A hit-corrected token count of 0 or less keeps the prior rate. This
  applies only to the corrected prefill, not to the shared rate guard.
- **The preview fixture's pause changed:**
  - **Before:** 512 tokens in 210 ms. With the cache hit added, that is
    fewer tokens than the hit's 944, so Prefill avg showed "—".
  - **After:** session `154825`'s real first checkpoint, 1146 tokens in
    1084 ms.
  - **Why this was the fixture's fault:** live counters always include the
    prefix.
- The punch list's "per-pause deltas" item was rewritten as a "session avg"
  label. Per-pause and per-prompt rates belong to phase AN.
