import Foundation
import Observation
import SwiftStarKit
import SwiftStarAppKit

/// The pool worker-turn loop, extracted from `AgentController` (P23).
///
/// Kept as its own extension for the same reason capture retention is: the
/// controller had grown to ~1,400 lines with at least ten responsibilities,
/// and this loop — queue drain, worktree preparation, watchdog, per-worker
/// event routing, validation, receipt folding — is self-contained around
/// `workerTurn` and `poolState`. P23 part 2 gives pool workers their own
/// context size, which lands here rather than in an already-overlong file.
///
/// Behaviour-preserving move: no logic changed, no signatures changed. The six
/// methods lost `private` because their callers now sit in another file, and
/// nothing was widened to `public`.
@MainActor
extension AgentController {
    // MARK: - P11 worker-turn loop (D4)

    /// Start the next queued worker's turn in the pooled engine (D4): send the
    /// `PoolPrompt` for worker N, open its outcome builder, and mark it running.
    func drainQueuedWorkers() {
        guard let (worker, packet) = PoolScheduler.nextWorker(poolState) else {
            injectPendingReceipts()
            return
        }
        // Prepare the worker's disposable worktree (P10 isolation): its file
        // mutations land here, never in the caller's tree.
        let repo = Self.resolveRepoRoot(from: settings.workspace)
        let worktree: WorktreeDispatcher.Worktree
        do {
            worktree = try WorktreeDispatcher.prepare(packet: packet, in: repo)
        } catch {
            let receipt = DispatchReceipt(worker: worker, ref: nil,
                reason: "worktree preparation failed", summary: "\(error)")
            poolState = PoolScheduler.apply(poolState, .workerFailed(worker, receipt))
            rollingDigest = RollingDigestReducer.record(rollingDigest, receipt: receipt)
            log("worker \(worker.rawValue): worktree prepare failed: \(error)")
            drainQueuedWorkers()
            return
        }
        poolState = PoolScheduler.apply(poolState, .workerStarted(worker))
        // P23: the worker's per-turn think comes from its packet's declared
        // sampling — the capture-integrity fix, since SamplingPolicy.think was
        // written, validated, asserted, and read by nothing at dispatch time
        // (ROADMAP:452) — gated on the advertised cap (D3). Its context is
        // clamped to [4096, parent] so a worker can never bypass admission (D8).
        let thinkDecision = TurnThinkPolicy.decide(
            requested: TurnThinkPolicy.effort(for: packet.sampling.think),
            family: AgentController.runningModelFamily(),
            capAdvertised: advertisedCaps.contains(TurnThinkPolicy.overrideCap))
        let effort: ThinkEffort?
        switch thinkDecision {
        case .useDefault: effort = nil
        case .override(let e): effort = e
        case .refused(let reason):
            log("worker \(worker.rawValue): think override refused: \(reason)")
            effort = nil
        }
        // Sent only when the cap is advertised: an engine that never claimed
        // the ctx key would treat the envelope's extra field as unknown and
        // run at the parent's context, which is a silent budget overrun.
        let workerCtx: Int? = advertisedCaps.contains(TurnThinkPolicy.overrideCap)
            ? WorkerContextPolicy.clamp(requested: settings.workerContextSize,
                                        parentContext: settings.contextSize)
            : nil
        // P24.1: the worker reads through the shared `.app` executor, whose read
        // tier is chosen from context size. Register the worker's own context
        // against its worktree root so it gets its tier, not the parent's — the
        // engine tiers per-worker too (`agent_read_default_lines` reads
        // `agent_worker_effective_ctx_size`). nil means the cap was not
        // advertised and the worker runs at the parent's context anyway.
        if let workerCtx {
            Self.hostToolExecutor.setContextSize(workerCtx, forRoot: worktree.url)
        }
        workerTurn.start(
            id: worker, packet: packet, worktree: worktree,
            outcomeBuilder: TurnOutcomeBuilder(
                model: settings.modelPath.lastPathComponent,
                build: buildSHA,
                task: packet.taskText,
                think: effort))
        if let pipe = process?.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(
                Data((PoolPrompt(worker: worker, text: packet.taskText,
                                 think: effort, contextSize: workerCtx).encode() + "\n").utf8))
        }
        armWorkerWatchdog(worker)
        log("worker \(worker.rawValue): turn started (worktree \(worktree.url.lastPathComponent))")
    }

    /// A worker turn ends on its `ready`; if that never arrives (engine wedged
    /// mid-turn) the scheduler's `running` slot is never freed and every later
    /// `/chat` and dispatch is refused "pool is busy" until a manual restart.
    /// The watchdog is the only bound on that — delivery is edge-triggered, so
    /// there is no poll left to notice.
    func armWorkerWatchdog(_ worker: WorkerId) {
        workerTurn.watchdog?.cancel()
        let gen = generation
        workerTurn.watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.workerTurnTimeoutSeconds))
            guard !Task.isCancelled, let self,
                  self.generation == gen, self.workerTurn.activeId == worker else { return }
            self.failActiveWorker(worker, reason: "worker turn timed out")
        }
    }

    /// Fold a wedged worker turn into a failure receipt and free the pool — the
    /// same bookkeeping `finishWorkerTurn` does, minus the outcome (there is no
    /// `ready`, so there is nothing to finalize).
    func failActiveWorker(_ worker: WorkerId, reason: String) {
        guard workerTurn.activeId == worker else { return }
        let isConsult = workerTurn.isConsult(worker)
        if let worktree = workerTurn.worktree {
            WorktreeDispatcher.discard(worktree, in: Self.resolveRepoRoot(from: settings.workspace))
        }
        workerTurn.clearActive()
        let receipt = DispatchReceipt(worker: worker, ref: nil, reason: reason, summary: reason)
        poolState = PoolScheduler.apply(poolState, .workerFailed(worker, receipt))
        if isConsult {
            workerTurn.removeConsult(worker)
            poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            transcript.appendSystem("→ chat failed: \(reason)")
        }
        log("worker \(worker.rawValue): \(reason)")
        drainQueuedWorkers()
    }

    /// Route one worker-tagged event through the worker's turn (D4): answer its
    /// tool requests (revision-checked against its packet's writableFiles), and
    /// finish the turn on its `ready`. `generation` is the wire generation this
    /// event was read under (threaded from `consumeWire`); item 3 (P22
    /// cleanup) made the tool executor and `finishWorkerTurn`'s validation
    /// genuinely async, so this — like `consumeWire` — re-checks it after
    /// every await before touching shared controller state.
    func handleWorkerEvent(worker: WorkerId, event: AgentEvent, generation: Int) async {
        workerTurn.outcomeBuilder?.apply(event)
        switch event {
        case .toolRequest(let idx, let name, let params):
            guard workerTurn.admitToolCall() else {
                let response = ToolCallbackResponder.budgetExceeded(idx: idx)
                writeToolResult(response)
                workerTurn.outcomeBuilder?.recordHostVerdict(
                    idx: idx, ok: false, mutations: [], exitStatus: nil,
                    outputDigest: nil, validationRan: false)
                rollingDigest = RollingDigestReducer.recordHostVerdict(
                    rollingDigest, mutations: [], exitStatus: nil, validationRan: false)
                return
            }
            let response = await ToolCallbackResponder.respond(
                idx: idx, name: name, params: params,
                workspace: workerTurn.worktree?.url ?? settings.workspace,
                shellAllowed: false,
                writableFiles: workerTurn.activePacket?.writableFiles,
                execute: Self.executeHostTool)
            guard generation == self.generation else { return }
            writeToolResult(response)
            workerTurn.outcomeBuilder?.recordHostVerdict(
                idx: idx, ok: response.ok, mutations: response.mutations,
                exitStatus: response.exitStatus, outputDigest: response.outputDigest,
                validationRan: response.validationRan)
            rollingDigest = RollingDigestReducer.recordHostVerdict(
                rollingDigest, mutations: response.mutations,
                exitStatus: response.exitStatus, validationRan: response.validationRan)
        case .toolRequestRefused(let idx, let reason):
            writeToolResult(ToolCallbackResponse(idx: idx, ok: false,
                s: ToolResultCondenser.condense(reason)))
        case .ready:
            if let builder = workerTurn.outcomeBuilder {
                let outcome = builder.finish()
                workerTurn.outcomeBuilder = nil
                await finishWorkerTurn(worker: worker, outcome: outcome, generation: generation)
            }
        default:
            break
        }
    }

    /// Fold a finished worker turn into a `DispatchReceipt`, record it in the
    /// rolling digest (D9) and the scheduler, and run the next worker (or inject
    /// the receipts back into the orchestrator when the queue empties, D4). The
    /// candidate-vs-receipt verdict is the pure `WorktreeDispatch.verdict`; the
    /// candidate *ref* (the worktree commit SHA) is produced by the P10
    /// `WorktreeDispatcher`, which the pooled path will reuse for the commit.
    func finishWorkerTurn(worker: WorkerId, outcome: TurnOutcome, generation: Int) async {
        workerTurn.watchdog?.cancel()
        let isConsult = workerTurn.isConsult(worker)
        let answerText: String? = isConsult ? outcome.text : nil
        let packet = workerTurn.activePacket ?? HandoffPacket(
            taskText: "", writableFiles: [], validationCommand: nil,
            baselines: [:], turnBudget: 0, toolCallBudget: 0)
        let receipt: DispatchReceipt
        if let worktree = workerTurn.worktree {
            let repo = Self.resolveRepoRoot(from: settings.workspace)
            let relativized = WorktreeDispatch.relativize(outcome: outcome, worktree: worktree.url)
            do {
                // Item 3 (P22 cleanup): async, off the MainActor — this used to
                // freeze the whole app's UI for as long as the validation
                // command ran. `finalize` itself stays sync (no subprocess).
                let validation = try await WorktreeDispatcher.runValidation(packet.validationCommand, in: worktree.url)
                let dispatchOutcome = try WorktreeDispatcher.finalize(
                    worktree, packet: packet, turnOutcome: relativized,
                    validation: validation, in: repo)
                switch dispatchOutcome {
                case .candidate(let ref, _, _):
                    receipt = DispatchReceipt(worker: worker, ref: ref, reason: nil,
                        summary: "candidate: \(relativized.mutations.count) mutation(s), \(relativized.generatedTokens) tokens",
                        answerText: answerText)
                case .receipt(let r):
                    receipt = DispatchReceipt(worker: worker, ref: nil,
                        reason: Self.receiptReason(r), summary: Self.receiptReason(r),
                        answerText: answerText)
                }
            } catch {
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: "infrastructure failure", summary: "\(error)",
                    answerText: answerText)
            }
            WorktreeDispatcher.discard(worktree, in: repo)
        } else {
            // No worktree (prepare failed earlier): fall back to the pure verdict.
            switch WorktreeDispatch.verdict(
                packet: packet, allowedMutations: outcome.mutations,
                turnOutcome: outcome, validation: nil) {
            case .candidate:
                receipt = DispatchReceipt(worker: worker, ref: nil, reason: nil,
                    summary: "candidate: \(outcome.mutations.count) mutation(s), \(outcome.generatedTokens) tokens",
                    answerText: answerText)
            case .receipt(let reason):
                receipt = DispatchReceipt(worker: worker, ref: nil,
                    reason: Self.receiptReason(reason), summary: Self.receiptReason(reason),
                    answerText: answerText)
            }
        }
        // Reentrancy guard (item 3): the worktree above is discarded either
        // way — no leak — but a restart during the `await` above (bumping
        // `generation`) already reset poolState/workerTurn/rollingDigest for a
        // brand-new session; folding this stale turn's receipt into that state
        // (or writing to the new session's wire) would corrupt it, so bail
        // once cleanup is done.
        guard generation == self.generation else { return }
        poolState = PoolScheduler.apply(poolState, .workerFinished(worker, receipt))
        // A consult runs read-only (writableFiles is empty by construction), so
        // its verdict is ALWAYS a refusal. Recording it would leave a phantom
        // "Worker N refused: noChanges" in the facts a later dispatch is planned
        // from — the digest gets implementer receipts only.
        if !isConsult {
            rollingDigest = RollingDigestReducer.record(rollingDigest, receipt: receipt)
        }
        workerTurn.clearActive()
        if isConsult {
            workerTurn.removeConsult(worker)
            // Surface the answer directly; never deliver a consult's receipt as
            // orchestrator prose — the answer IS the delivery. Clear the receipt
            // only when the send lands (at-least-once, matching
            // injectPendingReceipts): if the user started a turn mid-consult the
            // send is refused, and leaving the receipt pending lets the next
            // drain fold the answer in via `injectionPrompt()`.
            guard let answer = receipt.answerText.flatMap({ $0.isEmpty ? nil : $0 }) else {
                // `noChanges` is a write-dispatch verdict, not a response to a
                // read-only consultation. Never present it as the worker's
                // answer when the worker emitted no prose.
                poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
                transcript.appendSystem("→ chat failed: worker returned no answer")
                log("worker \(worker.rawValue): consult returned no answer")
                drainQueuedWorkers()
                return
            }
            let stats = ConsultedRowStats(
                generatedTokens: outcome.generatedTokens,
                decodeTPS: outcome.decodeTPS,
                ctxUsed: outcome.ctxUsed)
            if sendConsulted(answer, worker: worker, stats: stats) {
                poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            } else {
                transcript.append(.consulted(worker, answer, stats: stats))
            }
        }
        log("worker \(worker.rawValue): \(receipt.summary)")
        drainQueuedWorkers()
    }

    /// Inject any undelivered receipts back into the orchestrator as its next
    /// turn's prompt (D4): the orchestrator sees only the bounded receipts, not
    /// the worker transcripts. Consult workers never reach here — their answer
    /// is delivered directly in `finishWorkerTurn`.
    func injectPendingReceipts() {
        let receipts = poolState.pendingDelivery.values
            .sorted { $0.worker < $1.worker }
        guard !receipts.isEmpty else { return }
        let text = receipts.map { $0.injectionPrompt() }.joined(separator: "\n")
        // Send first, clear only on success — at-least-once delivery (a dropped
        // send must not silently lose the receipts).
        if send(text, asUser: false) {
            for worker in Array(poolState.pendingDelivery.keys) {
                poolState = PoolScheduler.apply(poolState, .receiptInjected(worker))
            }
        }
    }
}
