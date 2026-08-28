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
        #expect(TurnThinkPolicy.decide(requested: .off, family: .lagunaS, capAdvertised: false) == .useDefault)
        #expect(TurnThinkPolicy.decide(requested: .max, family: .lagunaS, capAdvertised: false) == .useDefault)
    }

    @Test func lagunaFamilyOverridesAreAllowed() {
        // Laguna contributes zero think tokens to the system prompt, so a
        // per-turn flip costs exactly one token in the assistant prefix (D4).
        for family in [ModelFamily.lagunaS, ModelFamily.lagunaXS, ModelFamily.mellum] {
            #expect(TurnThinkPolicy.decide(requested: .off, family: family, capAdvertised: true) == .override(.off))
            #expect(TurnThinkPolicy.decide(requested: .high, family: family, capAdvertised: true) == .override(.high))
            #expect(TurnThinkPolicy.decide(requested: .max, family: family, capAdvertised: true) == .override(.max))
        }
    }

    @Test func glmOverridesAreRefused() {
        // D4: on GLM the reasoning-effort text is a system message at the
        // front; a flip forces a full system re-prefill and a cache overwrite.
        for effort in [ThinkEffort.off, .high, .max] {
            #expect(TurnThinkPolicy.decide(requested: effort, family: .glm, capAdvertised: true) ==
                    .refused(reason: "glm cannot flip think mode per turn without a prefix bust"))
        }
    }

    @Test func deepSeekMaxIsRefusedButHighAndNoneAreNot() {
        // D4: DeepSeek V4 busts the prefix for MAX↔anything only; HIGH↔NONE is
        // free. Refusal tests get sibling success tests (binding rule 4).
        #expect(TurnThinkPolicy.decide(requested: .max, family: .deepSeekV4Flash, capAdvertised: true) ==
                .refused(reason: "deepseek-v4-flash cannot flip think mode to max per turn without a prefix bust"))
        #expect(TurnThinkPolicy.decide(requested: .high, family: .deepSeekV4Flash, capAdvertised: true) == .override(.high))
        #expect(TurnThinkPolicy.decide(requested: .off, family: .deepSeekV4Flash, capAdvertised: true) == .override(.off))
    }

    /// Regression guard for the Optional-collision landmine. `ThinkEffort`'s
    /// no-think case is named `off`, not `none`, because `decide` takes a
    /// `ThinkEffort?`: a case named `none` makes `requested: .none` resolve to
    /// `Optional.none` (nil) and silently mean "send no override", which would
    /// make `/quick` a no-op that still passed every other test in this file.
    /// The wire value must stay `"none"` — that is what the engine parses.
    @Test func theNoThinkCaseIsNotNamedNoneAndStillWiresAsNone() {
        #expect(ThinkEffort.off.rawValue == "none")
        #expect(ThinkEffort(rawValue: "none") == .off)
        // The distinction that matters: an explicit no-think request is an
        // override, while a genuinely absent request is not.
        let explicit: ThinkEffort? = .off
        let absent: ThinkEffort? = nil
        #expect(TurnThinkPolicy.decide(requested: explicit, family: .lagunaS, capAdvertised: true)
                == .override(.off))
        #expect(TurnThinkPolicy.decide(requested: absent, family: .lagunaS, capAdvertised: true)
                == .useDefault)
    }

    // MARK: - the packet mapping (the capture-integrity fix)

    @Test func thinkModeMapsToEffort() {
        #expect(TurnThinkPolicy.effort(for: .off) == .off)
        #expect(TurnThinkPolicy.effort(for: .on) == .high)
        #expect(TurnThinkPolicy.effort(for: .bounded) == .high)
    }

    // MARK: - the sampler record (Task 5 consumes this)

    @Test func samplerRecordCarriesTheEffortActuallyUsed() {
        #expect(TurnThinkPolicy.samplerRecord(.useDefault) == "think=default")
        #expect(TurnThinkPolicy.samplerRecord(.override(.off)) == "think=none")
        #expect(TurnThinkPolicy.samplerRecord(.override(.high)) == "think=high")
        #expect(TurnThinkPolicy.samplerRecord(.override(.max)) == "think=max")
        #expect(TurnThinkPolicy.samplerRecord(.refused(reason: "x")) == "think=refused")
    }
}
