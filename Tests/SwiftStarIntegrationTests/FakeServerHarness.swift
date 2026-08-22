import Foundation
import Darwin
import SwiftStarKit

enum FakeServerHarnessError: LocalizedError {
    case bindFailed(errno: Int32)
    case connectFailed(errno: Int32)
    case compileFailed(status: Int32, output: String)
    case timeout(eventCount: Int)
    case unexpectedEOF

    var errorDescription: String? {
        switch self {
        case .bindFailed(let code):
            return "bind failed: \(String(cString: strerror(code)))"
        case .connectFailed(let code):
            return "connect failed: \(String(cString: strerror(code)))"
        case .compileFailed(let status, let output):
            return "swiftc failed (exit \(status)): \(output)"
        case .timeout(let count):
            return "timed out waiting for [DONE]; got \(count) events"
        case .unexpectedEOF:
            return "unexpected EOF before [DONE]"
        }
    }
}

struct FakeProcess {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
}

enum FakeServerHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func fixture(_ name: String) throws -> URL {
        repoRoot.appendingPathComponent("fixtures/server").appendingPathComponent(name)
    }

    /// Returns a free port. Known race: the port is released before the caller
    /// binds it. Accepted for this harness (sequential tests, short window); the
    /// fake server sets SO_REUSEADDR to survive the rebound.
    static func freePort() throws -> Int {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let r = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard r == 0 else { throw FakeServerHarnessError.bindFailed(errno: errno) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { throw FakeServerHarnessError.bindFailed(errno: errno) }
        return Int(got.sin_port.bigEndian)
    }

    /// Resolves the Swift compiler: $SWIFT_EXEC, then xcrun, then /usr/bin/swiftc.
    static func resolveSwiftc() throws -> URL {
        if let env = ProcessInfo.processInfo.environment["SWIFT_EXEC"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let xcrun = Process()
        xcrun.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        xcrun.arguments = ["--find", "swiftc"]
        let out = Pipe()
        xcrun.standardOutput = out
        xcrun.standardError = Pipe()
        try xcrun.run()
        xcrun.waitUntilExit()
        if xcrun.terminationStatus == 0 {
            let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/usr/bin/swiftc")
    }

    static func compileFake(source: String, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mainFile = dir.appendingPathComponent("main.swift")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let binary = dir.appendingPathComponent("fake-ds4-server")
        let process = Process()
        process.executableURL = try resolveSwiftc()
        process.arguments = [mainFile.path, "-o", binary.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FakeServerHarnessError.compileFailed(status: process.terminationStatus, output: output)
        }
        return binary
    }

    static func spawn(_ binary: URL, arguments: [String], env: [String: String]) throws -> FakeProcess {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = env
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        return FakeProcess(process: process, stdout: out, stderr: err)
    }

    /// Reads the SSE stream from the fake server until `data: [DONE]`, feeding
    /// the Kit parser. Retries the connect briefly (the fake may not have bound
    /// yet) and reads in buffered chunks so the loop blocks rather than spins.
    static func readEvents(port: Int, timeout: TimeInterval = 30) throws -> [SSEEvent] {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        var connected = false
        let connectDeadline = Date().addingTimeInterval(5)
        repeat {
            let r = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if r == 0 {
                connected = true
                break
            }
            if Date() >= connectDeadline {
                throw FakeServerHarnessError.connectFailed(errno: errno)
            }
            usleep(50_000)
        } while !connected

        var parser = SSEParser()
        var events: [SSEEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let n = Darwin.read(s, &chunk, chunk.count)
            if n == 0 { throw FakeServerHarnessError.unexpectedEOF }
            if n < 0 { throw FakeServerHarnessError.connectFailed(errno: errno) }
            buffer.append(contentsOf: chunk[0..<n])
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let event = parser.feed(line) {
                    events.append(event)
                    if event == .done { return events }
                }
            }
        }
        throw FakeServerHarnessError.timeout(eventCount: events.count)
    }
}
