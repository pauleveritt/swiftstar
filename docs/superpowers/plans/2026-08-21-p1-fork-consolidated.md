# P1 — The fork, consolidated: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork `antirez/ds4` to `pauleveritt/ds4`, rebase the 22 app-required engine patches onto a clean `main`+`laguna-s2.1` base, ship one integration branch the submodule pins, and take the two golden captures from the real binaries.

**Architecture:** The engine (a C Makefile project) becomes an owned fork with a pristine `main` mirror, a small rebased `patch-set` (never merged into main), and one shipped `swiftstar-integration` branch = `main` + `laguna-s2.1` + patch set. SwiftStar pins `external/ds4` to that branch's SHA. A `just engine` recipe builds both binaries. Golden captures (NDJSON recapture + SSE first capture) are taken by a throwaway line-stamping script under the verbatim-raw rule.

**Tech Stack:** git, GitHub CLI (`gh`), make (Metal build on macOS), `just`, bash/awk for the capture script, curl for SSE.

**Spec:** `docs/superpowers/specs/2026-08-21-p1-fork-consolidated-design.md`

## Global Constraints

- **Contingency — `d0b0caa` (recorded 2026-08-21, before fork deletion):** the pre-existing
  `pauleveritt/ds4` carried one unique commit, `d0b0caa` ("Fix merge: restore
  wrap_f32_decode_model_range, force_model_view param and callers", 38 lines in
  `ds4_metal.m`), a merge-conflict fix restoring two laguna-line Metal symbols dropped when
  `laguna-s2.1` was merged into `notatestuser/ds4` v2. Those symbols are native to upstream
  `laguna-s2.1` (5/7 occurrences) and absent from both antirez main and notatestuser v2, so
  P1's merge of upstream laguna into antirez main brings them in and the fix is expected to be
  redundant. **Trigger to restore:** if Task 3's laguna-into-main merge drops
  `wrap_f32_decode_model_range` or `force_model_view` (or the recapture/Task 6 build shows a
  missing-symbol error), restore from the preserved bundle at
  `.worktrees/ds4-fork-backup/ds4-control-patches-v3.bundle` (gitignored) and record it as a
  ledger row. Do **not** port it preemptively.
- **Decision B:** delete the existing `pauleveritt/ds4` (parented to `notatestuser`) and re-fork from `antirez/ds4` so the parent is antirez. GitHub cannot re-parent a fork.
- **`main` is pristine**: mirrors `antirez/main`, never edited, fast-forward only.
- **`patch-set` is small, rebased, never merged into main.**
- **The submodule pins `swiftstar-integration` and only that branch.**
- **22 app commits** total: status marker (2) + turn-interrupt (1) + stale-interrupt latch (1) + `--json-events` (16) + startup memory plan (2).
- **Standing rule (write it down):** the patch set instruments `ds4_agent.c`'s decode loops and emitters, so a rebase can apply cleanly and still be semantically wrong. Golden-fixture recapture against the real binary is mandatory on every submodule bump.
- **Verbatim-raw:** captures store the wire byte-for-byte; receive times go in a sidecar (one line per captured line, in order).
- **No Python** in the capture script (D11: Python is docs-only). `date +%s%N` works on this Mac (epoch ns).
- **No app, no Swift, no Mellum on the integration, no `--subagent-pool`, no upstream PRs.** All out of scope.
- **Weights:** `~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf` (48GB, Laguna S 2.1) for captures.
- **The Metal env-var gotcha:** running `ds4-agent`/`ds4-server` *from inside* `external/ds4/` needs no env vars; running from elsewhere needs all 21 `DS4_METAL_<NAME>_SOURCE` vars (paths relative to CWD otherwise). Always `cd` into the submodule before running the binary.

---

## Task 1: Create the fork

**Files:**
- No repo files; this is GitHub operations.

**Interfaces:**
- Consumes: nothing.
- Produces: `pauleveritt/ds4` on GitHub, parented to `antirez/ds4`, default branch `main` mirroring antirez main.

- [ ] **Step 1: Verify the pre-existing repo holds no unique work**

Run:
```bash
gh repo view pauleveritt/ds4 --json parent,defaultBranchRef 2>&1
gh api repos/pauleveritt/ds4/branches --jq '.[].name' 2>&1
```
Expected: parent is `notatestuser/ds4` (that's why we're deleting); branches are only mirrors of notatestuser's (`ds4-control-patches*`, `ds4f-mxfp4`, `glm5.2`, `laguna-s2.1`, `main`, `responses-api`). Confirm none carries local-only work before deleting.

- [ ] **Step 2: Delete the existing fork**

Run:
```bash
gh repo delete pauleveritt/ds4 --yes
gh repo view pauleveritt/ds4 2>&1
```
Expected: deletion succeeds; the view command reports the repo not found.

- [ ] **Step 3: Fork antirez/ds4**

Run:
```bash
gh repo fork antirez/ds4 --fork-name ds4 --remote=false
```
Expected: `pauleveritt/ds4` created.

- [ ] **Step 4: Verify parentage and default branch**

Run:
```bash
gh repo view pauleveritt/ds4 --json parent,defaultBranchRef
```
Expected: `parent` full_name is `antirez/ds4`; `defaultBranchRef` name is `main`.

- [ ] **Step 5: Keep main pristine (no README on main)**

Per the spec's "pristine mirror, never edited" policy, `main` carries no README
note (a fork-identity README on main would break the pristine-SHA check in Task
8 and the engine-lines policy). Fork identity lives in the swiftstar-integration
docs (Task 4: `docs/fork-ledger.md`, `docs/upstream-proposals.md`, `REBASING.md`).

Verify main is untouched:
```bash
git clone https://github.com/pauleveritt/ds4.git /tmp/ds4-readme && cd /tmp/ds4-readme
# Do NOT commit anything to main. Confirm clean:
git status
```
Expected: working tree clean; main exactly matches antirez main (`git log -1`).
Note: this resolves a spec-internal contradiction (the spec's "add a short
README on main" conflicts with "pristine mirror, never edited"); pristine wins.

- [ ] **Step 6: Commit**

```bash
# No SwiftStar commit needed; this task is GitHub state. Record it in the session log.
```
Note: this task's deliverable is remote state; it is verified by the checks above, not a local commit.

---

## Task 2: Push development branches for a durable home

**Files:**
- No repo files; pushes `laguna-xs2.1` and `mellum-2.1-overnight` from `~/projects/ds4` to the fork.

**Interfaces:**
- Consumes: Task 1's fork.
- Produces: `laguna-xs2.1` and `mellum-2.1-overnight` branches on `pauleveritt/ds4`.

- [ ] **Step 1: Add the fork as a remote in `~/projects/ds4`**

Run:
```bash
cd ~/projects/ds4
git remote add pauleveritt https://github.com/pauleveritt/ds4.git 2>/dev/null || git remote set-url pauleveritt https://github.com/pauleveritt/ds4.git
git remote -v
```
Expected: `pauleveritt` points at the fork.

- [ ] **Step 2: Push the two dev branches**

Run:
```bash
cd ~/projects/ds4
git push pauleveritt laguna-xs2.1
git push pauleveritt mellum-2.1-overnight
```
Expected: both pushes succeed (they are new branches on the fork).

- [ ] **Step 3: Verify**

Run:
```bash
git ls-remote --heads https://github.com/pauleveritt/ds4.git laguna-xs2.1 mellum-2.1-overnight
```
Expected: both branch names listed with SHAs.

- [ ] **Step 4: Commit**

```bash
# Remote state; record in the session log.
```

---

## Task 3: The rebase — build `patch-set` and `swiftstar-integration`

**Files:**
- Create: nothing in SwiftStar; a scratch clone of the fork (suggest `/tmp/ds4-rebase`).
- Modify: nothing in SwiftStar.

**Interfaces:**
- Consumes: Task 1's fork; the DS4 Control agent-mode worktree's submodule branches (`ds4-control-status-marker`, `ds4-control-laguna`) as the patch source; `upstream/laguna-s2.1` from antirez.
- Produces: `patch-set` and `swiftstar-integration` branches on `pauleveritt/ds4`, with the 22 rebased app commits.

**Source of truth paths:**
- Patch source worktree submodule: `~/projects/ds4-control/.claude/worktrees/agent-mode/external/ds4`
- Patch source branches: `ds4-control-status-marker` (2 commits), `ds4-control-laguna` (the rest)

**The 22 commits, in cherry-pick order (original SHAs):**
```
310d5a4  a9eda6d                 # status marker (2)
1f18723                          # turn-interrupt (1)
9bca6d4                          # stale-interrupt latch (1)
66c3de2 a3e49d9 334db1a c8adbc1 7df204e 8bf46bc f9190ec eda644d
ae2c781 8b6ecc4 44202f5 db8eb73 12ff1fa a86cd9f b3d1600 1a14a6c   # --json-events (16)
83501bb 8267745                  # startup memory plan (2)
```
Cherry-pick ranges: `310d5a4`, `a9eda6d`, `1f18723`, `9bca6d4`, then `66c3de2^..1a14a6c` (16), then `83501bb`, `8267745`.

- [ ] **Step 1: Fetch the patch source into the worktree submodule**

The source is already checked out; just ensure its refs are current:
```bash
cd ~/projects/ds4-control/.claude/worktrees/agent-mode/external/ds4
git branch -a | grep -E 'ds4-control-(status-marker|laguna)'
```
Expected: both branches present. (They are the authoritative source; do not modify them.)

- [ ] **Step 2: Create a scratch clone of the fork**

```bash
rm -rf /tmp/ds4-rebase && git clone https://github.com/pauleveritt/ds4.git /tmp/ds4-rebase
cd /tmp/ds4-rebase
git remote add upstream https://github.com/antirez/ds4.git
git remote add source ~/projects/ds4-control/.claude/worktrees/agent-mode/external/ds4
git fetch upstream
git fetch source
```
Expected: clone succeeds; `origin` = fork, `upstream` = antirez, `source` = the worktree submodule; fetch brings `upstream/main`, `upstream/laguna-s2.1`, `source/ds4-control-status-marker`, `source/ds4-control-laguna`.

- [ ] **Step 3: Create `patch-set` from `origin/laguna-s2.1` (option A)**

Per the option-A reframe (see spec "The rebase"): the shipped integration is
"the union of model lines," not "main + lines." At P1 the one model line is
`laguna-s2.1`, so `patch-set` is based on `origin/laguna-s2.1` directly — no
`laguna-s2.1`-into-`main` merge (that was 14 conflicted files of antirez's own
future merge, half untestable on macOS).

```bash
cd /tmp/ds4-rebase
git checkout -b patch-set origin/laguna-s2.1
```
Expected: `patch-set` at `448d569` (upstream laguna-s2.1 tip on the fork).

- [ ] **Step 4: Cherry-pick the 22 app commits in order**

```bash
cd /tmp/ds4-rebase
git cherry-pick 310d5a4 a9eda6d 1f18723 9bca6d4
git cherry-pick 66c3de2^..1a14a6c
git cherry-pick 83501bb 8267745
```
Expected: cherry-picks complete. Conflicts are confined to `ds4_agent.c`
(the local-laguna-vs-upstream-laguna divergence in the tool-syntax context the
json-events patches instrument). Resolve by hand **preserving the app patch's
semantics**; the wire contract (`docs/json-events.md`, carried by the patch set)
must stay intact. (Observed 2026-08-21: exactly one conflict — the
`bool edit_upto; bool json_events;` addition to `agent_config`, resolved by
keeping the patch's additions.)

- [ ] **Step 4a: Contingency — hard dependency on a notatestuser agent commit**

If a conflict (or the later recapture, Task 6) reveals that one of the
dropped notatestuser agent commits (`b030961`, `355da75`, `0fa15c6`) is
load-bearing, do **not** carry the commit wholesale. Extract the minimal
needed change, fold it into the patch set as its own small commit, and record
it in the fork ledger (Task 4) as its own divergence row with its own
retirement condition. Verify the extract is minimal (git diff shows only the
needed lines) before committing.

- [ ] **Step 5: Verify the patch set applied cleanly**

```bash
cd /tmp/ds4-rebase
git log --oneline origin/laguna-s2.1..patch-set | head -30
git status
```
Expected: 22 app commits above `laguna-s2.1`; working tree clean.

- [ ] **Step 6: Build both binaries from the rebased tree** (dev check, not a SwiftStar gate)

```bash
cd /tmp/ds4-rebase
make ds4-server ds4-agent -j8 2>&1 | tail -5
```
Expected: builds succeed (Metal on macOS). If a build error surfaces a semantic collision, fix the offending patch against new upstream (re-derive, do not hand-edit the wire).

- [ ] **Step 7: Run the engine's own agent test as a dev check**

```bash
cd /tmp/ds4-rebase
make ds4_agent_test -j8 2>&1 | tail -3 && ./ds4_agent_test 2>&1 | tail -5
```
Expected: test binary builds and passes. This is a development check, not a SwiftStar deliverable.

- [ ] **Step 8: Create `swiftstar-integration` at the patch-set tip**

```bash
cd /tmp/ds4-rebase
git checkout -b swiftstar-integration patch-set
git push origin swiftstar-integration
git push origin patch-set
```
Expected: both branches pushed to the fork.

- [ ] **Step 9: Verify the branches on the fork**

Run:
```bash
git ls-remote --heads https://github.com/pauleveritt/ds4.git patch-set swiftstar-integration
```
Expected: both listed with SHAs.

- [ ] **Step 10: Record new SHAs**

Run:
```bash
cd /tmp/ds4-rebase
git log --oneline --reverse patch-set | head -30
```
Expected: the 22 commits with their **new** SHAs. Save this mapping (original → new) for the fork ledger (Task 4).

- [ ] **Step 11: Commit**

```bash
# Remote state; record in the session log.
```

---

## Task 4: Write the fork docs — ledger, REBASING.md, upstream-proposals.md

**Files:**
- Create in the fork (via `/tmp/ds4-rebase` or a fresh clone):
  - `REBASING.md` (fork root)
  - `docs/fork-ledger.md`
  - `docs/upstream-proposals.md`

**Interfaces:**
- Consumes: Task 3's new SHAs (original → new mapping).
- Produces: the three docs committed to `swiftstar-integration` (they describe the divergence, so they live on the shipped branch, not on pristine `main`).

- [ ] **Step 1: Write `REBASING.md`** (fork root)

Content — the standing rule, verbatim:

> The patch set instruments `ds4_agent.c`'s decode loops and emitters, so a rebase
> can apply cleanly and still be semantically wrong. Golden-fixture recapture
> against the real binary is mandatory on every submodule bump.

Plus a short "How to rebase this fork" section: fetch `upstream/main` + `upstream/laguna-s2.1`, merge into `patch-set`'s base, re-apply the 22-commit series (see `docs/fork-ledger.md` for the mapping), build, and **recapture before pushing** — never trust a clean `git rebase` as success.

- [ ] **Step 2: Write `docs/fork-ledger.md`**

Header: the standing rule, verbatim, referencing `REBASING.md` as canonical (the
rule must be found from the ledger too):

> The patch set instruments `ds4_agent.c`'s decode loops and emitters, so a
> rebase can apply cleanly and still be semantically wrong. Golden-fixture
> recapture against the real binary is mandatory on every submodule bump.
> Canonical text: `REBASING.md`.

One row per divergence. Each row: name, commits (original SHA → new SHA), why it exists, what would retire it, upstream-bound? (yes/no + proposal link). The six rows:

1. **status marker** — 2 commits; why: non-interactive agent must emit observable state; retires when upstream lands structured status emission, or SwiftStar stops launching ds4-agent without `--json-events`.
2. **turn-interrupt** — 1 commit; why: interrupt a generation mid-turn from a spawned non-interactive process; retires when upstream lands a first-class interrupt signal.
3. **stale-interrupt latch** — 1 commit; why: a stale interrupt must not kill the next turn; retires with turn-interrupt.
4. **`--json-events`** — 16 commits; why: structured NDJSON wire (text/think/tool/status/ready/queued, `idx`, param `name`, finish `calls`); retires when upstream lands a structured events mode (flagship proposal #1); documented at `docs/json-events.md`.
5. **startup memory plan** — 2 commits; why: know the memory plan at startup to gate feasibility (P3/P4); retires when upstream exposes it via a first-class API.
6. **integration structure** (`swiftstar-integration` = main + laguna-s2.1 + patch set) — not an engine change; fork hygiene; retires when laguna-s2.1 merges to antirez main, then ultimately when the whole patch set lands upstream.

Plus a **development branches** section: `laguna-s2.1` (upstream mirror, in the integration), `laguna-xs2.1` and `mellum-2.1-overnight` (local dev branches, pushed for a durable home, enter the integration only when SwiftStar ships a `Variant` at P12+). The Mellum row's retirement condition notes the SFT snapshot (`683ca310…`, 2026-08-21) whose canonical `MellumForCausalLM` config removes the fixtures-drift reason.

Include the original → new SHA mapping from Task 3 Step 12.

- [ ] **Step 3: Write `docs/upstream-proposals.md`**

One entry per ledger row marked upstream-bound, phrased as an actual proposal (problem, what the patch does, suggested upstream shape). The flagship: a structured-events mode for non-interactive agents (`--json-events`). State that nothing has been filed upstream; this is the intention record.

- [ ] **Step 4: Commit the docs to `swiftstar-integration`**

```bash
cd /tmp/ds4-rebase
git checkout swiftstar-integration
git add REBASING.md docs/fork-ledger.md docs/upstream-proposals.md
git commit -m "docs: fork ledger, rebasing rule, and upstream proposals"
git push origin swiftstar-integration
```
Expected: docs committed on top of the 22-commit series; `swiftstar-integration` = patch set + docs commit.

- [ ] **Step 5: Verify**

Run:
```bash
git log --oneline -1 origin/swiftstar-integration
git ls-tree origin/swiftstar-integration REBASING.md docs/fork-ledger.md docs/upstream-proposals.md
```
Expected: the docs commit is HEAD; all three files present in the tree.

---

## Task 5: Integrate the submodule into SwiftStar + `just engine`

**Files:**
- Modify: `Justfile` (add `engine` recipe).
- Create: `external/ds4` submodule (gitlink + `.gitmodules`).

**Interfaces:**
- Consumes: Task 4's `swiftstar-integration` branch on the fork.
- Produces: SwiftStar pins `external/ds4` to `swiftstar-integration`'s SHA; `just engine` builds both binaries.

- [ ] **Step 1: Add the submodule**

```bash
cd ~/projects/pauleveritt/swiftstar
git submodule add -b swiftstar-integration https://github.com/pauleveritt/ds4.git external/ds4
git submodule status
```
Expected: submodule added; `.gitmodules` records `branch = swiftstar-integration`; the gitlink pins the SHA of `swiftstar-integration`'s tip.

- [ ] **Step 2: Add the upstream remote in the submodule checkout**

```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
git remote add upstream https://github.com/antirez/ds4.git 2>/dev/null || git remote set-url upstream https://github.com/antirez/ds4.git
git remote -v
```
Expected: `origin` = fork, `upstream` = antirez.

- [ ] **Step 3: Add the `engine` recipe to the Justfile**

Add to the existing `Justfile`:

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

- [ ] **Step 4: Run the one command**

```bash
cd ~/projects/pauleveritt/swiftstar
just engine 2>&1 | tail -5
```
Expected: builds both binaries at `external/ds4/ds4-server` and `external/ds4/ds4-agent`, from the pinned SHA (verified by `git -C external/ds4 rev-parse HEAD` matching the gitlink).

- [ ] **Step 5: Commit**

```bash
cd ~/projects/pauleveritt/swiftstar
git add Justfile .gitmodules external/ds4
git commit -m "P1: pin ds4 submodule to swiftstar-integration and add just engine"
```

---

## Task 6: NDJSON golden capture (recapture) from `ds4-agent`

**Files:**
- Create in SwiftStar: `fixtures/agent/golden.ndjson`, `fixtures/agent/golden.ndjson.sidecar`, `fixtures/agent/provenance.md`.
- Throwaway capture script (not committed).

**Interfaces:**
- Consumes: `just engine` output (Task 5); weights at `~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf`; the existing DS4 Control fixture `agent-events-golden.ndjson` (983 lines, at `8267745`) as the expected-output reference.
- Produces: the committed NDJSON capture + sidecar + provenance.

**Why recapture:** the on-disk DS4 Control fixture is already at `8267745` with memory fields — the *same content* the rebased patch set should produce. P1 recaptures against the rebuilt binary at the new pinned SHA: the recapture is a **re-verification** that the rebase preserved the wire contract. If the recapture's event kinds/shapes diverge from the reference fixture, the rebase broke something — stop and re-derive.

- [ ] **Step 1: Prepare the scratch working directory**

```bash
rm -rf /tmp/ds4-capture-agent && mkdir -p /tmp/ds4-capture-agent/work
printf 'First seed file line one.\nSecond seed file line two.\nThird seed file line three.\n' > /tmp/ds4-capture-agent/work/notes.txt
printf 'Other file line one.\nOther file line two.\n' > /tmp/ds4-capture-agent/work/other.txt
cd /tmp/ds4-capture-agent
mkfifo agent-in.fifo
( while :; do sleep 3600; done ) > agent-in.fifo &
KEEP_PID=$!
echo "keepalive pid: $KEEP_PID"
```
Expected: workdir with the two seed files (read targets for the read/write prompts); FIFO with a live keepalive writer so individual prompt writes don't transiently hand EOF.

- [ ] **Step 2: Write the throwaway timestamper script**

Create `/tmp/ds4-capture-agent/timestamper.sh`:

```bash
#!/usr/bin/env bash
# Verbatim-raw timestamper: one receive timestamp (epoch ns) per line read,
# appended to the sidecar. The WIRE ITSELF is written by `tee`, untouched;
# this script never re-emits it, so the capture is byte-for-byte.
sidecar="$1"
while IFS= read -r _; do
    printf '%s\n' "$(date +%s%N)" >> "$sidecar"
done
```
Note: the sidecar gets one line per newline-terminated line of the wire, in
order. The wire bytes go through `tee` (Task 6 Step 3), never through this
script — that is the verbatim-raw contract.

- [ ] **Step 3: Launch ds4-agent with `--json-events` into the stamper**

```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4   # metal/*.metal resolve relative to CWD
./ds4-agent -m ~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf \
  -c 32768 --chdir /tmp/ds4-capture-agent/work --metal --non-interactive --json-events \
  < /tmp/ds4-capture-agent/agent-in.fifo \
  2> /tmp/ds4-capture-agent/agent.stderr \
  | tee /tmp/ds4-capture-agent/golden.ndjson \
  | /tmp/ds4-capture-agent/timestamper.sh /tmp/ds4-capture-agent/golden.ndjson.sidecar
```
(Launch in background with `& AGENT_PID=$!`; `tee` writes the wire byte-for-byte to the capture; the timestamper only records receive times.)
Expected: agent launches; the `ready` event appears in `golden.ndjson` within ~30-60s (model load). Watch `tail -f /tmp/ds4-capture-agent/golden.ndjson` until the first `{"t":"ready",...}` with the four memory fields.

- [ ] **Step 4: Send the prompts one at a time, waiting for idle between turns**

For each prompt below, write one line to the FIFO and wait until a fresh `ready` event (turn boundary) appears in the capture before sending the next:

1. **Reasoning puzzle** (reliably produces non-empty `think`):
   "Five people (Alice, Bob, Carol, Dave, Eve) occupy houses numbered 1 to 5, one each. Constraints: Alice is not in house 1 or house 5. Bob is directly to the right of Carol. Dave is in an even-numbered house. Eve is somewhere to the left of Bob. Carol is not in house 3. Work out every assignment that satisfies all constraints, showing your deductions."
2. **Read + write, non-ASCII**: "Please read the file notes.txt in the current directory, then write a new file called result.txt containing exactly this text: Café — €12 total. Do both the read and the write."
3. **Edit**: "Edit result.txt: change the word Café to Bistro, keeping the rest of the line the same."
4. **Multi-call block**: "Please read both notes.txt and other.txt right now, one after the other in the same response, then briefly compare their contents."
5. **Bash with `#` in output**: "Run a bash command that prints the exact line: # Section Heading"
6. **Long generation + interrupt**: "Write a very detailed, thorough 1200-word essay about the history of chess. Cover its origins in ancient India, its spread through Persia and the Islamic world, its adoption and rule changes in medieval Europe, the rise of formal competition and world championships, the Soviet school of chess, the Fischer-Spassky match, and the computer-chess era." Once `status` shows `generating` at >= 200 tokens, send a bare ETX byte (`printf '\x03'`) to the FIFO to interrupt.

Run:
```bash
printf '%s\n' "PROMPT_TEXT" > /tmp/ds4-capture-agent/agent-in.fifo
```
Expected: each turn produces NDJSON lines in `golden.ndjson`; prompt 6's interrupt produces a `finish` with `"status":"[tool call interrupted]\n"`.

- [ ] **Step 5: End the session**

```bash
kill -TERM "$AGENT_PID" 2>/dev/null
sleep 1
kill "$KEEP_PID" 2>/dev/null
rm -f /tmp/ds4-capture-agent/agent-in.fifo
```
Expected: agent exits cleanly; no other ds4-agent touched.

- [ ] **Step 6: Verify the capture — every line parses as JSON**

Run:
```bash
cd /tmp/ds4-capture-agent
while read -r l; do printf '%s\n' "$l" | /usr/bin/python3 -c 'import sys,json; json.loads(sys.stdin.read())' || echo "BAD LINE: $l"; done < golden.ndjson 2>&1 | tail -3
echo "lines: $(wc -l < golden.ndjson)  sidecar: $(wc -l < golden.ndjson.sidecar)"
```
Expected: zero parse failures; line counts match. (The python check is a *verification step*, allowed — D11 restricts Python's role in the repo, not one-off verification. If you prefer, use `ruby -rjson -e`.)

- [ ] **Step 7: Check coverage against the reference fixture**

Compare event kinds with the reference (`~/projects/ds4-control/.claude/worktrees/agent-mode/Tests/DS4ControlTests/Fixtures/agent-events-golden.ndjson`). Required: `text`, `think`, `tool`, `status`, `ready` kinds; tool phases `start`/`tool`/`param_begin`/`param_value`/`param_end`/`output`/`finish`; `idx` on every tool event; `name` on every `param_begin`; four memory fields on `ready`; at least one `finish` with `"status"` (interrupted); at least one `output` event (prompt 5's bash). Gaps are recorded in provenance, never hand-filled.

- [ ] **Step 8: Write `provenance.md`**

Follow the existing DS4 Control `agent-events-golden.md` structure: provenance (SHA of `external/ds4` at capture time — the pinned gitlink; built with `just engine`), exact command line, model file, seed files, the FIFO-keepalive gotcha, prompts in order and what each produced, event kinds/tool phases present, and **gaps** (what was not captured and why).

- [ ] **Step 9: Commit the fixtures**

```bash
cd ~/projects/pauleveritt/swiftstar
mkdir -p fixtures/agent
cp /tmp/ds4-capture-agent/golden.ndjson fixtures/agent/golden.ndjson
cp /tmp/ds4-capture-agent/golden.ndjson.sidecar fixtures/agent/golden.ndjson.sidecar
cp /tmp/ds4-capture-agent/provenance.md fixtures/agent/provenance.md
git add fixtures/agent
git commit -m "P1: golden NDJSON capture from ds4-agent (recapture)"
```

---

## Task 7: SSE golden capture (first capture) from `ds4-server`

**Files:**
- Create in SwiftStar: `fixtures/server/golden.sse`, `fixtures/server/golden.sse.sidecar`, `fixtures/server/provenance.md`.
- Throwaway capture script (not committed).

**Interfaces:**
- Consumes: `just engine` output (Task 5); weights; the SSE emitter path in `ds4_server.c` (`sse_chunk`, `sse_done` → `data: {...}` chunks + `data: [DONE]`).
- Produces: the committed SSE capture + sidecar + provenance.

**Why first capture:** no SSE capture from `ds4-server` exists anywhere. This is a fresh artifact.

- [ ] **Step 1: Prepare the throwaway timestamper script**

Create `/tmp/ds4-capture-server/timestamper.sh` (identical to Task 6 Step 2) and a working dir:
```bash
rm -rf /tmp/ds4-capture-server && mkdir -p /tmp/ds4-capture-server
# copy timestamper.sh from Task 6, or re-create it
```

- [ ] **Step 2: Launch ds4-server**

```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
./ds4-server -m ~/projects/ds4/gguf/laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf \
  -c 32768 --host 127.0.0.1 --port 8000 \
  > /tmp/ds4-capture-server/server.stdout 2> /tmp/ds4-capture-server/server.stderr &
SERVER_PID=$!
echo "server pid: $SERVER_PID"
sleep 1
tail -3 /tmp/ds4-capture-server/server.stderr
```
Expected: "ds4-server: listening on http://127.0.0.1:8000" appears; model loads (may take ~30-60s).

- [ ] **Step 3: Send a chat request and capture the SSE stream**

Wait until the server reports listening (or a bit longer for model load), then:
```bash
curl -sS -N -X POST http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages":[{"role":"user","content":"Explain, in three sentences, why the sky is blue."}],"stream":true}' \
  | tee /tmp/ds4-capture-server/golden.sse \
  | /tmp/ds4-capture-server/timestamper.sh /tmp/ds4-capture-server/golden.sse.sidecar
```
Expected: SSE stream of `data: {...}` chunks (token deltas) ending with `data: [DONE]`, stored byte-for-byte in `golden.sse` via `tee`, timestamps in the sidecar.

- [ ] **Step 4: Take a second, richer capture (optional but recommended for coverage)**

Repeat Step 3 with a reasoning-heavy prompt (e.g. the house puzzle from Task 6) so the SSE stream includes `reasoning_content` deltas if the model emits them, plus a longer generation. Append to a second file or overwrite — the committed fixture should be the richest single capture. Keep both if coverage differs; `provenance.md` records which is canonical.

- [ ] **Step 5: Stop the server**

```bash
kill -TERM "$SERVER_PID" 2>/dev/null
```
Expected: server exits; nothing else on port 8000 disturbed.

- [ ] **Step 6: Verify the capture**

Run:
```bash
cd /tmp/ds4-capture-server
echo "sse lines: $(wc -l < golden.sse)  sidecar: $(wc -l < golden.sse.sidecar)"
tail -3 golden.sse
```
Expected: lines end with `data: [DONE]`; sidecar line count matches; every `data: {...}` chunk parses as JSON (spot-check a few with the python/ruby one-liner from Task 6).

- [ ] **Step 7: Write `provenance.md`**

SHA of `external/ds4` at capture time, exact server command line, model, the curl request, the prompt(s), event shape observed (delta chunks + `[DONE]`), and any gaps.

- [ ] **Step 8: Commit the fixtures**

```bash
cd ~/projects/pauleveritt/swiftstar
mkdir -p fixtures/server
cp /tmp/ds4-capture-server/golden.sse fixtures/server/golden.sse
cp /tmp/ds4-capture-server/golden.sse.sidecar fixtures/server/golden.sse.sidecar
cp /tmp/ds4-capture-server/provenance.md fixtures/server/provenance.md
git add fixtures/server
git commit -m "P1: golden SSE capture from ds4-server (first capture)"
```

---

## Task 8: Final verification against done-when

**Files:**
- Modify: nothing (verification task). Optionally `ROADMAP.md` P1 status → complete.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: a verified P1 completion, recorded in the session log and (optionally) the roadmap.

- [ ] **Step 1: Verify the fork exists and is parented to antirez**

Run:
```bash
gh repo view pauleveritt/ds4 --json parent,defaultBranchRef
```
Expected: parent = `antirez/ds4`; default branch = `main`.

- [ ] **Step 2: Verify main is pristine**

Run:
```bash
git ls-remote https://github.com/pauleveritt/ds4.git main | cut -f1
git ls-remote https://github.com/antirez/ds4.git main | cut -f1
```
Expected: the two SHAs are equal (fork main mirrors antirez main).

- [ ] **Step 3: Verify the integration branch carries the 22 patches**

Run (from the SwiftStar submodule):
```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
git fetch origin
git log --oneline origin/main..origin/swiftstar-integration | wc -l
git log --oneline origin/main..origin/swiftstar-integration | grep -cE 'json-events|interrupt|status|memory|startup|ready'
```
Expected: 22 app commits (+ the Laguna merge + docs commit) above main; the patch names present.

- [ ] **Step 4: Verify the submodule pins a SHA on swiftstar-integration**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar
git submodule status
git -C external/ds4 rev-parse HEAD
git ls-remote https://github.com/pauleveritt/ds4.git swiftstar-integration | cut -f1
```
Expected: `git submodule status` shows the pinned gitlink; `external/ds4` HEAD matches the gitlink; both match the remote `swiftstar-integration` tip.

- [ ] **Step 5: Verify one command builds both binaries**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar
just engine 2>&1 | tail -3
ls -la external/ds4/ds4-server external/ds4/ds4-agent
```
Expected: build succeeds; both binaries present.

- [ ] **Step 6: Verify the fork ledger has a row per divergence**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
grep -E '^\|' docs/fork-ledger.md | head -20
```
Expected: the six divergence rows (status marker, turn-interrupt, stale-interrupt latch, `--json-events`, startup memory plan, integration structure) each with a retirement condition.

- [ ] **Step 7: Verify `docs/upstream-proposals.md` exists with upstream-bound entries**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
test -f docs/upstream-proposals.md && echo present
grep -c 'upstream' docs/upstream-proposals.md
```
Expected: file present; contains upstream-bound entries.

- [ ] **Step 8: Verify both captures are committed**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar
git ls-files fixtures/agent fixtures/server
```
Expected: `golden.ndjson`, `golden.ndjson.sidecar`, `provenance.md` under `fixtures/agent/`; `golden.sse`, `golden.sse.sidecar`, `provenance.md` under `fixtures/server/`.

- [ ] **Step 9: Verify `REBASING.md` carries the standing rule**

Run:
```bash
cd ~/projects/pauleveritt/swiftstar/external/ds4
grep -c 'recapture' REBASING.md
```
Expected: the rule text present (>= 1 match).

- [ ] **Step 10: Update ROADMAP.md (P1 complete)**

Edit `ROADMAP.md`: change P1's status from "next" to "**complete (2026-08-21)**" and, if desired, add a one-line prior-work entry. Commit:
```bash
cd ~/projects/pauleveritt/swiftstar
git add ROADMAP.md
git commit -m "P1: mark complete"
```

---

## Self-Review Notes

- **Spec coverage:** every done-when item maps to a task — fork (T1), main pristine (T1/T8-S2), integration branch (T3), submodule pinned (T5), `just engine` (T5), ledger (T4/T8-S6), upstream-proposals (T4/T8-S7), both captures (T6/T7/T8-S8), recapture rule in `REBASING.md` (T4/T8-S9).
- **Scope discipline:** no Swift, no app, no Mellum on the integration, no `--subagent-pool`, no upstream PRs — all excluded.
- **Patch-id honesty:** the local Laguna line and upstream `laguna-s2.1` share titles but only 4/16 patch-ids match (spec "A finding"); Task 3's merge therefore may conflict — expected, resolved by hand.
- **Placeholder scan:** no TBDs; every step has a runnable command or concrete content.
