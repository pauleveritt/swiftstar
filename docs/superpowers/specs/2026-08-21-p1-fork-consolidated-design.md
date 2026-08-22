# SwiftStar P1 design: the fork, consolidated

**Date:** 2026-08-21
**Status:** approved (brainstormed within P1; the phase list and architecture are
settled by `BRIEF.md` / `ROADMAP.md` / `2026-08-21-swiftstar-design.md`).
**Phase:** P1 — The fork, consolidated.

This spec is the authority on *how* P1 is done. It is scoped to P1 only: it does
not reopen the phase list, the architecture, or the engine seam. The project-level
why lives in `BRIEF.md`; the decision record (including what was rejected) lives in
`docs/superpowers/specs/2026-08-21-swiftstar-design.md`.

## Problem

SwiftStar has no engine it owns. Three things are true at once:

1. `~/projects/ds4` tracks `antirez/ds4` directly; local branches (`laguna-s2.1`,
   `laguna-xs2.1`, `mellum-2.1-overnight`, `paul/laguna`, and worktree branches)
   exist only on one disk.
2. DS4 Control's submodule pins `ebacae9` on `notatestuser/ds4`
   (`ds4-control-patches-v2`) — someone else's fork — for the app-required patch
   set.
3. Different worktrees pin different submodule SHAs, so "the engine" is not a
   single thing.

P1 forks `antirez/ds4` to `pauleveritt/ds4`, absorbs both into one shipped
integration branch the submodule pins, with a small rebased patch set, a fork
ledger, `docs/upstream-proposals.md`, and two golden captures. The merge conflicts
are real, which is why P1 is its own phase and why its done-when does not require
an app.

## A finding that corrects the brief's account of the patch set

The brief describes the patch set as "absorbed from `notatestuser/ds4` and from the
local `paul/laguna` work." **That is not where it is.** Verified against the
sources on 2026-08-21:

- `json_event` appears in **zero** branches of `notatestuser/ds4` or `~/projects/ds4`.
- All five app-required patches were **developed from scratch** in DS4 Control's
  agent-mode worktree (`.claude/worktrees/agent-mode/external/ds4`), applied to a
  local submodule branch `ds4-control-laguna`, and **never pushed anywhere**. The
  SDD progress ledger `progress.md` (1463 lines) is the development record:
  Tasks 1–7, multiple review rounds, a Fable deep review, and six fix rounds on the
  UTF-8-truncation bug class alone.
- A second local branch `ds4-control-status-marker` carries the 2 status-marker
  commits; the rest is on `ds4-control-laguna`.

Consequence for P1: "absorb the patch set" is not cherry-picking a labeled series
out of a fork. It is **re-grounding 22 verified commits** onto a clean antirez base,
preserving their wire contract, and proving the result by rebuilding and
recapturing. The original SHAs are recorded so the rebase is auditable.

The patch set maps to the brief's five names as follows (original SHAs, topological
order):

| # | Brief name | Commits | First / last SHA |
|---|---|---|---|
| 1 | status marker | 2 | `310d5a4` … `a9eda6d` |
| 2 | turn-interrupt | 1 | `1f18723` |
| 3 | stale-interrupt latch | 1 | `9bca6d4` |
| 4 | `--json-events` | 16 | `66c3de2` … `1a14a6c` |
| 5 | startup memory plan | 2 | `83501bb`, `8267745` |

Total: 22 commits. In the source, they are interleaved with the 16-commit Laguna
S 2.1 model line (which sits between the status marker and the interrupt patches)
and are based on `ebacae9` = antirez main + 114 notatestuser Metal/MXFP4/M5 commits
(including 3 agent-specific commits: `b030961`, `355da75`, `0fa15c6`).

**The local Laguna line and upstream `laguna-s2.1` are the same feature set but
diverged commits.** They share commit titles, but only 4 of 16 patch-ids match
exactly (verified 2026-08-21); the other 12 differ because the local line was
applied onto the notatestuser base (`ebacae9`) rather than antirez main. The
shipped integration uses **upstream** `laguna-s2.1` (the canonical, current line),
so the app patches — developed against the local line's context — are rebased onto
a base that differs from the one they were written against. This is a second,
independent conflict surface, on top of dropping the notatestuser base.

## Scope

### In scope

1. `pauleveritt/ds4` exists, forked from `antirez/ds4` (parent = antirez), achieved
   by delete + re-fork (the pre-existing repo is parented to `notatestuser/ds4`;
   GitHub cannot re-parent).
2. `main` is a pristine mirror of `antirez/main`, never edited.
3. One shipped integration branch `swiftstar-integration` carries
   `antirez/laguna-s2.1` plus the 22 rebased app patches (the "union of model
   lines" — at P1, one line; `main` is the pristine mirror / rebase source,
   not the integration base).
4. The SwiftStar repo carries `external/ds4` as a submodule pinned to a SHA on
   `swiftstar-integration` (and only that branch).
5. One command builds `ds4-server` and `ds4-agent` from the pinned SHA.
6. The fork ledger has a row per divergence naming what would retire it.
7. `docs/upstream-proposals.md` exists with an entry per upstream-bound row.
8. Two golden captures committed to SwiftStar: NDJSON + timestamp sidecar from
   `ds4-agent` (a recapture) and SSE + timestamp sidecar from `ds4-server` (a first
   capture).
9. The recapture-on-every-submodule-bump rule is written down where a future rebase
   will find it.

### Out of scope (tangents; do not drift into P1)

- **No app, no Swift.** P2 is the walking skeleton. P1 produces no `.swift` files.
- **No Mellum on the shipped integration.** Mellum is a P12 `Variant`; its dev
  branch is recorded in the ledger, never pinned. The new SFT snapshot
  (`JetBrains/sft_mellum_v23_mixopt_fullx5_p2_joint-iter-3015` @ `683ca310…`,
  2026-08-21) is P12 context, recorded in the ledger's retirement condition — not a
  P1 build target. P1's captures use the Laguna line (the line the app ships first).
- **No `swiftstar-drive`.** That is P5. P1's captures use a throwaway line-stamping
  script under the verbatim-raw rule.
- **No `--subagent-pool`, no worker ids.** That is P11. The patch set is the five
  named patches only.
- **No Mellum weights, no GGUF/MLX conversion.** The conversion/imatrix pipeline is
  the Mellum branch's largest unpriced work item, P12's problem.
- **No upstream PRs filed.** `docs/upstream-proposals.md` is an intention record.

## The fork

**Creation** (implementation step 1, after this spec is approved):

1. `gh repo delete pauleveritt/ds4 --yes` — the existing repo is a fork of
   `notatestuser/ds4` carrying only mirrored branches, no unique work. Deletion is
   irreversible; it is a recorded step, not done silently.
2. Fork `antirez/ds4` to `pauleveritt/ds4` so the parent is `antirez/ds4`.
3. Set default branch to `main`; add a short README noting this is SwiftStar's
   engine fork, pointing at `swiftstar-integration` and the fork ledger.

**Remotes** (in the fork, so `~/projects/ds4` and any future clone can fetch all):
`origin` → `pauleveritt/ds4`; `upstream` → `antirez/ds4`.

**Branch structure:**

| Branch | Contents | Policy |
|---|---|---|
| `main` | pristine `antirez/main` mirror | never edited; fast-forward from `upstream/main` only |
| `laguna-s2.1` | mirror of `upstream/laguna-s2.1` | development branch, never pinned |
| `mellum-2.1-overnight` | local Mellum dev branch, pushed for a durable home | development branch, never pinned |
| `laguna-xs2.1` | local XS dev branch, pushed for a durable home | development branch, never pinned |
| `patch-set` | the 22 app commits, rebased onto `main`+`laguna-s2.1` | small, rebased, **never merged** into main |
| `swiftstar-integration` | `patch-set` at the pinned SHA | the one branch the submodule pins |

Two branch names are materialized — `patch-set` (the small rebased series, the
thing re-rebased onto new upstream) and `swiftstar-integration` (the pinned union)
— even though at P1 they are the same commit, so that the "small, rebased, never
merged" property stays legible when P12 adds a second model line.

## The rebase

**Amended 2026-08-21 (option A).** The original draft said "merge
`upstream/laguna-s2.1` into `main`, then apply the patches." Attempting that
produced **14 conflicted files, ~26 hunks** — a `laguna-s2.1` (17 commits
ahead of a 155-behind merge base) into current `main` (155 commits ahead) is
front-running antirez's own future merge, and half the conflicts were semantic
kernel merges (`metal/moe.metal` 530 lines; `rocm/*` untestable on macOS).

The brief's fork policy defines the shipped integration as "the union base
carrying every model line the app ships a Variant for" — *not* "main + model
lines." At P1 there is one model line: `laguna-s2.1`. So the integration is
**`laguna-s2.1` + the 22 patches**, with no model-line merge. `main` stays the
pristine mirror used as the rebase *source* when antirez eventually merges
laguna into main (the standing recapture rule covers that re-rebase).

**Source of truth** for the patch commits: the DS4 Control agent-mode worktree's
submodule, branches `ds4-control-status-marker` (2 commits) and `ds4-control-laguna`
(the rest).

**Procedure** (implementation step 2, executed 2026-08-21):

1. In the fork, create `patch-set` from `origin/laguna-s2.1` (the upstream
   model line, already on the fork from the antirez fork).
2. Cherry-pick the 22 commits in topological order, **dropping the 16 local
   Laguna-line commits** — their feature set is already present in
   `laguna-s2.1` (the local line was a variant of upstream laguna; patch-ids
   differ 4/16 because the local line was applied onto the notatestuser base).
3. `swiftstar-integration` = the resulting `patch-set` tip; pin the submodule there.

**Result (verified):** all 22 cherry-picked cleanly onto `laguna-s2.1` with
**exactly one conflict** — a trivial struct-field placement in `ds4_agent.c`
(the `bool edit_upto; bool json_events;` addition to `agent_config`), resolved
by keeping the patch's additions. This confirms the option-A reframe: the
local-laguna-vs-upstream-laguna divergence is contained to `ds4_agent.c`, which
is the one file the recapture (Task 6) verifies. The 13 other conflict files
from the abandoned main+laguna merge do not arise.

## Patch set inventory + fork ledger

**Location:** `docs/fork-ledger.md` in `pauleveritt/ds4` (reachable through the
submodule at `external/ds4/docs/fork-ledger.md`). Audience: a future rebaser in the
fork. Cites the SDD `progress.md`.

**Schema — one row per divergence:** name, commits (original SHA → new SHA), *why
it exists*, *what would retire it* (a falsifiable condition), and an *upstream-bound?*
flag pointing into `upstream-proposals.md`.

The six rows:

| Divergence | Commits | Why it exists | What retires it |
|---|---|---|---|
| status marker (`+DWARFSTAR_STATUS`) | 2 | ds4-agent in non-interactive mode must emit observable state; the pre-json-events scraper reads it. (json-events `status` events supersede it on the agent wire, but it remains the mechanism outside `--json-events`.) | upstream lands structured status emission for non-interactive mode, **or** SwiftStar stops launching ds4-agent without `--json-events` and no consumer reads the marker |
| turn-interrupt | 1 | the app must interrupt a generation mid-turn from a spawned non-interactive process (no TTY, no SIGINT-to-linenoise path) | upstream lands a first-class interrupt signal for non-interactive mode |
| stale-interrupt latch | 1 | a stale interrupt from a prior turn must not kill the next turn's first submission | retires *with* turn-interrupt — a correctness detail of the interrupt mechanism, not independent |
| `--json-events` | 16 | the app needs a structured NDJSON wire (text/think/tool/status/ready/queued, `idx`, param `name`, finish `calls`) instead of scraping ANSI; documented at `docs/json-events.md` | upstream lands a structured events mode (flagship proposal #1); individual events can retire piecemeal as upstream lands them |
| startup memory plan | 2 | the app must know the memory plan at startup to gate feasibility (P3/P4) before load | upstream exposes the memory plan via a first-class API |
| integration structure (`swiftstar-integration` = main + laguna-s2.1 + patch set) | — | the submodule must pin one branch carrying model line + patches; fork hygiene, not an engine change | laguna-s2.1 merges to antirez main (then integration = main + patch set); ultimately the whole patch set lands upstream and the fork can be archived |

**Development branches** — a separate section of the ledger, not divergence rows
(they are model lines, not patch divergences):

- `laguna-s2.1` — upstream mirror; already in the integration (P1).
- `laguna-xs2.1` — local dev branch, pushed for a durable home; enters the
  integration when SwiftStar ships an XS `Variant` (P12+).
- `mellum-2.1-overnight` — canonical Mellum line, pushed for a durable home; enters
  the integration when SwiftStar ships a Mellum `Variant` (P12). Retirement
  condition notes the new SFT snapshot (`683ca310…`, 2026-08-21) as the checkpoint
  whose canonical `MellumForCausalLM` config removes the fixtures-drift reason,
  while the conversion/imatrix pipeline remains the unpriced work item.

**Living doc.** A retired divergence gets its row marked *retired* with the date and
the upstream commit that did it — never deleted, so "carried forever" is visible
rather than silently accumulating.

## The build command

ds4 is a plain C Makefile project. On macOS the default targets build Metal
binaries; `ds4-server` and `ds4-agent` are individual targets (`Makefile:67,76`).
Binaries land at `external/ds4/ds4-server` and `external/ds4/ds4-agent` — what
`DS4_DIR` points a dev build at.

The one command is a `just engine` recipe in SwiftStar's Justfile:

```justfile
# Build ds4-server and ds4-agent from the pinned submodule SHA (P1).
#
# STANDING RULE — recapture on every bump: whenever external/ds4's pinned SHA
# changes, golden fixtures MUST be recaptured against the freshly rebuilt
# binary before the bump lands. A rebase can apply cleanly and still be
# semantically wrong (the patch set instruments ds4_agent.c's decode loops and
# emitters). See BRIEF.md "The fork" and external/ds4/docs/fork-ledger.md.
engine:
    git submodule update --init external/ds4
    make -C external/ds4 ds4-server ds4-agent
```

`git submodule update --init` forces the checkout to the **pinned SHA** — the
command cannot accidentally build whatever happens to be checked out. This is what
"from a pinned SHA" means operationally: the SHA lives in the parent repo's gitlink.

The standing rule travels with the command: a dev who bumps the submodule edits
this recipe's neighborhood and reads the warning in the same breath. This is the
SwiftStar-side enforcement point; the fork-side canonical text is `REBASING.md`
(see "Golden captures").

Metal is the correct default (Apple silicon; the product is GPU-anchored). `make
cpu` exists but nothing pins it. The engine's own `make test` / `ds4_agent_test` is
run as a development check during the rebase but is **not** wired into `just` — it
is not a SwiftStar deliverable, and a subprocess-in-CI gate would fight the
fast-tier tripwire P2 introduces.

## Golden captures

Two captures, both verbatim-raw, both with a timestamp sidecar. The done-when names
the NDJSON sidecar explicitly; the SSE sidecar is spec'd too, because binding rule 5
(capture is separate from analysis) and P6's diagnostics both want receive times for
the server wire, and timestamps are cheap now, expensive to regret later.

**Location** — a top-level `fixtures/` directory that P2's fake-engine generation
consumes:

```
fixtures/
  agent/
    golden.ndjson            # ds4-agent wire, byte-for-byte
    golden.ndjson.sidecar    # receive timestamps, one per line
    provenance.md            # prompts, command, model, SHA, gaps
  server/
    golden.sse               # ds4-server wire, byte-for-byte
    golden.sse.sidecar       # receive timestamps
    provenance.md
```

**NDJSON is a recapture, not a first capture.** DS4 Control has an 815-line
`agent-events-golden.ndjson`, captured at `b3d1600` — *before* the memory-plan
commits (`83501bb`, `8267745`), which add a memory-budget field to `ready`. P1
recaptures at the pinned SHA. This is the standing rule exercising itself on the
first bump.

**SSE is a first capture.** It must cover a complete chat turn over
`/v1/chat/completions`: stream open, token-delta events, terminal `[DONE]`. The
plan pins the exact request shape against `ds4_server.c`'s
`responses_sse_emit_event` path.

**Coverage requirement** (keeps the analyzer honest, binding rule 6): each capture
exercises the wire's event vocabulary — for NDJSON, the five event kinds, tool
phases, `idx`, param `name`, and a real multi-call block; for SSE, the full
delta→finish arc. A fixture silently missing a kind weakens every test built on it.
Gaps are *recorded* in `provenance.md`, never hand-filled.

**The throwaway line-stamping script** drives the real binaries (`swiftstar-drive`
does not exist until P5):

- Drives `ds4-agent` with `--json-events --non-interactive -m <Laguna GGUF>` and a
  FIFO stdin; drives `ds4-server` by launching it and hitting `/v1/chat/completions`.
- Stores the wire **byte-for-byte** — no inline timestamps, no reformatting, CR/LF
  preserved — and writes receive times to the sidecar (one line per captured line,
  in order).
- Is deliberately **not** a committed permanent tool: it is throwaway by design (P5
  replaces it). The script's exact commands and prompts are recorded in
  `provenance.md` so the capture is auditable and re-doable. Python is **not** used
  (D11: Python is docs-only); shell/awk is fine.

**Standing rule, fork-side location.** `REBASING.md` at the fork root is the
canonical text, read by anyone re-rebasing the patch set. The rule, verbatim:

> The patch set instruments `ds4_agent.c`'s decode loops and emitters, so a rebase
> can apply cleanly and still be semantically wrong. Golden-fixture recapture
> against the real binary is mandatory on every submodule bump.

Referenced from three places: `REBASING.md` (canonical), the fork ledger header, and
the `just engine` recipe comment.

## `docs/upstream-proposals.md`

Lives at `pauleveritt/ds4/docs/upstream-proposals.md`, adjacent to the ledger. One
entry per ledger row marked upstream-bound, each phrased as an actual proposal —
problem, what the patch does, suggested upstream shape — not a note. The flagship is
`--json-events` (a structured-events mode for non-interactive agents). Purpose: the
brief's — *"upstream-bound" must not quietly become "carried forever."* Intention
record only; **nothing is filed upstream during P1.**

## Submodule integration into SwiftStar

- `git submodule add https://github.com/pauleveritt/ds4 external/ds4`, with
  `.gitmodules` recording `branch = swiftstar-integration`.
- The gitlink pins the SHA of `swiftstar-integration`'s tip; `git submodule update
  --init` checks out exactly that SHA (Section "The build command" depends on it).
- In the submodule checkout, `origin` = `pauleveritt/ds4` and `upstream` =
  `antirez/ds4`, so future rebases can fetch antirez main + laguna-s2.1 without a
  separate clone.
- SwiftStar's P1 commits consist of: `.gitmodules`, the gitlink, `fixtures/`, and
  docs. No Swift yet — that is P2.

## Done-when (the test the plan writes against)

1. `pauleveritt/ds4` exists, forked from `antirez/ds4` (parent = antirez).
2. `main` is a pristine mirror of `antirez/main`, never edited.
3. `swiftstar-integration` carries `antirez/laguna-s2.1` + the 22 rebased app
   patches.
4. SwiftStar carries `external/ds4` pinned to a SHA on `swiftstar-integration`.
5. `just engine` builds both binaries from the pinned SHA.
6. The fork ledger has a row per divergence naming what would retire it.
7. `docs/upstream-proposals.md` has an entry per upstream-bound row.
8. Both golden captures are committed — NDJSON + sidecar (recapture), SSE + sidecar
   (first capture) — from the real binaries.
9. `REBASING.md` states the recapture-on-every-submodule-bump rule where a future
   rebase will find it.
