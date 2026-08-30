import Foundation
import Darwin
import SwiftStarKit

enum FakeAgentHarnessError: LocalizedError {
    case compileFailed(status: Int32, output: String)
    case timeout(eventCount: Int)
    case unexpectedEOF
    case readFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .compileFailed(let status, let output):
            return "swiftc failed (exit \(status)): \(output)"
        case .timeout(let count):
            return "timed out reading agent events; got \(count)"
        case .unexpectedEOF:
            return "unexpected EOF reading agent events"
        case .readFailed(let code):
            return "read failed: \(String(cString: strerror(code)))"
        }
    }
}

/// The agent fake's process handles. A separate struct from the server
/// harness's `FakeProcess` because the agent wire is stdin/stdout pipes (no
/// socket), and the fake needs the stdin pipe to write prompts and the ETX
/// interrupt byte.
struct FakeAgentProcess {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
    let stdin: Pipe
    let output: PollingLineReader
}

enum FakeAgentHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> URL {
        repoRoot.appendingPathComponent("fixtures/agent").appendingPathComponent(name)
    }

    static func compileFake(source: String, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mainFile = dir.appendingPathComponent("main.swift")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = try FakeProcessHarness.resolveSwiftc()
        process.arguments = [mainFile.path, "-o", dir.appendingPathComponent("fake-ds4-agent").path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FakeAgentHarnessError.compileFailed(status: process.terminationStatus, output: output)
        }
        return dir.appendingPathComponent("fake-ds4-agent")
    }

    static func spawnAgent(_ binary: URL, arguments: [String], env: [String: String]) throws -> FakeAgentProcess {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        let inp = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = inp
        try process.run()
        return FakeAgentProcess(process: process, stdout: out, stderr: err, stdin: inp,
                                output: PollingLineReader(fd: out.fileHandleForReading.fileDescriptor))
    }

    static func writePrompt(_ fake: FakeAgentProcess, _ prompt: String) {
        fake.stdin.fileHandleForWriting.write(Data((prompt + "\n").utf8))
    }

    /// Reads the fake's stdout, feeding `PoolWireParser`, until `until` returns
    /// true or the timeout elapses — the pooled-wire sibling of `readAgentEvents`
    /// (same raw-byte read loop; the parser is `PoolWireParser`, so each event
    /// carries its worker id).
    static func readPoolEvents(_ fake: FakeAgentProcess,
                               parser: inout PoolWireParser,
                               until: @escaping ([PoolWireEvent]) -> Bool,
                               timeout: TimeInterval = 30) throws -> [PoolWireEvent] {
        var events: [PoolWireEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw FakeAgentHarnessError.timeout(eventCount: events.count) }
            let line: String
            do {
                line = try fake.output.nextLine(timeout: remaining)
            } catch PollingLineReaderError.timedOut {
                throw FakeAgentHarnessError.timeout(eventCount: events.count)
            } catch PollingLineReaderError.endOfFile {
                throw FakeAgentHarnessError.unexpectedEOF
            } catch PollingLineReaderError.readFailed(let code) {
                throw FakeAgentHarnessError.readFailed(errno: code)
            } catch {
                throw FakeAgentHarnessError.unexpectedEOF
            }
            if let event = parser.feed(line) {
                events.append(event)
                if until(events) { return events }
            }
        }
    }

    static func writeETX(_ fake: FakeAgentProcess) {
        fake.stdin.fileHandleForWriting.write(Data([0x03]))
    }

    static func closeStdin(_ fake: FakeAgentProcess) {
        try? fake.stdin.fileHandleForWriting.close()
    }

    /// Reads the fake's stdout, feeding `AgentWireParser`, until `until`
    /// returns true or the timeout elapses. The fake stays alive between
    /// prompts, so completion is a predicate, not EOF. Uses a blocking
    /// `Darwin.read` loop (the same shape as `FakeProcessHarness.readEvents`):
    /// `FileHandle.availableData` blocks with no way to honour the deadline,
    /// and conflates "quiet" with "EOF" — a slow fake would hang the test or
    /// fail it spuriously. Reading raw bytes keeps the deadline real. The
    /// parser is caller-owned and shared across calls (see the interrupt
    /// test): a fresh parser on a second call would refuse the first
    /// mid-stream line as a non-handshake.
    static func readAgentEvents(_ fake: FakeAgentProcess,
                                parser: inout AgentWireParser,
                                until: @escaping ([AgentEvent]) -> Bool,
                                timeout: TimeInterval = 30) throws -> [AgentEvent] {
        var events: [AgentEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw FakeAgentHarnessError.timeout(eventCount: events.count) }
            let line: String
            do {
                line = try fake.output.nextLine(timeout: remaining)
            } catch PollingLineReaderError.timedOut {
                throw FakeAgentHarnessError.timeout(eventCount: events.count)
            } catch PollingLineReaderError.endOfFile {
                throw FakeAgentHarnessError.unexpectedEOF
            } catch PollingLineReaderError.readFailed(let code) {
                throw FakeAgentHarnessError.readFailed(errno: code)
            } catch {
                throw FakeAgentHarnessError.unexpectedEOF
            }
            if let event = parser.feed(line) {
                events.append(event)
                if until(events) { return events }
            }
        }
    }
}
