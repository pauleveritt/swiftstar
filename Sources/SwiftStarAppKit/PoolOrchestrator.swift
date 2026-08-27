import Foundation
import SwiftStarKit
import Darwin

/// The headless orchestrator (P11 addendum D7): the loop that was inside
/// `AgentController`, extracted so the harness can drive a pooled engine without
/// SwiftUI. Spawns `ds4-agent --subagent-pool 3` (workers 1 and 2, v1) and runs
/// one phase at a time in a worktree.
public final class PoolOrchestrator {
    private let process: Process
    private let stdin: FileHandle
    private let stdoutFD: Int32
    private let model: String
    /// Item 4 (P22 cleanup): the host-tool execution itself now lives once, in
    /// `HostToolExecutor`, shared with `AgentController` — a fresh instance
    /// per phase (the `.pool` policy's per-turn read cache and vetted-commands
    /// allowlist), mirroring the old `readCache.removeAll()` +
    /// `vettedCommands = [...]` reset at the top of `runPhase`.
    private var hostToolExecutor = HostToolExecutor(policy: .pool(vettedCommands: []))

    /// `workers` (P12.5): the pool size passed to `--subagent-pool`. Defaults
    /// to 3 (orchestrator + workers 1/2 — implement/repair), preserving every
    /// existing call site's behavior unchanged. A caller that needs an extra
    /// independent KV-cache session (e.g. a decompose dispatch on its own
    /// worker id, so it cannot collide with another role's session) passes a
    /// larger value.
    public init(settings: AgentSettings, workers: Int = 3) throws {
        self.model = settings.modelPath.lastPathComponent
        let binary = AgentCommand.binaryPath(settings: settings)
        let process = Process()
        process.executableURL = binary
        process.arguments = PoolEngine.argv(settings: settings, workers: workers)
        process.currentDirectoryURL = settings.engineDir
        process.environment = ProcessInfo.processInfo.environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError  // inherit: engine stderr goes to the harness log
        // The engine chdir's to `--workspace`; Metal shaders load cwd-relative
        // and would not resolve there. Point each at its absolute path (the same
        // override `swiftstar-drive` uses), so Metal resolves regardless of cwd.
        var engineEnv = ProcessInfo.processInfo.environment
        let metalDir = settings.engineDir.appendingPathComponent("metal", isDirectory: true)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: metalDir.path) {
            for name in names where name.hasSuffix(".metal") {
                let stem = String(name.dropLast(".metal".count))
                engineEnv["DS4_METAL_\(stem.uppercased())_SOURCE"] = metalDir.appendingPathComponent(name).path
            }
        }
        process.environment = engineEnv
        try process.run()
        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting
        self.stdoutFD = stdoutPipe.fileHandleForReading.fileDescriptor
    }

    /// Run one phase: send the `PoolPrompt` for `worker`, drain worker-tagged
    /// events, answer tool requests (revision-checked against `packet.writableFiles`
    /// and confined to `worktree`), and return the turn's `TurnOutcome`
    /// relativized against the worktree. The worker codes blind
    /// (`shellAllowed: false`); validation is the harness's job.
    public func runPhase(worker: WorkerId, packet: HandoffPacket, worktree: URL,
                         capture: FileHandle? = nil) throws -> TurnOutcome {
        var builder = TurnOutcomeBuilder(
            model: model, build: "pooled", sampler: "engine-defaults", task: packet.taskText)
        var toolCallCount = 0
        var lastRefusedSignature: String?
        var refusedStreak = 0
        let vettedCommands = [packet.validationCommand, packet.selfTestCommand]
            .compactMap { $0 }.filter { !$0.isEmpty }
        hostToolExecutor = HostToolExecutor(policy: .pool(vettedCommands: vettedCommands))
        let prompt = PoolPrompt(worker: worker, text: packet.taskText).encode() + "\n"
        stdin.write(Data(prompt.utf8))

        var parser = PoolWireParser()
        var result: TurnOutcome?
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let turnTimeout = Double(ProcessInfo.processInfo.environment["AGENTTEST_TURN_TIMEOUT"] ?? "1800") ?? 1800
        let deadline = Date().addingTimeInterval(turnTimeout)

        loop: while Date() < deadline {
            var pfd = pollfd(fd: stdoutFD, events: Int16(POLLIN), revents: 0)
            let pr = Darwin.poll(&pfd, 1, 1000)
            guard pr >= 0 else { continue }
            guard (pfd.revents & Int16(POLLIN)) != 0 || (pfd.revents & Int16(POLLHUP)) != 0 else { continue }
            let n = Darwin.read(stdoutFD, &chunk, chunk.count)
            if n <= 0 { break loop }
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let capture { capture.write(Data((line + "\n").utf8)) }
                guard let poolEvent = parser.feed(line), poolEvent.worker == worker else { continue }
                let event = poolEvent.event
                if ProcessInfo.processInfo.environment["AGENTTEST_DEBUG"] != nil {
                    switch event {
                    case .ready(_, let stop, let gen, let ctx): FileHandle.standardError.write(Data("[orch] ready stop=\(stop ?? "nil") gen=\(gen.map(String.init) ?? "nil") ctx=\(ctx.map(String.init) ?? "nil")\n".utf8))
                    case .toolRequest(_, let name, _): FileHandle.standardError.write(Data("[orch] tool_request \(name)\n".utf8))
                    case .text(let s): FileHandle.standardError.write(Data("[orch] text \(s.prefix(60))\n".utf8))
                    default: break
                    }
                }
                builder.apply(event)
                switch event {
                case .toolRequest(let idx, let name, let params):
                    toolCallCount += 1
                    if toolCallCount > packet.toolCallBudget {
                        // Enforce the budget during the turn (D8): refuse the call,
                        // don't execute it, so a thrashing worker is cut off instead
                        // of filling the context.
                        let r = ToolCallbackResponse(idx: idx, ok: false,
                            s: ToolResultCondenser.condense("tool budget exceeded"))
                        stdin.write(Data((ToolCallbackResponder.resultLine(r) + "\n").utf8))
                        continue
                    }
                    var response = ToolCallbackResponder.respond(
                        idx: idx, name: name, params: params,
                        workspace: worktree, shellAllowed: true,  // bash is vetted in the executor
                        writableFiles: packet.writableFiles,
                        execute: hostToolExecutor.execute)
                    // Repeat-refusal guard: a worker that retries an identical
                    // refused call gets a hint after the third repeat so it
                    // breaks the loop instead of burning the tool budget.
                    if !response.ok {
                        let signature = name + "|"
                            + params.map { "\($0.name)=\($0.value)" }.joined(separator: "\u{1e}")
                        if signature == lastRefusedSignature {
                            refusedStreak += 1
                            if refusedStreak >= 3 {
                                let hint = "(hint: you have repeated this identical request \(refusedStreak) times and it was refused each time; it will not be allowed. Run one of the vetted commands exactly as given, or edit the code instead.)"
                                response = ToolCallbackResponse(
                                    idx: response.idx, ok: false, s: response.s + " " + hint,
                                    mutations: response.mutations, exitStatus: response.exitStatus,
                                    outputDigest: response.outputDigest, validationRan: response.validationRan)
                            }
                        } else {
                            lastRefusedSignature = signature
                            refusedStreak = 1
                        }
                    } else {
                        lastRefusedSignature = nil
                        refusedStreak = 0
                    }
                    stdin.write(Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
                    builder.recordHostVerdict(
                        idx: idx, ok: response.ok, mutations: response.mutations,
                        exitStatus: response.exitStatus, outputDigest: response.outputDigest,
                        validationRan: response.validationRan)
                case .toolRequestRefused(let idx, let reason):
                    let r = ToolCallbackResponse(idx: idx, ok: false, s: ToolResultCondenser.condense(reason))
                    stdin.write(Data((ToolCallbackResponder.resultLine(r) + "\n").utf8))
                case .ready:
                    // v1: the first worker-N ready is the turn-end (the startup
                    // ready is worker 0, which we filter out above).
                    result = WorktreeDispatch.relativize(outcome: builder.finish(), worktree: worktree)
                    break loop
                default:
                    break
                }
            }
        }
        guard let result else {
            throw PoolOrchestratorError.turnDidNotEnd
        }
        return result
    }

    public func stop() {
        try? stdin.close()
        process.terminate()
    }

}

public enum PoolOrchestratorError: Error, Sendable {
    case turnDidNotEnd
}
