import Testing
import Foundation
import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FakeAgentIntegrationTests {

    /// A deterministic skills dir (built per call) whose SKILL.md content is
    /// fixed, so `SuperpowersBootstrap.build` renders the same index text
    /// regardless of the temp path. Mirrors the app's bootstrap path (P8 D1):
    /// only the input dir is a small fixture, the renderer is the real one.
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

    private func makeSettings(workspace: URL, shellAllowed: Bool = false) throws -> AgentSettings {
        // P8 D1/D4: the app always passes the Superpowers bootstrap via -sys,
        // built deterministically from the resolved skills dir. The fake's
        // expected argv therefore carries -sys + that same index text.
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

    private func buildFake(fixture: String, settings: AgentSettings) throws -> (URL, [String]) {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("\(fixture).ndjson"))
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(capture: capture, engineArgv: argv)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p7-fake-agent-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        return (binary, argv)
    }

    /// Parses the fixture directly for the expected event sequence.
    private func expectedEvents(_ fixture: String) throws -> [AgentEvent] {
        let capture = try Data(contentsOf: FakeAgentHarness.fixture("\(fixture).ndjson"))
        var parser = AgentWireParser()
        var out: [AgentEvent] = []
        for line in String(decoding: capture, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if let e = parser.feed(String(line)) { out.append(e) }
        }
        return out
    }

    @Test func fakeArgvCarriesSysAndBootstrap() throws {
        // P8 D1/D4: the app always passes the Superpowers bootstrap via -sys,
        // so the fake's expected argv must carry it. The -sys value is the
        // deterministic index built by `SuperpowersBootstrap` from the
        // resolved skills dir — the same text the app would pass.
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: true)
        let argv = AgentCommand.argv(settings: settings)
        let sysIndex = argv.firstIndex(of: "-sys")
        #expect(sysIndex != nil, "argv must carry -sys (the app always passes the bootstrap)")
        guard let i = sysIndex else { return }
        let bootstrap = SuperpowersBootstrap.build(skillsDir: try fixtureSkillsDir())
        #expect(argv[i + 1] == bootstrap.indexPrompt,
                "the -sys value is the deterministic SuperpowersBootstrap index")
    }

    @Test func fakeReplaysCaptureEventsEquivalently() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: true)
        let (binary, argv) = try buildFake(fixture: "golden-tools", settings: settings)

        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv, env: ["FAKE_SPEED": "0"])
        defer {
            fake.process.terminate()
            fake.process.waitUntilExit()
        }
        let expected = try expectedEvents("golden-tools")
        var parser = AgentWireParser()
        FakeAgentHarness.writePrompt(fake, "run your tools")
        let actual = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { $0.count >= expected.count })
        #expect(actual == expected, "fake replay must produce the same events as the capture")
    }

    @Test func fakeRefusesWrongArgv() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: false)
        let (binary, _) = try buildFake(fixture: "golden-tools", settings: settings)

        // Wrong argv: workspace differs from what the fake was generated with.
        var wrong = settings
        wrong.workspace = URL(fileURLWithPath: "/tmp/other")
        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: AgentCommand.argv(settings: wrong), env: [:])
        fake.process.waitUntilExit()
        let stderr = String(data: fake.stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(fake.process.terminationStatus != 0)
        #expect(stderr.contains("argv mismatch"))
    }

    @Test func fakeHonorsETXAsInterrupt() throws {
        let ws = URL(fileURLWithPath: "/tmp/swiftstar-p7-ws")
        let settings = try makeSettings(workspace: ws, shellAllowed: true)
        let (binary, argv) = try buildFake(fixture: "golden-tools", settings: settings)

        let fake = try FakeAgentHarness.spawnAgent(binary, arguments: argv,
                                                   env: ["FAKE_SPEED": "1", "FAKE_MIN_LINE_DELAY": "0.2"])
        defer {
            fake.process.terminate()
            fake.process.waitUntilExit()
        }
        // One parse session across both reads: the second call starts mid-stream
        // (after the `start` event), so a fresh parser would refuse the first
        // line it sees as a non-handshake.
        var parser = AgentWireParser()
        FakeAgentHarness.writePrompt(fake, "run your tools")
        // Read until a tool block opens, then interrupt mid-replay.
        let sawStart = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { events in
            events.contains {
                if case .tool(let te) = $0, te.phase == .start { return true } else { return false }
            }
        })
        #expect(sawStart.contains { if case .tool(let te) = $0, te.phase == .start { return true } else { return false } })
        FakeAgentHarness.writeETX(fake)
        // Wait for the turn-end ready (the last of the three lines
        // `emitInterrupt` emits: finish, status, ready). Targeting the ready —
        // not the finish — guarantees the preceding finish and status are already
        // collected: `Darwin.read` unblocks on the first available byte, so the
        // finish could be read alone and the harness would return before the
        // status/ready arrive. The ready is the natural turn-end signal.
        let interrupted = try FakeAgentHarness.readAgentEvents(fake, parser: &parser, until: { events in
            events.contains {
                if case .ready(_, let stopReason, _, _) = $0, stopReason == "interrupt" { return true } else { return false }
            }
        }, timeout: 10)
        #expect(interrupted.contains {
            if case .tool(let te) = $0, te.phase == .finish, te.status?.contains("interrupted") == true { return true } else { return false }
        })
        #expect(interrupted.contains { if case .status(let s) = $0, s.ctxUsed == 0 { return true } else { return false } })
        // The fake returns to waiting on stdin (ready), the turn is over, and
        // the D12 fields ride the turn-end ready: the interrupt is the stop reason.
        #expect(interrupted.contains {
            if case .ready(_, let stopReason, _, _) = $0, stopReason == "interrupt" { return true } else { return false }
        })
    }
}
