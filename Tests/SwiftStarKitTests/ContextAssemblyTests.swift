import Testing
@testable import SwiftStarKit

struct ContextAssemblyTests {
    @Test func assembleBundlesObjectiveDigestReadsAndAdaptation() {
        var d = RollingDigest()
        d = RollingDigestReducer.record(d, receipt: DispatchReceipt(worker: WorkerId(1), ref: "ref1", reason: nil, summary: "s"))
        let task = ContextAssembly.assemble(
            objective: "Fix the broken test",
            digest: d,
            loaded: ["ROADMAP.md": "P11 is next"],
            adaptation: "The worker should edit Tests/FooTests.swift")
        #expect(task.contains("Fix the broken test"))
        #expect(task.contains("ref1"))            // digest folded in
        #expect(task.contains("ROADMAP.md"))       // staged read named
        #expect(task.contains("edit Tests/FooTests.swift"))
    }
    @Test func deterministicAdaptationSizesToImplementer() {
        let small = ContextAssembly.deterministicAdaptation(objective: "o", digest: RollingDigest(), loaded: ["a.swift": "x"], implementer: "mellum")
        let large = ContextAssembly.deterministicAdaptation(objective: "o", digest: RollingDigest(), loaded: ["a.swift": "x"], implementer: "laguna")
        #expect(small.contains("one at a time"))       // small-capability: finer, chunked
        #expect(!large.contains("one at a time"))      // large-capability: coarse
        #expect(large.contains("as you see fit"))
    }
    @Test func adaptationPromptTargetsImplementerSize() {
        let prompt = ContextAssembly.adaptationPrompt(
            objective: "o", digest: RollingDigest(), loaded: ["f": "x"], implementer: "mellum")
        #expect(prompt.contains("mellum"))
        #expect(prompt.contains("split into smaller chunks"))
    }
    @Test func assembleWithoutAdaptationStillCarriesObjective() {
        let task = ContextAssembly.assemble(objective: "o", digest: RollingDigest(), loaded: [:], adaptation: "")
        #expect(task.contains("o"))
    }
}
