# Harvest

**This directory is evidence, not source.**

It records what four bodies of prior work proved, so that SwiftStar can re-earn
each behavior deliberately instead of rediscovering it by incident — and so
that nothing valuable is lost when those repositories are retired.

Read `BRIEF.md`'s "Clean-room policy" first. The short version: **code does not
cross; facts may cross, with a citation and a fresh test.** Every fact recorded
here carries the citation that lets a future phase transplant it honestly.

| Brief | Source | What it holds |
|---|---|---|
| [ds4-control.md](ds4-control.md) | `~/projects/ds4-control` | The retiring app: shipped features, and the gardened facts each one earned |
| [telemetry-findings.md](telemetry-findings.md) | `ds4-control` commit `b7cc10a` | The measured context-degradation finding that reframes the product |
| [capture-driver.md](capture-driver.md) | an uncommitted test file | The headless capture driver's contract — recorded because the artifact keeps being lost |
| [swiftstar-md.md](swiftstar-md.md) | `~/projects/ds4`, `SWIFTSTAR.md` | The rival embedded-engine design: what was rejected, and the ideas worth keeping |
| [engine-lines.md](engine-lines.md) | `~/projects/ds4` branches | Laguna S 2.1, Laguna XS 2.1, Mellum 2 — the engine work that moves over directly |

```{toctree}
:maxdepth: 1
:hidden:

ds4-control
telemetry-findings
capture-driver
swiftstar-md
engine-lines
```
