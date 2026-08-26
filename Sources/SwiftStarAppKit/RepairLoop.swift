import Foundation
import SwiftStarKit

/// What the packet builder needs to assemble one authored repair packet. The
/// builder is worktree-independent: it renders the directive, contract, and
/// writable note only; `RepairLoop` appends `MachineEvidence` afterward (D5/D6).
public struct RepairContext: Sendable {
    public let failedRef: String
    public let grade: GradeResult
    public let round: Int
    public init(failedRef: String, grade: GradeResult, round: Int) {
        self.failedRef = failedRef
        self.grade = grade
        self.round = round
    }
}

/// The bounded repair orchestrator (D1/D4/D5/D8/D9): post-grade recovery as up
/// to `maxCandidateRounds` chained `role: .repair` dispatches, each re-graded.
/// A receipt ends the loop immediately (a retry would replay the same dispatch);
/// only a candidate that re-fails grading yields new evidence and another round.
public enum RepairLoop {

    public struct RoundRecord: Codable, Sendable {
        public let round: Int
        public let candidateRef: String?
        public let receipt: Receipt?
        public let grade: GradeResult?
        public let elapsed: Int
        public init(round: Int, candidateRef: String?, receipt: Receipt?, grade: GradeResult?, elapsed: Int) {
            self.round = round
            self.candidateRef = candidateRef
            self.receipt = receipt
            self.grade = grade
            self.elapsed = elapsed
        }
    }

    public enum Outcome: Sendable {
        case passed(ref: String, grade: GradeResult, worktree: WorktreeDispatcher.Worktree)
        case exhausted(lastGrade: GradeResult?, receipt: Receipt)
    }

    public static func run(
        repo: URL, failedRef: String, initialGrade: GradeResult,
        packetBuilder: (RepairContext) throws -> HandoffPacket,
        runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome,
        grade: (URL) throws -> GradeResult,
        capture: FileHandle? = nil, captureDir: URL? = nil,
        maxCandidateRounds: Int = 2, outputCap: Int = 8192, fileCap: Int = 16384,
        emissionFollowUp: String? = nil
    ) throws -> Outcome {
        var head = failedRef
        var lastGrade = initialGrade

        for round in 1...maxCandidateRounds {
            let start = Date()
            let ctx = RepairContext(failedRef: head, grade: lastGrade, round: round)
            let authored = try packetBuilder(ctx)
            if case .invalid(let reasons) = HandoffPacketValidator.validate(authored) {
                throw RepairLoopError.packetInvalid(reasons)
            }

            let wt = try WorktreeDispatcher.prepare(packet: authored, in: repo, baseRef: head)
            // Discard the disposable worktree on every exit from this iteration
            // (normal fall-through, `continue`-equivalent, `return`, or `throw`)
            // except the `.passed` path below, which hands the live worktree to
            // the caller and clears this flag before returning.
            var shouldDiscardWorktree = true
            defer { if shouldDiscardWorktree { WorktreeDispatcher.discard(wt, in: repo) } }

            // Text-contract repair re-emits a *complete* file; evidence truncated
            // to `fileCap` would be re-emitted truncated and overwrite a good copy.
            // Refuse the round instead of silently shipping a partial view.
            if authored.textContract {
                for path in authored.writableFiles {
                    let url = fileURL(path, in: wt.url)
                    if let data = FileManager.default.contents(atPath: url.path),
                       data.count > fileCap {
                        write(record: RoundRecord(round: round, candidateRef: nil, receipt: .contractNotFollowed, grade: nil, elapsed: Int(Date().timeIntervalSince(start))), to: captureDir)
                        return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed)
                    }
                }
            }

            // Assemble machine evidence from the worktree + the failing grade.
            var contents: [String: String] = [:]
            var truncations: [String] = []
            for path in authored.writableFiles {
                let url = fileURL(path, in: wt.url)
                if let data = FileManager.default.contents(atPath: url.path) {
                    if let text = String(data: data, encoding: .utf8) {
                        let (kept, note) = MachineEvidence.cappedContent(text, cap: fileCap)
                        contents[path] = kept
                        if let note { truncations.append(note) }
                    } else {
                        // File exists but contains binary data that isn't valid UTF-8.
                        contents[path] = "(file exists but is not valid UTF-8 — cannot be shown as text)"
                    }
                } else {
                    // A writable path that doesn't exist in this worktree is a
                    // real, plausible live-run failure mode (an earlier phase never
                    // wrote it). Silently omitting the key makes it indistinguishable
                    // from "unchanged/fine" in the rendered evidence, so mark it
                    // explicitly instead.
                    contents[path] = "(file does not exist in this worktree)"
                }
            }
            let (out, outNote) = MachineEvidence.cappedFailureOutput(lastGrade.output, cap: outputCap)
            if let outNote { truncations.append(outNote) }
            let evidence = MachineEvidence(failureOutput: out, fileContents: contents, truncations: truncations)
            for hit in evidence.redactHits(authored.redacts) {
                FileHandle.standardError.write(Data(
                    ("[repair] note: redacted string \"\(hit)\" present in machine evidence\n").utf8))
            }

            let packet = HandoffPacket(
                taskText: authored.taskText + "\n\n" + evidence.render(),
                writableFiles: authored.writableFiles,
                validationCommand: authored.validationCommand,
                selfTestCommand: authored.selfTestCommand,
                baselines: authored.baselines,
                turnBudget: authored.turnBudget,
                toolCallBudget: authored.toolCallBudget,
                textContract: authored.textContract,
                facts: authored.facts,
                redacts: authored.redacts,
                role: authored.role,
                sampling: authored.sampling)

            // Per-round capture of the assembled packet (evidence included).
            // `RepairLoop` is the only place this packet exists — the evidence
            // is folded into `taskText` right above, and nothing downstream
            // reconstructs it — so `RepairLoop` is where it must be captured,
            // written alongside `repair-round-N.json` below.
            writePacketCapture(packet: packet, round: round, to: captureDir)

            var turn = try runPhase(packet, wt.url, capture)
            if turn.stopReason == .limit || turn.stopReason == .contextFull {
                throw RepairLoopError.sessionExhausted(turn.stopReason)
            }
            // Text-contract harvest seam: a text-only turn (no tool calls, eos)
            // under a `textContract` packet is a candidate the host extracts via
            // the labeled-block parser and writes itself — the model never touched
            // the write tool, so the host materializes its declared mutations.
            if packet.textContract, turn.toolCalls.isEmpty, turn.stopReason == .eos {
                // Shared with the build arm — see `TextContractHarvest` for the
                // two-turn emission protocol and the evidence behind it.
                let attempt = try TextContractHarvest.run(
                    firstTurn: turn, packet: packet, worktree: wt.url,
                    emissionFollowUp: emissionFollowUp, capture: capture,
                    runPhase: runPhase,
                    onFollowUpTurn: { followUp in
                        if followUp.stopReason == .limit || followUp.stopReason == .contextFull {
                            throw RepairLoopError.sessionExhausted(followUp.stopReason)
                        }
                    })
                // The emitting turn replaces the reasoning turn as the round's
                // outcome: its text is what the host harvests, and its token
                // count is what the budget check must see.
                turn = attempt.turn
                let harvest = attempt.result
                if harvest.degenerateRepetition {
                    FileHandle.standardError.write(Data(
                        "[repair] harvest: stopped at a repeated heading (\(harvest.files.count) file(s) kept)\n".utf8))
                }
                if harvest.files.isEmpty {
                    FileHandle.standardError.write(Data("[repair] harvest: 0 labeled blocks from text:\n\(turn.text)\n".utf8))
                    write(record: RoundRecord(round: round, candidateRef: nil, receipt: .contractNotFollowed, grade: nil, elapsed: Int(Date().timeIntervalSince(start))), to: captureDir)
                    return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed)
                }
                for (path, content) in harvest.files {
                    try WorktreeDispatcher.writeFile(content, to: path, in: wt.url)
                }
                turn.mutations = harvest.files.map(\.path)
            }
            let validation = try WorktreeDispatcher.runValidation(packet.validationCommand, in: wt.url)
            let dispatchOutcome = try WorktreeDispatcher.finalize(
                wt, packet: packet, turnOutcome: turn, validation: validation, in: repo)

            let elapsed = Int(Date().timeIntervalSince(start))
            switch dispatchOutcome {
            case .candidate(let ref, _, _):
                let g = try grade(wt.url)
                write(record: RoundRecord(round: round, candidateRef: ref, receipt: nil, grade: g, elapsed: elapsed),
                      to: captureDir)
                if g.passed {
                    shouldDiscardWorktree = false
                    return .passed(ref: ref, grade: g, worktree: wt)
                }
                head = ref
                lastGrade = g
            case .receipt(let receipt):
                write(record: RoundRecord(round: round, candidateRef: nil, receipt: receipt, grade: nil, elapsed: elapsed),
                      to: captureDir)
                if case .validationFailed = receipt, let validation {
                    // Unlike the other receipts, this one carries real new evidence: the
                    // round's own candidate broke the import check differently than the
                    // one before it. Receipt.validationFailed itself only carries
                    // exit+digest (dropped at the pure WorktreeDispatch.verdict boundary),
                    // but the real ValidationResult -- with its full output -- is still
                    // in scope right here. Refresh lastGrade from it and let the existing
                    // round budget continue; head stays unchanged since no candidate was
                    // produced to advance to.
                    lastGrade = GradeResult(exit: validation.exit, output: validation.output)
                    continue
                }
                return .exhausted(lastGrade: lastGrade, receipt: receipt)
            }
        }
        return .exhausted(lastGrade: lastGrade, receipt: .repairExhausted)
    }

    private static func fileURL(_ path: String, in worktree: URL) -> URL {
        var url = worktree
        for component in path.split(separator: "/") {
            url = url.appendingPathComponent(String(component))
        }
        return url
    }

    private static func write(record: RoundRecord, to dir: URL?) {
        guard let dir else { return }
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: dir.appendingPathComponent("repair-round-\(record.round).json"))
        }
    }

    private static func writePacketCapture(packet: HandoffPacket, round: Int, to dir: URL?) {
        guard let dir else { return }
        if let data = try? JSONEncoder().encode(packet) {
            try? data.write(to: dir.appendingPathComponent("repair-packet-\(round).json"))
        }
    }
}

public enum RepairLoopError: Error, Sendable {
    case sessionExhausted(TurnStopReason)
    case packetInvalid([String])
}
