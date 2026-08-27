import Foundation
import Darwin
import SwiftStarKit

/// Generic process-spawn harness for integration tests (extracted from the
/// retired `FakeServerHarness` when the Chat server surface went away — the
/// download tests still need a way to compile + run a local HTTP file server).
enum FakeProcessHarnessError: LocalizedError {
    case bindFailed(errno: Int32)
    case compileFailed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .bindFailed(let code):
            return "bind failed: \(String(cString: strerror(code)))"
        case .compileFailed(let status, let output):
            return "swiftc failed (exit \(status)): \(output)"
        }
    }
}

struct FakeProcess {
    let process: Process
    let stdout: Pipe
    let stderr: Pipe
}

enum FakeProcessHarness {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Returns a free port. Known race: the port is released before the caller
    /// binds it. Accepted for this harness (sequential tests, short window).
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
        guard r == 0 else { throw FakeProcessHarnessError.bindFailed(errno: errno) }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var got = sockaddr_in()
        let g = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(s, $0, &len)
            }
        }
        guard g == 0 else { throw FakeProcessHarnessError.bindFailed(errno: errno) }
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

    /// Compiles a committed Swift main file (e.g. the RangeFileServer) into a
    /// binary in the given directory.
    static func compileFile(at path: URL, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try compile(sourceFile: path, binary: dir.appendingPathComponent(path.deletingPathExtension().lastPathComponent))
    }

    private static func compile(sourceFile: URL, binary: URL) throws -> URL {
        let process = Process()
        process.executableURL = try resolveSwiftc()
        process.arguments = [sourceFile.path, "-o", binary.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw FakeProcessHarnessError.compileFailed(status: process.terminationStatus, output: output)
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
}
