import Foundation
import SwiftStarKit

// swiftstar-drive: the committed live-capture program (P5). Drives the real
// ds4-agent, tees stdout/stderr byte-for-byte, and writes the fixed capture
// format. Never part of CI; run via `just capture`.

// MARK: - Knobs

let env = ProcessInfo.processInfo.environment
guard let ggufPath = env["CAPTURE_GGUF"], !ggufPath.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-drive: CAPTURE_GGUF is required (absolute path to the gguf)\n".utf8))
    exit(2)
}
let ctx = Int(env["CAPTURE_CTX"] ?? "32768") ?? 32768
let loadTimeout = Double(env["CAPTURE_MODEL_LOAD_TIMEOUT"] ?? "900") ?? 900
let turnTimeout = Double(env["CAPTURE_TURN_TIMEOUT"] ?? "900") ?? 900

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let engineDir = repoRoot.appendingPathComponent("external/ds4", isDirectory: true)
let engineBinary = engineDir.appendingPathComponent("ds4-agent")

// MARK: - Prompts

let prompts: [String]
if let pf = env["CAPTURE_PROMPTS_FILE"] {
    let text = (try? String(contentsOfFile: pf, encoding: .utf8)) ?? ""
    prompts = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
} else {
    prompts = [
        "Explain, in three sentences, why the sky is blue.",
        "List the first ten prime numbers.",
    ]
}
guard !prompts.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-drive: no prompts\n".utf8))
    exit(2)
}

// MARK: - Capture directory + trace path

let df = DateFormatter()
df.dateFormat = "yyyyMMdd-HHmmss"
let modelSlug = URL(fileURLWithPath: ggufPath).lastPathComponent
let captureDir = repoRoot
    .appendingPathComponent("captures", isDirectory: true)
    .appendingPathComponent("\(df.string(from: Date()))-\(modelSlug)", isDirectory: true)
try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
let tracePath = captureDir.appendingPathComponent("wire.trace")

@MainActor
func logProgress(_ line: String) {
    let stamped = "[\(Date())] \(line)\n"
    FileHandle.standardError.write(Data(stamped.utf8))
    if let pp = env["CAPTURE_PROGRESS_LOG"] {
        let h = FileHandle(forWritingAtPath: pp)
        h?.seekToEndOfFile()
        h?.write(Data(stamped.utf8))
        try? h?.close()
    }
}

func submoduleSHA(_ dir: URL) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir.path, "rev-parse", "HEAD"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// MARK: - Shared drive state (lock-protected; @unchecked Sendable for the pipe callbacks)

final class DriveState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var ready = 0

    func appendStdout(_ d: Data) { lock.lock(); stdoutData.append(d); lock.unlock() }
    func appendStderr(_ d: Data) { lock.lock(); stderrData.append(d); lock.unlock() }
    func noteReady() { lock.lock(); ready += 1; lock.unlock() }
    var readyCount: Int { lock.lock(); defer { lock.unlock() }; return ready }
    var snapshot: (stdout: Data, stderr: Data) {
        lock.lock(); defer { lock.unlock() }
        return (stdoutData, stderrData)
    }
}

let state = DriveState()

// MARK: - Spawn the engine

let process = Process()
process.executableURL = engineBinary
process.arguments = [
    "-m", ggufPath,
    "-c", "\(ctx)",
    "--metal",
    "--non-interactive",
    "--json-events",
    "--trace", tracePath.path,
]
process.currentDirectoryURL = engineDir
process.environment = ["DS4_LOCK_FILE": "/tmp/ds4-capture.lock"]

let stdinPipe = Pipe()
let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardInput = stdinPipe
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

let stdoutHandle = stdoutPipe.fileHandleForReading
let stderrHandle = stderrPipe.fileHandleForReading

logProgress("spawning \(engineBinary.lastPathComponent) -m \(modelSlug) -c \(ctx)")
try process.run()

// stderr: verbatim tee on a background queue (no logic).
stderrHandle.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty {
        handle.readabilityHandler = nil
        return
    }
    state.appendStderr(data)
}

// MARK: - stdout line reader (main thread; owns the parser)

var parser = WireEventParser()
var lineBuf = Data()

/// Read stdout until `predicate` is satisfied or EOF. Tees every byte and feeds
/// complete lines to the parser (counting `ready` events). Returns false on EOF
/// or deadline.
@discardableResult
@MainActor
func drainStdout(until predicate: () -> Bool, deadline: Date) -> Bool {
    while !predicate() {
        if Date() > deadline { return false }
        let data = stdoutHandle.availableData
        if data.isEmpty { return false }  // EOF
        state.appendStdout(data)
        lineBuf.append(data)
        while let nl = lineBuf.firstIndex(of: 0x0A) {
            let lineData = lineBuf[..<nl]
            lineBuf.removeSubrange(lineBuf.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                if let event = parser.feed(line), case .ready = event {
                    state.noteReady()
                }
            }
        }
    }
    return true
}

@MainActor
func writePrompt(_ prompt: String) {
    stdinPipe.fileHandleForWriting.write(Data((prompt + "\n").utf8))
}

// MARK: - Drive

var failed = false

logProgress("waiting for model load (ready event)…")
let loadDeadline = Date().addingTimeInterval(loadTimeout)
if !drainStdout(until: { state.readyCount >= 1 }, deadline: loadDeadline) {
    logProgress("FATAL: no ready event before load timeout")
    failed = true
}

if !failed {
    for (i, prompt) in prompts.enumerated() {
        let target = state.readyCount + 1
        logProgress("sending prompt \(i + 1)/\(prompts.count)…")
        writePrompt(prompt)
        let turnDeadline = Date().addingTimeInterval(turnTimeout)
        if !drainStdout(until: { state.readyCount >= target }, deadline: turnDeadline) {
            logProgress("FATAL: turn \(i + 1) did not finish before timeout")
            failed = true
            break
        }
    }
}

// Drain trailing output to EOF (or a short grace), then stop.
_ = drainStdout(until: { false }, deadline: Date().addingTimeInterval(10))
try? stdinPipe.fileHandleForWriting.close()
if process.isRunning { process.terminate() }
process.waitUntilExit()
stdoutHandle.readabilityHandler = nil

// MARK: - Write the capture

let manifest = CaptureManifest(
    submoduleSHA: submoduleSHA(engineDir),
    commandLine: [engineBinary.path] + (process.arguments ?? []),
    model: modelSlug,
    ctx: ctx,
    startedAt: Date()
)

let (wire, stderr) = state.snapshot
do {
    try CaptureWriter.write(directory: captureDir, wire: wire, stderr: stderr, manifest: manifest)
} catch {
    logProgress("FATAL: capture write failed: \(error)")
    failed = true
}

logProgress(failed ? "capture FAILED (see log)" : "capture complete: \(captureDir.path)")
exit(failed ? 1 : 0)
