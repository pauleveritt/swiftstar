import Testing
import Foundation
import Darwin
import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FakeHostToolsIntegrationTests {

    // MARK: - settings + argv

    /// A deterministic skills dir (built per call) whose SKILL.md content is
    /// fixed, so `SuperpowersBootstrap.build` renders the same index text
    /// regardless of the temp path. Mirrors the app's bootstrap path (P8 D1).
    private func fixtureSkillsDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-fake-skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let skills: [(String, String)] = [
            ("zebra", "Use when sorting animals"),
            ("apple", "Use when craving fruit"),
        ]
        for (dir, desc) in skills {
            let d = tmp.appendingPathComponent(dir)
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let md = """
            ---
            name: \(dir)
            description: \(desc)
            ---

            # \(dir)
            """
            try md.write(to: d.appendingPathComponent("SKILL.md"),
                         atomically: true, encoding: .utf8)
        }
        return tmp
    }

    private func makeSettings(workspace: URL, shellAllowed: Bool = true) throws -> AgentSettings {
        let bootstrap = SuperpowersBootstrap.build(skillsDir: try fixtureSkillsDir())
        return AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 32768,
            workspace: workspace,
            shellAllowed: shellAllowed,
            systemPrompt: bootstrap.indexPrompt
        )
    }

    // MARK: - build helpers (reuse FakeAgentHarness for both agent and app)

    private func buildAgent(fixture: String, settings: AgentSettings) throws -> (URL, [String]) {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("\(fixture).ndjson"))
        var argv = AgentCommand.argv(settings: settings)
        argv.append("--host-tools")  // host mode: the app owns the tools
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv, hostTools: true)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p9-fake-agent-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        return (binary, argv)
    }

    private func buildApp(answers: [String: String]) throws -> URL {
        let source = FakeAppSource.generate(answers: answers)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p9-fake-app-\(UUID().uuidString)", isDirectory: true)
        return try FakeAgentHarness.compileFake(source: source, into: work)
    }

    /// Counts the tool blocks (`finish` events) in a capture — the number of
    /// `tool_request` lines the host-tools fake agent will emit per turn.
    private func countToolBlocks(_ data: Data) -> Int {
        var n = 0
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.contains("\"phase\":\"finish\"") { n += 1 }
        }
        return n
    }

    // MARK: - blocking stdin/stdout line readers (raw fd; stdio buffering
    // would hide a result written right after the request's newline)

    /// Blocking read of one line from `fd`, with a deadline. Returns nil on
    /// EOF or timeout.
    private func readLine(fd: Int32, timeout: TimeInterval) throws -> String? {
        var line = [UInt8]()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 1000) > 0 else { continue }
            guard (p.revents & Int16(POLLIN)) != 0 else { continue }
            var b: UInt8 = 0
            let n = Darwin.read(fd, &b, 1)
            if n <= 0 { return line.isEmpty ? nil : String(decoding: line, as: UTF8.self) }
            if b == 0x0A { return String(decoding: line, as: UTF8.self) }
            line.append(b)
        }
        return nil
    }

    /// Synchronous round trip: reads the agent's stdout line by line, feeding
    /// the parser; on a `tool_request` it forwards the line to the fake app's
    /// stdin and relays the app's `tool_result` back to the agent's stdin
    /// before the agent continues. The protocol is strictly request→result
    /// (the agent blocks per request), so a single-threaded pump cannot
    /// deadlock: the agent emits one request, blocks; we forward it, read the
    /// one result, relay it; the agent unblocks and emits the next events.
    private func runRoundTrip(agent: FakeAgentProcess, app: FakeAgentProcess,
                              prompt: String, nRequests: Int,
                              timeout: TimeInterval = 30) throws -> [AgentEvent] {
        FakeAgentHarness.writePrompt(agent, prompt)
        var parser = AgentWireParser()
        var events: [AgentEvent] = []
        let agentFD = agent.stdout.fileHandleForReading.fileDescriptor
        let appFD = app.stdout.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var requestCount = 0
        while Date() < deadline {
            var p = pollfd(fd: agentFD, events: Int16(POLLIN), revents: 0)
            guard poll(&p, 1, 1000) > 0 else { continue }
            guard (p.revents & Int16(POLLIN)) != 0 else { continue }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(agentFD, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let event = parser.feed(line) {
                    events.append(event)
                    if case .toolRequest = event {
                        requestCount += 1
                        // Forward the request to the app; relay the result back.
                        app.stdin.fileHandleForWriting.write(Data((line + "\n").utf8))
                        if let result = try readLine(fd: appFD, timeout: 10) {
                            agent.stdin.fileHandleForWriting.write(Data((result + "\n").utf8))
                        }
                    }
                    // Completion: all requests emitted AND the turn-end ready
                    // (eos) that follows the last request's trailing text.
                    if requestCount >= nRequests,
                       case .ready(_, let stopReason, _, _) = event,
                       stopReason == "eos" {
                        return events
                    }
                }
            }
        }
        throw FakeAgentHarnessError.timeout(eventCount: events.count)
    }

    private func spawn(_ binary: URL, _ argv: [String], _ env: [String: String]) throws -> FakeAgentProcess {
        try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: env)
    }

    // MARK: - the round trip

    @Test func roundTripFakeAgentAndFakeApp() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p9-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: true)
        let (agentBinary, agentArgv) = try buildAgent(fixture: "golden-tools", settings: settings)

        // The golden-tools capture exercises write/read/edit/list/bash; the
        // fake app answers each by name (canned). The answers' content is
        // irrelevant to the round trip — the fake agent consumes the result and
        // continues — but keying by name exercises the lookup path.
        let answers = [
            "write": "wrote seed.txt",
            "read": "read seed.txt",
            "edit": "edited seed.txt",
            "list": "listed .",
            "bash": "ran echo hello-world",
        ]
        let appBinary = try buildApp(answers: answers)

        let capture = try Data(contentsOf: FakeAgentHarness.fixture("golden-tools.ndjson"))
        let nRequests = countToolBlocks(capture)

        let agent = try spawn(agentBinary, agentArgv, ["FAKE_SPEED": "0"])
        let app = try spawn(appBinary, [], ["FAKE_SPEED": "0"])
        defer {
            agent.process.terminate(); app.process.terminate()
            agent.process.waitUntilExit(); app.process.waitUntilExit()
        }

        let events = try runRoundTrip(agent: agent, app: app,
                                      prompt: "run your tools", nRequests: nRequests)

        // The agent emitted one tool_request per tool block (no `tool` phases —
        // the host-tools mode replaces them with requests).
        let reqCount = events.filter {
            if case .toolRequest = $0 { return true } else { return false }
        }.count
        #expect(reqCount == nRequests, "fake agent emitted \(reqCount) requests, expected \(nRequests)")
        #expect(!events.contains {
            if case .tool = $0 { return true } else { return false }
        }, "host-tools mode must not emit the observation-only `tool` phase stream")
        // The agent continued past every request: it reached a turn-end ready.
        #expect(events.contains {
            if case .ready(_, let stopReason, _, _) = $0, stopReason == "eos" { return true } else { return false }
        }, "fake agent must continue to the turn-end ready after the round trip")
    }

    @Test func roundTripRefusedResultsDoNotHang() throws {
        // The spec's refused-result path: when the app answers every request
        // with ok:false (empty answers → every name unkeyed → the fixed
        // refusal), the agent must still consume the result and continue to
        // the turn-end ready — it must not hang waiting for a result it will
        // never get a "success" for. `ok:false` is a result, not an absence.
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p9-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: true)
        let (agentBinary, agentArgv) = try buildAgent(fixture: "golden-tools", settings: settings)
        let appBinary = try buildApp(answers: [:])  // refuse everything

        let capture = try Data(contentsOf: FakeAgentHarness.fixture("golden-tools.ndjson"))
        let nRequests = countToolBlocks(capture)

        let agent = try spawn(agentBinary, agentArgv, ["FAKE_SPEED": "0"])
        let app = try spawn(appBinary, [], ["FAKE_SPEED": "0"])
        defer {
            agent.process.terminate(); app.process.terminate()
            agent.process.waitUntilExit(); app.process.waitUntilExit()
        }

        let events = try runRoundTrip(agent: agent, app: app,
                                      prompt: "run your tools", nRequests: nRequests)
        let reqCount = events.filter {
            if case .toolRequest = $0 { return true } else { return false }
        }.count
        #expect(reqCount == nRequests)
        #expect(events.contains {
            if case .ready(_, let stopReason, _, _) = $0, stopReason == "eos" { return true } else { return false }
        }, "agent must reach the turn-end ready even when every result is refused")
    }

    // MARK: - the fake app: canned answers + fixed refusal

    @Test func fakeAppAnswersKeyedName() throws {
        let appBinary = try buildApp(answers: ["write": "wrote it"])
        let app = try spawn(appBinary, [], ["FAKE_SPEED": "0"])
        defer { app.process.terminate(); app.process.waitUntilExit() }

        let request = #"{"t":"tool_request","idx":0,"name":"write","params":[],"ts":0}"#
        app.stdin.fileHandleForWriting.write(Data((request + "\n").utf8))

        let line = try readLine(fd: app.stdout.fileHandleForReading.fileDescriptor, timeout: 10)
        guard let line = line, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("fake app produced no tool_result"); return
        }
        #expect((obj["t"] as? String) == "tool_result")
        #expect((obj["ok"] as? Bool) == true)
        #expect((obj["s"] as? String) == "wrote it")
        #expect((obj["idx"] as? NSNumber)?.intValue == 0)
    }

    @Test func fakeAppRefusesUnkeyedName() throws {
        // An empty answers map: every name is unkeyed, so the app answers with
        // ok:false and the fixed refusal (D4). idx is echoed back untouched.
        let appBinary = try buildApp(answers: [:])
        let app = try spawn(appBinary, [], ["FAKE_SPEED": "0"])
        defer { app.process.terminate(); app.process.waitUntilExit() }

        let request = #"{"t":"tool_request","idx":7,"name":"unknown","params":[],"ts":0}"#
        app.stdin.fileHandleForWriting.write(Data((request + "\n").utf8))

        let line = try readLine(fd: app.stdout.fileHandleForReading.fileDescriptor, timeout: 10)
        guard let line = line, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("fake app produced no tool_result"); return
        }
        #expect((obj["t"] as? String) == "tool_result")
        #expect((obj["ok"] as? Bool) == false)
        #expect((obj["s"] as? String) == FakeAppSource.refusal)
        #expect((obj["idx"] as? NSNumber)?.intValue == 7)
    }

    @Test func fakeAppIgnoresNonRequestLines() throws {
        // The app shares the agent's stdout stream in the round trip; it must
        // silently skip non-tool_request lines (hello/status/text/ready) and
        // only answer tool_request lines.
        let appBinary = try buildApp(answers: ["write": "wrote it"])
        let app = try spawn(appBinary, [], ["FAKE_SPEED": "0"])
        defer { app.process.terminate(); app.process.waitUntilExit() }

        let appFD = app.stdout.fileHandleForReading.fileDescriptor
        // Send a non-request line, then a request; expect exactly one result.
        let noise = #"{"t":"status","state":"idle","ts":0}"#
        let request = #"{"t":"tool_request","idx":0,"name":"write","params":[],"ts":0}"#
        app.stdin.fileHandleForWriting.write(Data((noise + "\n" + request + "\n").utf8))

        let line = try readLine(fd: appFD, timeout: 10)
        guard let line = line, let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("fake app produced no tool_result"); return
        }
        #expect((obj["ok"] as? Bool) == true)
        #expect((obj["s"] as? String) == "wrote it")
    }
}
