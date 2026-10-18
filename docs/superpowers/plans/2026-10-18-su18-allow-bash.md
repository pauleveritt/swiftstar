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
