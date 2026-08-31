# P23 Wire-Level Control — Implementation Plan (part 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship P23's no-engine-patch half — correct Laguna XS's memory model and
raise its context ceiling, bound runaway thinking with the flag the engine
already has, and prepare the wire/argv seams — leaving the codebase ready for the
engine patch in part 2.

**Architecture:** Nothing here touches `external/ds4`, bumps the submodule, or
requires a golden recapture. Every change is Swift or documentation, proven in
the fast tier (746 tests, ~0.05 s). Two tasks are pure refactors with a
provable no-op property; two ship user-visible behavior; one is a measurement
that feeds part 2's design.

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing (`@Test`/`@Suite`,
not XCTest), SwiftPM. macOS. `swift-testing` fast tier gated by the
`FastTierGuard` build-tool plugin.

**Spec:** [`docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md`](../specs/2026-08-28-p23-wire-level-control-design.md)

**Research:** [`docs/superpowers/research/2026-08-28-p23-wire-control-research.md`](../research/2026-08-28-p23-wire-control-research.md)

## Global Constraints

- **Fast tier must stay green and must stay fast.** `swift test` — no model, no
  network, no subprocess. The `FastTierGuard` plugin fails the build if a
  `SwiftStarKitTests` source mentions `Process(`, `URLSession`, `NWConnection`,
  `posix_spawn`, `Darwin.`, or `socket(`.
- **Integration tier** is `SWIFTSTAR_INTEGRATION=1 swift test`; every
  integration suite carries `@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))`.
- **BRIEF.md binding rule 2:** every new test must be shown to fail when the
  behavior it pins is broken — break it, observe the failure, restore. Several
  tasks below build this in by writing the test before the fix.
- **BRIEF.md binding rule 4:** a refusal test has a sibling success test.
- **No engine changes in this plan.** Do not edit `external/ds4`, do not run
  `just engine`, do not bump the submodule. Those are part 2.
- **Commit message style:** phase-prefixed subject (`P23: …`), body explaining
  why, and end with:
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- **Test count is an assertion, not a vibe.** Baseline is **746**. Task 2
  removes 3 tests (→743); tasks 4, 6, 8, 9 add tests. State the expected count
  in each commit.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `ROADMAP.md` | phase record; P23 row currently describes half the phase | 1 |
| `README.md` | front door; phase status is 13 phases stale | 1 |
| `Sources/SwiftStarKit/ShellVocabulary.swift` | **delete** — speculative registry, zero production consumers | 2 |
| `Tests/SwiftStarKitTests/ShellVocabularyTests.swift` | **delete** — 3 tests pinning the above | 2 |
| `fixtures/server/` | **delete** — 780 KB of SSE captures whose parser no longer exists | 2 |
| `Sources/SwiftStarKit/Variant.swift` | `MemoryBudget` — the KV anchor model | 4 |
| `Sources/SwiftStarKit/VariantRegistry.swift` | XS's anchors and ceiling | 4, 5 |
| `Tests/SwiftStarKitTests/VariantRegistryTests.swift` | registry invariants | 4, 5 |
| `Sources/SwiftStarKit/AgentDefaultSettings.swift` | resolves `AgentSettings` from `UserDefaults` | 6 |
| `Sources/SwiftStar/SettingsView.swift` | the think-budget control | 6 |
| `Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift` | resolution tests | 6 |
| `Sources/SwiftStarKit/WireStatusDecoder.swift` | **new** — the one `status`/`ready` field decoder both parsers call | 8 |
| `Sources/SwiftStarKit/AgentWireParser.swift` | live-path parser; keeps its own enum | 8 |
| `Sources/SwiftStarKit/WireEventParser.swift` | telemetry parser; keeps its own enum | 8 |
| `Sources/SwiftStar/AgentController.swift` | inlines the pooled argv; hosts the 238-line pool loop | 9, 10 |
| `Sources/SwiftStar/AgentPoolTurnLoop.swift` | **new** — the extracted pool worker-turn loop | 10 |

---

### Task 1: ROADMAP and README truth

The P23 row describes about half the phase and books a ledger slot P22 already
took. Nothing else in this plan is safe to reason about until the record is
right.

**Files:**
- Modify: `ROADMAP.md:15` (P25 `## Now` residue), `ROADMAP.md:227` (the P23 row)
- Modify: `README.md:17,25`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing code-facing. Later tasks cite the corrected row.

- [ ] **Step 1: Fix the P25 residue in `## Now`**

`ROADMAP.md:15` still says Cycle 4b "wants review" while the P25 row at :229
says it shipped and closed. Replace the clause
`4b wants review;` with:

```
4b shipped and closed 2026-08-28 (see the row);
```

- [ ] **Step 2: Rewrite the P23 row**

Replace the Direction cell of the P23 row (`ROADMAP.md:227`) with:

```
Per-turn think on the agent wire (`reasoning_effort`-style) **plus per-worker context for pool workers** (the small-ctx/RLM lever, descoped from P20 2026-08-27 and merged here). The think leg buys correctness and responsiveness — it bounds the observed think-to-the-wall failure and delivers the "fast reply"; its wall-clock ceiling is ~9.3%, so it is **not** a throughput lever. The per-worker-context leg carries the measured speed (4.2x prefill ceiling; ~6.15 GB → ~1.5 GB scratch per worker). One engine patch, **fork-ledger row #14** (P22's SSD widening took #13), one golden recapture. Spec: [`2026-08-28-p23-wire-level-control-design.md`](docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md)
```

And replace its Status cell with:

```
**planned** — spec written 2026-08-28. Blocker cleared: the small-ctx-workers dependency on P22's XS golden recapture shipped 2026-08-28. Note the "toolless" half of the quick reply is **descoped** (dropping tool schemas for one turn busts the KV prefix in both directions; the non-busting token-ban approach is unverified) — `/quick` means no-think, not toolless
```

- [ ] **Step 3: Fix the README status paragraph**

`README.md:16` currently reads `**Phases P0–P11 complete.**` and `:25` ends
`See [`ROADMAP.md`](ROADMAP.md) for what is next (P12).` Replace the phase
count with `**Phases P0–P22 and P25 complete.**` and the trailing sentence
with:

```
See [`ROADMAP.md`](ROADMAP.md) for what is next (P23).
```

- [ ] **Step 4: Verify no other stale P12 pointer**

Run: `grep -n "next (P1[0-9]\?)\|P0–P11\|P0-P11" README.md ROADMAP.md`
Expected: no matches.

- [ ] **Step 5: Run the fast tier**

Run: `swift test`
Expected: `746 tests` pass. (Docs-only change; the count must not move.)

- [ ] **Step 6: Commit**

```bash
git add ROADMAP.md README.md
git commit -m "$(cat <<'EOF'
P23: correct the phase record before opening the phase

The P23 row described about half the phase — small-ctx workers were
merged into it on 2026-08-27 (:389, and P24's row at :228) but the row
never picked it up — and booked fork-ledger row #13, which P22's SSD
gate widening already took. P23's row is #14.

Also records that the small-ctx-workers blocker (P22's XS golden
recapture) shipped, that the "toolless" half of the quick reply is
descoped, and clears two stale pointers: the P25 residue in ## Now and
README's phase count, which was 13 phases behind.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Delete proven-dead weight

`ShellVocabulary` is a speculative registry for a consumer that was never built;
its own doc comment names it ("the future image-describer"). It has a test suite,
which makes it look alive. `fixtures/server/` fed the SSE parser that P19
deleted.

**Files:**
- Delete: `Sources/SwiftStarKit/ShellVocabulary.swift`
- Delete: `Tests/SwiftStarKitTests/ShellVocabularyTests.swift`
- Delete: `fixtures/server/` (5 files, 780 KB)

**Interfaces:**
- Consumes: nothing.
- Produces: test count drops 746 → **743**.

- [ ] **Step 1: Prove `ShellVocabulary` is dead before deleting it**

Run each and confirm the expected result — do not delete on the first command
alone:

```bash
grep -rn "ShellVocabulary\|ShellRegion" Sources/ Tools/ Plugins/ | grep -v "Sources/SwiftStarKit/ShellVocabulary.swift"
grep -rn "accessibilityIdentifier" Sources/
grep -rnE "\"(sidebar|toolbar|inspector|composer|transcript|toolCard|statusBar|ringGauge|modelMenu|workspaceControl|phaseBrowserRail)\"" Sources/
```

Expected: **all three produce no output.** If any produces output, STOP — the
type is live; report and skip this task.

- [ ] **Step 2: Prove `fixtures/server/` is unreferenced**

```bash
grep -rn "fixtures/server\|golden\.sse\|golden\.short\.sse" Sources/ Tests/ Tools/ Plugins/ Justfile Package.swift
```

Expected: no output.

- [ ] **Step 3: Delete**

```bash
git rm -q Sources/SwiftStarKit/ShellVocabulary.swift Tests/SwiftStarKitTests/ShellVocabularyTests.swift
git rm -rq fixtures/server
```

- [ ] **Step 4: Run the fast tier**

Run: `swift test`
Expected: **743 tests** pass, 0 failures. A compile error here means step 1
missed a reference — restore and re-check rather than patching around it.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
P23: delete ShellVocabulary and the retired SSE fixtures

ShellVocabulary is a component/region registry built in P19.1 for a
consumer that was never built — its own doc comment names it ("the
future image-describer and the agent's layout reasoning"). Zero
production references, zero uses of its 21 region ids as string
literals, zero accessibilityIdentifier uses anywhere in Sources/. Its
3-test suite was the only thing making it look alive.

fixtures/server/ (780 KB) fed SSEParser, which P19 deleted with the
Chat surface. Unreferenced by Sources/, Tests/, Tools/, Plugins/,
Justfile, and Package.swift.

743 fast-tier tests (746 - 3).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Submodule precondition

Divergences #12 and #13 exist only in this machine's submodule clone, and the
pin sits on a branch `.gitmodules` does not declare. Part 2 adds #14 on top.
**This task is git operations only — no code, no engine build.**

**Files:**
- Modify: `.gitmodules` (branch declaration)
- Modify: `external/ds4/docs/fork-ledger.md` (missing rows) — *in the submodule*

**Interfaces:**
- Consumes: nothing.
- Produces: a pin reachable from a remote ref, so part 2's divergence #14 lands
  on recoverable history.

- [ ] **Step 1: Initialize the submodule in this worktree**

A fresh worktree has no submodule contents.

Run: `git submodule update --init external/ds4`
Expected: checks out `79b8590`.

- [ ] **Step 2: Confirm the problem before fixing it**

```bash
git -C external/ds4 branch -r --contains 96286b3
git -C external/ds4 branch -r --contains 849f375
```

Expected: **both empty** — this is the defect. If either prints a remote branch,
that divergence is already pushed; note it and continue.

- [ ] **Step 3: Push the pinned branch**

```bash
git -C external/ds4 push -u origin p20-dispatch-schema
```

Expected: success. **If this fails on auth or a missing remote, STOP and report**
— do not invent a remote.

- [ ] **Step 4: Verify the pin is now reachable**

```bash
git -C external/ds4 branch -r --contains 96286b3
git -C external/ds4 branch -r --contains 849f375
```

Expected: both list `origin/p20-dispatch-schema`.

- [ ] **Step 5: Make `.gitmodules` declare the branch actually pinned**

`.gitmodules` declares `branch = swiftstar-integration`; the pin is on
`p20-dispatch-schema`, 301 commits ahead of local `swiftstar-integration`.
`REBASING.md`'s procedure run as written would silently drop #12 and #13.
Change the `branch =` line to:

```
	branch = p20-dispatch-schema
```

- [ ] **Step 6: Add the two missing fork-ledger rows**

`--think-budget` (`1f9a4c5`) and the Mellum loader changes (`32bed2d`,
`f56d0ca`) are in the pinned tree with no ledger row. Append to the divergence
table in `external/ds4/docs/fork-ledger.md`, matching the existing column shape
(`# | Divergence | Commits | Why it exists | What retires it`):

```
| 13a | `--think-budget`: a per-round thinking ceiling that forces `</think>` and bans reopening for the round | `1f9a4c5` | Bounds a model that drafts a complete answer and never transitions to acting, without amputating reasoning the way `--nothink` does. Landed 2026-08-24 with no row; recorded here for auditability. P23 makes it per-turn. | Upstream adopting a per-round think ceiling. |
| 13b | Mellum loader: reject non-Q8_0 down tensors in the decode contract; crafted-artifact admission loader test | `32bed2d`, `f56d0ca` | Mellum's quant contract is enforced at load rather than trusted. Landed with no row. | Upstream enforcing the same contract. |
```

Number them `13a`/`13b` rather than renumbering — P23's row is **#14** and the
existing numbering is cited from the parent repo.

- [ ] **Step 7: Commit the submodule's ledger, then the parent**

```bash
git -C external/ds4 add docs/fork-ledger.md
git -C external/ds4 commit -m "$(cat <<'EOF'
fork-ledger: record the two unrowed divergences (13a, 13b)

--think-budget (1f9a4c5) and the Mellum loader changes (32bed2d,
f56d0ca) are ancestors of the pinned SHA but never got ledger rows, so
the ledger's count of 13 understated the real divergence count. Added
as 13a/13b rather than renumbering, since the existing numbers are
cited from the parent repo and P23's row is #14.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git -C external/ds4 push origin p20-dispatch-schema
```

- [ ] **Step 8: Commit the parent's `.gitmodules` and the gitlink**

```bash
git add .gitmodules external/ds4
git commit -m "$(cat <<'EOF'
P23: make the submodule pin recoverable before adding divergence #14

Divergences #12 (dispatch schema) and #13 (SSD gate widening) existed
only in this machine's submodule clone — `git branch -r --contains`
was empty for both, so a fresh `git clone --recursive` could not
resolve the pin. Pushed p20-dispatch-schema.

.gitmodules declared `branch = swiftstar-integration` while the pin
sits on p20-dispatch-schema, 301 commits ahead. BRIEF.md:221-222 says
the submodule pins a SHA on the declared branch and only that branch,
and REBASING.md's rebase procedure run as written would have silently
dropped #12 and #13. The declaration now matches reality.

Also bumps the gitlink for the submodule's fork-ledger rows 13a/13b.
No engine code changed; no recapture owed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Fix Laguna XS's KV anchor, and pin the invariant

`MemoryBudget.kvGiB(at:)` extrapolates above ctx 32,768 from the
`kvGiBAt32k → kvGiBAt40k` slope. XS declares both as `1.31`, so the slope is
zero and KV is planned flat at any context above 32k. Three of four variants'
40k anchors match their own 16k→32k slope to four decimals; XS's is a copy of
its 32k value. **The fix must land before Task 5 raises the ceiling** — that is
the whole reason this is two tasks.

**Files:**
- Modify: `Sources/SwiftStarKit/VariantRegistry.swift:112`
- Test: `Tests/SwiftStarKitTests/VariantRegistryTests.swift`

**Interfaces:**
- Consumes: `Variant.contract.memoryBudget` — `MemoryBudget` with stored
  properties `kvGiBAt16k: Double`, `kvGiBAt32k: Double`, `kvGiBAt40k: Double`,
  `minContext: Int`, `maxContext: Int`, and `func kvGiB(at ctx: Int) -> Double?`.
- Produces: a registry-wide linearity invariant later variants must satisfy.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiftStarKitTests/VariantRegistryTests.swift`, inside the
existing suite:

```swift
    /// Every variant's 40k KV anchor must lie on the line its own 16k and 32k
    /// anchors define. `MemoryBudget.kvGiB(at:)` extrapolates above ctx 32,768
    /// from the 32k→40k slope, so an anchor copied from the 32k value makes KV
    /// plan flat at any larger context — under-planning memory the moment a
    /// variant's `maxContext` rises above 32,768.
    @Test func everyVariantsKVAnchorsLieOnOneLine() {
        for variant in VariantRegistry.all {
            let b = variant.contract.memoryBudget
            let slopePerToken = (b.kvGiBAt32k - b.kvGiBAt16k) / Double(32_768 - 16_384)
            let implied40k = b.kvGiBAt32k + slopePerToken * Double(40_960 - 32_768)
            #expect(
                abs(b.kvGiBAt40k - implied40k) < 0.01,
                """
                \(variant.id): kvGiBAt40k is \(b.kvGiBAt40k) but its own \
                16k→32k slope implies \(implied40k). A 40k anchor copied from \
                the 32k value makes kvGiB(at:) extrapolate flat above 32,768.
                """
            )
        }
    }
```

- [ ] **Step 2: Run it and watch it fail on XS**

Run: `swift test --filter everyVariantsKVAnchorsLieOnOneLine`
Expected: **FAIL**, naming `laguna-xs-2.1`, reporting `kvGiBAt40k is 1.31 but
its own 16k→32k slope implies 1.62`. This is binding rule 2 satisfied by
construction — the test is red before the fix.

If it passes, STOP: someone already changed the anchor and this task's premise
is gone.

- [ ] **Step 3: Fix the anchor**

In `Sources/SwiftStarKit/VariantRegistry.swift`, in the `lagunaXS` budget,
change `kvGiBAt40k: 1.31,` to:

```swift
                    // Derived from this variant's own 16k→32k slope
                    // (+0.62 GiB per 16,384 tokens → +0.31 per 8,192), not
                    // copied from the 32k anchor. `MemoryBudget.kvGiB(at:)`
                    // extrapolates above 32,768 from the 32k→40k slope, so a
                    // copied anchor plans KV flat at any larger context —
                    // dormant only while `maxContext` was 32,768.
                    kvGiBAt40k: 1.62,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter everyVariantsKVAnchorsLieOnOneLine`
Expected: PASS.

- [ ] **Step 5: Run the whole fast tier**

Run: `swift test`
Expected: **744 tests** (743 + 1), 0 failures. If an existing admission or
budget test now fails, it was asserting the flat value — read it before changing
it, and report rather than silently updating an expectation.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/VariantRegistry.swift Tests/SwiftStarKitTests/VariantRegistryTests.swift
git commit -m "$(cat <<'EOF'
P23: fix Laguna XS's 40k KV anchor and pin the linearity invariant

MemoryBudget.kvGiB(at:) extrapolates above ctx 32,768 from the
kvGiBAt32k -> kvGiBAt40k slope. Laguna XS declared both as 1.31, so the
slope was zero and KV planned flat at any larger context.

Extending each variant's own 16k->32k slope by 8,192 tokens predicts its
40k anchor. Mellum (0.5900), Laguna S (1.9453), and DeepSeek V4 Flash
(1.3056) all match their declared values to four decimals; XS's 1.31 was
a copy of its 32k anchor and should be 1.62. Unfixed, raising XS's
maxContext would under-plan KV by 19% at 40k and ~35% at 51,200.

The error was dormant only because maxContext capped at 32,768 — and
raising that cap is the next task. New test fails red on XS before the
fix.

744 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Raise Laguna XS's context ceiling

XS's GGUF declares `laguna.context_length = 262144`; the registry caps it at
32,768 on a budget whose own comment says "Measured on 32 GB M1 Pro". That cap
forced the compaction cliff behind 37.5% of the 1809 capture's Σ-suffix. With
Task 4's anchor corrected, the ceiling can rise to the app's own default.

**Files:**
- Modify: `Sources/SwiftStarKit/VariantRegistry.swift:113-114`
- Test: `Tests/SwiftStarKitTests/VariantRegistryTests.swift`

**Interfaces:**
- Consumes: Task 4's corrected `kvGiBAt40k: 1.62`.
- Produces: `VariantRegistry.lagunaXS.contract.memoryBudget.maxContext == 51_200`,
  so `AgentDefaultSettings.resolve` no longer clamps the app default for XS.

- [ ] **Step 1: Write the failing test**

Append to `Tests/SwiftStarKitTests/VariantRegistryTests.swift`:

```swift
    /// Laguna XS admits the app's own default context (51,200). Its GGUF
    /// declares context_length 262,144; the previous 32,768 cap was a 32 GB
    /// memory-tier budget, and running the main agent under it forced the
    /// compaction cliff measured in the 2026-08-27 capture.
    @Test func lagunaXSAdmitsTheAppDefaultContext() {
        let budget = VariantRegistry.lagunaXS.contract.memoryBudget
        #expect(budget.maxContext >= 51_200)
        #expect(budget.clampContext(51_200) == 51_200)
        let kv = budget.kvGiB(at: 51_200)
        #expect(kv != nil)
        // Linear from the corrected anchors: 1.31 + (51200-32768) * (0.31/8192)
        #expect(abs((kv ?? 0) - 2.0077) < 0.01)
    }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `swift test --filter lagunaXSAdmitsTheAppDefaultContext`
Expected: **FAIL** — `maxContext` is 32,768, `clampContext(51_200)` returns
32,768, and `kvGiB(at: 51_200)` returns nil.

- [ ] **Step 3: Raise the ceiling**

In `Sources/SwiftStarKit/VariantRegistry.swift`, change the `lagunaXS` budget's
`maxContext: 32_768` to:

```swift
                    // Raised from 32,768 (P23). The old cap was the 16/32 GB
                    // shipping budget — its own comment reads "Measured on
                    // 32 GB M1 Pro" — not a model limit: the GGUF declares
                    // laguna.context_length = 262144. Running the main agent
                    // at 32,768 forced five compactions in 24 minutes in the
                    // 2026-08-27 capture, manufacturing 37.5% of its
                    // Sigma-suffix. Capped at the app's own default (51,200)
                    // rather than the model ceiling, so the raise stays
                    // inside a measured envelope; VariantGate still admits
                    // against real memory.
                    maxContext: 51_200
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter lagunaXSAdmitsTheAppDefaultContext`
Expected: PASS.

- [ ] **Step 5: Run the whole fast tier**

Run: `swift test`
Expected: **745 tests**, 0 failures.

**Watch for one specific breakage:** `AgentDefaultSettingsTests` has a test
asserting XS clamps the app default down to 32,768
(`contextSizeIsClampedToASelectedVariantsMaxContext`). If it names XS, it is now
asserting the old behavior. Read it, and if it is XS-specific, retarget it at
Mellum (`maxContext: 40_960`), which still clamps — do **not** delete the
clamping test, since clamping is still real behavior.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/VariantRegistry.swift Tests/SwiftStarKitTests/VariantRegistryTests.swift Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift
git commit -m "$(cat <<'EOF'
P23: raise Laguna XS's context ceiling to the app default

XS's GGUF declares laguna.context_length = 262144. The registry capped
it at 32,768 on a budget whose own comment reads "Measured on 32 GB M1
Pro" — a memory-tier choice, not a model limit. Running the main agent
under that cap forced five compactions in 24 minutes in the 2026-08-27
capture, each discarding ~23k tokens, and the re-reading that followed
manufactured 37.5% of the session's Sigma-suffix.

Raised to 51,200 — the app's own default — rather than the model
ceiling, so the change stays inside a measured envelope. VariantGate
still admits against real memory, and Task 4's anchor fix means KV now
extrapolates correctly across the newly reachable range instead of flat.

745 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Ship the think budget

`--think-budget` is wired end-to-end already — `AgentSettings.thinkBudget` →
`AgentCommand.argv` → the engine's per-round enforcement. **The app has never
set it.** Probe A reproduced what that permits: 7 rounds, 15,873 of 16,384
tokens spent reasoning, no answer.

This is a guardrail, not a tuning knob. Default 2,048 — an ordinary round spends
~25 think tokens, so it never fires normally, and it does fire on a runaway.

**Files:**
- Modify: `Sources/SwiftStarKit/AgentDefaultSettings.swift` (the `resolve` return)
- Modify: `Sources/SwiftStar/SettingsView.swift` (the Agent section)
- Test: `Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift`

**Interfaces:**
- Consumes: `AgentSettings.thinkBudget: Int` (already exists; `0` = disabled)
  and `AgentCommand.argv(settings:)`, which appends
  `["--think-budget", String(settings.thinkBudget)]` when `thinkBudget > 0`.
- Produces: `UserDefaults` key `"agentThinkBudget"`, default `2048`.

- [ ] **Step 1: Write the failing tests**

Append to `struct AgentDefaultSettingsTests` in
`Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift`. That suite already
has `scratchDefaults() -> (defaults: UserDefaults, name: String)` and
`cleanUp(_:_:)` — use them exactly as written below; do **not** add a second
defaults fixture.

```swift
    // MARK: - think budget (P23)

    /// The app sets a think budget by default (P23). It is a guardrail, not a
    /// tuning knob: an ordinary round spends ~25 think tokens, so 2,048 never
    /// fires normally — but the 2026-08-28 probe reproduced a run that spent
    /// 15,873 of 16,384 tokens reasoning and never answered.
    @Test func thinkBudgetDefaultsToTheRunawayGuardrail() {
        let (defaults, name) = scratchDefaults()
        defer { cleanUp(defaults, name) }
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.thinkBudget == 2048)
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("--think-budget"))
        #expect(argv.contains("2048"))
    }

    /// Zero disables the flag entirely rather than passing `--think-budget 0`,
    /// which the engine would read as a live ceiling of zero.
    @Test func aZeroThinkBudgetOmitsTheFlag() {
        let (defaults, name) = scratchDefaults()
        defer { cleanUp(defaults, name) }
        defaults.set(0, forKey: "agentThinkBudget")
        let settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: [:], projectRoot: nil)
        #expect(settings.thinkBudget == 0)
        #expect(!AgentCommand.argv(settings: settings).contains("--think-budget"))
    }

    /// `thinkBudget` must stay below `maxTokens` or the forced `</think>`
    /// lands with no room left to act (AgentCommand's own doc comment). The
    /// app sets no `maxTokens`, so the pair only binds when a caller sets both
    /// — the agent test does. Sibling success case for the clamp above
    /// (binding rule 4): an unset `maxTokens` leaves the budget untouched.
    @Test func thinkBudgetIsClampedBelowAnExplicitMaxTokens() {
        let (defaults, name) = scratchDefaults()
        defer { cleanUp(defaults, name) }
        defaults.set(4096, forKey: "agentThinkBudget")
        var settings = AgentDefaultSettings.resolve(
            defaults: defaults, environment: [:], projectRoot: nil)
        #expect(AgentSettings.clampThinkBudget(settings) == 4096)  // maxTokens unset
        settings.maxTokens = 2048
        #expect(AgentSettings.clampThinkBudget(settings) == 1024)  // min(4096, 2048/2)
    }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter thinkBudget`
Expected: FAIL — `thinkBudget` resolves to 0 today, and
`AgentSettings.clampThinkBudget` does not exist.

- [ ] **Step 3: Add the clamp helper**

In `Sources/SwiftStarKit/AgentCommand.swift`, add to `AgentSettings`:

```swift
    /// `thinkBudget` must stay below `maxTokens` or the engine's forced
    /// `</think>` lands with no room left to act. The app sets no `maxTokens`
    /// (0 = engine default), so this only binds when a caller sets both — the
    /// agent test does. Returns the budget to actually pass.
    public static func clampThinkBudget(_ settings: AgentSettings) -> Int {
        guard settings.thinkBudget > 0 else { return 0 }
        guard settings.maxTokens > 0 else { return settings.thinkBudget }
        return Swift.min(settings.thinkBudget, settings.maxTokens / 2)
    }
```

Then, in `AgentCommand.argv`, replace the existing think-budget append with one
that routes through the clamp:

```swift
        let budget = AgentSettings.clampThinkBudget(settings)
        if budget > 0 {
            argv.append(contentsOf: ["--think-budget", String(budget)])
        }
```

- [ ] **Step 4: Resolve the budget from `UserDefaults`**

In `Sources/SwiftStarKit/AgentDefaultSettings.swift`, before the `return
AgentSettings(...)`, add:

```swift
        // P23: a standing guardrail against a runaway think loop. The
        // 2026-08-28 probe reproduced a turn that spent 15,873 of 16,384
        // tokens reasoning and never answered (the failure P20's closure
        // verdict also recorded). An ordinary round spends ~25 think tokens,
        // so 2,048 never fires normally. 0 disables the flag.
        let thinkBudget = defaults.object(forKey: "agentThinkBudget") as? Int ?? 2_048
```

and pass `thinkBudget: thinkBudget,` in the `AgentSettings(...)` call.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter thinkBudget`
Expected: PASS (3 tests).

- [ ] **Step 6: Add the Settings control**

In `Sources/SwiftStar/SettingsView.swift`, add the `@AppStorage` property beside
the other agent settings:

```swift
    @AppStorage("agentThinkBudget") private var agentThinkBudget = 2048
```

and add this row to the **Agent** section (the one holding "Allow shell
commands"), not Delegation:

```swift
                Stepper("Think budget: \(agentThinkBudget == 0 ? "off" : "\(agentThinkBudget) tokens")",
                        value: $agentThinkBudget, in: 0...8192, step: 256)
                Text("Caps one round's reasoning. The engine forces a close at the ceiling and bans reopening for that round. 0 disables it; the default never fires on an ordinary turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

- [ ] **Step 7: Run the whole fast tier**

Run: `swift test`
Expected: **748 tests** (745 + 3), 0 failures.

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiftStarKit/AgentDefaultSettings.swift Sources/SwiftStarKit/AgentCommand.swift Sources/SwiftStar/SettingsView.swift Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift
git commit -m "$(cat <<'EOF'
P23: set a think budget by default

--think-budget has been wired end-to-end since 2026-08-24 —
AgentSettings.thinkBudget -> AgentCommand.argv -> the engine's per-round
forced </think> — and the app has never set it. Only swiftstar-agenttest
and unit tests did.

The 2026-08-28 probe reproduced what that permits: Laguna XS at ctx
16,384 spent 7 rounds and 15,873 of 16,384 tokens reasoning and never
answered — the same failure P20's closure verdict recorded ("think-looped
to the 8192-token limit with 0 tools").

Default 2,048. This is a guardrail, not a tuning knob: an ordinary round
spends ~25 think tokens, so it never fires normally. Deliberately not
tighter — the same probe showed a 64-token budget cut thinking 20x but
took more rounds and shifted output into text, so a tight budget risks
converting reasoning into rambling. That trade is not settled by n=2 and
the default stays generous until it is.

Also adds AgentSettings.clampThinkBudget, honouring the constraint
AgentCommand's own doc comment already stated (the budget must stay below
maxTokens or the forced close lands with no room to act).

748 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Measure what the system prompt costs in thinking

**This task writes no production code.** Probe A found that thinking is
prompt-induced, not flag-induced: the same model at `think=high` produced zero
thinking on a bare prompt and 80%-thinking with a reasoning-inducing system
prompt. If the app's own `-sys` text drives think cost, that is a lever with no
engine patch — and part 2's design should know before it is written.

**Files:**
- Create: `docs/superpowers/research/2026-08-28-p23-sysprompt-think-cost.md`

**Interfaces:**
- Consumes: `SuperpowersBootstrap.build(...).indexPrompt` and
  `DispatchPreferenceRule.text` — the two strings `AgentController.startAgent`
  concatenates into `-sys`.
- Produces: a recorded measurement part 2 cites. No API.

- [ ] **Step 1: Capture the app's actual system prompt**

Write a throwaway script under the scratchpad (not the repo) that prints
`SuperpowersBootstrap.build(skillsDir:).indexPrompt + "\n\n" + DispatchPreferenceRule.text`
and its token-ish size. Record the byte and approximate token count.

- [ ] **Step 2: Run three arms against the real engine**

Same model, same task prompt, ctx 16,384, `--think`, varying only `-sys`:
no system prompt; the bootstrap alone; the bootstrap plus the dispatch rule.
Use the engine directly (`external/ds4/ds4-agent`), exporting
`DS4_METAL_<STEM>_SOURCE` for every `external/ds4/metal/*.metal` file and
`DS4_LOCK_FILE` — the engine aborts startup without the shader paths, and it
`chdir`s to `--workspace`, so a relative `--trace` path lands there.

- [ ] **Step 3: Tally think vs text characters per arm**

Count `{"t":"think"}` and `{"t":"text"}` payload characters off each wire.

- [ ] **Step 4: Write the findings doc**

Record: the three arms, their think/text split, and a plain statement of whether
the app's system prompt materially drives think cost. **Pre-register that this
is n=1 per arm and measures think volume only — no task-success claim.** If the
effect is large, note that trimming `-sys` is a zero-engine-work lever that
part 2 should weigh against the wire patch.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/research/2026-08-28-p23-sysprompt-think-cost.md
git commit -m "$(cat <<'EOF'
P23: measure what the app's system prompt costs in thinking

Probe A found thinking is prompt-induced, not flag-induced: the same
model at think=high produced zero think output on a bare prompt and 80%
with a reasoning-inducing -sys. This measures the app's own system
prompt — the Superpowers bootstrap plus DispatchPreferenceRule — against
no system prompt at all.

If the app's -sys materially drives think cost, trimming it is a
zero-engine-work lever that part 2 must weigh against the wire patch.

n=1 per arm; think volume only, no task-success claim.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: One `status`/`ready` decoder, two enums

`AgentWireParser` and `WireEventParser` decode `status` and `ready` with **45
code lines each whose diff is empty** once the enum name is normalized. That
split already shipped a live-path bug: `status.power` and `status.error` were
added to one parser and not the other, and both files carry comments about the
incident. Part 2 adds a field to this wire; sharing the decoder first is what
stops it happening a third time.

Keep **both enums** — the sibling-not-extension argument at
`AgentWireParser.swift:62-66` is sound for the enums. Only the field extraction
is shared.

**Files:**
- Create: `Sources/SwiftStarKit/WireStatusDecoder.swift`
- Modify: `Sources/SwiftStarKit/AgentWireParser.swift:99-124`
- Modify: `Sources/SwiftStarKit/WireEventParser.swift:98-116`
- Test: `Tests/SwiftStarKitTests/WireStatusDecoderTests.swift` (new)

**Interfaces:**
- Consumes: `StatusSnapshot` (in `WireEventParser.swift`), whose memberwise init
  is `init(ctxUsed:ctxSize:prefillTPS:genTPS:ts:generated:state:power:error:)`
  with `power` and `error` defaulted.
- Produces:
  - `WireStatusDecoder.status(from: [String: Any]) -> StatusSnapshot`
  - `WireStatusDecoder.ready(from: [String: Any]) -> WireStatusDecoder.Ready`,
    where `Ready` has `plannedBytes: Int64?`, `stopReason: String?`,
    `generated: Int?`, `ctxUsed: Int?`.

- [ ] **Step 1: Write the failing test**

Create `Tests/SwiftStarKitTests/WireStatusDecoderTests.swift`:

```swift
import Foundation
import Testing
@testable import SwiftStarKit

@Suite struct WireStatusDecoderTests {
    /// One status line carrying every documented field must surface intact
    /// through BOTH parsers. This is the regression the power/error drop
    /// needed and never had: those fields were parsed by WireEventParser and
    /// silently dropped by AgentWireParser — the parser that feeds the running
    /// app — for multiple phases.
    @Test func everyStatusFieldReachesBothParsers() {
        let line = """
        {"t":"status","state":"generating","prefill_tps":231.5,"gen_tps":46.3,\
        "generated":352,"ctx_used":1233,"ctx_size":16384,"power":100,\
        "error":"boom","ts":802076707009}
        """
        var agent = AgentWireParser()
        _ = agent.feed(#"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"]}"#)
        guard case .status(let a)? = agent.feed(line) else {
            Issue.record("AgentWireParser did not yield .status"); return
        }
        var wire = WireEventParser()
        _ = wire.feed(#"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"]}"#)
        guard case .status(let w)? = wire.feed(line) else {
            Issue.record("WireEventParser did not yield .status"); return
        }
        #expect(a == w, "the two parsers disagree on the same status line")
        for s in [a, w] {
            #expect(s.state == "generating")
            #expect(s.prefillTPS == 231.5)
            #expect(s.genTPS == 46.3)
            #expect(s.generated == 352)
            #expect(s.ctxUsed == 1233)
            #expect(s.ctxSize == 16384)
            #expect(s.power == 100)
            #expect(s.error == "boom")
            #expect(s.ts == 802076707009)
        }
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter everyStatusFieldReachesBothParsers`
Expected: **PASS** — both parsers are correct *today*. That is the point: this
test locks in the agreement before the decoder is shared, so step 5 proves the
refactor is a no-op. To satisfy binding rule 2, verify it *can* fail: temporarily
change `power` to `.power * 2` in one parser, re-run, observe FAIL, then restore.

- [ ] **Step 3: Create the shared decoder**

Create `Sources/SwiftStarKit/WireStatusDecoder.swift`:

```swift
import Foundation

/// The one place `status` and `ready` fields are read off the wire.
///
/// `AgentWireParser` and `WireEventParser` stay separate types with separate
/// event enums — their consumers switch exhaustively over different cases, and
/// that split is deliberate. What was NOT deliberate was two byte-identical
/// copies of the field extraction: `status.power` and `status.error` were added
/// to one and not the other, so the parser feeding the running app returned
/// zero-value defaults for both across several phases. A field added here now
/// reaches both consumers or neither.
public enum WireStatusDecoder {
    public static func status(from object: [String: Any]) -> StatusSnapshot {
        StatusSnapshot(
            ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue ?? 0,
            ctxSize: (object["ctx_size"] as? NSNumber)?.intValue ?? 0,
            prefillTPS: (object["prefill_tps"] as? NSNumber)?.doubleValue ?? 0,
            genTPS: (object["gen_tps"] as? NSNumber)?.doubleValue ?? 0,
            ts: (object["ts"] as? NSNumber)?.uint64Value ?? 0,
            generated: (object["generated"] as? NSNumber)?.intValue ?? 0,
            state: (object["state"] as? String) ?? "",
            power: (object["power"] as? NSNumber)?.doubleValue ?? 0,
            error: (object["error"] as? String) ?? ""
        )
    }

    /// The turn-end payload. Every field is optional because `ready` is emitted
    /// twice with different shapes: once at startup carrying the memory plan,
    /// and once per turn end carrying the outcome.
    public struct Ready: Equatable, Sendable {
        public let plannedBytes: Int64?
        public let stopReason: String?
        public let generated: Int?
        public let ctxUsed: Int?
    }

    public static func ready(from object: [String: Any]) -> Ready {
        Ready(
            plannedBytes: (object["planned_bytes"] as? NSNumber)?.int64Value,
            stopReason: object["stop_reason"] as? String,
            generated: (object["generated"] as? NSNumber)?.intValue,
            ctxUsed: (object["ctx_used"] as? NSNumber)?.intValue
        )
    }
}
```

- [ ] **Step 4: Route both parsers through it**

In `Sources/SwiftStarKit/AgentWireParser.swift`, replace the `case "status":`
and `case "ready":` bodies with:

```swift
        case "status":
            return .status(WireStatusDecoder.status(from: object))
        case "ready":
            let r = WireStatusDecoder.ready(from: object)
            return .ready(
                plannedBytes: r.plannedBytes,
                stopReason: r.stopReason,
                generated: r.generated,
                ctxUsed: r.ctxUsed
            )
```

Make the identical replacement in `Sources/SwiftStarKit/WireEventParser.swift`,
using its own event enum's cases. Move the long `power`/`error` incident comment
from `AgentWireParser` into `WireStatusDecoder`'s doc comment (already drafted
above) rather than leaving it orphaned beside a one-line call.

- [ ] **Step 5: Run the whole fast tier**

Run: `swift test`
Expected: **749 tests** (748 + 1), 0 failures. **Every pre-existing parser test
must pass unchanged** — if any needed editing, the refactor was not a no-op and
should be reworked rather than have its tests adjusted.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/WireStatusDecoder.swift Sources/SwiftStarKit/AgentWireParser.swift Sources/SwiftStarKit/WireEventParser.swift Tests/SwiftStarKitTests/WireStatusDecoderTests.swift
git commit -m "$(cat <<'EOF'
P23: share the status/ready decoder between the two wire parsers

AgentWireParser and WireEventParser decoded status and ready with 45
code lines each whose diff is empty once the enum name is normalized.
The split already shipped a bug: status.power and status.error were
added to WireEventParser and not to AgentWireParser — the parser that
feeds the running app — so a live consumer reading .power/.error off
AgentController.lastStatus got zero-value defaults for several phases.
Both files carry comments about the incident.

Extracts WireStatusDecoder and routes both parsers through it. The two
event enums stay separate: their consumers switch exhaustively over
different cases and that split is deliberate. Only the field extraction
is shared, so a field added to the wire now reaches both consumers or
neither.

P23 part 2 adds a field to this wire, which is why this lands first.
Pure refactor: every pre-existing parser test passes unchanged, and the
new test asserts both parsers agree field-for-field on one status line.

749 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Route the app's spawn through `PoolEngine.argv`

`PoolEngine.argv` exists precisely to be the one pooled-argv builder, and
`PoolOrchestrator` uses it — but `AgentController` inlines the identical
expression. A flag added to `PoolEngine.argv` in part 2 would silently never
reach the shipping app.

**Files:**
- Modify: `Sources/SwiftStar/AgentController.swift:438`
- Test: `Tests/SwiftStarIntegrationTests/PoolEngineArgvTests.swift`

**Interfaces:**
- Consumes: `PoolEngine.argv(settings: AgentSettings, workers: Int) -> [String]`.
- Produces: no new API; removes a divergence risk.

- [ ] **Step 1: Write the failing test**

`AgentController` is `@MainActor` app-target code, so assert the property that
actually matters — that the seam and the inline expression agree — in
`Tests/SwiftStarIntegrationTests/PoolEngineArgvTests.swift`:

```swift
    /// The app's spawn argv must come from PoolEngine.argv, not a copy of it.
    /// PoolOrchestrator already uses the seam; AgentController inlined the same
    /// expression, so a flag added to the seam would reach the harness and not
    /// the shipping app.
    @Test func poolEngineArgvIsTheOnlyPooledArgvBuilder() throws {
        // `FakeAgentHarness.repoRoot` is built from `#filePath`, so this does
        // not depend on the test process's working directory.
        let controller = try String(
            contentsOf: FakeAgentHarness.repoRoot
                .appendingPathComponent("Sources/SwiftStar/AgentController.swift"),
            encoding: .utf8)
        #expect(
            !controller.contains(#"["--subagent-pool", String(pool)]"#),
            "AgentController still inlines the pooled argv instead of calling PoolEngine.argv"
        )
        #expect(controller.contains("PoolEngine.argv("))
    }
```

- [ ] **Step 2: Run it and watch it fail**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter poolEngineArgvIsTheOnlyPooledArgvBuilder`
Expected: FAIL on the first expectation.

- [ ] **Step 3: Use the seam**

In `Sources/SwiftStar/AgentController.swift`, replace

```swift
        process.arguments = AgentCommand.argv(settings: settings) + ["--subagent-pool", String(pool)]
```

with

```swift
        process.arguments = PoolEngine.argv(settings: settings, workers: pool)
```

Add `import SwiftStarAppKit` if the file does not already import it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter poolEngineArgvIsTheOnlyPooledArgvBuilder`
Expected: PASS.

- [ ] **Step 5: Run both tiers**

Run: `swift test`
Expected: 749 tests, 0 failures.
Run: `SWIFTSTAR_INTEGRATION=1 swift test`
Expected: green, +1 test.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStar/AgentController.swift Tests/SwiftStarIntegrationTests/PoolEngineArgvTests.swift
git commit -m "$(cat <<'EOF'
P23: build the app's pooled argv through PoolEngine.argv

PoolEngine.argv is documented as "the engine argv for a pooled spawn"
and PoolOrchestrator calls it — but AgentController inlined the same
expression, so PoolEngineArgvTests only covered the seam the shipping
app does not use. A flag added to the seam would have reached the
harness and silently missed the app.

P23 part 2 adds flags to this argv, which is why this lands first.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Extract the pool worker-turn loop

`AgentController.swift` is 1,397 lines with two `// MARK:` dividers and at least
ten responsibilities. Part 2 adds per-turn think state and per-worker context to
it. The pool worker-turn loop is self-contained around `workerTurn` and
`poolState` and is exactly the region part 2 edits.

**This is the riskiest task in the plan** — a behavior-preserving move of
MainActor-bound async code. It ships no feature; its whole value is that the
existing tests still pass.

**Files:**
- Create: `Sources/SwiftStar/AgentPoolTurnLoop.swift`
- Modify: `Sources/SwiftStar/AgentController.swift:753-990`

**Interfaces:**
- Consumes: `PoolScheduler`, `PoolState`, `ActiveWorkerTurn`, `HandoffPacket`,
  `DispatchReceipt`, `WorktreeDispatcher`, `TurnOutcomeBuilder`.
- Produces: no new public API. `AgentController` keeps every method name it has
  today; they move to an extension in the new file.

- [ ] **Step 1: Record the baseline**

```bash
swift test 2>&1 | tail -2
wc -l Sources/SwiftStar/AgentController.swift
```

Write both numbers down. The test count must be identical at the end; the line
count must drop by roughly 238.

- [ ] **Step 2: Move the loop into an extension, unchanged**

Create `Sources/SwiftStar/AgentPoolTurnLoop.swift`:

```swift
import Foundation
import SwiftStarKit
import SwiftStarAppKit

/// The pool worker-turn loop, extracted from `AgentController` (P23).
///
/// Kept as its own extension for the same reason capture retention is: the
/// controller had grown to ~1,400 lines with at least ten responsibilities,
/// and this loop — queue drain, worktree preparation, watchdog, per-worker
/// event routing, validation, receipt folding — is self-contained around
/// `workerTurn` and `poolState`. P23 part 2 gives workers their own context
/// size, which lands here rather than in an already-overlong file.
///
/// Behaviour-preserving move: no logic changed, no signatures changed.
@MainActor
extension AgentController {
    // Move, verbatim, from AgentController.swift:
    //   drainQueuedWorkers, armWorkerWatchdog, failActiveWorker,
    //   handleWorkerEvent, finishWorkerTurn, injectPendingReceipts
    // Do not rename, reorder, or "tidy" them in this commit.
}
```

Cut those six methods from `AgentController.swift` and paste them inside the
extension. Change nothing else — no renames, no signature edits, no
simplification. Any `private` member they touch that now lives across files must
become `internal` (drop the `private` keyword); do not widen anything to
`public`.

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles. Access-level errors here are the expected friction — fix them
by relaxing `private` → internal on the specific members named in the errors,
nothing broader.

- [ ] **Step 4: Run both tiers and compare to the baseline**

Run: `swift test`
Expected: **749 tests, identical to step 1**. A changed count means something was
dropped in the move.
Run: `SWIFTSTAR_INTEGRATION=1 swift test`
Expected: green, same count as before the task.

- [ ] **Step 5: Confirm the file actually shrank**

Run: `wc -l Sources/SwiftStar/AgentController.swift`
Expected: roughly 238 lines fewer than step 1 (~1,159).

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStar/AgentPoolTurnLoop.swift Sources/SwiftStar/AgentController.swift
git commit -m "$(cat <<'EOF'
P23: extract the pool worker-turn loop from AgentController

AgentController was 1,397 lines with two MARK dividers and at least ten
responsibilities: process lifecycle, wire drain, turn state machine,
tool-request routing, the pool worker-turn loop, receipt folding,
capture tee, model-switch wiring, skills staging, and retention.

The worker-turn loop (drainQueuedWorkers, armWorkerWatchdog,
failActiveWorker, handleWorkerEvent, finishWorkerTurn,
injectPendingReceipts) is self-contained around workerTurn/poolState and
is exactly the region P23 part 2 edits to give workers their own context
size. Moving it now means that change lands in a focused file instead of
making an overlong one worse — the same pattern the capture-retention
extension already established.

Behaviour-preserving move: no logic, signatures, or names changed; only
`private` relaxed to internal where the move crossed a file boundary.
Test counts identical in both tiers.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Done when

- Fast tier green at **749 tests**; integration tier green.
- Laguna XS admits ctx 51,200 with a KV model that extrapolates correctly.
- The app spawns with `--think-budget 2048`.
- One `status`/`ready` decoder; one pooled-argv builder.
- The submodule pin is reachable from a remote and `.gitmodules` tells the truth.
- `AgentController.swift` is ~1,159 lines.
- **No engine change, no submodule bump beyond the ledger docs, no recapture.**

## What part 2 covers

Cycles 5–8 of the spec: `TurnThinkPolicy`, `PoolPrompt`'s new fields, `/quick`,
the `optionalCaps` negotiation, engine divergence **#14** (per-turn think + the
`hello` cap + per-worker `ctx` + `sysprompt-<ctx>.kv`), and the golden
recapture. Write that plan after this one lands — the engine patch's shape
depends on Task 7's measurement and on the submodule being reconciled.
