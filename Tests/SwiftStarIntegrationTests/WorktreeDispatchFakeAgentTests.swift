import Testing
import Foundation
import SwiftStarKit
import SwiftStarAppKit

/// A real fake-agent-through-dispatch round trip: the fake agent (host-tools
/// mode) emits a `tool_request`, the attempt closure "executes" the write into
/// the worktree and answers a `tool_result`, and `WorktreeDispatcher.dispatch`
/// commits the candidate. This closes the gap the P10 integration left (it
/// stopped at a scripted attempt closure).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct WorktreeDispatchFakeAgentTests {

    private func fixtureRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("p10-fakeagent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try git(dir, ["init", "-q"])
        try git(dir, ["config", "user.email", "test@example.com"])
        try git(dir, ["config", "user.name", "Test"])
        try "seed".write(toFile: dir.appendingPathComponent("seed.txt").path, atomically: true, encoding: .utf8)
        try git(dir, ["add", "seed.txt"])
        try git(dir, ["commit", "-q", "-m", "seed"])
        return dir
    }

    private func git(_ dir: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    private func buildFakeAgent(settings: AgentSettings) throws -> (URL, [String]) {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("golden-tools.ndjson"))
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: true)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p10-fakeagent-src-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        return (binary, argv)
    }

    @Test func fakeAgentToolRequestCommitsCandidate() throws {
        let repo = try fixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let workspace = URL(fileURLWithPath: "/tmp/unused")  // replaced by the dispatcher's worktree
        let settings = AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 32768,
            workspace: workspace,
            shellAllowed: false)

        let packet = HandoffPacket(
            taskText: "write seed.txt",
            writableFiles: ["seed.txt"],
            validationCommand: nil,
            baselines: [:],
            turnBudget: 10_000,
            toolCallBudget: 8)

        let outcome = try WorktreeDispatcher.dispatch(packet: packet, in: repo) { enriched, worktree in
            let (binary, argv) = try self.buildFakeAgent(settings: settings)
            let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: ["FAKE_SPEED": "0"])
            defer { fake.process.terminate(); fake.process.waitUntilExit() }

            FakeAgentHarness.writePrompt(fake, "write seed.txt")

            var parser = AgentWireParser()
            var sawRequest = false
            var mutations: Set<String> = []
            var wroteSeed = false
            var done = false
            let reader = PollingLineReader(fd: fake.stdout.fileHandleForReading.fileDescriptor)
            let deadline = Date().addingTimeInterval(30)
            while Date() < deadline && !done {
                guard let line = try? reader.nextLine(timeout: deadline.timeIntervalSinceNow),
                      let event = parser.feed(line) else { break }
                switch event {
                    case .toolRequest(let idx, let name, let params):
                        sawRequest = true
                        if name == "write" || name == "edit" {
                            // "Execute" the mutation into the worktree (the host's job).
                            if let path = params.first(where: { $0.name == "path" })?.value {
                                mutations.insert(path)
                                if name == "write",
                                   let content = params.first(where: { $0.name == "content" })?.value {
                                    try content.write(toFile: worktree.appendingPathComponent(path).path,
                                                      atomically: true, encoding: .utf8)
                                    if path == "seed.txt" { wroteSeed = true }
                                } else {
                                    // edit: write a placeholder that keeps the file changed.
                                    try ("edited\n").write(toFile: worktree.appendingPathComponent(path).path,
                                                            atomically: true, encoding: .utf8)
                                }
                            }
                        }
                        let answer = #"{"t":"tool_result","idx":\#(idx),"ok":true,"s":"done"}"#
                        fake.stdin.fileHandleForWriting.write(Data((answer + "\n").utf8))
                    case .ready(_, let stopReason, _, _):
                        if wroteSeed && stopReason != nil { done = true }
                    default:
                        break
                }
            }
            #expect(sawRequest)
            var outcome = TurnOutcome(
                model: "m", build: "b", sampler: "s", task: packet.taskText,
                generatedTokens: 0, ctxUsed: 0, stopReason: .eos, toolCalls: [])
            outcome.mutations = Array(mutations)
            outcome.validationRan = false
            return outcome
        }

        guard case .candidate(let ref, let carried, let baselines) = outcome else {
            Issue.record("expected a candidate, got \(outcome)")
            return
        }
        #expect(carried.mutations.contains("seed.txt"))
        #expect(ref.hasPrefix("refs/swiftstar/candidates/"))
        #expect(!baselines.isEmpty)  // F6: the enriched packet carried the baseline
        // The ref must resolve to a commit whose seed.txt was actually mutated
        // (the fake agent's write/edit tool_requests went through the host).
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "show", "\(ref):seed.txt"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        let content = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        #expect(content != "seed", "seed.txt should have been mutated by the attempt")
    }
}
