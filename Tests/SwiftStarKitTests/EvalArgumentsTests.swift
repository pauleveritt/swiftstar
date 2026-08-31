import Testing
@testable import SwiftStarKit

/// Task 6: the ten analyzer verbs moved into `swiftstar-eval` unchanged. This
/// only checks the shared verb registry (`EvalArguments.knownVerbs`) — the
/// registry Task 5's `run` and Task 7's `experiment`/`verdict` extend rather
/// than each rewriting a switch. It does not exercise the verbs' behavior
/// (unchanged from `swiftstar-analyze`, spot-checked byte-for-byte instead).
struct EvalArgumentsTests {
    @Test func everyAnalyzeVerbIsReachable() {
        let verbs = [
            "list", "summary", "trace", "diff", "rereads",
            "findings", "taxonomy", "validate", "report", "index",
        ]
        for verb in verbs {
            #expect(EvalArguments.isKnownVerb(verb), "expected \(verb) to be a known verb")
        }
    }

    @Test func summariseIsRejected() {
        // Sibling refusal (binding rule 4): a near-miss verb name is not
        // silently accepted.
        #expect(!EvalArguments.isKnownVerb("summarise"))
    }
}
