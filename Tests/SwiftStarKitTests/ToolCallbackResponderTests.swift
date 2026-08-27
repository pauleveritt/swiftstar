import Testing
import Foundation
@testable import SwiftStarKit

/// P9 Task 4: the pure `request → result` mapping (`ToolCallbackResponder`) and
/// the host-mode `TurnOutcomeBuilder` extension. The side-effecting execution
/// lives in the app target (`AgentController`); this suite pins the pure logic
/// the controller routes through — the consent check (D1/D6: workspace confine
/// + shell gate + unknown/web refuse), the `respond` mapping (consent →
/// execute → condense → response), the `tool_result` line (D2), and the
/// builder's host-mode verdict + host-fact accumulation (D5).
struct ToolCallbackResponderTests {
    private let ws = URL(fileURLWithPath: "/tmp/swiftstar-consent-ws")

    private func param(_ name: String, _ value: String) -> ToolParam {
        ToolParam(name: name, value: value)
    }

    // MARK: - consent (D1/D6: the same rules P7 put in the engine, host-side)

    @Test func consentFileReadProceeds() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "read",
            params: [param("path", "seed.txt")],
            workspace: ws, shellAllowed: false)
        guard case .proceed(let req) = r else { Issue.record("expected proceed"); return }
        #expect(req.name == "read")
        #expect(req.params == [param("path", "seed.txt")])
        #expect(req.resolvedPath == "/tmp/swiftstar-consent-ws/seed.txt")
    }

    @Test func consentFileToolDefaultsPathToWorkspaceRoot() {
        // `list` with no `path` param → defaults to the workspace root → proceed.
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "list", params: [],
            workspace: ws, shellAllowed: false)
        guard case .proceed(let req) = r else { Issue.record("expected proceed for pathless list"); return }
        #expect(req.resolvedPath == "/tmp/swiftstar-consent-ws")
    }

    @Test func consentAllowsNestedPathInsideWorkspace() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "write",
            params: [param("path", "sub/dir/seed.txt"), param("content", "hi")],
            workspace: ws, shellAllowed: false)
        guard case .proceed(let req) = r else { Issue.record("expected proceed for nested path"); return }
        #expect(req.resolvedPath == "/tmp/swiftstar-consent-ws/sub/dir/seed.txt")
    }

    @Test func consentRefusesPathEscapeViaDotDot() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "read",
            params: [param("path", "../../etc/passwd")],
            workspace: ws, shellAllowed: false)
        guard case .refuse(let reason) = r else { Issue.record("expected refuse"); return }
        #expect(reason.contains("workspace") || reason.contains("escape") || reason.contains("outside"))
    }

    @Test func consentRefusesAbsolutePathOutsideWorkspace() {
        // The engine resolves an absolute path as-is (realpath) and refuses it
        // when it is outside the workspace; the host matches (D1).
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "read",
            params: [param("path", "/etc/passwd")],
            workspace: ws, shellAllowed: false)
        guard case .refuse = r else { Issue.record("expected refuse for absolute escape"); return }
    }

    @Test func consentRefusesAdjacentSiblingDirectory() {
        // `/tmp/other` shares a string prefix with `/tmp/swiftstar-consent-ws`
        // but is NOT inside it — the prefix check must be directory-scoped.
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "read",
            params: [param("path", "/tmp/swiftstar-other")],
            workspace: ws, shellAllowed: false)
        guard case .refuse = r else { Issue.record("expected refuse for sibling dir"); return }
    }

    @Test func consentRefusesShellWhenOff() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "bash",
            params: [param("command", "echo hi")],
            workspace: ws, shellAllowed: false)
        guard case .refuse(let reason) = r else { Issue.record("expected refuse"); return }
        #expect(reason.contains("shell"))
    }

    @Test func consentProceedsBashWhenOn() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "bash",
            params: [param("command", "echo hi")],
            workspace: ws, shellAllowed: true)
        guard case .proceed(let req) = r else { Issue.record("expected proceed"); return }
        #expect(req.name == "bash")
        #expect(req.resolvedPath == nil)  // shell tools have no confined path
    }

    @Test func consentProceedsAllShellVariantsWhenOn() {
        for name in ["bash", "bash_status", "bash_stop"] {
            let r = ToolCallbackResponder.consent(
                idx: 0, name: name, params: [],
                workspace: ws, shellAllowed: true)
            guard case .proceed = r else { Issue.record("expected proceed for \(name)"); return }
        }
    }

    @Test func consentRefusesAllShellVariantsWhenOff() {
        for name in ["bash", "bash_status", "bash_stop"] {
            let r = ToolCallbackResponder.consent(
                idx: 0, name: name, params: [],
                workspace: ws, shellAllowed: false)
            guard case .refuse = r else { Issue.record("expected refuse for \(name) when shell off"); return }
        }
    }

    @Test func consentRefusesUnknownTool() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "invent", params: [],
            workspace: ws, shellAllowed: true)
        guard case .refuse(let reason) = r else { Issue.record("expected refuse for unknown tool"); return }
        #expect(reason.contains("unknown") || reason.contains("unsupported"))
    }

    @Test func consentRefusesWebTools() {
        // D6: the host runs read/write/edit/list/search/bash — web tools
        // (google_search/visit_page) are not part of the workspace/shell consent
        // and the host does not execute them.
        for name in ["google_search", "visit_page"] {
            let r = ToolCallbackResponder.consent(
                idx: 0, name: name, params: [],
                workspace: ws, shellAllowed: true)
            guard case .refuse = r else { Issue.record("expected refuse for web tool \(name)"); return }
        }
    }

    @Test func consentProceedsAllFileTools() {
        for name in ["read", "more", "write", "list", "edit", "search"] {
            let r = ToolCallbackResponder.consent(
                idx: 0, name: name, params: [param("path", "seed.txt")],
                workspace: ws, shellAllowed: false)
            guard case .proceed = r else { Issue.record("expected proceed for file tool \(name)"); return }
        }
    }

    // MARK: - P10 dispatched-mode revision check (D2: writableFiles confines
    // mutating tools; read aids are unaffected; nil disables the check).

    @Test func consentRefusesWriteOutsideWritableFiles() {
        // A dispatched attempt (writableFiles set) refuses a `write` whose
        // workspace-relative path is not in the contract — host-side, so the
        // tool is never executed.
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "write",
            params: [param("path", "outside.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["a.txt"])
        guard case .refuse(let reason) = r else { Issue.record("expected refuse for out-of-contract write"); return }
        #expect(reason.contains("writable-files") || reason.contains("contract"))
    }

    @Test func consentRefusesEditOutsideWritableFiles() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "edit",
            params: [param("path", "outside.txt"), param("old", "a"), param("new", "b")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["a.txt"])
        guard case .refuse = r else { Issue.record("expected refuse for out-of-contract edit"); return }
    }

    @Test func consentAllowsWriteInsideWritableFiles() {
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "write",
            params: [param("path", "a.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["a.txt"])
        guard case .proceed(let req) = r else { Issue.record("expected proceed for in-contract write"); return }
        #expect(req.name == "write")
    }

    @Test func consentAllowsNestedWriteInWritableFiles() {
        // A nested writable file matches its worktree-relative form.
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "write",
            params: [param("path", "sub/b.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["sub/b.txt"])
        guard case .proceed = r else { Issue.record("expected proceed for nested in-contract write"); return }
    }

    @Test func consentAllowsReadAidsOutsideWritableFiles() {
        // D2: the worker gets read/write/edit (and list/search as read aids).
        // The revision check confines only mutating tools; reads are free.
        for name in ["read", "more", "list", "search"] {
            let r = ToolCallbackResponder.consent(
                idx: 0, name: name, params: [param("path", "outside.txt")],
                workspace: ws, shellAllowed: false,
                writableFiles: ["a.txt"])
            guard case .proceed = r else { Issue.record("expected proceed for read aid \(name) outside writableFiles"); return }
        }
    }

    @Test func consentIgnoresWritableFilesWhenNil() {
        // nil writableFiles (the normal Agent-tab mode) disables the check: a
        // write anywhere in the workspace proceeds.
        let r = ToolCallbackResponder.consent(
            idx: 0, name: "write",
            params: [param("path", "anywhere.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: nil)
        guard case .proceed = r else { Issue.record("expected proceed when writableFiles is nil"); return }
    }

    @Test func respondRefusesOutContractWriteAndDoesNotExecute() {
        // A refused revision check returns ok:false with no mutation, and the
        // executor is never called — the tool is not executed host-side.
        var didExecute = false
        let resp = ToolCallbackResponder.respond(
            idx: 9, name: "write",
            params: [param("path", "outside.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["a.txt"],
            execute: { _ in
                didExecute = true
                return ToolExecutionResult(ok: true, text: "should not run",
                                            mutations: ["outside.txt"])
            })
        #expect(resp.ok == false)
        #expect(resp.idx == 9)
        #expect(resp.mutations == [], "a refused revision check must not record a mutation")
        #expect(!didExecute, "an out-of-contract write must not be executed")
    }

    @Test func respondExecutesInContractWriteAndRecordsMutation() {
        let resp = ToolCallbackResponder.respond(
            idx: 1, name: "write",
            params: [param("path", "a.txt"), param("content", "x")],
            workspace: ws, shellAllowed: false,
            writableFiles: ["a.txt"],
            execute: { req in
                ToolExecutionResult(ok: true, text: "wrote",
                                    mutations: [req.resolvedPath ?? ""])
            })
        #expect(resp.ok == true)
        #expect(resp.mutations == ["/tmp/swiftstar-consent-ws/a.txt"])
    }

    // MARK: - respond (the pure request→result mapping; execute is injected)

    @Test func respondRefuseReturnsOkFalseAndDoesNotExecute() {
        // A shell-off bash: consent refuses → ok:false, the reason condensed,
        // no host facts, and `execute` is never called.
        var didExecute = false
        let resp = ToolCallbackResponder.respond(
            idx: 7, name: "bash",
            params: [param("command", "ls")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                didExecute = true
                return ToolExecutionResult(ok: true, text: "should not be used",
                                            mutations: [], exitStatus: nil,
                                            outputDigest: nil, validationRan: false)
            })
        #expect(resp.ok == false)
        #expect(resp.idx == 7)
        #expect(!resp.s.isEmpty)
        #expect(resp.mutations == [])
        #expect(resp.exitStatus == nil)
        #expect(resp.outputDigest == nil)
        #expect(resp.validationRan == false)
        #expect(!didExecute, "a refused consent must not call execute")
    }

    @Test func respondProceedExecutesAndCarriesCondensedResult() {
        let resp = ToolCallbackResponder.respond(
            idx: 1, name: "read",
            params: [param("path", "seed.txt")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                ToolExecutionResult(ok: true, text: "hello",
                                    mutations: [], exitStatus: nil,
                                    outputDigest: nil, validationRan: false)
            })
        #expect(resp.ok == true)
        #expect(resp.s == "hello")  // under the 8000-byte limit → unchanged
        #expect(resp.idx == 1)
    }

    @Test func respondCondensesLongResultUnderLimit() {
        let long = String(repeating: "x", count: 10000)
        let resp = ToolCallbackResponder.respond(
            idx: 0, name: "read",
            params: [param("path", "big.txt")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                ToolExecutionResult(ok: true, text: long,
                                    mutations: [], exitStatus: nil,
                                    outputDigest: nil, validationRan: false)
            })
        #expect(resp.s.utf8.count <= 8000)
        #expect(resp.s.contains("truncated"))
    }

    @Test func respondCarriesHostFacts() {
        let resp = ToolCallbackResponder.respond(
            idx: 0, name: "bash",
            params: [param("command", "make test")],
            workspace: ws, shellAllowed: true,
            execute: { _ in
                ToolExecutionResult(ok: true, text: "all good",
                                    mutations: ["/tmp/a", "/tmp/b"],
                                    exitStatus: 0, outputDigest: "sha256:deadbeef",
                                    validationRan: true)
            })
        #expect(resp.ok == true)
        #expect(resp.mutations == ["/tmp/a", "/tmp/b"])
        #expect(resp.exitStatus == 0)
        #expect(resp.outputDigest == "sha256:deadbeef")
        #expect(resp.validationRan == true)
    }

    @Test func respondPropagatesExecutionFailureAsOkFalse() {
        // The executor itself may fail (file not found, bash non-zero) — its
        // `ok:false` carries the error text; the host facts still ride along.
        let resp = ToolCallbackResponder.respond(
            idx: 0, name: "read",
            params: [param("path", "missing.txt")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                ToolExecutionResult(ok: false, text: "error: file not found",
                                    mutations: [], exitStatus: 2,
                                    outputDigest: nil, validationRan: false)
            })
        #expect(resp.ok == false)
        #expect(resp.s == "error: file not found")
        #expect(resp.exitStatus == 2)
    }

    // MARK: - async respond (item 3, P22 cleanup): identical mapping to the
    // sync overload, awaiting an async `execute` closure instead.

    @Test func asyncRespondRefuseReturnsOkFalseAndDoesNotExecute() async {
        var didExecute = false
        let resp = await ToolCallbackResponder.respond(
            idx: 7, name: "bash",
            params: [param("command", "ls")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                didExecute = true
                return ToolExecutionResult(ok: true, text: "should not be used")
            })
        #expect(resp.ok == false)
        #expect(resp.idx == 7)
        #expect(!didExecute, "a refused consent must not call execute")
    }

    @Test func asyncRespondProceedAwaitsExecuteAndCarriesCondensedResult() async {
        let resp = await ToolCallbackResponder.respond(
            idx: 1, name: "read",
            params: [param("path", "seed.txt")],
            workspace: ws, shellAllowed: false,
            execute: { _ in
                // A real suspension point, not just an async-labeled sync
                // closure — proves `respond` genuinely awaits `execute`.
                try? await Task.sleep(nanoseconds: 1_000_000)
                return ToolExecutionResult(ok: true, text: "hello")
            })
        #expect(resp.ok == true)
        #expect(resp.s == "hello")
        #expect(resp.idx == 1)
    }

    @Test func asyncRespondCarriesHostFacts() async {
        let resp = await ToolCallbackResponder.respond(
            idx: 0, name: "bash",
            params: [param("command", "make test")],
            workspace: ws, shellAllowed: true,
            execute: { _ in
                ToolExecutionResult(ok: true, text: "all good",
                                    mutations: ["/tmp/a"],
                                    exitStatus: 0, outputDigest: "sha256:deadbeef",
                                    validationRan: true)
            })
        #expect(resp.ok == true)
        #expect(resp.mutations == ["/tmp/a"])
        #expect(resp.exitStatus == 0)
        #expect(resp.outputDigest == "sha256:deadbeef")
        #expect(resp.validationRan == true)
    }

    @Test func asyncDispatchProceedsWhenWellFormedWithoutCallingExecute() async {
        let params = [ToolParam(name: "taskText", value: "fix a.swift")]
        let r = await ToolCallbackResponder.respond(
            idx: 0, name: "dispatch", params: params,
            workspace: URL(fileURLWithPath: "/tmp/w"), shellAllowed: false,
            execute: { _ in
                Issue.record("execute must not run for dispatch")
                return ToolExecutionResult(ok: true, text: "nope")
            })
        #expect(r.ok)
        #expect(r.s == "dispatched")
    }

    // MARK: - resultLine (the tool_result JSON line, D2)

    @Test func resultLineIsJsonToolResult() {
        let resp = ToolCallbackResponse(
            idx: 3, ok: true, s: "wrote seed.txt",
            mutations: [], exitStatus: nil, outputDigest: nil, validationRan: false)
        let line = ToolCallbackResponder.resultLine(resp)
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("resultLine must be valid JSON"); return
        }
        #expect((obj["t"] as? String) == "tool_result")
        #expect((obj["idx"] as? NSNumber)?.intValue == 3)
        #expect((obj["ok"] as? Bool) == true)
        #expect((obj["s"] as? String) == "wrote seed.txt")
    }

    @Test func resultLineEscapesSpecialCharacters() {
        let resp = ToolCallbackResponse(
            idx: 0, ok: false, s: #"error: "quote" and \backslash"#,
            mutations: [], exitStatus: nil, outputDigest: nil, validationRan: false)
        let line = ToolCallbackResponder.resultLine(resp)
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("resultLine must be valid JSON"); return
        }
        #expect((obj["s"] as? String) == #"error: "quote" and \backslash"#)
    }

    @Test func resultLineKeysAreSorted() {
        // `.sortedKeys` → idx < ok < s < t (lexicographic).
        let resp = ToolCallbackResponse(
            idx: 0, ok: true, s: "x",
            mutations: [], exitStatus: nil, outputDigest: nil, validationRan: false)
        let line = ToolCallbackResponder.resultLine(resp)
        let positions = ["\"idx\":", "\"ok\":", "\"s\":", "\"t\":"].compactMap { key -> (String, Range<String.Index>)? in
            guard let r = line.range(of: key) else { return nil }
            return (key, r)
        }
        #expect(positions.count == 4, "resultLine must carry all four keys")
        let sorted = positions.sorted { $0.1.lowerBound < $1.1.lowerBound }
        #expect(sorted.map(\.0) == ["\"idx\":", "\"ok\":", "\"s\":", "\"t\":"])
    }

    // P11 (D3): dispatch is a host-control tool — well-formed admits, missing
    // taskText refuses, and no execute runs.
    @Test func dispatchProceedsWhenWellFormed() {
        let params = [ToolParam(name: "taskText", value: "fix a.swift"),
                      ToolParam(name: "writableFiles", value: "a.swift")]
        let r = ToolCallbackResponder.respond(
            idx: 0, name: "dispatch", params: params,
            workspace: URL(fileURLWithPath: "/tmp/w"), shellAllowed: false,
            execute: { _ in
                Issue.record("execute must not run for dispatch")
                return ToolExecutionResult(ok: true, text: "nope")
            })
        #expect(r.ok)
        #expect(r.s == "dispatched")
    }

    @Test func dispatchRefusedWithoutTaskText() {
        let r = ToolCallbackResponder.respond(
            idx: 0, name: "dispatch", params: [],
            workspace: URL(fileURLWithPath: "/tmp/w"), shellAllowed: false,
            execute: { _ in ToolExecutionResult(ok: true, text: "nope") })
        #expect(!r.ok)
        #expect(r.s.contains("taskText"))
    }
}
