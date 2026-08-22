import Foundation
import Darwin
import SwiftStarKit

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
        guard r == 0 else { throw NSError(domain: "harness", code: 1) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { throw NSError(domain: "harness", code: 2) }
        return Int(got.sin_port.bigEndian)
    }

    static func compileFake(source: String, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let mainFile = dir.appendingPathComponent("main.swift")
        try source.write(to: mainFile, atomically: true, encoding: .utf8)
        let binary = dir.appendingPathComponent("fake-ds4-server")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = [mainFile.path, "-o", binary.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "compile", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: out])
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
    /// the Kit parser, and returns the events.
    static func readEvents(port: Int, timeout: TimeInterval = 30) throws -> [SSEEvent] {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw NSError(domain: "connect", code: 3) }

        var parser = SSEParser()
        var events: [SSEEvent] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            var byte: UInt8 = 0
            let n = Darwin.read(s, &byte, 1)
            if n <= 0 { break }
            buffer.append(byte)
            if byte == 0x0A {
                let line = String(decoding: buffer, as: UTF8.self)
                buffer.removeAll(keepingCapacity: true)
                if let event = parser.feed(line) {
                    events.append(event)
                    if event == .done { return events }
                }
            }
        }
        throw NSError(domain: "timeout", code: 4, userInfo: [NSLocalizedDescriptionKey: "timed out waiting for [DONE]; got \(events.count) events"])
    }
}
