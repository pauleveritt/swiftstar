import Testing
@testable import SwiftStarKit

/// P20 (D3): the orchestrate directive and the dispatch-preference rule are
/// pure text — the fast tier asserts the required clauses are present with no
/// engine and no model.
struct OrchestrateDirectiveTests {
    @Test func embedsTaskVerbatim() {
        let text = OrchestrateDirective.build(task: "build the thing", writableFiles: [])
        #expect(text.contains("Task: build the thing"))
    }

    @Test func rendersEmptyScopeAsWholeWorkspace() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("the whole workspace"))
    }

    @Test func rendersFileScopeCommaSeparated() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: ["a.swift", "b.swift"])
        #expect(text.contains("a.swift, b.swift"))
    }

    @Test func namesDispatchToolAndItsParameters() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("`dispatch`"))
        #expect(text.contains("taskText"))
        #expect(text.contains("writableFiles"))
        #expect(text.contains("validationCommand"))
    }

    @Test func statesOneShotFirst() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("One-shot-first"))
        #expect(text.contains("at most once"))
    }

    @Test func forbidsDispatchingWithoutAnAcceptancePredicate() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("acceptance predicate"))
        #expect(text.contains("watched interactive"))
    }

    @Test func requiresValidatingTheIntegratedResult() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("validate the whole result"))
        #expect(text.contains("exits 0"))
    }

    @Test func instructsDecompositionWithMachineCheckableAcceptance() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(text.contains("Decompose"))
        #expect(text.contains("machine-checkable"))
    }

    @Test func embedsProjectContextWhenProvided() {
        let text = OrchestrateDirective.build(
            task: "t", writableFiles: [], projectContext: "Web framework: fastapi[standard]")
        #expect(text.contains("Project context:"))
        #expect(text.contains("fastapi[standard]"))
    }

    @Test func omitsProjectContextSectionWhenAbsent() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [])
        #expect(!text.contains("Project context:"))
    }

    @Test func omitsProjectContextSectionWhenWhitespaceOnly() {
        let text = OrchestrateDirective.build(task: "t", writableFiles: [], projectContext: "  \n  ")
        #expect(!text.contains("Project context:"))
    }
}
