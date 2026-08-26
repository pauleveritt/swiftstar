import Foundation
import SwiftStarKit

/// What the packet builder needs to assemble one authored repair packet. The
/// builder is worktree-independent: it renders the directive, contract, and
/// writable note only; `RepairLoop` appends `MachineEvidence` afterward (D5/D6).
public struct RepairContext: Sendable {
    public let failedRef: String
    public let grade: GradeResult
    public let round: Int
    /// Which of the run's writable files do not exist at `failedRef`, computed
    /// by `RepairLoop` from the repo directly (D-fix, 2026-08-26): a packet
    /// builder that unconditionally asserts "exactly one file is wrong" while
    /// this list holds 2+ paths is asserting something its own evidence will
    /// then contradict -- the overnight matrix's dominant harness defect
    /// (39/40 Mellum cells). Defaults to `[]` for callers that don't need it.
    public let missingWritableFiles: [String]
    public init(failedRef: String, grade: GradeResult, round: Int, missingWritableFiles: [String] = []) {
        self.failedRef = failedRef
        self.grade = grade
        self.round = round
        self.missingWritableFiles = missingWritableFiles
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

    /// The furthest repair actually got before running out of budget: its last
    /// committed candidate, that candidate's grade, and a live worktree checked
    /// out at it. Rounds are cumulative (see the `.validationFailed` path
    /// below), so the last candidate contains every prior round's work and is
    /// the most complete tree repair produced.
    ///
    /// Exists because exhaustion previously threw this away: the caller kept
    /// grading the *pre-repair* tree, so `code.md`, the qualitative verdict and
    /// the reported acceptance exit all described a tree that predated every
    /// repair round -- in one measured case faulting the run for what was
    /// missing from a `models.py` repair had itself written (2026-08-26,
    /// 21 of 21 affected cells). The worktree is handed over live on the same
    /// ownership contract as `.passed`: the caller discards it.
    public struct BestReached: Sendable {
        public let ref: String
        public let grade: GradeResult
        public let worktree: WorktreeDispatcher.Worktree
        public init(ref: String, grade: GradeResult, worktree: WorktreeDispatcher.Worktree) {
            self.ref = ref
            self.grade = grade
            self.worktree = worktree
        }
    }

    public enum Outcome: Sendable {
        case passed(ref: String, grade: GradeResult, worktree: WorktreeDispatcher.Worktree)
        case exhausted(lastGrade: GradeResult?, receipt: Receipt, best: BestReached?)
    }

    public static func run(
        repo: URL, failedRef: String, initialGrade: GradeResult,
        writableFiles: [String] = [],
        packetBuilder: (RepairContext) throws -> HandoffPacket,
        runPhase: (HandoffPacket, URL, FileHandle?) throws -> TurnOutcome,
        grade: (URL) throws -> GradeResult,
        capture: FileHandle? = nil, captureDir: URL? = nil,
        maxCandidateRounds: Int = 2, outputCap: Int = 8192, fileCap: Int = 16384,
        emissionFollowUp: String? = nil
    ) throws -> Outcome {
        var head = failedRef
        var lastGrade = initialGrade
        // The furthest repair has got so far. Its worktree is deliberately kept
        // alive between rounds (a superseded one is discarded the moment a newer
        // candidate replaces it), so exhaustion can hand the caller the most
        // complete tree repair produced instead of silently dropping it.
        var best: BestReached?

        for round in 1...maxCandidateRounds {
            let start = Date()
            // Checked against the repo's object store directly, via `head` --
            // no worktree exists yet this round, and creating one just to ask
            // "does this path exist" would be strictly more expensive than the
            // git plumbing below for what is otherwise a no-op until a builder
            // reads `missingWritableFiles`.
            let missing = try missingFiles(writableFiles, at: head, in: repo)
            let ctx = RepairContext(failedRef: head, grade: lastGrade, round: round, missingWritableFiles: missing)
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
                        return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed, best: best)
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
            // V7: strip everything that varies between two runs of the same
            // input (worktree UUIDs, pytest durations) BEFORE capping, so the
            // dispatched packet is byte-stable across runs at the same seed.
            let stableOutput = MachineEvidence.normalizingEphemera(lastGrade.output)
            let (out, outNote) = MachineEvidence.cappedFailureOutput(stableOutput, cap: outputCap)
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
                    return .exhausted(lastGrade: lastGrade, receipt: .contractNotFollowed, best: best)
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
                    if let previous = best { WorktreeDispatcher.discard(previous.worktree, in: repo) }
                    return .passed(ref: ref, grade: g, worktree: wt)
                }
                if let previous = best { WorktreeDispatcher.discard(previous.worktree, in: repo) }
                shouldDiscardWorktree = false
                best = BestReached(ref: ref, grade: g, worktree: wt)
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
                    // round budget continue.
                    //
                    // `head` MUST advance to include this round's write (D-fix,
                    // 2026-08-26): `finalize` never commits on the `.receipt` path
                    // (only `.candidate` does), so leaving `head` unchanged meant the
                    // next round's worktree was re-prepared from the SAME base --
                    // discarding this round's file the instant its own worktree is
                    // torn down below. "N rounds" collapsed into N independent
                    // single-shot attempts against the same starting point (2026-08-26
                    // overnight matrix, 18/40 Mellum cells; two files -- app.py then
                    // models.py -- verified to import cleanly TOGETHER but never
                    // survived to be applied together). `commitForRepair` already
                    // exists for exactly this: P12.8 uses it to seed RepairLoop's
                    // first `failedRef` from a phase that failed validation; this
                    // reuses it every subsequent round instead of only the first. When
                    // the round wrote nothing, `commitForRepair` -> `commitDiff` finds
                    // no staged changes and returns the parent SHA unchanged -- head
                    // correctly stays put in that degenerate case, no extra check needed.
                    head = try WorktreeDispatcher.commitForRepair(wt, packet: packet, in: repo)
                    lastGrade = GradeResult(exit: validation.exit, output: validation.output)
                    continue
                }
                return .exhausted(lastGrade: lastGrade, receipt: receipt, best: best)
            }
        }
        return .exhausted(lastGrade: lastGrade, receipt: .repairExhausted, best: best)
    }

    /// Which of `files` are absent at `ref` in `repo`, checked directly
    /// against the object store (`git cat-file -e`) rather than a worktree,
    /// since none exists yet for the round this is called from.
    private static func missingFiles(_ files: [String], at ref: String, in repo: URL) throws -> [String] {
        var missing: [String] = []
        for path in files {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", repo.path, "cat-file", "-e", "\(ref):\(path)"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                missing.append(path)
            }
        }
        return missing
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
