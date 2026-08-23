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
// P7 consent knobs (nil = P5 shape: no --workspace/--shell appended).
let workspace = env["CAPTURE_WORKSPACE"]  // nil = no --workspace
let shell = env["CAPTURE_SHELL"]          // nil = no --shell

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

// MARK: - Drive state (callback-driven; @unchecked Sendable for the handlers)

final class DriveState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var ready = 0
    private var parser = WireEventParser()
    private var lineBuf = Data()
    private var refusedReason: String?

    /// Called only from the stdout readabilityHandler (serial per handle).
    func onStdoutData(_ d: Data) {
        lock.lock()
        stdoutData.append(d)
        lineBuf.append(d)
        while let nl = lineBuf.firstIndex(of: 0x0A) {
            let lineData = lineBuf[..<nl]
            lineBuf.removeSubrange(lineBuf.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8),
               let event = parser.feed(line) {
                switch event {
                case .ready: ready += 1
                case .refused(let reason): if refusedReason == nil { refusedReason = reason }
                default: break
                }
            }
        }
        lock.unlock()
    }

    func onStderrData(_ d: Data) {
        lock.lock(); stderrData.append(d); lock.unlock()
    }

    var readyCount: Int { lock.lock(); defer { lock.unlock() }; return ready }
    /// Non-nil when the first wire line was not a valid handshake (binding rule 7).
    var refusal: String? { lock.lock(); defer { lock.unlock() }; return refusedReason }
    var snapshot: (stdout: Data, stderr: Data) {
        lock.lock(); defer { lock.unlock() }; return (stdoutData, stderrData)
    }
}

let state = DriveState()

// MARK: - Spawn the engine

let process = Process()
process.executableURL = engineBinary
var args: [String] = [
    "-m", ggufPath,
    "-c", "\(ctx)",
    "--metal",
    "--non-interactive",
    "--json-events",
    "--trace", tracePath.path,
]
// P7 consent flags appended after `--trace` (nil = P5 shape, absent).
// NOTE: `Process.arguments` is a Foundation `copy` property — appending via
// `process.arguments?.append(...)` mutates a throwaway copy and does not persist
// (the brief's sketch hit this trap: `--workspace`/`--shell` were silently dropped,
// so the engine ran in bare-CLI mode and `seed.txt` landed in `external/ds4`).
// Build the array on a local `var` and assign once.
if let workspace {
    args += ["--workspace", workspace]
}
if let shell {
    args += ["--shell", shell]
}
process.arguments = args
process.currentDirectoryURL = engineDir
var engineEnv = ProcessInfo.processInfo.environment
engineEnv["DS4_LOCK_FILE"] = "/tmp/ds4-capture-\(ProcessInfo.processInfo.processIdentifier).lock"
// P7: `--workspace` chdir's the engine into the workspace, but Metal sources load
// cwd-relative (`metal/*.metal`) and would not resolve there (the engine aborts with
// "metal backend unavailable"). The engine sanctions per-source `DS4_METAL_*_SOURCE`
// overrides for exactly this ("a diagnostic run can swap one source file"); point each
// at its absolute path so Metal resolves regardless of cwd. The P5 shape (no
// `CAPTURE_WORKSPACE`) is untouched — cwd stays `external/ds4` and Metal loads from
// there as before, so no env vars are added and the recaptured `golden` is unchanged.
if workspace != nil {
    let metalDir = engineDir.appendingPathComponent("metal", isDirectory: true)
    if let names = try? FileManager.default.contentsOfDirectory(atPath: metalDir.path) {
        for name in names where name.hasSuffix(".metal") {
            let stem = String(name.dropLast(".metal".count))
            engineEnv["DS4_METAL_\(stem.uppercased())_SOURCE"] =
                metalDir.appendingPathComponent(name).path
        }
    }
}
process.environment = engineEnv

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

stdoutHandle.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { handle.readabilityHandler = nil; return }
    state.onStdoutData(data)
}
stderrHandle.readabilityHandler = { handle in
    let data = handle.availableData
    if data.isEmpty { handle.readabilityHandler = nil; return }
    state.onStderrData(data)
}

// MARK: - Drive (poll the ready-count; never block on the pipe)

func waitReady(_ target: Int, timeout: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while state.readyCount < target {
        if Date() > deadline { return false }
        Thread.sleep(forTimeInterval: 0.2)
    }
    return true
}

@MainActor
func writePrompt(_ prompt: String) {
    stdinPipe.fileHandleForWriting.write(Data((prompt + "\n").utf8))
}

var failed = false

logProgress("waiting for model load (ready event)…")
if !waitReady(1, timeout: loadTimeout) {
    logProgress("FATAL: no ready event before load timeout")
    failed = true
}
if let refusal = state.refusal {
    logProgress("FATAL: wire handshake refused: \(refusal)")
    failed = true
}

if !failed {
    for (i, prompt) in prompts.enumerated() {
        let target = state.readyCount + 1
        logProgress("sending prompt \(i + 1)/\(prompts.count)…")
        writePrompt(prompt)
        if !waitReady(target, timeout: turnTimeout) {
            logProgress("FATAL: turn \(i + 1) did not finish before timeout")
            failed = true
            break
        }
    }
}

// Stop the engine: EOF on stdin, a short grace for trailing output, then SIGTERM.
try? stdinPipe.fileHandleForWriting.close()
Thread.sleep(forTimeInterval: 2)
if process.isRunning { process.terminate() }
process.waitUntilExit()
stdoutHandle.readabilityHandler = nil
stderrHandle.readabilityHandler = nil
// Final drain: the handlers may not have processed the last (EOF-delivered)
// batch before we nil'd them — read whatever the OS still has buffered.
let outRest = stdoutHandle.readDataToEndOfFile()
if !outRest.isEmpty { state.onStdoutData(outRest) }
let errRest = stderrHandle.readDataToEndOfFile()
if !errRest.isEmpty { state.onStderrData(errRest) }

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
