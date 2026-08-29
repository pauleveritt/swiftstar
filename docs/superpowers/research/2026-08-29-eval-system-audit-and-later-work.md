# Eval-system audit: the "Later" work

**2026-08-29.** Two independent reviews of the eval/telemetry infrastructure —
an initial deep audit and a second, skeptical pass that verified its claims
against the actual repo and specifically reconsidered its Python/SQLite
recommendation. Both agreed the individual measurements (the overnight
campaign's pre-registration, void-vs-fail separation, negative controls) are
unusually rigorous, and that the *system* around them is not: ~8–10
independent eval/experiment codebases sharing almost no code, ≥7 incompatible
result-file schemas, a `swiftstar-analyze` CLI that only computes performance
numbers (tok/s, ctx_used) with no notion of a finding or verdict, and a
deterministic findings engine (`SwiftStarKit/DiagnosticsAnalyzer.swift` +
`Finding.swift`) that already exists but is wired only to the app's
Diagnostics tab — no eval or CLI has ever consumed it.

The urgent subset of the fix — correcting the stale ROADMAP claims, committing
the untracked campaign work, freezing one results schema — is **P26** (see the
phase table). This document is the fuller list: valuable, but nothing here
corrupts the next round of results if it waits.

## The Python/SQLite question, settled

The first review recommended consolidating experiment runners in Python and
adding a `captures/index.sqlite` queried by both Python and Swift. The second
review reconsidered this against the repo's own stated conventions and
reversed it:

- **BRIEF.md is explicit:** "Python exists in this repository for
  documentation and nothing else." Python as a permanent analysis substrate
  contradicts the project's own charter.
- **The telemetry skill's Rule 0** already says the parsers and the math live
  in `SwiftStarKit`, not ad-hoc scripts. `Tools/campaign-report.py` and
  `Tools/directive-taxonomy.py` are exactly the ad-hoc layer that rule
  forbids, just written in a different language.
- **No new dependency is needed either way**: macOS ships `libsqlite3`, so
  `import SQLite3` inside `SwiftStarKit` costs nothing — no GRDB, no
  package-graph addition, consistent with `Package.swift`'s one
  provenance-justified dependency.

Settled direction: analysis, indexing, and findings are **Swift-native**,
as new `swiftstar-analyze` verbs backed by `SwiftStarKit` types. Start with a
flat, re-derivable index (one NDJSON/TSV row per capture, gitignored like the
captures themselves); reach for the system `SQLite3` module only once a real
relational query need appears — never a Python query layer sitting on top of
a Swift-produced database. Python keeps exactly one job: babysitting overnight
subprocess orchestration (timeouts, process-group kill, orphan reaping) —
genuinely a `subprocess` strength, not an analysis concern. Every line of
classification/reporting logic in the Python runners is debt to be moved
behind `swiftstar-analyze`.

## The Later list

Ordered by priority; none of these are prerequisites for resuming trustworthy
measurement (that's P26), but each closes a real gap found during the audit.

1. **`swiftstar-analyze findings` and `swiftstar-analyze index`, in Swift.**
   Wire the existing `DiagnosticsAnalyzer` into the CLI — it already consumes
   exactly the `[WireEvent] + [TraceEvent]` types `swiftstar-analyze` parses,
   so this is a small verb, not new machinery. `index` emits one flat row per
   capture (config, engine pin, variant, seed, outcome) to a gitignored file
   under `captures/`; add the system `SQLite3` module only when a query needs
   a join a flat file can't give cheaply.
2. **Port `campaign-report.py` and `directive-taxonomy.py` into
   `swiftstar-analyze` verbs, then delete the Python originals.** Removes the
   ad-hoc-outside-Swift layer Rule 0 forbids and collapses two of the ≥7
   result schemas into whatever the new verbs standardize on.
3. **The zero-Metal replay tier.** `TextContractHarvest` and the rest of the
   repair/build harvest path are already pure `SwiftStarKit` code operating on
   stored turn text — a replay tier re-runs a prospective harness change (a
   reworded contract, a normalization fix) against the corpus of *already
   captured* turns with no live model and no Metal, before spending a night of
   GPU time on a live arm. This is the same pattern P23 already used once
   (a ~10s scripted probe replacing a 695s agentclinic run), generalized to
   the eval layer.
4. **Kill list.** Delete the six dead one-off shell runners (`overnight-chain`,
   `overnight-idle-launch`, `p13-laguna-xs-overnight`, `measure-batch`,
   `p11-gate`, `p11-smoke-gate`); delete `audit-goal-invariants.py`'s V1–V4
   (only V5/V6 are live, per that script's own docstring); remove the
   committed `Tools/__pycache__/` and gitignore it.
5. **`DeepSeekGrader` calibration.** It backs P22/P13-style "verdict good"
   acceptance claims from single live runs, with no calibration set anywhere
   in the repo and a live network dependency. Either calibrate it against the
   13-test acceptance oracle on captures already on disk, or demote it to
   advisory-only text and re-run the key acceptance claims at n≥3 against the
   oracle instead.
6. **A second fixture app, and a real hard/superhard difficulty tier.** Every
   fixture today is a variation on one FastAPI complaints-board app; "hard"
   rests on as few as 6 cells; nothing resembles the worst production failure
   mode found (dozens of consecutive LOCATE calls, zero mutations). Fold P18's
   `mellum-fixture` design (flat 13-requirement oracle scored even on partial
   failure, frozen pre-registered manifest) into the unified runner from P26
   rather than building a seventh/eighth mechanism.

## Sources

The two review transcripts this document summarizes were not saved verbatim;
this is the durable record of their conclusions. Re-derive detail from the
files each review actually cites: `Sources/swiftstar-analyze/main.swift`,
`Sources/SwiftStarKit/DiagnosticsAnalyzer.swift`, `Sources/SwiftStarKit/Finding.swift`,
`Tools/run-experiment.py`, `Tools/run-orchestrate-campaign.py`,
`Tools/audit-goal-invariants.py`, `BRIEF.md`, and
[`2026-08-29-block-b-negative-result-analysis.md`](2026-08-29-block-b-negative-result-analysis.md).
