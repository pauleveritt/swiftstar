import Testing
import Foundation
@testable import SwiftStarKit

struct TurnOutcomeTests {
    private static let hello = AgentEvent.hello(version: 1, capabilities: ["text", "tool", "status", "ts"])

    private func tool(_ phase: AgentToolPhase, idx: Int = 0, name: String? = nil,
                      status: String? = nil, calls: Int? = nil, value: String? = nil) -> AgentEvent {
        .tool(AgentToolEvent(phase: phase, idx: idx, name: name, paramKind: nil,
                             paramName: nil, value: value, status: status, calls: calls))
    }

    @Test func builderAccumulatesText() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.text("Hello "))
        b.apply(.text("world."))
        let o = b.finish()
        #expect(o.text == "Hello world.")
    }

    @Test func cleanReadCallIsEmittedParsedExecuted() {
        var b = TurnOutcomeBuilder(model: "m.gguf", build: "abc123", task: "read it")
        for e in [Self.hello, tool(.start), tool(.tool, name: "read"), tool(.paramBegin),
                  tool(.paramValue, value: "seed.txt"), tool(.paramEnd), tool(.finish, calls: 1),
                  .ready(plannedBytes: nil, stopReason: "eos", generated: 12, ctxUsed: 120)] {
            b.apply(e)
        }
        let outcome = b.finish()
        #expect(outcome.toolCalls == [ToolCallOutcome(name: "read", transitions: [.emitted, .parsed, .executed])])
        #expect(outcome.stopReason == .eos)
        #expect(outcome.generatedTokens == 12)
        #expect(outcome.ctxUsed == 120)
        #expect(outcome.model == "m.gguf")
        #expect(outcome.build == "abc123")
        // P23: the sampler records the think decision, not a fixed literal.
        #expect(outcome.sampler == "think=default")
        #expect(outcome.task == "read it")
    }

    @Test func bashOutputExecutesOnce() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        for e in [tool(.start), tool(.tool, name: "bash"), tool(.finish, calls: 1),
                  tool(.output, value: "hello-world\n"),
                  .ready(plannedBytes: nil, stopReason: "eos", generated: 3, ctxUsed: 9)] {
            b.apply(e)
        }
        // .executed arrives twice (output + clean finish) but records once.
        #expect(b.finish().toolCalls == [ToolCallOutcome(name: "bash", transitions: [.emitted, .parsed, .executed])])
    }

    @Test func interruptedFinishRejectsEveryCallInTheBlock() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        for e in [tool(.start), tool(.tool, idx: 0, name: "read"), tool(.tool, idx: 1, name: "bash"),
                  tool(.finish, idx: 1, status: "[tool call interrupted]\n", calls: 2),
                  .ready(plannedBytes: nil, stopReason: "interrupt", generated: 5, ctxUsed: 20)] {
            b.apply(e)
        }
        let outcome = b.finish()
        #expect(outcome.toolCalls == [
            ToolCallOutcome(name: "read", transitions: [.emitted, .rejected]),
            ToolCallOutcome(name: "bash", transitions: [.emitted, .rejected]),
        ])
        #expect(outcome.stopReason == .interrupt)
    }

    @Test func multipleBlocksAccumulateWithinATurn() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        for e in [tool(.start), tool(.tool, name: "read"), tool(.finish, calls: 1),
                  tool(.start), tool(.tool, name: "edit"), tool(.finish, calls: 1),
                  .ready(plannedBytes: nil, stopReason: "limit", generated: 99, ctxUsed: 32768)] {
            b.apply(e)
        }
        #expect(b.finish().toolCalls.map(\.name) == ["read", "edit"])
        #expect(b.finish().stopReason == .limit)
    }

    @Test func appOverrideBeatsWireReason() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "eos", generated: 1, ctxUsed: 2))
        // The app sent ETX; the wire may have already reported a stale reason.
        #expect(b.finish(appStopReason: .interrupt).stopReason == .interrupt)
        // Timeout is app-side only — the vocabulary case exists so the record
        // is complete (no controller policy in P7).
        #expect(b.finish(appStopReason: .timeout).stopReason == .timeout)
    }

    @Test func wireWithoutStopReasonDefaultsToEOS() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.ready(plannedBytes: 4, stopReason: nil, generated: nil, ctxUsed: nil))
        #expect(b.finish().stopReason == .eos)
    }

    @Test func contextFullMapsFromWire() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "context_full", generated: 0, ctxUsed: 32768))
        #expect(b.finish().stopReason == .contextFull)
    }

    @Test func goldenToolsYieldsFullLifecycleOutcomes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/agent/golden-tools.ndjson")
        let text = try String(contentsOf: url, encoding: .utf8)
        var parser = AgentWireParser()
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "whole capture")
        for line in text.split(whereSeparator: \.isNewline) {
            if let e = parser.feed(String(line)) { b.apply(e) }
        }
        let outcome = b.finish()
        // Evidence floor (binding rule 6): the real tool capture yields calls
        // with the full lifecycle — every call emitted, the bash call executed
        // — and a wire stop reason off its turn-end readys.
        #expect(!outcome.toolCalls.isEmpty)
        #expect(outcome.toolCalls.allSatisfy { $0.transitions.first == .emitted })
        #expect(outcome.toolCalls.contains { $0.name == "bash" && $0.transitions.contains(.executed) })
        #expect(outcome.toolCalls.contains { $0.name == "read" && $0.transitions.contains(.parsed) })
        #expect(outcome.stopReason == .eos || outcome.stopReason == .limit || outcome.stopReason == .interrupt || outcome.stopReason == .contextFull)
    }

    // P9 host-authoritative facts (D5): the record gains `mutations`,
    // `exitStatus`, `outputDigest`, and `validationRan`. The wire cannot carry
    // them (the host learns them by executing), so the builder leaves them at
    // their defaults and the app sets them on the finished record.
    // MARK: outcomes.ndjson — the capture's per-turn record

    @Test func outcomeRoundTripsAsOneNdjsonLine() throws {
        // outcomes.ndjson is one JSON line per finished turn. Two things must
        // hold for a capture to be readable evidence: the encoding survives a
        // round trip, and it never contains a raw newline (that would split one
        // turn across two records).
        var builder = TurnOutcomeBuilder(model: "laguna-s.gguf", build: "abc123",
                                         task: "multi\nline\ntask")
        builder.apply(.text("an answer\nwith newlines"))
        let outcome = builder.finish()

        let data = try JSONEncoder().encode(outcome)
        let line = String(decoding: data, as: UTF8.self)
        #expect(!line.contains("\n"))

        let decoded = try JSONDecoder().decode(TurnOutcome.self, from: data)
        #expect(decoded == outcome)
    }

    @Test func hostFactFieldsDefaultInBuilderFinish() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "eos", generated: 1, ctxUsed: 2))
        let outcome = b.finish()
        #expect(outcome.mutations == [])
        #expect(outcome.exitStatus == nil)
        #expect(outcome.outputDigest == nil)
        #expect(outcome.validationRan == false)
    }

    @Test func hostFactFieldsAreSettable() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.ready(plannedBytes: nil, stopReason: "eos", generated: 7, ctxUsed: 9))
        var outcome = b.finish()
        outcome.mutations = ["/tmp/a", "/tmp/b"]
        outcome.exitStatus = 0
        outcome.outputDigest = "sha256:deadbeef"
        outcome.validationRan = true
        #expect(outcome.mutations == ["/tmp/a", "/tmp/b"])
        #expect(outcome.exitStatus == 0)
        #expect(outcome.outputDigest == "sha256:deadbeef")
        #expect(outcome.validationRan == true)
        // The wire-derived fields are unaffected by setting the host facts.
        #expect(outcome.stopReason == .eos)
        #expect(outcome.generatedTokens == 7)
        #expect(outcome.ctxUsed == 9)
    }

    // MARK: - host-mode tool requests (D5: the host owns the verdict)
    //
    // In host mode the wire carries `.toolRequest` (not `.tool` phases); the
    // builder records each request as `emitted` and the host's verdict as
    // `executed` (ok) or `rejected` (refused), and accumulates the
    // host-authoritative facts (mutations/exitStatus/outputDigest/
    // validationRan) onto the finished record. The request `idx` is scoped to
    // the current block (the existing idx contract) and may repeat across
    // blocks, so the builder keys host calls by arrival order, not by idx.

    @Test func hostModeToolRequestRecordsEmitted() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.toolRequest(idx: 0, name: "read",
                             params: [ToolParam(name: "path", value: "seed.txt")]))
        let outcome = b.finish()
        #expect(outcome.toolCalls == [ToolCallOutcome(name: "read", transitions: [.emitted])])
        #expect(outcome.mutations == [])
        #expect(outcome.exitStatus == nil)
        #expect(outcome.validationRan == false)
    }

    @Test func recordHostVerdictOkExecutesAndCarriesFacts() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.toolRequest(idx: 0, name: "bash", params: []))
        b.recordHostVerdict(idx: 0, ok: true,
                            mutations: ["/tmp/a"], exitStatus: 0,
                            outputDigest: "sha256:abc", validationRan: true)
        let outcome = b.finish()
        #expect(outcome.toolCalls == [ToolCallOutcome(name: "bash", transitions: [.emitted, .executed])])
        #expect(outcome.mutations == ["/tmp/a"])
        #expect(outcome.exitStatus == 0)
        #expect(outcome.outputDigest == "sha256:abc")
        #expect(outcome.validationRan == true)
    }

    @Test func recordHostVerdictRefusedRejects() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.toolRequest(idx: 2, name: "bash", params: []))
        b.recordHostVerdict(idx: 2, ok: false,
                            mutations: [], exitStatus: nil,
                            outputDigest: nil, validationRan: false)
        let outcome = b.finish()
        #expect(outcome.toolCalls == [ToolCallOutcome(name: "bash", transitions: [.emitted, .rejected])])
        #expect(outcome.mutations == [])
        #expect(outcome.exitStatus == nil)
        #expect(outcome.validationRan == false)
    }

    @Test func hostModeMultipleRequestsAccumulateAcrossBlocks() {
        // Each block resets idx; the builder keys by arrival order, so two
        // requests both carrying idx 0 (one per block) become two distinct
        // tool calls in the outcome.
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.toolRequest(idx: 0, name: "read", params: []))
        b.recordHostVerdict(idx: 0, ok: true,
                            mutations: [], exitStatus: nil,
                            outputDigest: nil, validationRan: false)
        b.apply(.toolRequest(idx: 0, name: "bash", params: []))
        b.recordHostVerdict(idx: 0, ok: true,
                            mutations: ["/tmp/x"], exitStatus: 0,
                            outputDigest: "sha256:1", validationRan: true)
        let outcome = b.finish()
        #expect(outcome.toolCalls.count == 2)
        #expect(outcome.toolCalls[0].name == "read")
        #expect(outcome.toolCalls[1].name == "bash")
        #expect(outcome.mutations == ["/tmp/x"])
        #expect(outcome.exitStatus == 0)
        #expect(outcome.outputDigest == "sha256:1")
        #expect(outcome.validationRan == true)
    }

    @Test func hostModeFactsAccumulateAcrossMultipleBashCalls() {
        // Mutations accumulate across the turn; exitStatus/outputDigest keep
        // the last set (a turn with several bash calls records the last one's
        // command facts).
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        b.apply(.toolRequest(idx: 0, name: "bash", params: []))
        b.recordHostVerdict(idx: 0, ok: true,
                            mutations: ["/tmp/a"], exitStatus: 1,
                            outputDigest: "sha256:first", validationRan: true)
        b.apply(.toolRequest(idx: 0, name: "bash", params: []))
        b.recordHostVerdict(idx: 0, ok: true,
                            mutations: ["/tmp/b"], exitStatus: 0,
                            outputDigest: "sha256:second", validationRan: true)
        let outcome = b.finish()
        #expect(outcome.mutations == ["/tmp/a", "/tmp/b"])
        #expect(outcome.exitStatus == 0)  // last bash call's exit
        #expect(outcome.outputDigest == "sha256:second")
        #expect(outcome.validationRan == true)
        #expect(outcome.toolCalls.count == 2)
        #expect(outcome.toolCalls.allSatisfy { $0.transitions.contains(.executed) })
    }

    @Test func hostToolsModeDoesNotDoubleCount() {
        var b = TurnOutcomeBuilder(model: "m", build: "b", task: "t")
        // The transcript view (`.tool`) AND the execution view (`.toolRequest`)
        // describe the SAME call; finish() must count it once.
        b.apply(.tool(AgentToolEvent(phase: .tool, idx: 0, name: "write",
                                     paramKind: nil, paramName: nil, value: nil,
                                     status: nil, calls: nil)))
        b.apply(.tool(AgentToolEvent(phase: .finish, idx: 0, name: nil,
                                     paramKind: nil, paramName: nil, value: nil,
                                     status: nil, calls: 1)))
        b.apply(.toolRequest(idx: 0, name: "write", params: []))
        b.recordHostVerdict(idx: 0, ok: true, mutations: [],
                            exitStatus: nil, outputDigest: nil, validationRan: false)
        let outcome = b.finish()
        #expect(outcome.toolCalls.count == 1)   // not 2
        #expect(outcome.toolCalls.first?.name == "write")
        #expect(outcome.toolCalls.first?.transitions.contains(.executed) == true)
    }

    // MARK: - P23 sampler truth

    @Test func samplerCarriesTheEffortActuallyUsed() throws {
        // The "engine-defaults" literal was false the moment the app started
        // sending overrides; the outcome must record the effort the builder was
        // given, and it must survive the Codable round-trip (outcomes.ndjson
        // replays).
        let builder = TurnOutcomeBuilder(model: "m", build: "b", task: "t", think: .off)
        let outcome = builder.finish()
        #expect(outcome.sampler == "think=none")
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(TurnOutcome.self, from: data)
        #expect(decoded.sampler == "think=none")
    }

    @Test func defaultThinkRendersAsThinkDefault() {
        let outcome = TurnOutcomeBuilder(model: "m", build: "b", task: "t").finish()
        #expect(outcome.sampler == "think=default")
    }
}
