import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-drive: the committed live-capture program (P5). Drives the real
// ds4-agent, tees stdout/stderr byte-for-byte, and writes the fixed capture
// format. Never part of CI; run via `just capture`.

// MARK: - Knobs

let env = ProcessInfo.processInfo.environment
let ggufPath = env["CAPTURE_GGUF"] ?? env["SWIFTSTAR_MODEL"] ?? ""
guard !ggufPath.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-drive: CAPTURE_GGUF (or SWIFTSTAR_MODEL) is required (absolute path to the gguf)\n".utf8))
    exit(2)
}
let ctx = Int(env["CAPTURE_CTX"] ?? "32768") ?? 32768
let loadTimeout = Double(env["CAPTURE_MODEL_LOAD_TIMEOUT"] ?? "900") ?? 900
let turnTimeout = Double(env["CAPTURE_TURN_TIMEOUT"] ?? "900") ?? 900
// P7 consent knobs (nil = P5 shape: no --workspace/--shell appended).
let workspace = env["CAPTURE_WORKSPACE"]  // nil = no --workspace
let shell = env["CAPTURE_SHELL"]          // nil = no --shell
// P24.1: CAPTURE_HOST_TOOLS=1 drives the engine the way the app does — tools
// delegated to the host over the wire. Requires a workspace, because every
// host file tool is confined to the grant and refuses without one.
let hostTools = (env["CAPTURE_HOST_TOOLS"].map { $0 == "1" || $0.lowercased() == "true" }) ?? false
// The engine throttle. `--power` is a SETTING, not a measurement: the engine
// defaults to 100 and the app drops to 70 whenever power-saving is on
// (`AgentSettings.powerSavingPercent`). A drive capture taken to reproduce an
// app session must be able to pin the same value, or the two are not
// comparable — on 2026-08-30 an app capture at 70 and a drive re-run at the
// default 100 differed by ~1.7x in both prefill and decode rate on ~the same
// volume of work, which was first read as an engine improvement.
//
// nil = don't append (engine default 100), keeping the P5 capture shape.
let power = env["CAPTURE_POWER"]
if let power, Int(power).map({ $0 < 1 || $0 > 100 }) ?? true {
    FileHandle.standardError.write(Data(
        "swiftstar-drive: CAPTURE_POWER must be an integer 1-100 (got \(power))\n".utf8))
    exit(2)
}
if hostTools && workspace == nil {
    FileHandle.standardError.write(Data(
        "swiftstar-drive: CAPTURE_HOST_TOOLS=1 requires CAPTURE_WORKSPACE (host file tools are confined to the workspace grant)\n".utf8))
    exit(2)
}

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
    guard let result = try? GitProcess.run(["rev-parse", "HEAD"], in: dir),
          result.exit == 0, !result.timedOut else { return "" }
    return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Drive state (callback-driven; @unchecked Sendable for the handlers)

final class DriveState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var ready = 0
    /// P24.1: `AgentWireParser`, not `WireEventParser` — the app's own parser,
    /// and the only one that surfaces `tool_request`. Drive exists to capture
    /// what the app does, so it must see what the app sees. The `.ready` and
    /// `.refused` cases it counts are identical.
    private var parser = AgentWireParser()
    private var lineBuf = LineBuffer()
    private var refusedReason: String?

    /// P24.1: set after the stdin pipe exists (it is created below this
    /// declaration). nil = the P5 shape: no host tools, requests unanswered.
    var onToolRequest: ((Int, String, [ToolParam]) -> Void)?
    /// A `tool_request` the parser could not read. The engine has already
    /// emitted it and is blocking on a result, so the host must answer
    /// `ok:false` or the turn deadlocks (`AgentWireParser:47-52`).
    var onToolRequestRefused: ((Int, String) -> Void)?

    /// Called only from the stdout readabilityHandler (serial per handle).
    func onStdoutData(_ d: Data) {
        // Tool requests are dispatched AFTER the lock is released: answering
        // one does file I/O, and the engine is blocked until it is answered —
        // holding the parse lock across that would stall this handler against
        // itself.
        var pending: [(Int, String, [ToolParam])] = []
        var refused: [(Int, String)] = []
        lock.lock()
        stdoutData.append(d)
        for lineData in lineBuf.append(d) {
            if let event = parser.feed(String(decoding: lineData, as: UTF8.self)) {
                switch event {
                case .ready: ready += 1
                case .refused(let reason): if refusedReason == nil { refusedReason = reason }
                case .toolRequest(let idx, let name, let params):
                    pending.append((idx, name, params))
                case .toolRequestRefused(let idx, let reason):
                    refused.append((idx, reason))
                default: break
                }
            }
        }
        lock.unlock()
        for (idx, reason) in refused { onToolRequestRefused?(idx, reason) }
        for (idx, name, params) in pending { onToolRequest?(idx, name, params) }
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
// P23: the per-turn think wire shape (CAPTURE_PER_TURN_THINK=1 appends the
// flag so a prompts file can carry {"t":"prompt",...,"think":"none"} lines).
if env["CAPTURE_PER_TURN_THINK"] != nil {
    args += ["--per-turn-think"]
}
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
// P24.1: `--host-tools` makes the engine delegate read/write/list/search/more
// to the host instead of running them itself. This is the path the app always
// takes (`AgentCommand.swift:105-113`) and the only one that exercises
// `HostToolExecutor` — without it a capture measures the engine's own tool
// implementations, which is how P24.1's first measurement attempt went wrong.
//
// Opt-in, and off by default: appending this unconditionally would change the
// P5 capture shape and every golden fixture generated from it.
if hostTools {
    args += ["--host-tools"]
}
if let power {
    args += ["--power", power]
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

// P24.1: the host-tool loop. The engine emits one `tool_request` and blocks on
// stdin until a `tool_result` with the same idx arrives, so every request must
// be answered — including malformed ones. Uses the same pure responder and the
// same `.app`-policy executor the app uses, so a capture taken here exercises
// exactly the code path a real session does.
if hostTools {
    let executor = HostToolExecutor(policy: .app, contextSize: ctx)
    let workspaceURL = URL(fileURLWithPath: workspace!, isDirectory: true)
    let shellAllowed = shell != nil
    func writeResult(_ response: ToolCallbackResponse) {
        try? stdinPipe.fileHandleForWriting.write(
            contentsOf: Data((ToolCallbackResponder.resultLine(response) + "\n").utf8))
    }
    state.onToolRequest = { idx, name, params in
        let response = ToolCallbackResponder.respond(
            idx: idx, name: name, params: params,
            workspace: workspaceURL, shellAllowed: shellAllowed,
            execute: executor.execute)
        writeResult(response)
    }
    state.onToolRequestRefused = { idx, reason in
        writeResult(ToolCallbackResponse(idx: idx, ok: false, s: "error: \(reason)"))
    }
    logProgress("host tools ON (workspace \(workspace!), shell \(shellAllowed ? "on" : "off"))")
}

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
