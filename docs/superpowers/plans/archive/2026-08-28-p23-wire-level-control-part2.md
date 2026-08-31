# P23 Wire-Level Control — Implementation Plan (part 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship P23's engine-patch half — per-turn think on the agent wire (`/quick`, the `think` field, the `hello` cap, `TurnThinkPolicy`), per-worker context (the `ctx` field, `sysprompt-<ctx>.kv`, the clamp), retire the `"engine-defaults"` sampler lie, and close the phase with fork-ledger row **#14**, one golden recapture, and the submodule bump.

**Architecture:** Spec cycles 5–8. Cycles 5 lands entirely in Swift **before** the engine bump: pure decision policy, wire encoding, `/quick` routing, cap negotiation, and the sampler-truth refactor — all cap-gated so an old engine degrades exactly as the spec's D3 requires (never send an unadvertised field). Cycles 6–7 are one engine divergence (**#14**, ~150–250 lines think + ~40–80 ctx) with gated C unit tests, built against the local submodule working tree. Cycle 8 is the phase's one expensive step: decide D11, capture the new flag-exercising fixture, re-capture `golden` against the rebuilt binary, add ledger row #14, push the submodule, bump the gitlink, and **only then** add `--per-turn-think` to the app's argv (the app must never pass a flag the pinned engine does not know).

**Tech Stack:** Swift 6 (strict concurrency), Swift Testing (`@Test`/`@Suite`), SwiftPM, macOS; C (`ds4_agent.c`, `make -C external/ds4 test` for the gated engine self-tests); `swiftstar-drive` for the captures. Fast tier ~0.05 s; engine rebuild ~1.5 s; recapture minutes–~25 min.

**Spec:** [`docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md`](../specs/2026-08-28-p23-wire-level-control-design.md) — the authority. The plan argues from it; executors read both.

**Research:** [`docs/superpowers/research/2026-08-28-p23-wire-control-research.md`](../research/2026-08-28-p23-wire-control-research.md), [`docs/superpowers/research/2026-08-28-p23-sysprompt-think-cost.md`](../research/2026-08-28-p23-sysprompt-think-cost.md) (Task 7's measurement: the app's `-sys` does **not** induce thinking; think cost tracks the task — the strongest argument for per-turn control).

**Part 1:** [`docs/superpowers/plans/2026-08-28-p23-wire-level-control.md`](2026-08-28-p23-wire-level-control.md) — landed on `main` (merge `20048f1`). Its "What part 2 covers" section is the mandate for this plan.

## Global Constraints

- **Fast tier must stay green and must stay fast.** `swift test` — no model, no network, no subprocess. The `FastTierGuard` plugin fails the build if a `SwiftStarKitTests` source mentions `Process(`, `URLSession`, `NWConnection`, `posix_spawn`, `Darwin.`, or `socket(`.
- **Integration tier** is `SWIFTSTAR_INTEGRATION=1 swift test`; every integration suite carries `@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))`.
- **BRIEF.md binding rule 2:** every new test must be shown to fail when the behavior it pins is broken — write the test, observe the failure, then fix.
- **BRIEF.md binding rule 4:** a refusal test has a sibling success test.
- **BRIEF.md binding rule 7:** the wire announces itself. A consumer never sends a field the engine has not claimed to understand (D3). `"think_override"` is a **new cap** — see Task 4/D3 note; the spec's literal `"think"` collides with the existing think-*event* cap and cannot negotiate.
- **REBASING.md standing rule:** recapture on every submodule bump that changes engine code. P23 touches an emitter (`agent_emit_hello`) → **a golden recapture is owed** (D9), copied to `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}`.
- **BRIEF.md:221-222:** the submodule pins a SHA on the branch `.gitmodules` declares — already reconciled to `p20-dispatch-schema` in part 1; keep it that way.
- **Submodule discipline:** engine commits land in `external/ds4` on `p20-dispatch-schema` and are pushed **before** the parent gitlink bump. Never edit engine code on the parent side.
- **The app must never pass a flag the pinned engine does not know.** `--per-turn-think` enters `AgentCommand.argv` in Task 10, in the same change as the gitlink bump. Before that, the app sends overrides only when the cap is advertised (which the old engine never does).
- **No golden-fixture content edits.** The recapture replaces fixtures wholesale per `fixtures/agent/provenance.md`; never hand-edit a capture to match.
- **Commit message style:** phase-prefixed subject (`P23: …`), body explaining why, ending with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- **Test count is an assertion, not a vibe.** Baseline is **751** (verified 2026-08-28). Each task states its delta; run `swift test 2>&1 | tail -1` at every gate.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `Sources/SwiftStarKit/TurnThinkPolicy.swift` | **new** — the per-turn think decision authority (D4, D6) | 1 |
| `Sources/SwiftStarKit/Variant.swift` | `ModelFamily.glm` case (the policy's GLM refusal family) | 1 |
| `Sources/SwiftStarKit/PoolPrompt.swift` | `think` + `contextSize` fields on the wire envelope (D2) | 2 |
| `Sources/SwiftStarKit/CommandRouter.swift` | `/quick` parse | 3 |
| `Sources/SwiftStar/AgentView.swift` | `/quick` routing (the `/chat`/`/orchestrate` pattern) | 3 |
| `Sources/SwiftStar/AgentController.swift` | `quick(task:)`; cap-gated `inject(_:row:think:)`; advertised-caps capture; sampler truth | 3, 4, 5, 9 |
| `Sources/SwiftStarKit/AgentWireParser.swift` | `optionalCaps` surface (D3) | 4 |
| `Sources/SwiftStarKit/PoolWireParser.swift` | forward `optionalCaps` | 4 |
| `Sources/SwiftStarKit/TurnOutcome.swift` | sampler semantics (the effort record) | 5 |
| `Sources/SwiftStar/AgentPoolTurnLoop.swift` | worker think + ctx threading; sampler truth | 5, 9 |
| `Sources/SwiftStarAppKit/PoolOrchestrator.swift` | sampler truth | 5 |
| `external/ds4/ds4_agent.c` | divergence #14 — think half (parse, queue, `worker_run_turn`, hello cap, flag, refusal, N=1) | 6 |
| `external/ds4/ds4_agent.c` | divergence #14 — ctx half (`ctx` key, session re-create, `sysprompt-<ctx>.kv`, `effective_think_mode`) | 7 |
| `Sources/SwiftStarKit/WorkerContextPolicy.swift` | **new** — pure worker-ctx clamp + defaults (D8) | 8 |
| `Sources/SwiftStarKit/AgentCommand.swift` | `AgentSettings.workerContextSize` | 8 |
| `Sources/SwiftStarKit/AgentDefaultSettings.swift` | resolve worker ctx from `UserDefaults` | 8 |
| `Sources/SwiftStar/SettingsView.swift` | worker-ctx control (Agent section) | 8 |
| `Sources/SwiftStarKit/FakeAgentSource.swift` | generated-fake prompt-guard seam (cap tests) | 9 |
| `fixtures/agent/think-override.{ndjson,trace,stderr,provenance.md}` | **new** — flag-exercising capture (the recapture evidence) | 10 |
| `fixtures/agent/golden.{ndjson,trace,stderr,provenance.md}` | re-captured against the rebuilt binary (standing rule) | 10 |
| `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` | bundled recapture copy (D9, provenance.md:162-166) | 10 |
| `external/ds4/docs/fork-ledger.md` | row #14 (think + ctx divergence) | 10 |
| `Sources/SwiftStarKit/AgentCommand.swift` | `--per-turn-think` in argv (lands with the bump) | 10 |
| `Sources/swiftstar-drive/main.swift` | `CAPTURE_PER_TURN_THINK` knob | 10 |
| `ROADMAP.md` | P23 row close, D11 record, spec stamp | 10 |
| `docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md` | stamp `implemented` | 10 |

---

### Task 1: `TurnThinkPolicy` — the per-turn think decision authority

Spec component 1, spec test 1 (the matrix), D4 (family refusals), D6 (budget vs mode). Pure; no I/O; fast-tier tested. This is the single decision authority everything else consults: the `/quick` path, the dispatch path, and the sampler record.

**Files:**
- Create: `Sources/SwiftStarKit/TurnThinkPolicy.swift`
- Modify: `Sources/SwiftStarKit/Variant.swift` (add `case glm` to `ModelFamily`)

**Interfaces:**
- Consumes: `ModelFamily` (exists; gains `glm`).
- Produces:
  - `public enum ThinkEffort: String, Sendable { case none, high, max }` — the wire values (`"none"` | `"high"` | `"max"`).
  - `public enum TurnThinkDecision: Equatable, Sendable { case useDefault, override(ThinkEffort), refused(reason: String) }`
  - `public struct TurnThinkPolicy` with
    - `public static func decide(requested: ThinkEffort?, family: ModelFamily, capAdvertised: Bool) -> TurnThinkDecision`
    - `public static func effort(for mode: ThinkMode) -> ThinkEffort` — off→`.none`, on→`.high`, bounded→`.high` (the budget is the standing guardrail, D6; bounded ≠ a tighter per-turn mode)
    - `public static func samplerRecord(_ decision: TurnThinkDecision) -> String` — `"think=default"` | `"think=none"` | `"think=high"` | `"think=max"` | `"think=refused"` (the effort the `TurnOutcome.sampler` records; Task 5)
- Rules (D3, D4): `requested == nil` → `.useDefault`; `!capAdvertised` → `.useDefault` (never send an unadvertised field); `.glm` → `.refused` for any override; `.deepSeekV4Flash` + `.max` → `.refused` (MAX↔anything busts the prefix); everything else → `.override(requested)`.

**D3 note (resolved here, not reopened):** the spec's D3 wording says advertise `"think"`, but `"think"` is already a `caps` entry (the think *event* kind) on every engine since P5 — advertising it again is a no-op and cannot negotiate. The cap is therefore the new string **`"think_override"`** everywhere in this plan (engine hello, Swift `optionalCaps`, fixtures). The negotiation mechanism is exactly D3's; only the literal is disambiguated.

- [ ] **Step 1: Add `glm` to `ModelFamily`**

In `Sources/SwiftStarKit/Variant.swift`:

```swift
public enum ModelFamily: String, Equatable, Sendable {
    case mellum
    case lagunaXS
    case lagunaS
    case deepSeekV4Flash
    /// P23: the policy's GLM refusal family. No GLM `Variant` ships in the
    /// registry, so no runtime path constructs this — it exists so the
    /// `TurnThinkPolicy` refusal matrix is complete and tested (D4: on GLM a
    /// per-turn think flip changes a system message at the front of the
    /// transcript and busts the `sysprompt.kv` memcmp).
    case glm
}
```

- [ ] **Step 2: Write the failing tests**

Append to `Tests/SwiftStarKitTests/` a new `TurnThinkPolicyTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct TurnThinkPolicyTests {
    // MARK: - the decide matrix (spec test 1)

    @Test func nilRequestedUsesEngineDefault() {
        for family in [ModelFamily.lagunaS, ModelFamily.glm, ModelFamily.deepSeekV4Flash] {
            #expect(TurnThinkPolicy.decide(requested: nil, family: family, capAdvertised: true) == .useDefault)
            #expect(TurnThinkPolicy.decide(requested: nil, family: family, capAdvertised: false) == .useDefault)
        }
    }

    @Test func noCapNeverSendsAnOverride() {
        // D3: an old engine (no "think_override" cap) must not receive the
        // field — the wire never degrades silently.
        #expect(TurnThinkPolicy.decide(requested: .none, family: .lagunaS, capAdvertised: false) == .useDefault)
        #expect(TurnThinkPolicy.decide(requested: .max, family: .lagunaS, capAdvertised: false) == .useDefault)
    }

    @Test func lagunaFamilyOverridesAreAllowed() {
        // Laguna contributes zero think tokens to the system prompt, so a
        // per-turn flip costs exactly one token in the assistant prefix (D4).
        for family in [ModelFamily.lagunaS, ModelFamily.lagunaXS, ModelFamily.mellum] {
            #expect(TurnThinkPolicy.decide(requested: .none, family: family, capAdvertised: true) == .override(.none))
            #expect(TurnThinkPolicy.decide(requested: .high, family: family, capAdvertised: true) == .override(.high))
            #expect(TurnThinkPolicy.decide(requested: .max, family: family, capAdvertised: true) == .override(.max))
        }
    }

    @Test func glmOverridesAreRefused() {
        // D4: on GLM the reasoning-effort text is a system message at the
        // front; a flip forces a full system re-prefill and a cache overwrite.
        for effort in [ThinkEffort.none, .high, .max] {
            #expect(TurnThinkPolicy.decide(requested: effort, family: .glm, capAdvertised: true) ==
                    .refused("glm cannot flip think mode per turn without a prefix bust"))
        }
    }

    @Test func deepSeekMaxIsRefusedButHighAndNoneAreNot() {
        // D4: DeepSeek V4 busts the prefix for MAX↔anything only; HIGH↔NONE is
        // free. Refusal tests get sibling success tests (binding rule 4).
        #expect(TurnThinkPolicy.decide(requested: .max, family: .deepSeekV4Flash, capAdvertised: true) ==
                .refused("deepseek-v4-flash cannot flip think mode to max per turn without a prefix bust"))
        #expect(TurnThinkPolicy.decide(requested: .high, family: .deepSeekV4Flash, capAdvertised: true) == .override(.high))
        #expect(TurnThinkPolicy.decide(requested: .none, family: .deepSeekV4Flash, capAdvertised: true) == .override(.none))
    }

    // MARK: - the packet mapping (the capture-integrity fix)

    @Test func thinkModeMapsToEffort() {
        #expect(TurnThinkPolicy.effort(for: .off) == .none)
        #expect(TurnThinkPolicy.effort(for: .on) == .high)
        #expect(TurnThinkPolicy.effort(for: .bounded) == .high)
    }

    // MARK: - the sampler record (Task 5 consumes this)

    @Test func samplerRecordCarriesTheEffortActuallyUsed() {
        #expect(TurnThinkPolicy.samplerRecord(.useDefault) == "think=default")
        #expect(TurnThinkPolicy.samplerRecord(.override(.none)) == "think=none")
        #expect(TurnThinkPolicy.samplerRecord(.override(.high)) == "think=high")
        #expect(TurnThinkPolicy.samplerRecord(.override(.max)) == "think=max")
        #expect(TurnThinkPolicy.samplerRecord(.refused("x")) == "think=refused")
    }
}
```

- [ ] **Step 3: Run them and watch them fail**

Run: `swift test --filter TurnThinkPolicyTests`
Expected: **FAIL** — `TurnThinkPolicy` does not exist.

- [ ] **Step 4: Write the minimal implementation**

Create `Sources/SwiftStarKit/TurnThinkPolicy.swift`:

```swift
import Foundation

/// The per-turn think effort on the agent wire (P23, D1/D4/D6). `none` is
/// `/quick`'s no-think turn; `high` and `max` map 1:1 to the engine's
/// `DS4_THINK_HIGH`/`DS4_THINK_MAX`. Absent from the wire = the engine
/// default, which is `DS4_THINK_HIGH` on the shipped line.
public enum ThinkEffort: String, Sendable {
    case none
    case high
    case max
}

/// What a think request resolves to, once the family and the advertised caps
/// are known (D3/D4). `.useDefault` sends nothing — the engine default runs
/// the turn. `.refused` is the loud app-side refusal for a prefix-busting
/// family; the engine refuses the same cases loudly if one slips through.
public enum TurnThinkDecision: Equatable, Sendable {
    case useDefault
    case override(ThinkEffort)
    case refused(reason: String)
}

/// The single decision authority for per-turn think (P23, spec component 1).
/// Pure: no I/O, no engine, no parser. `decide` is the only place that maps
/// (requested, family, cap) → decision; the `/quick` path, the dispatch path,
/// and the sampler record all consult it.
public struct TurnThinkPolicy {
    /// D3: the engine advertises the per-turn override with the new
    /// `"think_override"` cap (the base cap `"think"` is the think EVENT kind,
    /// present since P5, and cannot negotiate a feature). The app sends an
    /// override only when the cap is present; otherwise `.useDefault` — the
    /// wire never degrades silently.
    public static let overrideCap = "think_override"

    public static func decide(requested: ThinkEffort?, family: ModelFamily, capAdvertised: Bool) -> TurnThinkDecision {
        guard let requested else { return .useDefault }
        guard capAdvertised else { return .useDefault }
        switch family {
        case .glm:
            // D4: the reasoning-effort text is a system message at the front
            // of the transcript; a flip fails the sysprompt.kv memcmp and
            // forces a full system re-prefill AND a cache overwrite every flip.
            return .refused("glm cannot flip think mode per turn without a prefix bust")
        case .deepSeekV4Flash where requested == .max:
            // D4: MAX↔anything busts the prefix; HIGH↔NONE does not.
            return .refused("deepseek-v4-flash cannot flip think mode to max per turn without a prefix bust")
        default:
            return .override(requested)
        }
    }

    /// The wire effort for a handoff packet's declared `ThinkMode` (the
    /// capture-integrity fix: `SamplingPolicy.think` was written, validated,
    /// asserted — and read by nothing at dispatch time). `.bounded` maps to
    /// `.high`: the per-round ceiling is the process-level `--think-budget`
    /// standing guardrail (D6), not a distinct wire mode.
    public static func effort(for mode: ThinkMode) -> ThinkEffort {
        switch mode {
        case .off: return .none
        case .on, .bounded: return .high
        }
    }

    /// The effort actually used, rendered for `TurnOutcome.sampler` (P23
    /// retires the `"engine-defaults"` literal — it is false the moment the
    /// app sends any override; the outcome must record the truth).
    public static func samplerRecord(_ decision: TurnThinkDecision) -> String {
        switch decision {
        case .useDefault: return "think=default"
        case .override(let effort): return "think=\(effort.rawValue)"
        case .refused: return "think=refused"
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter TurnThinkPolicyTests`
Expected: PASS (7 tests).

- [ ] **Step 6: Run the whole fast tier**

Run: `swift test`
Expected: **758 tests** (751 + 7), 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarKit/TurnThinkPolicy.swift Sources/SwiftStarKit/Variant.swift Tests/SwiftStarKitTests/TurnThinkPolicyTests.swift
git commit -m "$(cat <<'EOF'
P23: add TurnThinkPolicy, the per-turn think decision authority

The engine has had three-valued think mode since the fork and the app
has had no way to change it per turn. This is the pure decision layer
of the wire patch: given (requested effort, model family, advertised
caps) it says useDefault / override / refused.

D3: the app never sends an unadvertised field, so a missing cap means
useDefault (an old engine silently runs the default). D4: GLM refuses
any flip (a system message at the transcript front busts the sysprompt
memcmp) and DeepSeek V4 refuses MAX only (MAX<->anything busts the
prefix; HIGH<->NONE is free) - Laguna flips cost exactly one token.

Also maps HandoffPacket's declared ThinkMode to a wire effort (the
capture-integrity fix: SamplingPolicy.think was written and asserted
and read by nothing at dispatch time), and defines the sampler record
that retires the "engine-defaults" literal in Task 5.

Note: the spec's D3 literal "think" collides with the existing think
EVENT cap (present since P5) and cannot negotiate; the cap is the new
string "think_override". Mechanism unchanged.

758 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `PoolPrompt` gains `think` and `contextSize`

Spec component 2, spec test 2 (byte-identical when nil). The encoder is the single authority for the C patch and the fake — an absent field must mean "engine default", and the output must be byte-identical to today when both are nil (that is what keeps every existing fixture and fake valid).

**Files:**
- Modify: `Sources/SwiftStarKit/PoolPrompt.swift`

**Interfaces:**
- Consumes: `ThinkEffort` (Task 1).
- Produces: `PoolPrompt(worker:text:think:contextSize:)` — `think: ThinkEffort?`, `contextSize: Int?`, each emitted into the sorted-keys JSON object only when non-nil. Key names on the wire: `"think"` (the string values from `ThinkEffort.rawValue`) and `"ctx"`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiftStarKitTests/PoolPromptTests.swift`:

```swift
    // MARK: - P23 per-turn fields

    @Test func nilFieldsKeepTodayBytes() {
        // The byte-identical contract: every existing fixture and fake was
        // encoded with these two fields absent; a nil field must not add a
        // byte.
        #expect(PoolPrompt(worker: .orchestrator, text: "go").encode()
                == #"{"s":"go","t":"prompt","worker":0}"#)
    }

    @Test func thinkFieldEncodesOnlyWhenSet() {
        #expect(PoolPrompt(worker: .orchestrator, text: "go", think: .none).encode()
                == #"{"s":"go","t":"prompt","think":"none","worker":0}"#)
        #expect(PoolPrompt(worker: .orchestrator, text: "go", think: .max).encode()
                == #"{"s":"go","t":"prompt","think":"max","worker":0}"#)
    }

    @Test func contextFieldEncodesOnlyWhenSet() {
        #expect(PoolPrompt(worker: WorkerId(1), text: "do it", contextSize: 8192).encode()
                == #"{"ctx":8192,"s":"do it","t":"prompt","worker":1}"#)
    }

    @Test func bothFieldsSortedWithEverythingElse() {
        #expect(PoolPrompt(worker: WorkerId(1), text: "do it", think: .none, contextSize: 8192).encode()
                == #"{"ctx":8192,"s":"do it","t":"prompt","think":"none","worker":1}"#)
    }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter PoolPromptTests`
Expected: FAIL — `PoolPrompt` has no `think:`/`contextSize:` init parameters.

- [ ] **Step 3: Extend `PoolPrompt`**

Replace the body of `Sources/SwiftStarKit/PoolPrompt.swift`:

```swift
import Foundation

/// The inbound prompt line (D1): how the app addresses a worker's turn on the
/// pooled wire. A bare line (no `worker`) is the orchestrator (worker 0). The
/// encoder is the single authority; the C patch and the fake both consume it.
public struct PoolPrompt: Equatable, Sendable {
    public let worker: WorkerId
    public let text: String
    /// P23 (D2): the per-turn think override, absent = engine default. Sent
    /// only when the engine advertised `think_override` (D3 — never send an
    /// unadvertised field); the absent byte shape is what keeps old engines
    /// and every existing fixture valid.
    public let think: ThinkEffort?
    /// P23 (D8): the worker's context size, absent = the engine default (the
    /// parent's). The app clamps it through the same `MemoryBudget` arithmetic
    /// the parent uses before it ever reaches the wire.
    public let contextSize: Int?
    public init(worker: WorkerId, text: String,
                think: ThinkEffort? = nil, contextSize: Int? = nil) {
        self.worker = worker
        self.text = text
        self.think = think
        self.contextSize = contextSize
    }

    /// `{"t":"prompt","worker":N,"s":"...","think":"none","ctx":8192}` — keys
    /// sorted for determinism; both P23 fields emitted only when non-nil, so
    /// the absent-field encoding is byte-identical to pre-P23.
    public func encode() -> String {
        var obj: [String: Any] = ["t": "prompt", "worker": worker.rawValue, "s": text]
        if let think { obj["think"] = think.rawValue }
        if let contextSize { obj["ctx"] = contextSize }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter PoolPromptTests`
Expected: PASS (4 new tests, all 3 pre-existing unchanged — the byte-identical contract holds).

- [ ] **Step 5: Run the whole fast tier**

Run: `swift test`
Expected: **762 tests** (758 + 4), 0 failures. No other suite may need edits — the new init parameters are defaulted, so every existing call site compiles untouched.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStarKit/PoolPrompt.swift Tests/SwiftStarKitTests/PoolPromptTests.swift
git commit -m "$(cat <<'EOF'
P23: PoolPrompt carries the per-turn think and context fields

The inbound prompt envelope gains think (ThinkEffort) and ctx (Int),
emitted only when non-nil and always in sorted-key order. The absent
byte shape is unchanged - the contract that keeps every existing
fixture, fake, and old-engine interaction valid - and the encoder stays
the single authority for the C patch (Task 6/7) and the fake.

762 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `/quick` — the per-turn no-think surface

Spec component 5, spec test 7. `/quick <prompt>` is the explicit per-turn choice (D6): `think=none` for one turn. Pure parse in `CommandRouter`; routing in `AgentView.send()` on the `/chat`/`/orchestrate` pattern; the controller refuses without the cap (D3 — "does not offer `/quick`"). **No composer control** (spec: that would be the first mode control in a 460-line view).

**Files:**
- Modify: `Sources/SwiftStarKit/CommandRouter.swift`
- Modify: `Sources/SwiftStar/AgentView.swift` (the `send()` switch)
- Modify: `Sources/SwiftStar/AgentController.swift` (`quick(task:)` — cap-gated; lands the `inject(_:row:think:)` signature)

**Interfaces:**
- Consumes: `TurnThinkPolicy.overrideCap` (Task 1); `PoolPrompt(think:)` (Task 2).
- Produces:
  - `Command.quick(task: String)`
  - `AgentController.quick(task: String)` — appends a system row and returns without sending when the engine did not advertise the cap; else `inject(task, row: .user, think: .none)`.
  - `inject(_ wireText: String, row: AgentTranscriptRow, think: ThinkEffort? = nil) -> Bool` — threads the decision into the `PoolPrompt` (component 4).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiftStarKitTests/CommandRouterTests.swift`:

```swift
    // MARK: - /quick (P23)

    @Test func quickParsesWithBody() {
        #expect(CommandRouter.parse("/quick sum 2 and 2") == .quick(task: "sum 2 and 2"))
        #expect(CommandRouter.parse("/quick") == .quick(task: ""))
    }

    @Test func quickRequiresAWholeToken() {
        #expect(CommandRouter.parse("/quickly go") == nil)
        #expect(CommandRouter.parse("/quickx") == nil)
    }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter CommandRouterTests`
Expected: FAIL — `.quick` does not exist.

- [ ] **Step 3: Add the command case and parse**

In `Sources/SwiftStarKit/CommandRouter.swift`:

```swift
public enum Command: Equatable, Sendable {
    case chat(task: String)
    case orchestrate(task: String, writableFiles: [String])
    /// P23: one no-think turn. The explicit per-turn choice (D6) — distinct
    /// from `/chat` (a read-only worker) and from the standing think budget
    /// (which only fires on a runaway).
    case quick(task: String)
}
```

and in `parse`:

```swift
        if let chat = match(trimmed, command: "/chat") { return .chat(task: chat) }
        if let quick = match(trimmed, command: "/quick") { return .quick(task: quick) }
        if let orch = match(trimmed, command: "/orchestrate") {
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CommandRouterTests`
Expected: PASS (2 new tests, pre-existing unchanged).

- [ ] **Step 5: Route it in `AgentView.send()`**

In `Sources/SwiftStar/AgentView.swift`, extend the `CommandRouter.parse` switch:

```swift
        case .quick(let task):
            input = ""
            controller.quick(task: task)
```

- [ ] **Step 6: Add the controller surface**

In `Sources/SwiftStar/AgentController.swift`:

```swift
    /// `/quick` (P23): one no-think turn. D3 — the app does not offer `/quick`
    /// when the engine did not advertise `think_override`: sending the field
    /// to an engine that does not claim it would be a silent degrade, and a
    /// no-think turn without engine support is not quick at all.
    func quick(task: String) {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcript.appendSystem("→ quick: no task given")
            return
        }
        guard canSend else {
            transcript.appendSystem("→ quick: agent not idle")
            return
        }
        guard advertisedCaps.contains(TurnThinkPolicy.overrideCap) else {
            transcript.appendSystem("→ /quick unavailable: this engine build does not advertise \(TurnThinkPolicy.overrideCap)")
            return
        }
        _ = inject(trimmed, row: .user(trimmed), think: .none)
    }
```

Add the stored property beside `parser`:

```swift
    /// The capabilities the engine's `hello` advertised (P23, D3): the app
    /// records what was advertised so it can gate outbound feature fields.
    /// `"think_override"` gates per-turn think sends; `/quick` is refused
    /// without it.
    private(set) var advertisedCaps: Set<String> = []
```

- [ ] **Step 7: Thread `think` through `inject`**

In `Sources/SwiftStar/AgentController.swift`, change `inject`'s signature and body:

```swift
    private func inject(_ wireText: String, row: AgentTranscriptRow,
                        think: ThinkEffort? = nil) -> Bool {
        guard canSend, !wireText.isEmpty, let process,
              let pipe = process.standardInput as? Pipe else { return false }
        transcript.append(row)
        lastPrefillTPS = 0
        lastGenTPS = 0
        decodeAccumulator = DecodeAccumulator()
        state = .generating
        sentInterrupt = false
        // P23: the decision authority resolves the request against the family
        // and the advertised caps; the outcome record carries the effort
        // actually used (retiring the "engine-defaults" literal — it is false
        // the moment an override goes out).
        let decision = TurnThinkPolicy.decide(
            requested: think,
            family: AgentController.familyOf(settings.modelPath),
            capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap))
        let effort: ThinkEffort?
        switch decision {
        case .useDefault:
            effort = nil
        case .override(let e):
            effort = e
        case .refused(let reason):
            log("think override refused: \(reason)")
            effort = nil
        }
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            think: effort,
            task: wireText
        )
        let line = PoolPrompt(worker: .orchestrator, text: wireText,
                              think: effort).encode() + "\n"
        pipe.fileHandleForWriting.write(Data(line.utf8))
        return true
    }
```

Add the family resolver as a `static` helper next to `defaultSettings()`:

```swift
    /// The running model's `ModelFamily` for `TurnThinkPolicy` (P23): from the
    /// staged variant when one exists, else `.lagunaS`'s family — the
    /// nothing-configured default. A custom/unverified model path resolves to
    /// the default family's policy (no app-side refusal); the engine's own
    /// loud refusal (D4) is the backstop for a prefix-busting family the app
    /// cannot identify. `internal`, not `private`: `AgentPoolTurnLoop` (a
    /// separate file extension of this type) consults it at dispatch time, and
    /// Swift's `private` is file-scoped.
    static func familyOf(_ modelPath: URL) -> ModelFamily {
        VariantResolver.resolveVariant(selectedVariantID: AgentController.effectiveSelectedVariantID())?.family
            ?? VariantRegistry.lagunaS.family
    }
```

Note: `VariantResolver.resolveVariant` is already imported (`SwiftStarKit`). If `familyOf` references a resolver signature mismatch, read `VariantResolver` (same module) and align — the intent is "the staged variant's family, else Laguna S's".

- [ ] **Step 8: Run the whole fast tier**

Run: `swift test`
Expected: **764 tests** (762 + 2), 0 failures. `AgentView` and `AgentController` are app-target (no test target) — the compile is the gate; `swift build` must be clean.

- [ ] **Step 9: Commit**

```bash
git add Sources/SwiftStarKit/CommandRouter.swift Sources/SwiftStar/AgentView.swift Sources/SwiftStar/AgentController.swift Tests/SwiftStarKitTests/CommandRouterTests.swift
git commit -m "$(cat <<'EOF'
P23: add /quick, the explicit no-think turn

The think budget bounds runaways; /quick is the explicit per-turn choice
(D6). One turn at think=none, routed on the /chat//orchestrate pattern -
pure CommandRouter parse, zero new UI. The controller refuses without
the advertised think_override cap (D3: an old engine gets no field and
the composer never offers the command).

inject(_:row:think:) now resolves the request through TurnThinkPolicy
and carries the effort on the PoolPrompt; the outcome record starts
carrying the sampler truth.

764 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Advertised-cap negotiation (`optionalCaps`)

Spec component 3, spec test 8 (integration). The parser records what `hello` advertised on a new `optionalCaps` surface (D3 — the cap does **not** join `requiredCaps`; the app must keep starting against an older engine, it just stops sending the field). The shared `WireStatusDecoder` from part 1 stays untouched — this is a parser-surface addition, not a field decode.

**Files:**
- Modify: `Sources/SwiftStarKit/AgentWireParser.swift`
- Modify: `Sources/SwiftStarKit/PoolWireParser.swift`
- Test: `Tests/SwiftStarKitTests/AgentWireParserTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `AgentWireParser.optionalCaps: Set<String>` (public getter, populated at the handshake with every advertised cap)
  - `PoolWireParser.optionalCaps: Set<String>` (forwards to the inner parser)
  - `AgentController.advertisedCaps` populated from it at `hello` (Task 3 added the property; this wires it).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/SwiftStarKitTests/AgentWireParserTests.swift`:

```swift
    // MARK: - advertised caps (P23, D3)

    @Test func optionalCapsRecordsWhatHelloAdvertised() {
        var p = AgentWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","think_override"],"ts":1}"#)
        #expect(p.optionalCaps.contains("think_override"))
        #expect(p.optionalCaps.contains("text"))
        #expect(p.optionalCaps.count == 8)
    }

    @Test func optionalCapsStaysEmptyWithoutACapableHello() {
        // The base-7 caps (no think_override) is the pre-bump engine's hello;
        // the app must keep running against it and simply not send overrides.
        var p = AgentWireParser()
        _ = p.feed(#"{"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts"],"ts":1}"#)
        #expect(p.optionalCaps == ["status", "ready", "text", "think", "tool", "queued", "ts"])
        #expect(!p.optionalCaps.contains("think_override"))
    }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter optionalCaps`
Expected: FAIL — `optionalCaps` does not exist.

- [ ] **Step 3: Add the surface to `AgentWireParser`**

In `Sources/SwiftStarKit/AgentWireParser.swift`:

```swift
    private var sawHandshake = false
    private static let requiredCaps: Set<String> = ["text", "tool", "status", "ts"]
    /// P23 (D3): every capability the handshake advertised, recorded so the
    /// app can gate outbound feature fields. Deliberately NOT part of
    /// `requiredCaps`: the required set governs what the app must be able to
    /// PARSE to read the wire safely; `optionalCaps` records what an older
    /// engine may not offer, and an absent feature field must not refuse
    /// startup — only the send.
    private(set) var optionalCaps: Set<String> = []
```

and inside the handshake branch:

```swift
            if t == "hello",
               let v = (object["v"] as? NSNumber)?.intValue, v == 1,
               let caps = object["caps"] as? [String],
               Self.requiredCaps.isSubset(of: Set(caps)) {
                optionalCaps = Set(caps)
                return .hello(version: v, capabilities: caps)
            }
```

- [ ] **Step 4: Forward it through `PoolWireParser`**

In `Sources/SwiftStarKit/PoolWireParser.swift`:

```swift
    private var inner = AgentWireParser()
    /// P23 (D3): the inner parser's advertised caps, forwarded so the
    /// controller can gate outbound feature fields after the handshake.
    var optionalCaps: Set<String> { inner.optionalCaps }
```

- [ ] **Step 5: Wire the controller**

In `Sources/SwiftStar/AgentController.swift`, inside `consumeWire`'s `case .hello:` (before `if state == .starting { state = .ready }`):

```swift
        case .hello:
            // P23 (D3): record what the engine advertised so per-turn feature
            // fields are gated on the send, never assumed.
            advertisedCaps = parser.optionalCaps
            if state == .starting { state = .ready }
```

- [ ] **Step 6: Run the parser tests and the whole fast tier**

Run: `swift test --filter optionalCaps` — PASS (2 tests).
Run: `swift test`
Expected: **766 tests** (764 + 2), 0 failures.

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStarKit/AgentWireParser.swift Sources/SwiftStarKit/PoolWireParser.swift Sources/SwiftStar/AgentController.swift Tests/SwiftStarKitTests/AgentWireParserTests.swift
git commit -m "$(cat <<'EOF'
P23: record advertised caps so outbound feature fields are gated

AgentWireParser gains optionalCaps, populated at the handshake with
every cap the engine advertised. It deliberately stays out of
requiredCaps (D3): the required set governs what the app must parse to
read the wire safely, and an older engine must not refuse startup for
an outbound optional feature - it simply never receives the field. The
controller records the caps at hello so /quick and the think override
are gated on the send, not assumed.

PoolWireParser forwards the surface; the shared WireStatusDecoder from
part 1 is untouched (this is a parser-surface addition, not a field
decode).

766 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: The `TurnOutcome` sampler tells the truth

Spec component 4's second half: retire the hardcoded `sampler: "engine-defaults"` — currently wrong at four sites (`AgentPoolTurnLoop.swift:50`, `AgentController.swift:873`, `PoolOrchestrator.swift:62,187`) plus `provenance.md` (`AgentController.swift:392`) — the moment any override goes out. The outcome records the effort actually used via `TurnThinkPolicy.samplerRecord` (Task 1).

**Files:**
- Modify: `Sources/SwiftStar/AgentPoolTurnLoop.swift` (`drainQueuedWorkers`'s builder)
- Modify: `Sources/SwiftStar/AgentController.swift` (provenance render + the `inject` site — already done in Task 3; this task updates the provenance literal and doc comments)
- Modify: `Sources/SwiftStarAppKit/PoolOrchestrator.swift` (both builders)
- Test: `Tests/SwiftStarKitTests/TurnOutcomeTests.swift` (a round-trip pin)

**Interfaces:**
- Consumes: `TurnThinkPolicy.samplerRecord` (Task 1); `ThinkEffort` (Task 1).
- Produces: `TurnOutcomeBuilder.init(model:build:task:think: ThinkEffort? = nil)` — the `sampler:` init parameter is replaced; `TurnOutcome.sampler` now carries `think=default|none|high|max|refused`.

- [ ] **Step 1: Write the failing test (the round-trip pin)**

Append to `Tests/SwiftStarKitTests/TurnOutcomeTests.swift`:

```swift
    // MARK: - P23 sampler truth

    @Test func samplerCarriesTheEffortActuallyUsed() {
        // The "engine-defaults" literal was false the moment the app started
        // sending overrides; the outcome must record the effort the builder was
        // given, and it must survive the Codable round-trip (outcomes.ndjson
        // replays).
        let builder = TurnOutcomeBuilder(model: "m", build: "b", think: .none, task: "t")
        let outcome = builder.finish()
        #expect(outcome.sampler == "think=none")
        let data = try! JSONEncoder().encode(outcome)
        let decoded = try! JSONDecoder().decode(TurnOutcome.self, from: data)
        #expect(decoded.sampler == "think=none")
    }

    @Test func defaultThinkRendersAsThinkDefault() {
        let outcome = TurnOutcomeBuilder(model: "m", build: "b", task: "t").finish()
        #expect(outcome.sampler == "think=default")
    }
```

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter samplerCarriesTheEffortActuallyUsed`
Expected: **FAIL** — `TurnOutcomeBuilder` has no `think:` init parameter (the red is the missing API; binding rule 2 satisfied by construction). After Task 5's Step 3 the same filter must pass.

- [ ] **Step 3: Give the builder the effort, and update the four sites**

In `Sources/SwiftStarKit/TurnOutcome.swift`, change `TurnOutcomeBuilder.init` from taking the sampler string to taking the effort:

```swift
    /// P23: the builder derives the sampler record from the effort actually
    /// used. nil = engine default ("think=default"); the hardcoded
    /// "engine-defaults" literal is retired — it was false the moment the app
    /// started sending overrides.
    public init(model: String, build: String, task: String, think: ThinkEffort? = nil) {
        self.model = model
        self.build = build
        self.task = task
        self.sampler = TurnThinkPolicy.samplerRecord(think.map { TurnThinkDecision.override($0) } ?? .useDefault)
    }
```

(The stored `sampler` field stays a plain `String`; the init now derives it. The `TurnThinkDecision.override` mapping keeps `samplerRecord` the single renderer.)

Then update the four creation sites to pass `think:` instead of `sampler:`:

In `Sources/SwiftStar/AgentController.swift`, `inject` (Task 3 already computed `effort`):

```swift
        outcomeBuilder = TurnOutcomeBuilder(
            model: settings.modelPath.lastPathComponent,
            build: buildSHA,
            think: effort,
            task: wireText
        )
```

In `Sources/SwiftStar/AgentPoolTurnLoop.swift`, `drainQueuedWorkers` (Task 9 computes `effort`; until then pass `nil` — a pre-Task-9 dispatch sends no override, so `"think=default"` is the truth):

```swift
        workerTurn.start(
            id: worker, packet: packet, worktree: worktree,
            outcomeBuilder: TurnOutcomeBuilder(
                model: settings.modelPath.lastPathComponent,
                build: buildSHA,
                think: nil,
                task: packet.taskText))
```

In `Sources/SwiftStarAppKit/PoolOrchestrator.swift`, `runPhase` (the harness targets the pinned engine, so the cap is assumed present and the packet's declared think is honored):

```swift
        var builder = TurnOutcomeBuilder(
            model: model, build: "pooled",
            think: TurnThinkPolicy.effort(for: packet.sampling.think),
            task: packet.taskText)
```

and `runOrchestrator` (the orchestrator's turn is the normal agent turn — default):

```swift
        var builder = TurnOutcomeBuilder(model: model, build: "pooled", task: prompt)
```

In `Sources/SwiftStar/AgentController.swift`, update `renderLiveProvenance`'s call site in `startAgent` (the provenance's Sampler fact must tell the truth too):

```swift
            try? Self.renderLiveProvenance(
                model: settings.modelPath.lastPathComponent, build: buildSHA,
                workspace: settings.workspace.path, contextSize: settings.contextSize,
                sampler: TurnThinkPolicy.samplerRecord(.useDefault), at: captureDir)
```

- [ ] **Step 4: Update the doc comments that asserted the old lie**

- `AgentController.swift` `inject`: replace "sampler is \"engine-defaults\": the app passes no sampler flags (D10's think default is the engine's too)" with: "sampler records the think decision actually used (P23): think=default when no override went out, think=none|high|max when one did."
- `TurnOutcome.swift`'s `sampler` field doc: "The spawn-time sampler identification the wire cannot carry" → append "(P23: the per-turn think decision — think=default|none|high|max|refused)."
- `PoolOrchestrator.swift`: the `runPhase` builder's new `think:` derives from the packet's declared sampling (the capture-integrity fix); note the harness targets the pinned engine, so the cap is assumed present.

- [ ] **Step 5: Prove the literal is gone**

Run: `rg -n "engine-defaults" Sources/`
Expected: **no output**. (The `rg` result is the binding-rule-2 red/green for this task: before Step 3 the four sites matched; after, none do.)

- [ ] **Step 6: Run the whole fast tier + build the app target**

Run: `swift test`
Expected: **767 tests** (766 + 1), 0 failures.
Run: `swift build` — must compile clean (the app-target edits have no test target; the build is the gate).

- [ ] **Step 7: Commit**

```bash
git add Sources/SwiftStar/AgentPoolTurnLoop.swift Sources/SwiftStar/AgentController.swift Sources/SwiftStarAppKit/PoolOrchestrator.swift Sources/SwiftStarKit/TurnOutcome.swift Tests/SwiftStarKitTests/TurnOutcomeTests.swift
git commit -m "$(cat <<'EOF'
P23: the turn outcome's sampler records the think decision

"engine-defaults" was hardcoded at four sites plus provenance.md, with a
doc comment asserting the app passes no sampler flags. That became false
the moment the app started sending per-turn think overrides. The
outcome now records the effort actually used (think=default|none|high|
max|refused) through TurnThinkPolicy.samplerRecord, surviving the
outcomes.ndjson Codable round-trip.

The harness (PoolOrchestrator) targets the pinned engine, so its
packet-derived sends assume the cap advertised; the app's live path
gates on the wire.

767 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Engine patch #14 — think half

Spec component 7 (think rows), spec cycle 6. One divergence in `external/ds4/ds4_agent.c`, built against the local submodule working tree (no bump yet — the app cannot pass the new flag until Task 10). Budget **~150–250 lines** (research §6: divergence #12 was 78; #13 was 4; this touches three high-churn regions).

**Files:**
- Modify: `external/ds4/ds4_agent.c` (in the submodule, branch `p20-dispatch-schema`)
- Test: the gated C self-tests (`make -C external/ds4 test`)

**Interfaces:**
- Consumes: the existing think primitives (`DS4_THINK_NONE/HIGH/MAX`, `ds4_think_mode_for_context`, `ds4_token_think_end`, the `--think-budget` machinery at :14312-14366).
- Produces (engine-side):
  - `--per-turn-think` flag (requires `--json-events`, like `--host-tools`)
  - `hello` advertises `"think_override"` in `caps` iff the flag is set (appended after `"pool"`)
  - `agent_parse_pool_prompt` recognizes the `"think"` key (`"none"|"high"|"max"` → `DS4_THINK_*`; unknown string → the key is ignored, not a drop) and JSON envelopes parse when `(n > 1) || per_turn_think` (the N=1 fix — the single-session wire must be able to carry overrides)
  - prompt-queue entries carry the override; `worker_submit` gains a think-override param; `worker_run_turn` honors it (D4 refusal for GLM / DeepSeek-MAX via a pure, C-tested predicate)

**D4 engine-side refusal (pure and tested):** extract a pure predicate so the C tests need no live engine:

```c
typedef enum {
    AGENT_FAMILY_LAGUNA,
    AGENT_FAMILY_GLM,
    AGENT_FAMILY_DEEPSEEK,
    AGENT_FAMILY_MELLUM,
    AGENT_FAMILY_UNKNOWN
} agent_family;

/* D4: per-turn think flips are refused on prefix-busting families. GLM's
 * reasoning-effort text is a system message at the transcript front - a flip
 * fails the sysprompt.kv text memcmp and forces a full system re-prefill and
 * cache overwrite every flip. DeepSeek V4 busts the prefix for MAX<->anything
 * only. A flip to the effective default costs nothing on any family (no flip). */
static bool agent_think_override_refused(agent_family family,
                                         ds4_think_mode requested,
                                         ds4_think_mode effective) {
    if (requested == effective) return false;
    if (family == AGENT_FAMILY_GLM) return true;
    if (family == AGENT_FAMILY_DEEPSEEK && requested == DS4_THINK_MAX) return true;
    return false;
}
```

The family mapping (`agent_worker_family(w)`) reads the engine's existing predicates — `agent_tool_syntax_for_engine(w->engine) == AGENT_TOOL_SYNTAX_GLM` for GLM; `ds4_engine_is_laguna` for Laguna; read `ds4.c:379-384`'s DeepSeek branch and `ds4_engine_is_mellum` (or the arch-name predicates the engine already uses) for the rest; unknown → `AGENT_FAMILY_UNKNOWN` (no refusal — the app-side policy already refused what it could identify, and Laguna-style flips are free).

**Honoring the override in `worker_run_turn`** (`:14129-14131`):

```c
static int worker_run_turn(agent_worker *w, const char *user_text) {
    agent_config *cfg = w->cfg;
    ds4_think_mode effective = effective_think_mode(cfg);
    ds4_think_mode think_mode = effective;
    if (w->think_override >= 0) {
        ds4_think_mode requested = (ds4_think_mode)w->think_override;
        if (!agent_think_override_refused(agent_worker_family(w), requested, effective)) {
            think_mode = requested;
        } else {
            agent_emit_event_str(w, "think_refused",
                "per-turn think override refused on this model family (prefix-busting)",
                strlen("per-turn think override refused on this model family (prefix-busting)"));
        }
        w->think_override = -1;   /* one turn: consume the override */
    }
    /* ... rest of worker_run_turn unchanged — the think_mode local above
     * already drives the generation loop (round_in_think, the stream renderer,
     * and the --think-budget checks all read it) ... */
```

(The refusal path is a loud wire event — `agent_emit_event_str` already emits `{"t":"<kind>","s":"...","ts":...}`; the Swift parser treats the unknown `think_refused` kind as `.ignored`, which is correct — the app never sends a refused override, this is defense-in-depth for a direct CLI user.)

**The queue and submit threading:**

```c
typedef struct {
    char *text;
    int think_override;   /* -1 = unset, else a ds4_think_mode */
} agent_queued_prompt;
```

- `agent_prompt_queue_push(q, text)` → `agent_prompt_queue_push(q, text, -1)`; new `agent_prompt_queue_push_override(q, text, override)`.
- `agent_prompt_queue_pop`/`take_all`/`push_front`/`peek`/`free` handle the struct; `take_all`'s merged turn inherits the FIRST entry's override (deterministic; the merged multi-prompt case is the single-session wire, and in practice the app never queues mixed overrides).
- `worker_submit(w, text)` → `worker_submit(w, text, think_override)` — sets `w->think_override` under `w->mu` next to `w->cmd_text`. All call sites (`:16845`, `:16852`, `:17029`, `:17237`) pass `-1` except the stdin parse path, which passes the parsed override.
- The `agent_worker` struct gains `int think_override;` (init `-1` in `agent_worker_init`'s memset).

**`agent_parse_pool_prompt`** (`:16723-16783`): add `int *out_think` (or a small struct) and the `"think"` key branch:

```c
} else if (!strcmp(key, "think")) {
    char *tv = NULL;
    if (!agent_json_parse_string(&p, &tv)) { free(key); goto drop; }
    if (!strcmp(tv, "none")) *out_think = DS4_THINK_NONE;
    else if (!strcmp(tv, "high")) *out_think = DS4_THINK_HIGH;
    else if (!strcmp(tv, "max")) *out_think = DS4_THINK_MAX;
    /* unknown value: leave the override unset (tolerate, don't drop) */
    free(tv);
}
```

The `pool_mode` argument becomes `(n > 1) || per_turn_think` at the call site (`:17006` — `agent_parse_pool_prompt(line, (n > 1) || cfg->per_turn_think, ...)`), so JSON envelopes parse on the single-session wire when the flag is on. The existing test `test_agent_parse_pool_prompt_routes_worker` must keep passing unchanged for `pool_mode=false` (its last assertion pins that behavior); the new N=1 JSON parse is a NEW test with `pool_mode=true`-equivalent behavior.

**Config + flags:**

- `agent_config` gains `bool per_turn_think;` (near `num_workers`).
- `parse_options`: `--per-turn-think` sets it. The requirement gate block (`:1046-1055`) gains:

```c
    /* P23 (fork divergence #14): the per-turn think override travels on the
     * JSON prompt envelope; without --json-events there is no wire for it. */
    if (c.per_turn_think && !c.json_events) {
        fprintf(stderr,
                "ds4-agent: --per-turn-think requires --json-events (the override rides the prompt envelope)\n");
        exit(2);
    }
```

- `agent_emit_hello` (`:5480-5497`) appends the cap after the pool cap:

```c
    if (w->cfg && w->cfg->num_workers > 1)
        agent_buf_puts(&b, ",\"pool\"");
    /* P23 (fork divergence #14): per-turn think overrides ride the prompt
     * envelope; advertise only when enabled so an unflag-ged capture's line 1
     * stays byte-identical (the golden fixtures' first line). */
    if (w->cfg && w->cfg->per_turn_think)
        agent_buf_puts(&b, ",\"think_override\"");
```

- [ ] **Step 1: Write the failing C tests first**

Add to `ds4_agent.c` near the existing pool tests (the `test_agent_*` pattern: zeroed worker + mock config, assert on `w.out`):

```c
/* P23 (fork divergence #14): the per-turn think refusal matrix (D4). Pure
 * predicate - no engine needed - so the family cases are pinned directly. */
static void test_agent_think_override_refusal_matrix(void) {
    AGENT_TEST_ASSERT(!agent_think_override_refused(AGENT_FAMILY_LAGUNA, DS4_THINK_NONE, DS4_THINK_HIGH));
    AGENT_TEST_ASSERT(!agent_think_override_refused(AGENT_FAMILY_MELLUM, DS4_THINK_HIGH, DS4_THINK_NONE));
    AGENT_TEST_ASSERT(agent_think_override_refused(AGENT_FAMILY_GLM, DS4_THINK_NONE, DS4_THINK_HIGH));
    AGENT_TEST_ASSERT(agent_think_override_refused(AGENT_FAMILY_GLM, DS4_THINK_MAX, DS4_THINK_HIGH));
    AGENT_TEST_ASSERT(!agent_think_override_refused(AGENT_FAMILY_GLM, DS4_THINK_HIGH, DS4_THINK_HIGH)); /* no flip */
    AGENT_TEST_ASSERT(agent_think_override_refused(AGENT_FAMILY_DEEPSEEK, DS4_THINK_MAX, DS4_THINK_HIGH));
    AGENT_TEST_ASSERT(!agent_think_override_refused(AGENT_FAMILY_DEEPSEEK, DS4_THINK_NONE, DS4_THINK_HIGH)); /* HIGH<->NONE is free */
    AGENT_TEST_ASSERT(!agent_think_override_refused(AGENT_FAMILY_UNKNOWN, DS4_THINK_MAX, DS4_THINK_HIGH));
}

/* P23 (fork divergence #14): hello advertises think_override iff the flag is
 * set, and the caps array still closes. This is the P9 defect class - the
 * commit that added the conditional "tool_request" dropped the closing "]"
 * and shipped invalid JSON past a green suite. */
static void test_agent_emit_hello_per_turn_think_cap(void) {
    /* flag off: base caps unchanged (this is what keeps the goldens' line 1
     * byte-identical without a recapture of every fixture). */
    {
        agent_worker w = {0};
        pthread_mutex_init(&w.mu, NULL);
        w.wake_fd[1] = -1;
        agent_config cfg = { .json_events = true, .per_turn_think = false };
        w.cfg = &cfg;
        agent_emit_hello(&w);
        AGENT_TEST_ASSERT(w.out != NULL);
        AGENT_TEST_ASSERT(strstr(w.out, "\"queued\",\"ts\"]") != NULL);
        AGENT_TEST_ASSERT(strstr(w.out, "think_override") == NULL);
        free(w.out);
        pthread_mutex_destroy(&w.mu);
    }
    /* flag on: caps closes with "think_override"]. */
    {
        agent_worker w = {0};
        pthread_mutex_init(&w.mu, NULL);
        w.wake_fd[1] = -1;
        agent_config cfg = { .json_events = true, .per_turn_think = true };
        w.cfg = &cfg;
        agent_emit_hello(&w);
        AGENT_TEST_ASSERT(w.out != NULL);
        AGENT_TEST_ASSERT(strstr(w.out, "\"queued\",\"ts\",\"think_override\"]") != NULL);
        free(w.out);
        pthread_mutex_destroy(&w.mu);
    }
}

/* P23 (fork divergence #14): the prompt envelope's think key maps to a think
 * mode; unknown values are tolerated, not drops; the wire stays quiet when
 * the key is absent. */
static void test_agent_parse_pool_prompt_think_key(void) {
    int wid = -1; char *text = NULL; int think = -1;
    int r = agent_parse_pool_prompt(
        "{\"t\":\"prompt\",\"worker\":0,\"think\":\"none\",\"s\":\"go\"}",
        true, &wid, &text, &think);
    AGENT_TEST_ASSERT(r == 1);
    AGENT_TEST_ASSERT(wid == 0);
    AGENT_TEST_ASSERT(strcmp(text, "go") == 0);
    AGENT_TEST_ASSERT(think == DS4_THINK_NONE);
    free(text);
    think = -1;
    r = agent_parse_pool_prompt(
        "{\"t\":\"prompt\",\"worker\":1,\"s\":\"plain\"}",
        true, &wid, &text, &think);
    AGENT_TEST_ASSERT(r == 1 && think == -1);
    free(text);
    think = -1;
    r = agent_parse_pool_prompt(
        "{\"t\":\"prompt\",\"worker\":0,\"think\":\"banana\",\"s\":\"x\"}",
        true, &wid, &text, &think);
    AGENT_TEST_ASSERT(r == 1 && think == -1);   /* unknown value: tolerate */
    free(text);
}
```

Register all three in the test runner (next to `test_agent_parse_pool_prompt_routes_worker();` at `:12065`).

- [ ] **Step 2: Run them and watch them fail**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: FAIL — compile errors (the functions/fields do not exist), then assertion failures once stubbed. Binding rule 2 by construction.

- [ ] **Step 3: Implement the think half**

Apply the changes above in order: the `agent_family` enum + refusal predicate, the config flag + `parse_options` + gate, `agent_parse_pool_prompt` (signature + `"think"` key + call-site `pool_mode`), the queue struct + helpers, `worker_submit` + all call sites, `agent_worker.think_override`, `worker_run_turn` honoring + refusal emission, `agent_emit_hello`. Keep the existing `test_agent_parse_pool_prompt_routes_worker` passing byte-for-byte (its `pool_mode=false` assertion pins pre-P23 bare-line behavior).

- [ ] **Step 4: Build and run the engine tests**

Run: `make -C external/ds4 ds4-agent ds4_agent_test`
Expected: clean build (zero warnings).
Run: `./external/ds4/ds4_agent_test`
Expected: green, including the three new tests. The P9 defect class is covered by the hello-JSON assertions (`"]"` closing check).

- [ ] **Step 5: Prove the flag's wire shape live (quick, cheap)**

Run (single-session, the N=1 JSON path — the exact shape the spec calls out):

```bash
cd external/ds4 && ./ds4-agent -m <xs-gguf> -c 16384 --metal --non-interactive --json-events --per-turn-think --workspace /tmp/p23-wt --shell off --think-budget 2048 <<< '{"t":"prompt","worker":0,"think":"none","s":"say pong in one word"}'
```

Expected: the first line's `caps` includes `"think_override"`; the turn produces **no** `{"t":"think"` events (think=none), then a `ready`. (Any model file works; the XS path from probe A is fastest.) If `--workspace` chdirs break Metal, export `DS4_METAL_*_SOURCE` per `fixtures/agent/provenance.md` gotcha #1.

- [ ] **Step 6: Commit (submodule, on `p20-dispatch-schema`)**

```bash
git -C external/ds4 add ds4_agent.c
git -C external/ds4 commit -m "$(cat <<'EOF'
P23 (fork divergence #14, think half): per-turn think overrides on the agent wire

--per-turn-think enables the wire feature: hello advertises
"think_override", the prompt envelope's "think" key ("none"|"high"|"max")
is parsed and threaded through the prompt queue into worker_run_turn,
and JSON envelopes parse on the single-session wire (the N=1 fix - the
pool_mode gate previously fed a JSON line to the model as literal text).

The override is refused loudly on prefix-busting families (D4): GLM's
reasoning-effort text is a system message at the transcript front, so a
flip fails the sysprompt.kv memcmp and forces a full re-prefill and
cache overwrite every flip; DeepSeek V4 busts the prefix for
MAX<->anything only. Laguna flips cost exactly one token and are free.
The refusal predicate is pure and C-tested; the wire event is a loud
"think_refused" line.

Flag-gated caps keep the committed goldens' line 1 byte-identical
without the flag; the hello-JSON tests cover the P9 defect class (the
conditional caps edit that dropped the closing bracket).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Engine patch #14 — per-worker context half

Spec component 7 (ctx rows), spec cycle 7, D8. The measured speed leg: a worker's session runs at a smaller ctx, so prefill is cheaper (4.2× ceiling) and scratch drops (~6.15 GB → ~1.5 GB at 4k). Budget **~40–80 lines**. The one real hazard is the shared `sysprompt.kv` (research §4) — fixed by ctx-qualifying the path.

**Files:**
- Modify: `external/ds4/ds4_agent.c` (submodule, `p20-dispatch-schema`)
- Test: gated C self-tests

**Interfaces:**
- Consumes: `agent_parse_pool_prompt`'s new signature (Task 6); `agent_worker_effective_ctx_size` (:545-549); `agent_worker_reset_to_sysprompt` (:6451); `ds4_kvstore_path_join`.
- Produces (engine-side):
  - the `"ctx"` key on the prompt envelope (`int`), parsed by `agent_parse_pool_prompt`
  - `worker_submit(w, text, think_override, pending_ctx)` — the ctx is applied before the turn
  - session re-create at the requested ctx (serialized under `pool_mu`, worker idle — rule 3: nothing kills a working session)
  - `sysprompt-<ctx>.kv` instead of the fixed `sysprompt.kv`
  - `effective_think_mode` uses the worker's session ctx (the MAX downgrade at :53348-53374 must see the worker's ctx, not `cfg`'s)

- [ ] **Step 1: Write the failing C tests first**

```c
/* P23 (fork divergence #14, ctx half): the envelope's ctx key parses to the
 * per-worker context; absent = unset (engine default = parent). */
static void test_agent_parse_pool_prompt_ctx_key(void) {
    int wid = -1; char *text = NULL; int think = -1; int ctx = 0;
    int r = agent_parse_pool_prompt(
        "{\"t\":\"prompt\",\"worker\":1,\"ctx\":8192,\"s\":\"do it\"}",
        true, &wid, &text, &think, &ctx);
    AGENT_TEST_ASSERT(r == 1);
    AGENT_TEST_ASSERT(ctx == 8192);
    free(text);
    ctx = 0;
    r = agent_parse_pool_prompt(
        "{\"t\":\"prompt\",\"worker\":0,\"s\":\"plain\"}",
        true, &wid, &text, &think, &ctx);
    AGENT_TEST_ASSERT(r == 1 && ctx == 0);
    free(text);
}
```

```c
/* P23 (fork divergence #14, ctx half): the sysprompt path is ctx-qualified,
 * so a mixed-ctx pool does not thrash one file (the parent writes at its
 * ctx, the small worker's load fails the saved_ctx > s->ctx_size check, and
 * the fallback prefill overwrites the file at the small ctx). */
static void test_agent_sysprompt_path_is_ctx_qualified(void) {
    char *p = agent_sysprompt_path("/tmp/cache", 8192);
    AGENT_TEST_ASSERT(p != NULL);
    AGENT_TEST_ASSERT(strstr(p, "sysprompt-8192.kv") != NULL);
    free(p);
    p = agent_sysprompt_path("/tmp/cache", 32768);
    AGENT_TEST_ASSERT(strstr(p, "sysprompt-32768.kv") != NULL);
    free(p);
}
```

Register both in the test runner.

- [ ] **Step 2: Run them and watch them fail**

Run: `make -C external/ds4 ds4_agent_test && ./external/ds4/ds4_agent_test`
Expected: FAIL (compile + assertions).

- [ ] **Step 3: Implement the ctx half**

1. **`agent_parse_pool_prompt`** gains `int *out_ctx` and the key branch:

```c
} else if (!strcmp(key, "ctx")) {
    if (!agent_json_parse_int(&p, out_ctx)) { free(key); goto drop; }
}
```

(`out_ctx` starts 0 = unset; the caller's effective-ctx arithmetic treats 0 as "use the default".)

2. **Path helper** (replaces the `ds4_kvstore_path_join(w->cache_dir, "sysprompt.kv")` at `:16513`):

```c
static char *agent_sysprompt_path(const char *cache_dir, int ctx) {
    char name[64];
    snprintf(name, sizeof(name), "sysprompt-%d.kv", ctx);
    return ds4_kvstore_path_join(cache_dir, name);
}
```

In `agent_worker_init`, `w->sysprompt_path = agent_sysprompt_path(w->cache_dir, cfg->gen.ctx_size);`

3. **Session re-create** (the ctx switch before a turn):

```c
/* P23 (D8): re-create the worker's session at the requested ctx and reload
 * the system prompt under the ctx-qualified path. Called from the worker
 * thread, under pool_mu, only when the worker is idle - no working session
 * is ever killed (rule 3). The sysprompt prefill at the smaller ctx is the
 * point: prefill cost tracks ctx (4.2x ceiling). */
static int agent_worker_set_session_ctx(agent_worker *w, int ctx,
                                        char *err, size_t err_len) {
    int cur = agent_worker_effective_ctx_size(w);
    if (cur == ctx || ctx <= 0) return 0;
    ds4_session_free(w->session);
    w->session = NULL;
    if (ds4_session_create(&w->session, w->engine, ctx) != 0) {
        snprintf(err, err_len, "failed to re-create session at ctx %d", ctx);
        return -1;
    }
    char *old = w->sysprompt_path;
    w->sysprompt_path = agent_sysprompt_path(w->cache_dir, ctx);
    free(old);
    if (!agent_worker_reset_to_sysprompt(w, err, err_len)) return -1;
    agent_trace(w, "worker session ctx %d (per-prompt)", ctx);
    return 0;
}
```

4. **`worker_submit`** gains `int pending_ctx`; stores `w->pending_ctx = pending_ctx` under `w->mu` (alongside `w->think_override`).

5. **`worker_main`** — inside the existing `pool_mu` region, before `worker_run_turn`:

```c
            pthread_mutex_lock(&pool_mu);
            if (w->pending_ctx > 0 &&
                w->pending_ctx != agent_worker_effective_ctx_size(w)) {
                char ctx_err[160] = {0};
                if (agent_worker_set_session_ctx(w, w->pending_ctx,
                                                 ctx_err, sizeof(ctx_err)) != 0) {
                    /* Loud failure: the turn cannot run at the requested ctx.
                     * Do not silently fall back to the parent's. */
                    agent_set_error(w, ctx_err[0] ? ctx_err : "failed to apply worker ctx");
                    w->pending_ctx = 0;
                    pthread_mutex_unlock(&pool_mu);
                    free(cmd);
                    continue;
                }
            }
            w->pending_ctx = 0;
            generating_worker = w->worker_id;
            worker_run_turn(w, cmd);
            generating_worker = -1;
            pthread_mutex_unlock(&pool_mu);
```

6. **`effective_think_mode` uses the worker's ctx** — change the two call sites (`:6239`, `:14131`) from `effective_think_mode(cfg)` to a new helper:

```c
static ds4_think_mode agent_worker_effective_think_mode(const agent_worker *w) {
    return ds4_think_mode_for_context(w->cfg->gen.think_mode,
                                      agent_worker_effective_ctx_size(w));
}
```

(Keep `effective_think_mode(cfg)` for any remaining `cfg`-only callers, or inline it; the semantic change is "the MAX downgrade sees the worker's live session ctx, not the spawn cfg's".)

7. **Call-site threading**: the stdin parse path passes the parsed `ctx` into the queue/submit path (entries gain `int ctx`; `take_all`'s merged turn keeps the first entry's ctx).

- [ ] **Step 4: Build and run the engine tests**

Run: `make -C external/ds4 ds4-agent ds4_agent_test`
Expected: clean build, all C tests green (new + pre-existing).

- [ ] **Step 5: Prove the worker ctx live (the memory assertion)**

Run a 2-worker session against the real engine:

```bash
cd external/ds4 && ./ds4-agent -m <xs-gguf> -c 32768 --metal --non-interactive --json-events --per-turn-think --subagent-pool 2 --workspace /tmp/p23-wt --shell off --think-budget 2048
```

then feed `{"t":"prompt","worker":1,"ctx":8192,"s":"reply pong"}`. Expected on the wire: worker 1's `ready` reports `ctx_size:8192` (the `status.ctx_size` routes through `agent_worker_effective_ctx_size`), and the kvstore gains `sysprompt-8192.kv` alongside the parent's `sysprompt-32768.kv` — two files, not one thrashed file (the spec's live validation).

- [ ] **Step 6: Commit (submodule)**

```bash
git -C external/ds4 add ds4_agent.c
git -C external/ds4 commit -m "$(cat <<'EOF'
P23 (fork divergence #14, ctx half): per-worker context size on the wire

The envelope's ctx key re-creates the worker's session at a smaller
context before its turn - serialized under pool_mu, only when the
worker is idle, so no working session is ever killed (rule 3). The
sysprompt checkpoint path becomes sysprompt-<ctx>.kv, fixing the
mixed-ctx thrash: previously all workers shared one fixed sysprompt.kv
and the small worker's load failed the saved_ctx > s->ctx_size check,
fell back to a full prefill, and overwrote the file at the small ctx.

effective_think_mode now reads the worker's live session ctx for the
MAX downgrade instead of the spawn cfg's.

Carries the measured speed leg: 4.2x prefill ceiling, ~6.15 GB -> ~1.5
GB scratch per worker at 4k.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `WorkerContextPolicy` — the app-side clamp

Spec D8, spec test 5. The app clamps the worker context through the same `MemoryBudget` arithmetic the parent uses, so a worker context can never bypass admission. Pure; fast-tier tested.

**Files:**
- Create: `Sources/SwiftStarKit/WorkerContextPolicy.swift`
- Modify: `Sources/SwiftStarKit/AgentCommand.swift` (`AgentSettings.workerContextSize`)
- Modify: `Sources/SwiftStarKit/AgentDefaultSettings.swift` (resolve)
- Modify: `Sources/SwiftStar/SettingsView.swift` (Agent section row)
- Test: `Tests/SwiftStarKitTests/WorkerContextPolicyTests.swift` (new); `Tests/SwiftStarKitTests/AgentDefaultSettingsTests.swift`

**Interfaces:**
- Consumes: nothing new (pure Int math + `UserDefaults`).
- Produces:
  - `public enum WorkerContextPolicy` with
    - `public static let defaultContext = 8192`
    - `public static let minContext = 4096`
    - `public static func clamp(requested: Int, parentContext: Int) -> Int` — `Swift.min(Swift.max(requested, minContext), parentContext)`
    - `public static func resolve(defaults: UserDefaults) -> Int` — key `"workerContextSize"`, default `defaultContext`
  - `AgentSettings.workerContextSize: Int` (default `WorkerContextPolicy.defaultContext`; `0` = inherit parent — resolved to the parent at dispatch)

- [ ] **Step 1: Write the failing tests**

Create `Tests/SwiftStarKitTests/WorkerContextPolicyTests.swift`:

```swift
import Testing
@testable import SwiftStarKit

struct WorkerContextPolicyTests {
    @Test func defaultIs8192() {
        #expect(WorkerContextPolicy.defaultContext == 8192)
    }

    @Test func clampKeepsInsideParentAndFloor() {
        #expect(WorkerContextPolicy.clamp(requested: 8192, parentContext: 32768) == 8192)
        #expect(WorkerContextPolicy.clamp(requested: 4096, parentContext: 32768) == 4096)
    }

    @Test func clampFloorsBelowTheMinimum() {
        // Below 4,096 the scratch savings stop and the engine's own floor
        // applies (D8: the clamp is [4096, parent]).
        #expect(WorkerContextPolicy.clamp(requested: 2048, parentContext: 32768) == 4096)
    }

    @Test func clampCapsAtTheParent() {
        // A worker context can never bypass admission: it cannot exceed the
        // parent's own admitted context.
        #expect(WorkerContextPolicy.clamp(requested: 16384, parentContext: 8192) == 8192)
        #expect(WorkerContextPolicy.clamp(requested: 1_000_000, parentContext: 51200) == 51200)
    }

    @Test func zeroInheritsTheParent() {
        #expect(WorkerContextPolicy.clamp(requested: 0, parentContext: 32768) == 32768)
    }

    @Test func resolvesFromUserDefaultsWithDefault() {
        let (defaults, name) = scratchDefaults()
        defer { cleanUp(defaults, name) }
        #expect(WorkerContextPolicy.resolve(defaults: defaults) == 8192)
        defaults.set(4096, forKey: "workerContextSize")
        #expect(WorkerContextPolicy.resolve(defaults: defaults) == 4096)
    }
}
```

(`scratchDefaults`/`cleanUp` are the fixture helpers from `AgentDefaultSettingsTests`; replicate them locally in this file if they are private to that suite.)

- [ ] **Step 2: Run them and watch them fail**

Run: `swift test --filter WorkerContextPolicyTests`
Expected: FAIL — type does not exist.

- [ ] **Step 3: Write the policy**

Create `Sources/SwiftStarKit/WorkerContextPolicy.swift`:

```swift
import Foundation

/// The per-worker context size for pool workers (P23, D8). The measured speed
/// leg: a 4k worker needs ~1.5 GB of scratch where a full-ctx worker needs
/// ~6.15 GB, and prefill cost tracks ctx (4.2× ceiling). The app clamps
/// through the same arithmetic the parent uses, so a worker context can never
/// bypass admission.
public enum WorkerContextPolicy {
    /// The default worker context. 8,192 halves scratch (~3.1 GB vs ~6.15 GB)
    /// while leaving a worker room to hold a bounded packet; scratch savings
    /// begin only below 16,384 (`rows = min(ctx, 16384)` on Laguna).
    public static let defaultContext = 8192
    /// The floor below which the engine's own minimums apply and the scratch
    /// curve stops helping (D8: clamped [4,096, parent]).
    public static let minContext = 4096

    public static func clamp(requested: Int, parentContext: Int) -> Int {
        let effective = requested > 0 ? requested : parentContext
        return Swift.min(Swift.max(effective, minContext), parentContext)
    }

    /// The configured worker context (UserDefaults `workerContextSize`,
    /// default 8,192; 0 = inherit the parent). The pure resolve so
    /// `AgentDefaultSettings` and tests agree.
    public static func resolve(defaults: UserDefaults) -> Int {
        defaults.object(forKey: "workerContextSize") as? Int ?? defaultContext
    }
}
```

- [ ] **Step 4: Add the settings field**

In `Sources/SwiftStarKit/AgentCommand.swift`, add to `AgentSettings` (stored property + init parameter):

```swift
    /// P23 (D8): the context size for subagent-pool workers, clamped to
    /// [4,096, parent] at dispatch time. 0 = inherit the parent's context.
    /// The value is a setting; the default is 8,192.
    public var workerContextSize: Int
```

with init default `workerContextSize: Int = WorkerContextPolicy.defaultContext` and the assignment in the init body.

- [ ] **Step 5: Resolve it**

In `Sources/SwiftStarKit/AgentDefaultSettings.swift`, before the return:

```swift
        // P23 (D8): the per-worker context setting (default 8,192; 0 = inherit
        // the parent). Clamped to [4096, parent] at dispatch time so it can
        // never bypass admission.
        let workerContextSize = WorkerContextPolicy.resolve(defaults: defaults)
```

and pass `workerContextSize: workerContextSize,` in the `AgentSettings(...)` call.

- [ ] **Step 6: Add the Settings control**

In `Sources/SwiftStar/SettingsView.swift`, beside the think-budget stepper (Agent section):

```swift
    @AppStorage("workerContextSize") private var workerContextSize = WorkerContextPolicy.defaultContext
```

and the row:

```swift
                Stepper("Worker context: \(workerContextSize == 0 ? "inherit parent" : "\(workerContextSize) tokens")",
                        value: $workerContextSize, in: 0...8192, step: 1024)
                Text("Context for pool workers (P23). Smaller = less prefill and scratch per worker; 0 inherits the parent's context. Clamped to at least 4096 and never above the parent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

(`WorkerContextPolicy` is in `SwiftStarKit`, already imported by `SettingsView`.)

- [ ] **Step 7: Run the fast tier**

Run: `swift test`
Expected: **773 tests** (767 + 6), 0 failures. (`swift build` must be clean for the app-target edits.)

- [ ] **Step 8: Commit**

```bash
git add Sources/SwiftStarKit/WorkerContextPolicy.swift Sources/SwiftStarKit/AgentCommand.swift Sources/SwiftStarKit/AgentDefaultSettings.swift Sources/SwiftStar/SettingsView.swift Tests/SwiftStarKitTests/WorkerContextPolicyTests.swift
git commit -m "$(cat <<'EOF'
P23: WorkerContextPolicy clamps the per-worker context

The worker context is a setting (default 8,192 - half the parent's
scratch at a third of the prefill) clamped to [4,096, parent] through
the same arithmetic the parent's admission uses, so a worker context
can never bypass admission. 0 inherits the parent.

AgentSettings.workerContextSize resolves from UserDefaults
("workerContextSize") and the Settings Agent section exposes it.

773 fast-tier tests.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Thread think + ctx through the dispatch path; integration tests

Spec component 4 (the loop threading), spec tests 8 (cap negotiation) and 9 (think-to-the-wall, gated). `drainQueuedWorkers` — extracted in part 1 exactly so this lands in a focused file — passes the worker's context (D8) and the packet's declared think (the capture-integrity fix: `SamplingPolicy.think` read at dispatch time at last). Consult workers ride the same path.

**Files:**
- Modify: `Sources/SwiftStar/AgentPoolTurnLoop.swift` (`drainQueuedWorkers`)
- Modify: `Sources/SwiftStarKit/FakeAgentSource.swift` (generated-fake prompt-guard seam)
- Test: `Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift` (cap negotiation); `Tests/SwiftStarIntegrationTests/ThinkToTheWallTests.swift` (new, gated)

**Interfaces:**
- Consumes: `WorkerContextPolicy` (Task 8), `TurnThinkPolicy` (Task 1), `PoolPrompt(think:contextSize:)` (Task 2).
- Produces: the worker PoolPrompt carries `think` (from `packet.sampling.think`) and `ctx` (clamped) when the cap is advertised. Consult workers ride the same path — their packets' default `SamplingPolicy` is `.bounded`, which maps to `.high`; `/quick` is the explicit no-think surface, not a consult property.

- [ ] **Step 1: Thread the dispatch path**

In `Sources/SwiftStar/AgentPoolTurnLoop.swift`, `drainQueuedWorkers` — replace the `workerTurn.start` + `PoolPrompt` block:

```swift
        // P23: the worker's per-turn think comes from its packet's declared
        // sampling (the capture-integrity fix — SamplingPolicy.think was
        // written and asserted and read by nothing at dispatch time), gated on
        // the advertised cap. Its context is clamped to [4096, parent] (D8).
        let thinkDecision = TurnThinkPolicy.decide(
            requested: TurnThinkPolicy.effort(for: packet.sampling.think),
            family: AgentController.familyOf(settings.modelPath),
            capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap))
        let effort: ThinkEffort?
        switch thinkDecision {
        case .useDefault: effort = nil
        case .override(let e): effort = e
        case .refused(let reason):
            log("worker \(worker.rawValue): think override refused: \(reason)")
            effort = nil
        }
        let workerCtx = WorkerContextPolicy.clamp(
            requested: settings.workerContextSize,
            parentContext: settings.contextSize)
        workerTurn.start(
            id: worker, packet: packet, worktree: worktree,
            outcomeBuilder: TurnOutcomeBuilder(
                model: settings.modelPath.lastPathComponent,
                build: buildSHA,
                think: effort,
                task: packet.taskText))
        if let pipe = process?.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(
                Data((PoolPrompt(worker: worker, text: packet.taskText,
                                 think: effort, contextSize: workerCtx).encode() + "\n").utf8))
        }
```

`AgentController.familyOf` is `internal` by design (Task 3 — Swift's `private` is file-scoped, and `AgentPoolTurnLoop` is a separate-file extension), so the extension reaches it directly.

- [ ] **Step 2: Write the failing integration tests (cap negotiation)**

First extend `FakeAgentSource` with the prompt-guard seam. In `Sources/SwiftStarKit/FakeAgentSource.swift`, the generated template's prompt loop becomes:

```swift
while let line = readPromptLine() {
__PROMPT_GUARD__
    replayOnce()
}
```

with `__PROMPT_GUARD__` defaulting to empty (existing fakes are byte-unchanged), and `generate(capture:engineArgv:promptGuard: String = "")` replacing the placeholder with the guard statement. A test passes a guard that writes a marker to stderr when a received prompt contains a `"think"` key — so the test can assert what actually reached the engine's stdin.

Then add to `Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift`. The app controller is `@MainActor`, so the two tests are `@MainActor`; they build the fake with the **pooled** argv the app actually spawns (`PoolEngine.argv`), point `AgentSettings.engineDir` at the fake's temp dir, `startAgent()`, wait for `.ready`, then drive `/quick`:

```swift
    // MARK: - P23 cap negotiation (spec test 8)

    /// Builds a fake at a temp dir whose argv matches the app's pooled spawn,
    /// and returns settings that point the controller at it.
    private func appSpawnableFake(capture: String, promptGuard: String) throws -> (URL, AgentSettings) {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p23-ws")
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        var settings = try makeSettings(workspace: ws, shellAllowed: true)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p23-fake-\(UUID().uuidString)", isDirectory: true)
        let argv = PoolEngine.argv(settings: settings, workers: 2)
        let source = try FakeAgentSource.generate(
            capture: Data(capture.utf8), engineArgv: argv, promptGuard: promptGuard)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        settings.engineDir = work  // AgentCommand.binaryPath = work/ds4-agent
        return (binary, settings)
    }

    /// D3: an engine that did not advertise think_override must receive no
    /// override and /quick must be refused.
    @Test @MainActor func engineWithoutThinkCapGetsNoOverrideAndNoQuick() throws {
        // golden-tools' hello is the base-7 caps (no think_override) — the
        // pre-bump engine's shape. The guard fails the fake if any prompt
        // line carries a "think" key, so an override on stdin kills it.
        let capture = try String(
            contentsOf: FakeAgentHarness.fixture("golden-tools.ndjson"), encoding: .utf8)
        let guardSource = #"if line.contains("\"think\"") { FileHandle.standardError.write(Data(("unexpected override: " + line + "\n").utf8)); exit(1) }"#
        let (_, settings) = try appSpawnableFake(capture: capture, promptGuard: guardSource)
        let controller = AgentController(settings: settings)
        controller.startAgent()
        // The fake emits its hello immediately; wait for the handshake.
        let deadline = Date().addingTimeInterval(10)
        while controller.state != .ready && Date() < deadline {
            await Task.yield()
        }
        #expect(controller.state == .ready)
        controller.quick("say hi")
        let refused = controller.transcript.rows.contains { row in
            if case .system(let s) = row { return s.contains("/quick unavailable") }
            return false
        }
        #expect(refused, "without the cap, /quick must be refused with a system row")
        #expect(controller.state == .ready, "a refused /quick must not start a turn")
        controller.stopAgent()
    }

    /// D3 (sibling success): an engine advertising think_override receives the
    /// field on stdin for /quick.
    @Test @MainActor func engineWithThinkCapReceivesTheOverride() throws {
        // A synthetic wire advertising the cap (the committed think-override
        // fixture lands in Task 10; this replay is the pre-capture shape).
        let capture = """
        {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","think_override"],"ts":1}
        {"t":"status","state":"idle","prefill_done":0,"prefill_total":0,"prefill_tps":0.0,"generated":0,"gen_tps":0.0,"ctx_used":0,"ctx_size":32768,"power":100,"error":"","ts":2}
        """
        // The guard records every prompt line to stderr; the assertion reads
        // the marker back.
        let guardSource = #"FileHandle.standardError.write(Data(("prompt:" + line + "\n").utf8))"#
        let (_, settings) = try appSpawnableFake(capture: capture, promptGuard: guardSource)
        let controller = AgentController(settings: settings)
        controller.startAgent()
        let deadline = Date().addingTimeInterval(10)
        while controller.state != .ready && Date() < deadline {
            await Task.yield()
        }
        controller.quick("say hi")
        // The fake writes the received prompt to its stderr; poll for the
        // marker carrying think=none.
        var saw = false
        let readDeadline = Date().addingTimeInterval(10)
        while !saw && Date() < readDeadline {
            saw = try promptOnStderrContains(settings.engineDir, "\"think\":\"none\"")
            await Task.yield()
        }
        controller.stopAgent()
        #expect(saw, "a /quick turn must reach the engine as think:none")
    }
```

The `promptOnStderrContains(_:_:)` helper reads the fake's stderr (redirect the fake's stderr to a file via the spawn environment, or extend `FakeAgentHarness` with a stderr-capture mode — follow the existing harness patterns; the assertion is the received prompt's bytes, which the guard makes visible). If `makeSettings`'s fixed `engineDir` conflicts, build the settings literal directly (the non-defaulted fields are `engineDir`/`modelPath`/`workspace`).

- [ ] **Step 3: Write the failing integration test (think-to-the-wall, gated ~10 s)**

Create `Tests/SwiftStarIntegrationTests/ThinkToTheWallTests.swift`:

```swift
import Testing
import Foundation
import Darwin

/// P23 spec test 9 — the phase's cheapest regression guard, replacing a 695 s
/// agentclinic run (probe A, 2026-08-28: the unbounded arm filled 15,873 of
/// 16,384 tokens reasoning across 7 rounds and never answered).
///
/// Pre-registered: n=1, mechanism-only. It pins that the think budget bounds
/// think-to-the-wall (unbounded think exceeds 90% ctx; the budgeted arm does
/// not). It does NOT claim the budget improves outcomes — the probe explicitly
/// declined that (a tight budget may convert reasoning into rambling).
///
/// Gated: needs a real model and the engine built at external/ds4. Drives the
/// engine directly (process flags, the probe's own configuration) rather than
/// through the app.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"
    && (ProcessInfo.processInfo.environment["SWIFTSTAR_LAGUNA_XS_MODEL"] != nil
        || ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"] != nil)))
struct ThinkToTheWallTests {
    /// Probe A's reasoning-inducing system prompt (the bare-prompt arm of the
    /// same probe produced zero thinking — thinking is prompt-induced, so the
    /// test uses the inducing configuration on purpose).
    private static let sys = "You are a careful analyst. Work through the problem step by step, "
        + "showing your full reasoning in <think> before every answer."
    private static let prompt = "A farmer has 17 sheep. All but 9 die. How many are left? Explain."
    private static let ctx = 16_384

    @Test func unboundedThinkHitsTheWallAndBudgetedDoesNot() throws {
        let model = ProcessInfo.processInfo.environment["SWIFTSTAR_LAGUNA_XS_MODEL"]
            ?? ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"]!
        let engineDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("external/ds4")
        let binary = engineDir.appendingPathComponent("ds4-agent")
        let ws = FileManager.default.temporaryDirectory
            .appendingPathComponent("p23-wall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ws, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ws) }

        let unbounded = try peakCtxUsed(
            binary: binary, engineDir: engineDir, model: model,
            sys: Self.sys, prompt: Self.prompt, budget: 0, workspace: ws)
        let budgeted = try peakCtxUsed(
            binary: binary, engineDir: engineDir, model: model,
            sys: Self.sys, prompt: Self.prompt, budget: 64, workspace: ws)

        #expect(Double(unbounded) > 0.9 * Double(Self.ctx),
            "unbounded arm peak ctx \(unbounded)/\(Self.ctx) did not approach the wall; "
            + "if seed variance broke the reproduction, record the numbers and STOP — "
            + "do not relax the threshold")
        #expect(Double(budgeted) < 0.9 * Double(Self.ctx),
            "budgeted arm peak ctx \(budgeted)/\(Self.ctx) still hit the wall; "
            + "--think-budget is not binding")
    }

    /// One engine run at the probe-A configuration, returning the peak
    /// `ctx_used` observed across the turn's status events. Runs until the
    /// turn-end ready or a 120 s deadline (the unbounded arm may never end on
    /// its own — the probe's failure mode), then kills the child.
    private func peakCtxUsed(binary: URL, engineDir: URL, model: String, sys: String,
                             prompt: String, budget: Int, workspace: URL) throws -> Int {
        var args = [binary.path, "-m", model, "-c", String(Self.ctx), "--metal",
                    "--non-interactive", "--json-events", "--think",
                    "-n", "512", "-sys", sys, "--workspace", workspace.path,
                    "--shell", "off"]
        if budget > 0 { args += ["--think-budget", String(budget)] }
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        // The engine chdirs to --workspace; Metal sources must resolve from
        // absolute paths (provenance.md gotcha #1).
        let metalDir = engineDir.appendingPathComponent("metal", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: metalDir.path) {
            for name in names where name.hasSuffix(".metal") {
                let stem = String(name.dropLast(".metal".count))
                env["DS4_METAL_\(stem.uppercased())_SOURCE"] =
                    metalDir.appendingPathComponent(name).path
            }
        }
        env["DS4_LOCK_FILE"] = "/tmp/ds4-p23-wall-\(getpid()).lock"
        process.environment = env
        let inPipe = Pipe(); let outPipe = Pipe(); let errPipe = Pipe()
        process.standardInput = inPipe; process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        inPipe.fileHandleForWriting.write(Data((prompt + "\n").utf8))
        var peak = 0
        var pending = ""
        let handle = outPipe.fileHandleForReading
        let deadline = Date().addingTimeInterval(120)
        var turnEnded = false
        while Date() < deadline && !turnEnded {
            let data = handle.availableData
            if data.isEmpty { break }  // EOF: the engine exited
            pending += String(decoding: data, as: UTF8.self)
            while let nl = pending.firstIndex(of: "\n") {
                let line = String(pending[..<nl])
                pending.removeSubrange(pending.startIndex...nl)
                guard let obj = try? JSONSerialization.jsonObject(
                    with: Data(line.utf8)) as? [String: Any] else { continue }
                let kind = obj["t"] as? String
                if kind == "status",
                   let used = (obj["ctx_used"] as? NSNumber)?.intValue {
                    peak = max(peak, used)
                } else if kind == "ready" {
                    turnEnded = true
                }
            }
        }
        process.terminate()
        return peak
    }
}
```

This drives the engine directly (the probe's configuration — process flags, not the wire override, which is exactly what the budget mechanism pins). If the unbounded arm fails to reproduce on the executor's machine, the failure message names the observed numbers; **stop and report rather than relaxing the threshold** — the spec pre-registered n=1 and the probe's own caveat stands.

- [ ] **Step 4: Run the integration tier**

Run: `SWIFTSTAR_INTEGRATION=1 swift test --filter ThinkToTheWallTests` (needs the Task 6/7 local engine build) and `SWIFTSTAR_INTEGRATION=1 swift test`
Expected: cap-negotiation tests green; think-to-the-wall green against the local build; the full integration tier green. Any fake-argv mismatch is the free conformance check working (a flag was added where the fake was generated from a different argv — regenerate).

- [ ] **Step 5: Run the fast tier**

Run: `swift test`
Expected: **773 tests**, unchanged (the new tests are integration-gated), 0 failures. `swift build` clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/SwiftStar/AgentPoolTurnLoop.swift Sources/SwiftStarKit/FakeAgentSource.swift Tests/SwiftStarIntegrationTests/FakeAgentIntegrationTests.swift Tests/SwiftStarIntegrationTests/ThinkToTheWallTests.swift
git commit -m "$(cat <<'EOF'
P23: workers get their packet's think and a clamped context

The dispatch path reads SamplingPolicy.think at last (the
capture-integrity fix - it was written, validated, and asserted, and
read by nothing at dispatch time) and gates it on the advertised cap;
the worker context is clamped to [4096, parent] (D8). Consult workers
ride the same path.

FakeAgentSource gains a prompt-guard seam so the cap-negotiation tests
can prove an engine that did not advertise think_override receives no
override and /quick is refused. Adds the gated think-to-the-wall
regression (spec test 9, ~10 s) that replaces the 695 s agentclinic
run: unbounded think exceeds 90% ctx, the budgeted arm does not.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Close the phase — recapture, ledger #14, bump

Spec cycle 8, D9 (ledger + recapture + bundled copy), D10 (submodule reconciliation — already done in part 1; keep it), D11 (warm-prefix decision). The phase's one expensive step.

**Files:**
- Modify: `ROADMAP.md` (P23 row status, D11 record)
- Modify: `docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md` (stamp `implemented`)
- Modify: `external/ds4/docs/fork-ledger.md` (row #14) — in the submodule
- Modify: `Sources/SwiftStarKit/AgentCommand.swift` (`--per-turn-think` in argv)
- Modify: `Sources/swiftstar-drive/main.swift` (`CAPTURE_PER_TURN_THINK` knob)
- Create: `fixtures/agent/think-override.{ndjson,trace,stderr,provenance.md}`
- Modify: `fixtures/agent/golden.{ndjson,trace,stderr,provenance.md}` (re-capture)
- Modify: `Sources/SwiftStarAppKit/Resources/golden.{ndjson,trace}` (bundled copy)
- Test: `Tests/SwiftStarIntegrationTests/FixtureReplayTests.swift` (replay the new fixture)

- [ ] **Step 1: Decide D11 and record it**

The warm-prefix routing decision (spec D11) is forced **before** the recapture: expose `ds4_session_common_prefix` as a wire query would cost a second recapture later, but is **out of scope** this phase (the backlog entry stays; a future phase pays the second recapture). Record in the ROADMAP P23 row's Status cell: "D11 decided: warm-prefix routing out of scope (second recapture deferred with the backlog entry)." Do not reopen.

- [ ] **Step 2: Add the fork-ledger row #14 (submodule)**

Append to the divergence table in `external/ds4/docs/fork-ledger.md`, matching the column shape:

```
| 14 | per-turn think + per-worker ctx on the agent wire (`--per-turn-think`) | (the two P23 commits above) | the app must bound and steer reasoning per turn and size each pool worker's session independently, without restarting the engine: `--per-turn-think` advertises a `think_override` cap, the prompt envelope carries `think` (`none|high|max`) and `ctx` keys, the override is refused loudly on prefix-busting families (GLM any flip; DeepSeek MAX), and the sysprompt checkpoint is ctx-qualified (`sysprompt-<ctx>.kv`) so a mixed-ctx pool does not thrash one file. JSON envelopes parse at N=1 when the flag is on. | upstream lands per-request reasoning_effort on the agent wire and per-session ctx (flagship proposal #1); then the flag is the engine's implementation of it |
```

- [ ] **Step 3: Add `--per-turn-think` to the app argv (with the bump)**

In `Sources/SwiftStarKit/AgentCommand.swift`, `argv(settings:)` — after the `--host-tools` entry:

```swift
            // P23: per-turn think overrides (think/ctx on the prompt envelope).
            // Unconditional like --host-tools: the app pins the engine (the
            // submodule bump in this phase shipped the flag); a DS4_DIR build
            // without it fails loudly at option-parse, never silently.
            "--per-turn-think",
```

In `Sources/swiftstar-drive/main.swift`, after the `--trace` entry:

```swift
// P23: the per-turn think wire shape (CAPTURE_PER_TURN_THINK=1 appends the
// flag so a prompts file can carry {"t":"prompt",...,"think":"none"} lines).
if env["CAPTURE_PER_TURN_THINK"] != nil {
    args += ["--per-turn-think"]
}
```

- [ ] **Step 4: Capture the new flag-exercising fixture**

Follow `fixtures/agent/provenance.md`'s worked method (the DS4_METAL env vars, the lock file, the workspace chdir gotchas). Rebuild first: `make -C external/ds4 ds4-agent`. Then:

```bash
printf '%s\n' \
  'Explain, in one sentence, what a KV cache is.' \
  '{"t":"prompt","worker":0,"think":"none","s":"List three prime numbers under twenty."}' \
  '{"t":"prompt","worker":0,"think":"high","s":"What is 2 to the 8th power?"}' \
  > /tmp/p23-prompts.txt
CAPTURE_GGUF=<xs-or-s-gguf> CAPTURE_CTX=16384 CAPTURE_PER_TURN_THINK=1 \
  CAPTURE_PROMPTS_FILE=/tmp/p23-prompts.txt swift run swiftstar-drive
```

Verify the capture before committing (the recapture gate):
- line 1 `caps` includes `"think_override"` and the JSON is valid (the P9 defect class),
- the second prompt's turn has **zero** `{"t":"think"` events (think=none held),
- the third prompt's turn has think events (think=high restored).

Copy the four files to `fixtures/agent/think-override.{ndjson,trace,stderr,provenance.md}` (write the provenance per the golden's template: submodule SHA, model, ctx, prompts, the three assertions above). **Do not hand-edit the wire bytes.**

- [ ] **Step 5: Re-capture `golden` against the rebuilt binary**

Per `fixtures/agent/provenance.md`'s method with the golden's exact config (same model, same `CAPTURE_CTX`, same prompt sequence — read the current provenance for both). Diff the new capture against the committed fixture:
- `golden.ndjson`: the base-7 caps line must be **unchanged** modulo `ts` (the flag was NOT passed — the flag-gated cap is the point); token/event counts may differ (nondeterministic generation — the P7/P9 precedent replaced the fixture wholesale).
- `golden.trace`: the sysprompt path line changes `sysprompt.kv` → `sysprompt-<ctx>.kv` (Task 7) — the expected diff, the reason the re-capture is owed.

Replace the four `golden.*` files + provenance, and copy the new `golden.{ndjson,trace}` to `Sources/SwiftStarAppKit/Resources/` (D9, provenance.md:162-166 — `bundledFixtureMatchesRepoFixture` stays green). If `replayYieldsStatusAndReadyThroughReducer`'s `memoryBudgetPlannedBytes == 49_943_965_040` assertion moves, the capture config did not match the original — fix the capture, do not update the assertion.

- [ ] **Step 6: Add a replay test for the new fixture**

In `Tests/SwiftStarIntegrationTests/FixtureReplayTests.swift`:

```swift
    /// P23: the think-override fixture's hello advertises the cap and the
    /// quick (think=none) turn emits no think events — the wire shape the
    /// recapture pins, replayed through the real parser.
    @Test func thinkOverrideFixtureAdvertisesCapAndQuickTurnHasNoThink() throws {
        let fixture = try FakeAgentHarness.fixture("think-override.ndjson")
        let lines = try String(contentsOf: fixture, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var parser = AgentWireParser()
        var sawOverrideCap = false
        var sawQuickTurnThink = false
        var sawNormalTurnThink = false
        for line in lines {
            guard let event = parser.feed(line) else { continue }
            switch event {
            case .hello(_, let caps):
                sawOverrideCap = caps.contains("think_override")
            case .think:
                sawNormalTurnThink = true
            default:
                break
            }
        }
        #expect(sawOverrideCap, "the fixture's hello must advertise think_override")
        // The three-turn shape is pinned in the fixture's provenance; the
        // think=none turn contributes no .think events (assertable as: at
        // least one think event exists overall — the quick turn's absence is
        // proven by the provenance's event-count assertions).
        #expect(sawNormalTurnThink)
    }
```

(If asserting the per-turn split precisely proves brittle across the parser's event model, keep the provenance as the per-turn authority and pin only the cap + the existence of think events here — the fixture's provenance.md carries the per-turn counts, exactly as `tool-rounds.provenance.md` carries its numbers.)

- [ ] **Step 7: Push the submodule and bump the gitlink**

```bash
git -C external/ds4 push origin p20-dispatch-schema
git add .gitmodules external/ds4
git commit -m "$(cat <<'EOF'
P23: bump the engine pin to divergence #14 (per-turn think + worker ctx)

Pushes p20-dispatch-schema's two P23 commits (fork-ledger row #14) and
moves the gitlink. The app's argv now passes --per-turn-think
unconditionally, matching how --host-tools and --subagent-pool already
work: the app pins the engine, and a DS4_DIR build without the flag
fails loudly at option-parse rather than degrading silently.

Recaptured golden against the rebuilt binary (standing rule): the
ndjson's base-7 caps line is unchanged (the cap is flag-gated), the
trace reflects the ctx-qualified sysprompt path. New think-override
fixture exercises the flag at N=1 (the JSON-envelope single-session
path).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Run both tiers**

Run: `swift test` — fast tier green, count unchanged from Task 9 (**773**; the fixture replay test is integration-gated).
Run: `SWIFTSTAR_INTEGRATION=1 swift test` — green, including `bundledFixtureMatchesRepoFixture`, the new fixture replay, the cap negotiation, and think-to-the-wall.

- [ ] **Step 9: Record the agenttest divergence, close the ROADMAP row, stamp the spec**

D12's third consequence: `swiftstar-agenttest` defaults to `noThink: true` (`main.swift`, `noThink: env["AGENTTEST_THINK"] != "1"`) while the app ships think=high — the harness has been measuring a different configuration than the app runs. The phase records and fixes it: the record goes in the ROADMAP P23 row (below); the fix is a comment at the site, so the divergence is deliberate and cited rather than accidental:

```swift
        // P23 (D12): the harness deliberately defaults to noThink while the
        // app ships think=high (the app's think cost is a property of its
        // task, not the flag — see the 2026-08-28 sysprompt-think-cost
        // measurement). This is a deterministic-testing choice, not an
        // accident; per-packet think is now available via the wire override
        // (divergence #14) if a fixture ever needs to match the app exactly.
        noThink: env["AGENTTEST_THINK"] != "1",
```

In `ROADMAP.md`, update the P23 row's Status cell to:

```
**implemented and closed 2026-08-28** — part 2: per-turn think (`/quick`, `think_override` cap, `TurnThinkPolicy`), per-worker ctx (clamped to [4096, parent]; `sysprompt-<ctx>.kv`), sampler truth, fork-ledger row #14, golden re-capture + think-override fixture. D11 decided: warm-prefix routing out of scope (second recapture deferred with the backlog entry). Live validation: /quick carries the override and the next normal turn shows no system re-prefill; refused override leaves the session untouched; 8k worker vs parent shows the predicted memory split.
```

In the spec, change `**Status:** proposed` → `**Status:** implemented` (the house convention this spec explicitly said it should not be the fifth to violate).
- [ ] **Step 10: Commit**

```bash
git add ROADMAP.md docs/superpowers/specs/2026-08-28-p23-wire-level-control-design.md
git commit -m "$(cat <<'EOF'
P23: close the phase — wire-level control is live

Per-turn think (think_override cap, /quick, TurnThinkPolicy, the
sampler truth) and per-worker context (clamped, sysprompt-<ctx>.kv)
shipped together in divergence #14; the phase record and spec now say
implemented, and the D11 warm-prefix decision is recorded rather than
deferred silently.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Done when

- Fast tier green at **773 tests**; integration tier green.
- `/quick` sends `think:"none"` only when the engine advertised `think_override`; an old engine gets no field and no `/quick` (D3).
- The engine (divergence #14): `--per-turn-think` advertises the cap, honors per-turn overrides with a loud refusal on GLM/DeepSeek-MAX (D4), parses JSON envelopes at N=1, and re-creates worker sessions at the per-prompt `ctx` with a ctx-qualified sysprompt (D8).
- `TurnOutcome.sampler` records the effort actually used; `"engine-defaults"` has zero matches in `Sources/`.
- Fork-ledger row **#14**; submodule pin pushed and bumped; golden re-captured and copied to bundled resources; `think-override` fixture committed with its provenance.
- The spec is stamped `implemented`; the ROADMAP row says so; D11 is recorded; the agenttest `noThink` divergence is recorded at its site (D12).
