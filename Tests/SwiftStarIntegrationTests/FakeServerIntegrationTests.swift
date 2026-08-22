import Testing
import Foundation
import SwiftStarKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct FakeServerIntegrationTests {

    private func makeSettings(port: Int) -> EngineSettings {
        EngineSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            port: port
        )
    }

    private func buildFake(fixture: String, settings: EngineSettings) throws -> (URL, [String]) {
        let capture = try Data(contentsOf: FakeServerHarness.fixture("\(fixture).sse"))
        let sidecar = try Data(contentsOf: FakeServerHarness.fixture("\(fixture).sse.sidecar"))
        let argv = ServerCommand.argv(settings: settings)
        let source = try FakeServerSource.generate(capture: capture, sidecar: sidecar, engineArgv: argv)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("p2-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeServerHarness.compileFake(source: source, into: work)
        return (binary, argv)
    }

    @Test func fakeReplaysCaptureEventsEquivalently() throws {
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)
        let (binary, argv) = try buildFake(fixture: "golden", settings: settings)

        let fake = try FakeServerHarness.spawn(binary, arguments: argv, env: ["FAKE_SPEED": "0"])

        // Wait for the fake to bind+listen before connecting (it announces on
        // stderr; the supervisor's ready detection uses the same line).
        let listening = fake.stderr.fileHandleForReading.availableData
        let announcement = String(data: listening, encoding: .utf8) ?? ""
        #expect(announcement.contains("listening on http://127.0.0.1:\(port)"))

        // Expected: the same event sequence as parsing the fixture directly.
        let capture = try Data(contentsOf: FakeServerHarness.fixture("golden.sse"))
        var direct = SSEParser()
        var expected: [SSEEvent] = []
        for line in String(decoding: capture, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if let e = direct.feed(String(line)) { expected.append(e) }
        }

        let actual = try FakeServerHarness.readEvents(port: port)
        #expect(actual == expected, "fake replay must produce the same events as the capture")

        fake.process.terminate()
        fake.process.waitUntilExit()
    }

    @Test func fakeRefusesWrongArgv() throws {
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)
        let (binary, _) = try buildFake(fixture: "golden.short", settings: settings)

        // Wrong argv: context size differs from what the fake was generated with.
        var wrong = settings
        wrong.contextSize = 16384
        let fake = try FakeServerHarness.spawn(binary, arguments: ServerCommand.argv(settings: wrong), env: ["FAKE_SPEED": "0"])
        fake.process.waitUntilExit()
        let stderr = String(data: fake.stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(fake.process.terminationStatus != 0)
        #expect(stderr.contains("argv mismatch"))
    }

    @Test func fakeAnnouncesListeningOnStderr() throws {
        let port = try FakeServerHarness.freePort()
        let settings = makeSettings(port: port)
        let (binary, argv) = try buildFake(fixture: "golden.short", settings: settings)

        let fake = try FakeServerHarness.spawn(binary, arguments: argv, env: ["FAKE_SPEED": "0"])

        // The fake must print the listening line on stderr (the supervisor's
        // ready detection depends on it).
        let lineData = fake.stderr.fileHandleForReading.availableData
        let line = String(data: lineData, encoding: .utf8) ?? ""
        #expect(line.contains("listening on http://127.0.0.1:\(port)"))

        fake.process.terminate()
        fake.process.waitUntilExit()
    }
}
