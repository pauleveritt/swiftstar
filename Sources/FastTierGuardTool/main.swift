import Foundation

// Fast-tier tripwire tool. Scans one Swift source file for symbols that could
// spawn a process or open a socket; exits 1 (build failure) with file:line hits.
// It is a drift alarm, not a sandbox — see the P2 spec D3.

let forbidden: [String] = [
    "Process(", "URLSession", "NWConnection", "posix_spawn", "Darwin.", "socket("
]

let path = CommandLine.arguments[1]
guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { exit(0) }

var hits: [String] = []
for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
    for symbol in forbidden where line.contains(symbol) {
        hits.append("\(path):\(index + 1): \(symbol)")
    }
}
if !hits.isEmpty {
    let message = """
    FAST-TIER TRIPWIRE: a default-tier test may spawn a process or open a socket.
    \(hits.joined(separator: "\n"))
    If this is deliberate, the test belongs in SwiftStarIntegrationTests (env-gated).
    """
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
exit(0)
