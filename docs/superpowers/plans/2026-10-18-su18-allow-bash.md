# SU.18 plan: run with `--allow-bash`, and show the fallback

[Spec](../specs/2026-10-18-su18-allow-bash-design.md), accepted by the
owner on 2026-10-18. The engine request (D4) is filed as
[ds4-engine#260](https://github.com/pauleveritt/ds4-engine/issues/260). The
recording (D5) waits for the owner's GPU go. The branch is `su18-allow-bash`.

## Decisions

The spec's D1–D3, plus:

- **D6.** A `run` card with an empty path is called a bash run. A command
  `--allow-run` admits looks the same on the wire. SwiftStar never passes
  `--allow-run`, so its "bash" header can mislabel only a `config.toml`
  `run_commands` entry.

## Tasks

1. **Kit.**
   - `DefaultsKey.allowBash`.
   - `EngineCommand`:
     - `arguments(…, allowBash:)` and `resumeArguments(…, allowBash:)`
       append `--allow-bash`
     - `allowsBash(_ argv:) -> Bool`
   - `EngineSessionModel.beginAnalysis(report:source:allowBash:)`.
   - `EngineToolCard`:
     - `bashRun: BashRun?`, parsed from the result's first line
     - `headerText` "bash" and `icon` "terminal" for a bash run
     - `metadataLine` "ran as bash in the sandbox · exit 1 · 2.3s", or "…
       · stopped at the 120 s limit"
     - `failed`, for a red facts line

   Tests:
   - `EngineCommandTests`: `allowBashIsAppended` (start and resume);
     `allowsBashReadsTheArgv`.
   - `EngineAnalysisTests`: `forkCarriesAllowBash`.
   - `BashRunCardTests` (new): exit 0, exit 1, stopped, still running, and
     a `run` with a path that stays as it is.
2. **Controller and UI.**
   - `EngineController` reads `allowBash` from the defaults for the start,
     a sidebar resume and Analyze's fork.
   - `bashFallbackOn` comes from the argv it spawned.
   - The inspector gets a Shell row, `ToolCardView` red when `failed`, and
     a Settings toggle with its help.

   Tests:
   - `allowBashSettingReachesTheSpawn`: the fake engine's spawn log, on a
     start and on a sidebar resume.

   Previews: bash cards, Settings, the inspector row.
3. **Docs.** ROADMAP, CHANGELOG, `provenance.md` (engine-code payloads), and
   both tiers.

## Result

D1–D4 done 2026-10-18, with no GPU. D5, the recording, waits for the
owner's go.

- **Commits:**
  - `afaf98f`: Task 1
  - `d4ca0eb`: Task 2
  - `6e01080`: the close
- **The engine request** is [ds4-engine#260](https://github.com/pauleveritt/ds4-engine/issues/260).
- **Tests:**
  - `just test` (218) and `just integration` (91) pass.
  - Every new behavior was broken, and its test failed: 8 in Task 1 and 3
    in Task 2. Two mutants first failed to build, and were caught once
    rewritten so they did.
- **Previews:** these were rendered and looked at:
  - ToolCardView's "bash runs": exit 0 gray; exit 1 and the limit red
  - Settings, with its Shell section (the window is 480 high now)
  - InspectorView's "Bash fallback on"
- **Diverged:**
  - **The seconds are the engine's text:** "exit 1 · 0.4 s", as sent, not
    reformatted.
  - **Analyze's fork takes the running session's policy,** not the
    toggle's: a fork continues that session.
- **Not checked live:** no bash run has gone through the app. The card
  reads the engine's own header format (`run_tool.py:119-124`). D5's
  recording is what pins it to a real stream.

### Revision, 2026-10-18: on by default

At the owner's request, an unsaved setting now means on
(`DefaultsKey.allowBashDefault`).
- **Tests:**
  - `allowBashSettingReachesTheSpawn` now runs with the key removed.
  - `allowBashOffKeepsTheFlagOut` is new.
  - Both were broken once each and failed.
  - Two exact-argv resume tests expect the default.

