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

    @Test func preregistrationCarriesQuestionAndFalsifier() throws {
        let experiment = try EvalExperiment.parse(Self.fixture("eval-valid.json"), exploratory: false)
        #expect(experiment.preregistration.contains(experiment.question))
        #expect(experiment.preregistration.contains(experiment.falsifier))
    }
}
