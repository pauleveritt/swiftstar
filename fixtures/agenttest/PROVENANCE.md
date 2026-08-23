# AgentClinic fixtures — provenance

Transplanted from `~/projects/pauleveritt/local-ai-pi`'s AgentClinic example
(`examples/agentclinic/`), which itself transplanted the roadmap from the prior
ds4-control project. Recovered from git history because the current
`local-ai-pi` tree keeps only Phase 1:

- `specs/roadmap.md` (3 phases) — `local-ai-pi` commit `8af05f8`.
- `specs/roadmap-user-story.md` (3 phases) — `local-ai-pi` commit `191895e`.
- `specs/mission.md`, `specs/tech-stack.md` — `local-ai-pi` commit `8af05f8`.
- `acceptance/test_acceptance.py` (cumulative Phase 1+2+3, harness-owned) — `8af05f8`.
- `reference/` (the full 3-phase solution) — `8af05f8` (`examples/reference/phase-3/`).
- `broken/app.py` (bare FastAPI app, zero routes) — current `local-ai-pi` tree.

The acceptance suite is **the grade**: human-authored, cumulative, contract-not-
implementation, and non-vacuous (the local-ai-pi `examples/acceptance/README.md`
rules). It is overlaid into the final checkout and run with `uv run pytest`.

## Evidence floor (2026-08-23)

- `reference/` + `test_acceptance.py` → **13 passed**.
- `broken/app.py` + `test_acceptance.py` → **fails** (collection error: the bare
  app has no `models`).

Run via `uv run --project ~/projects/pauleveritt/local-ai-pi pytest test_acceptance.py`
with the reference (or broken) code + the acceptance suite in the same directory.
The deps (fastapi 0.115.10, pytest 8.3.4, turbohtml 1.5.0) are `local-ai-pi`'s.
