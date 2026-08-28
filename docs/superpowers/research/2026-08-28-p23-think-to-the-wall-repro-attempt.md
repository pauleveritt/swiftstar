# P23 spec test 9 — think-to-the-wall reproduction attempt (deferred)

**2026-08-28.** Fable's review of part 2 flagged that the plan's Task 9 Step 3
(`Tests/SwiftStarIntegrationTests/ThinkToTheWallTests.swift`, spec test 9 —
"the phase's cheapest regression guard") was silently dropped during
execution. This note records the attempt to write it and why it's deferred
rather than shipped.

## What was tried

The plan's skeleton drives the engine directly with a reconstructed prompt
(`"A farmer has 17 sheep. All but 9 die. How many are left? Explain."`) and a
reasoning-inducing system prompt, asserting the unbounded `--think` arm's peak
`ctx_used` exceeds 90% of a 16,384 context while the `--think-budget 64` arm
stays under it — reproducing probe A's live finding (2026-08-28 research doc,
§"Probe A"): unbounded think filled 15,873/16,384 tokens (97%) across 7 rounds
and never answered.

Two real bugs in the plan's own skeleton were found and fixed first:
- `Process.arguments` included `binary.path` as the first element — Foundation's
  `Process` API takes the executable path via `executableURL`, not as
  `argv[0]` inside `arguments`. The engine read the binary's own path as an
  unrecognized flag and exited immediately.
- `FileManager.default.currentDirectoryPath` does not resolve to the package
  root under `swift test` (unlike a plain CLI invocation) — fixed to follow
  `FakeAgentHarness.repoRoot`'s existing `#filePath`-based convention.

With both fixed, the harness runs cleanly against the real engine, but the
reproduction itself does not hold: run against both `Laguna-XS-2.1-Q4_K_M.gguf`
and the contract-admitted `laguna-xs-2.1-RoutedQ3_K-biased.gguf` (with
`--ssd-streaming --ssd-streaming-cache-experts 3200 --prefill-chunk 4096`,
matching probe A's stated "XS, ctx 16384, SSD streaming" configuration), the
model answered the riddle directly in both runs with **zero think events** and
peak `ctx_used` around 1,000 of 16,384 — nowhere near the wall.

## Why

The research doc records probe A's *finding* but not the *literal prompt
text* it used — only the generic description "reasoning-inducing `-sys`,
multi-step problem." The plan's Task 9 skeleton (authored in a later session)
reconstructed a plausible-sounding prompt rather than replaying the original
probe's transcript, and that reconstruction does not induce the same
behavior. This is consistent with the phase's own headline finding:
**thinking is prompt-induced, not flag-induced** — the same model and flag
produced 0% and 80% thinking on two different prompts in probe A itself.

## Disposition

Per the plan's own pre-registration ("if the unbounded arm fails to
reproduce... stop and report rather than relaxing the threshold — do not
hunt for a prompt that works"), this was not pursued further by trial and
error. `ThinkToTheWallTests.swift` was **not** committed. The mechanism this
test would pin (`--think-budget` bounding think-to-the-wall) is not in doubt —
probe A already demonstrated it live, with its own exact numbers recorded in
the research doc — only a reliable, replayable *reproduction prompt* is
missing.

**Forward:** if this regression guard is wanted, either recover the literal
probe A transcript (if one was captured) to replay verbatim, or run a fresh
scoped probe to find and record a prompt that reproduces the wall on the
locally available models, before writing the test again.
