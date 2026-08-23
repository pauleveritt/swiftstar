import Foundation
import SwiftStarKit
import Darwin

/// The headless orchestrator (P11 addendum D7): the loop that was inside
/// `AgentController`, extracted so the harness can drive a pooled engine without
/// SwiftUI. Spawns `ds4-agent --subagent-pool 2` (one worker slot, v1) and runs
/// one phase at a time in a worktree.
public final class PoolOrchestrator {
    private let process: Process
    private let stdin: FileHandle
    private let stdoutFD: Int32
    private let model: String

    public init(settings: AgentSettings) throws {
        self.model = settings.modelPath.lastPathComponent
        let binary = AgentCommand.binaryPath(settings: settings)
        let process = Process()
        process.executableURL = binary
        process.arguments = PoolEngine.argv(settings: settings, workers: 2)
        process.currentDirectoryURL = settings.engineDir
        process.environment = ProcessInfo.processInfo.environment
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
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
    public func runPhase(worker: WorkerId, packet: HandoffPacket, worktree: URL) throws -> TurnOutcome {
        var builder = TurnOutcomeBuilder(
            model: model, build: "pooled", sampler: "engine-defaults", task: packet.taskText)
        let prompt = PoolPrompt(worker: worker, text: packet.taskText).encode() + "\n"
        stdin.write(Data(prompt.utf8))

        var parser = PoolWireParser()
        var result: TurnOutcome?
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(600)

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
                guard let poolEvent = parser.feed(line), poolEvent.worker == worker else { continue }
                let event = poolEvent.event
                builder.apply(event)
                switch event {
                case .toolRequest(let idx, let name, let params):
                    let response = ToolCallbackResponder.respond(
                        idx: idx, name: name, params: params,
                        workspace: worktree, shellAllowed: false,
                        writableFiles: packet.writableFiles,
                        execute: Self.executeHostTool)
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

    /// The host's file-tool executor, confined to the consent-cleared
    /// `resolvedPath` (already inside `worktree`). No shell — the worker codes
    /// blind; the harness runs validation.
    private static func executeHostTool(_ request: ToolExecutionRequest) -> ToolExecutionResult {
        switch request.name {
        case "read", "more":
            guard let path = request.resolvedPath,
                  let data = FileManager.default.contents(atPath: path),
                  let text = String(data: data, encoding: .utf8) else {
                return ToolExecutionResult(ok: false, text: "error: could not read")
            }
            return ToolExecutionResult(ok: true, text: text)
        case "list":
            guard let path = request.resolvedPath else { return ToolExecutionResult(ok: false, text: "error: no path") }
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: path)
                return ToolExecutionResult(ok: true, text: entries.sorted().joined(separator: "\n"))
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }
        case "search":
            guard let path = request.resolvedPath else { return ToolExecutionResult(ok: false, text: "error: no path") }
            let query = request.params.first(where: { $0.name == "query" })?.value ?? ""
            let matches = Self.searchRecursive(root: path, query: query, maxResults: 50)
            return ToolExecutionResult(ok: true, text: matches.isEmpty ? "No matches\n" : matches.joined(separator: "\n"))
        case "write":
            guard let path = request.resolvedPath else { return ToolExecutionResult(ok: false, text: "error: no path") }
            let content = request.params.first(where: { $0.name == "content" })?.value ?? ""
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return ToolExecutionResult(ok: true, text: "wrote \(path)", mutations: [path])
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }
        case "edit":
            guard let path = request.resolvedPath else { return ToolExecutionResult(ok: false, text: "error: no path") }
            let old = request.params.first(where: { $0.name == "old" })?.value ?? ""
            let new = request.params.first(where: { $0.name == "new" })?.value ?? ""
            guard !old.isEmpty else { return ToolExecutionResult(ok: false, text: "error: edit requires non-empty old text") }
            guard let data = FileManager.default.contents(atPath: path),
                  var text = String(data: data, encoding: .utf8) else {
                return ToolExecutionResult(ok: false, text: "error: could not read \(path)")
            }
            guard let range = text.range(of: old) else {
                return ToolExecutionResult(ok: false, text: "error: old text not found in \(path)")
            }
            text.replaceSubrange(range, with: new)
            do {
                try text.write(toFile: path, atomically: true, encoding: .utf8)
                return ToolExecutionResult(ok: true, text: "edited \(path)", mutations: [path])
            } catch {
                return ToolExecutionResult(ok: false, text: "error: \(error.localizedDescription)")
            }
        default:
            return ToolExecutionResult(ok: false, text: "error: unknown tool \(request.name)")
        }
    }

    private static func searchRecursive(root: String, query: String, maxResults: Int) -> [String] {
        guard !query.isEmpty else { return [] }
        let fm = FileManager.default
        var results: [String] = []
        let enumerator = fm.enumerator(atPath: root)
        while let entry = enumerator?.nextObject() as? String {
            if results.count >= maxResults { break }
            let full = (root as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            guard let data = fm.contents(atPath: full), let text = String(data: data, encoding: .utf8) else { continue }
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains(query) {
                if results.count >= maxResults { break }
                results.append("\(entry):\(i + 1):\(line)")
            }
        }
        return results
    }
}

public enum PoolOrchestratorError: Error, Sendable {
    case turnDidNotEnd
}
