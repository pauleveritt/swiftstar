import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-agenttest: the canonical agent test (P11 addendum).
//
// Decompose a roadmap into phases, run each phase as a subagent in a
// chained-worktree transaction, then grade the result with the deterministic
// acceptance suite. The DeepSeek qualitative read is a separate pass (the
// harness writes the report the grader consumes).
//
// Usage: swift run swiftstar-agenttest --spec <roadmap|roadmap-user-story> [--repo DIR]
// Env:   SWIFTSTAR_MODEL (gguf), DS4_DIR (engine), AGENTTEST_PY_PROJECT (the uv
//        project with the acceptance deps; default ~/projects/pauleveritt/local-ai-pi)

let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let specName = argValue("--spec") ?? "roadmap"
let repoURL = URL(fileURLWithPath: argValue("--repo")
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("agenttest-\(UUID().uuidString)").path)
let pyProject = env["AGENTTEST_PY_PROJECT"] ?? NSHomeDirectory() + "/projects/pauleveritt/local-ai-pi"

guard let gguf = env["SWIFTSTAR_MODEL"], !gguf.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-agenttest: SWIFTSTAR_MODEL is required\n".utf8))
    exit(2)
}
let engineDir = URL(fileURLWithPath: env["DS4_DIR"] ?? FileManager.default.currentDirectoryPath + "/external/ds4")

let fixtureDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("fixtures/agenttest")

// MARK: - read the spec + decompose into phases

let specText = try String(contentsOf: fixtureDir.appendingPathComponent("specs/\(specName).md"), encoding: .utf8)
let mission = (try? String(contentsOf: fixtureDir.appendingPathComponent("specs/mission.md"), encoding: .utf8)) ?? ""
let techStack = (try? String(contentsOf: fixtureDir.appendingPathComponent("specs/tech-stack.md"), encoding: .utf8)) ?? ""
let sharedContext = mission + "\n" + techStack

func decomposePhases(_ text: String) -> [String] {
    text.components(separatedBy: "\n## Phase ").dropFirst().map { "## Phase " + $0 }
}
let phases = decomposePhases(specText)
guard !phases.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-agenttest: no phases found in \(specName).md\n".utf8))
    exit(2)
}

// The task's file surface — the writable scope each phase may mutate.
let writableFiles = ["app.py", "models.py",
                     "templates/base.html", "templates/home.html", "templates/complaints.html",
                     "tests/test_app.py"]

// MARK: - the repo (a fresh disposable repo)

func git(_ dir: URL, _ a: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir.path] + a
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
}

try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
git(repoURL, ["init", "-q"])
git(repoURL, ["config", "user.email", "agenttest@local"])
git(repoURL, ["config", "user.name", "AgentTest"])
try "".write(to: repoURL.appendingPathComponent(".gitkeep"), atomically: true, encoding: .utf8)
git(repoURL, ["add", ".gitkeep"])
git(repoURL, ["commit", "-q", "-m", "seed"])

// MARK: - drive the transaction

let settings = AgentSettings(
    engineDir: engineDir, modelPath: URL(fileURLWithPath: gguf),
    contextSize: 32768, workspace: repoURL, shellAllowed: false)
let orch = try PoolOrchestrator(settings: settings)
defer { orch.stop() }
let txn = WorktreeTransaction(repo: repoURL)
defer { txn.abort() }

print("[agenttest] spec=\(specName) phases=\(phases.count)")

for (i, phaseText) in phases.enumerated() {
    // The prepared context (D4): the phase spec + the shared rubric + the writable
    // scope, so the worker knows exactly which files it may create/edit.
    let writableNote = "You may write or edit only these files:\n"
        + writableFiles.map { "- \($0)" }.joined(separator: "\n")
    let packet = HandoffPacket(
        taskText: phaseText + "\n\n" + writableNote + "\n\n" + sharedContext,
        writableFiles: writableFiles, validationCommand: nil,
        baselines: [:], turnBudget: 100_000, toolCallBudget: 64)
    print("[agenttest] phase \(i + 1)/\(phases.count) …")
    let wt = try txn.preparePhase(packet: packet)
    let outcome = try orch.runPhase(worker: WorkerId(1), packet: packet, worktree: wt.url)
    let result = try txn.finalizePhase(wt, packet: packet, turnOutcome: outcome, validation: nil)
    switch result {
    case .candidate(let ref, let carried, _):
        print("[agenttest]   phase \(i + 1): candidate \(ref) — \(carried.mutations.count) mutation(s), \(carried.generatedTokens) tokens")
    case .receipt(let r):
        print("[agenttest]   phase \(i + 1): receipt \(r)")
        print("[agenttest] STOPPING (phase receipt)")
        exit(1)
    }
}

guard let ref = txn.commitBack() else {
    print("[agenttest] no candidate ref"); exit(1)
}
print("[agenttest] final candidate: \(ref)")

// MARK: - grade (deterministic acceptance suite)

if let gradeWT = txn.finalWorktree {
    let acceptance = try String(contentsOf: fixtureDir.appendingPathComponent("acceptance/test_acceptance.py"), encoding: .utf8)
    try acceptance.write(to: gradeWT.url.appendingPathComponent("test_acceptance.py"), atomically: true, encoding: .utf8)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["uv", "run", "--project", pyProject, "pytest", "-q", "test_acceptance.py"]
    p.currentDirectoryURL = gradeWT.url
    let out = Pipe()
    p.standardOutput = out
    p.standardError = out
    try p.run()
    p.waitUntilExit()
    let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    print("[agenttest] acceptance exit=\(p.terminationStatus)")
    print(output)
} else {
    print("[agenttest] no final worktree to grade")
    exit(1)
}

txn.discardFinal()
print("[agenttest] done")
