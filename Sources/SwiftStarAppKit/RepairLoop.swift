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
                var harvest = LabeledBlockParser.parse(turn.text, writableFiles: packet.writableFiles)
                // Two-turn emission protocol. Measured 2026-08-25: Mellum reasons
                // *or* emits, never both in one turn. Allowed prose, it produces a
                // correct diagnosis and then stops at eos exactly where the file
                // should start (captures 20260825-160310, -164557). Forbidden prose,
                // it emits a flawless block whose body is a byte-identical copy of
                // the broken file already in context (capture 20260825-163139).
                //
                // A turn that reasoned and stopped is not a contract failure — it is
                // an unfinished turn. `runPhase` re-prompts the SAME pooled worker,
                // whose session carries the prior assistant turn (PoolOrchestrator
                // holds one engine session per WorkerId and never resets it between
                // calls), so the follow-up is a continuation: the model conditions on
                // its own diagnosis rather than on a re-injected paraphrase of it.
                if harvest.files.isEmpty, let emissionFollowUp,
                   !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let followUpPacket = HandoffPacket(
                        taskText: emissionFollowUp,
                        writableFiles: packet.writableFiles,
                        validationCommand: packet.validationCommand,
                        selfTestCommand: packet.selfTestCommand,
                        baselines: packet.baselines,
                        turnBudget: packet.turnBudget,
                        toolCallBudget: packet.toolCallBudget,
                        textContract: true,
                        facts: packet.facts,
                        redacts: packet.redacts,
                        role: packet.role,
                        sampling: packet.sampling)
                    let followUp = try runPhase(followUpPacket, wt.url, capture)
                    if followUp.stopReason == .limit || followUp.stopReason == .contextFull {
                        throw RepairLoopError.sessionExhausted(followUp.stopReason)
                    }
                    // The emitting turn replaces the reasoning turn as the round's
                    // outcome: its text is what the host harvests, and its token
                    // count is what the budget check must see.
                    turn = followUp
                    harvest = LabeledBlockParser.parse(followUp.text, writableFiles: packet.writableFiles)
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
