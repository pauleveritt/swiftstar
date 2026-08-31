import Testing
import Foundation
@testable import SwiftStarKit

/// `EvalExperiment` (task 3, eval-cli): the committed pre-registration a
/// `swiftstar-eval` run parses before spawning anything. One declared
/// variable, enough pairs to say something, a deterministic ABBA order.
struct EvalExperimentTests {
    private static var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SwiftStarKitTests
            .appendingPathComponent("Fixtures")
    }

    private static func fixture(_ name: String) -> Data {
        try! Data(contentsOf: fixturesRoot.appendingPathComponent(name))
    }

    /// A minimal valid file, inlined so tests that only need to vary one
    /// field (`pairs`, `variable`) don't need their own fixture file.
    private static func json(
        pairs: String = "",
        variable: String = "\"power\"",
        mode: String = "bare"
    ) -> Data {
        let pairsField = pairs.isEmpty ? "" : "\"pairs\": \(pairs),"
        let text = """
        {
          "name": "power-throttle-probe",
          "question": "Does power change decode throughput?",
          "falsifier": "If the effect is under 5% across all pairs, the claim is falsified.",
          "variable": \(variable),
          \(pairsField)
          "mode": "\(mode)",
          "promptFile": "prompts/throttle.md",
          "captureSelection": "latest",
          "arms": [
            { "id": "control", "overrides": { "power": "70" } },
            { "id": "treatment", "overrides": { "power": "100" } }
          ],
          "common": {}
        }
        """
        return Data(text.utf8)
    }

    /// Like `json(...)`, but lets a test supply its own `common`/arm
    /// `overrides` literals — for exercising `overrideKeyVocabulary`
    /// validation, which `json(...)`'s fixed `{"power": ...}` overrides never
    /// touch.
    private static func jsonWithOverrides(
        variable: String = "\"power\"",
        controlOverrides: String = #"{"power": "70"}"#,
        treatmentOverrides: String = #"{"power": "100"}"#,
        common: String = "{}"
    ) -> Data {
        let text = """
        {
          "name": "power-throttle-probe",
          "question": "Does power change decode throughput?",
          "falsifier": "If the effect is under 5% across all pairs, the claim is falsified.",
          "variable": \(variable),
          "pairs": 3,
          "mode": "bare",
          "promptFile": "prompts/throttle.md",
          "captureSelection": "latest",
          "arms": [
            { "id": "control", "overrides": \(controlOverrides) },
            { "id": "treatment", "overrides": \(treatmentOverrides) }
          ],
          "common": \(common)
        }
        """
        return Data(text.utf8)
    }

    // MARK: - Step 1 tests

    @Test func parsesTheCommittedFixture() throws {
        let experiment = try EvalExperiment.parse(Self.fixture("eval-valid.json"), exploratory: false)
        #expect(experiment.arms.count == 2)
        #expect(experiment.variable == "power")
    }

    @Test func refusesTwoVariables() throws {
        #expect(throws: EvalExperimentError.multipleVariables(["hostTools", "power"])) {
            _ = try EvalExperiment.parse(Self.fixture("eval-two-variables.json"), exploratory: false)
        }
    }

    @Test func refusesFewerThanThreePairs() throws {
        #expect(throws: EvalExperimentError.tooFewPairs(1)) {
            _ = try EvalExperiment.parse(Self.fixture("eval-one-pair.json"), exploratory: false)
        }
    }

    @Test func exploratoryAdmitsOnePair() throws {
        let experiment = try EvalExperiment.parse(Self.fixture("eval-one-pair.json"), exploratory: true)
        #expect(experiment.pairs == 1)
    }

    @Test func defaultsToFivePairs() throws {
        let experiment = try EvalExperiment.parse(Self.json(), exploratory: false)
        #expect(experiment.pairs == EvalExperiment.defaultPairs)
        #expect(EvalExperiment.defaultPairs == 5)
    }

    @Test func refusesSeedAsTheVariable() throws {
        #expect(throws: EvalExperimentError.seedIsNotAnAxis) {
            _ = try EvalExperiment.parse(Self.json(variable: "\"seed\""), exploratory: false)
        }
    }

    @Test func runOrderIsABBAAndSeedMatched() throws {
        let experiment = try EvalExperiment.parse(Self.json(pairs: "2"), exploratory: true)
        let order = experiment.runOrder()
        #expect(order.map(\.armID) == ["control", "treatment", "treatment", "control"])
        #expect(order[0].pair == 1 && order[1].pair == 1)
        #expect(order[2].pair == 2 && order[3].pair == 2)
        #expect(order[0].seed == order[1].seed)
        #expect(order[2].seed == order[3].seed)
        #expect(order[0].seed != order[2].seed)
    }

    @Test func runOrderIsDeterministicFromTheFile() throws {
        let data = Self.json(pairs: "3")
        let first = try EvalExperiment.parse(data, exploratory: false).runOrder()
        let second = try EvalExperiment.parse(data, exploratory: false).runOrder()
        #expect(first.map(\.seed) == second.map(\.seed))
        #expect(first.map(\.armID) == second.map(\.armID))
    }

    @Test func refusesArgvAsTheVariable() throws {
        #expect(throws: EvalExperimentError.argvIsNotAnAxis) {
            _ = try EvalExperiment.parse(Self.json(variable: "\"argv\""), exploratory: false)
        }
    }

    // Sibling success for refusesArgvAsTheVariable: one of the typed fields
    // argv is built from (runtimeFlags) is a real, admitted axis.
    @Test func admitsRuntimeFlagsInsteadOfArgv() throws {
        let experiment = try EvalExperiment.parse(Self.json(variable: "\"runtimeFlags\""), exploratory: false)
        #expect(experiment.variable == "runtimeFlags")
    }

    @Test func refusesAnUnknownVariable() throws {
        #expect(throws: EvalExperimentError.unknownVariable("hosttools")) {
            _ = try EvalExperiment.parse(Self.json(variable: "\"hosttools\""), exploratory: false)
        }
    }

    // Sibling success for refusesAnUnknownVariable: the correctly-spelled
    // property parses.
    @Test func admitsAKnownVariable() throws {
        let experiment = try EvalExperiment.parse(Self.json(variable: "\"hostTools\""), exploratory: false)
        #expect(experiment.variable == "hostTools")
    }

    @Test func refusesAnUnknownMode() throws {
        #expect(throws: EvalExperimentError.unknownMode("orchestrateee")) {
            _ = try EvalExperiment.parse(Self.json(mode: "orchestrateee"), exploratory: false)
        }
    }

    // Sibling success for refusesAnUnknownMode: a real EvalMode case parses.
    @Test func admitsAKnownMode() throws {
        let experiment = try EvalExperiment.parse(Self.json(mode: "orchestrate"), exploratory: false)
        #expect(experiment.mode == .orchestrate)
    }

    @Test func preregistrationCarriesQuestionAndFalsifier() throws {
        let experiment = try EvalExperiment.parse(Self.fixture("eval-valid.json"), exploratory: false)
        #expect(experiment.preregistration.contains(experiment.question))
        #expect(experiment.preregistration.contains(experiment.falsifier))
    }

    // MARK: - F1 (fable-fixes review): unknown/mistyped override keys

    // The design doc's own (since-corrected) example used `ctx`, `shell`,
    // `hostTools`, `variant`, `gitRef` in `common`/`overrides` — none
    // recognized by `applyOverride`. Before this gate, an unrecognized key
    // was silently dropped and the arm ran at defaults.
    @Test func refusesAnUnknownOverrideKey() throws {
        let data = Self.jsonWithOverrides(treatmentOverrides: #"{"ctx": 8192}"#)
        #expect(throws: EvalExperimentError.unknownOverrideKey(
            key: "ctx", context: "arm \"treatment\"",
            accepted: EvalExperiment.overrideKeyVocabulary.keys.sorted())
        ) {
            _ = try EvalExperiment.parse(data, exploratory: false)
        }
    }

    // Sibling success for refusesAnUnknownOverrideKey: the correctly-named
    // key (`contextSize`, not `ctx`) parses.
    @Test func admitsAKnownOverrideKey() throws {
        let data = Self.jsonWithOverrides(treatmentOverrides: #"{"contextSize": 8192}"#)
        let experiment = try EvalExperiment.parse(data, exploratory: false)
        #expect(experiment.arms[1].overrides["contextSize"] == .int(8192))
    }

    // A recognized key with the wrong JSON shape is the other half of F1's
    // silent drop — `applyOverride`'s `if case .int(let i) = value` pattern
    // match fails just as silently as an unknown key does.
    @Test func refusesAMistypedOverrideValue() throws {
        let data = Self.jsonWithOverrides(treatmentOverrides: #"{"maxTokens": "big"}"#)
        #expect(throws: EvalExperimentError.mistypedOverrideValue(
            key: "maxTokens", context: "arm \"treatment\"", accepted: ["int"])
        ) {
            _ = try EvalExperiment.parse(data, exploratory: false)
        }
    }

    // Sibling success for refusesAMistypedOverrideValue: the same key with
    // the right shape parses.
    @Test func admitsACorrectlyTypedOverrideValue() throws {
        let data = Self.jsonWithOverrides(treatmentOverrides: #"{"maxTokens": 2048}"#)
        let experiment = try EvalExperiment.parse(data, exploratory: false)
        #expect(experiment.arms[1].overrides["maxTokens"] == .int(2048))
    }

    // `common` is validated too, not just per-arm `overrides`.
    @Test func refusesAnUnknownKeyInCommon() throws {
        let data = Self.jsonWithOverrides(common: #"{"hostTools": true}"#)
        #expect(throws: EvalExperimentError.unknownOverrideKey(
            key: "hostTools", context: "common",
            accepted: EvalExperiment.overrideKeyVocabulary.keys.sorted())
        ) {
            _ = try EvalExperiment.parse(data, exploratory: false)
        }
    }

    // MARK: - F2 (fable-fixes review): gitRef is refused, not faked

    // Per-arm engine builds are not implemented (every arm resolves its
    // engine from the same DS4_DIR); `variable: "gitRef"` is refused outright
    // rather than admitted by a check (ArmDiff's declared-ref match) that
    // could never fail within one invocation.
    @Test func refusesGitRefAsTheVariable() throws {
        #expect(throws: EvalExperimentError.gitRefNotSupported) {
            _ = try EvalExperiment.parse(Self.json(variable: "\"gitRef\""), exploratory: false)
        }
    }
}
