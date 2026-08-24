import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-agenttest: the canonical agent test (P11 addendum).
//
// Decompose a roadmap into phases, run each phase as a subagent in a
// chained-worktree transaction, then grade the result with the deterministic
// acceptance suite and the DeepSeek qualitative read (D6).
//
// Usage: swift run swiftstar-agenttest --spec <roadmap|roadmap-user-story> [--repo DIR] [--batch N]
// Env:   SWIFTSTAR_MODEL (gguf), DS4_DIR (engine), AGENTTEST_PY_PROJECT (the uv
//        project with the acceptance deps; default ~/projects/pauleveritt/local-ai-pi)

let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let specName = argValue("--spec") ?? "roadmap"
let batchCount = Int(argValue("--batch") ?? "1") ?? 1
let explicitRepo = argValue("--repo")
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

/// Path *presentation* — how deliverable paths are rendered in the task text.
/// Distinct from the grant (`writableFiles`), which stays workspace-relative
/// because it is the boundary the dispatcher revision-checks against. B8 found
/// that swapping relative deliverable paths for absolute ones — one variable —
/// took Mellum from 0 tool calls to 4-of-4 files, and C1 found the same
/// correlation for Laguna. `AGENTTEST_PATH_STYLE=absolute` runs that arm.
let absolutePathStyle = env["AGENTTEST_PATH_STYLE"] == "absolute"

/// Strings this run's spec is supposed to withhold, comma-separated
/// (`AGENTTEST_REDACT="default_factory,fastapi.responses"`). An experiment cell
/// that claims the worker must *diagnose* a fix declares the fix here, and the
/// harness refuses to dispatch a packet that states it anywhere — the check
/// that would have caught the near-miss cell shipping its own answer.
let redacts = (env["AGENTTEST_REDACT"] ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

/// Split a spec on `## Phase` headers. The text before the first phase (the
/// title, intro, and any shared "data model" section) is returned as the
/// `preamble`, and is prepended to every packet so shared contract facts reach
/// the worker even though they are not phase text.
func decompose(_ text: String) -> (preamble: String, phases: [String]) {
    let parts = text.components(separatedBy: "\n## Phase ")
    let preamble = parts.first ?? ""
    let phases = parts.dropFirst().map { "## Phase " + $0 }
    return (preamble, phases)
}
let (preamble, phases) = decompose(specText)
guard !phases.isEmpty else {
    FileHandle.standardError.write(Data("swiftstar-agenttest: no phases found in \(specName).md\n".utf8))
    exit(2)
}

// The task's file surface — the writable scope each phase may mutate.
let writableFiles = ["app.py", "models.py",
                     "templates/base.html", "templates/home.html", "templates/complaints.html",
                     "tests/test_app.py"]

/// Build one phase's packet. Phase packets do not depend on the worktree or the
/// orchestrator, so they can be assembled — and validated — before any model is
/// loaded.
/// `absoluteRoot` renders the deliverable list as absolute paths under that
/// root. The worktree only exists after `preparePhase`, so the caller builds
/// once relatively to create it, then rebuilds with the real root.
func phasePacket(_ phaseText: String, absoluteRoot: String? = nil) -> HandoffPacket {
    let vettedImport = "uv run --project \(pyProject) python -c 'import app'"
    let vettedPytest = "uv run --project \(pyProject) python -m pytest tests/test_app.py -q"
    let renderedFiles: String
    let pathRule: [String]
    if let root = absoluteRoot {
        renderedFiles = writableFiles.map { "- \(root)/\($0)" }.joined(separator: "\n")
        pathRule = ["All tool paths above are absolute; use them exactly as written."]
    } else {
        renderedFiles = writableFiles.map { "- \($0)" }.joined(separator: "\n")
        pathRule = ["All tool paths are relative to the workspace root (e.g. `app.py`,",
                    "`templates/base.html`) — never absolute paths."]
    }
    let writableNote = ([
        "You may write or edit only these files:",
        renderedFiles,
    ] + pathRule + [
        "You may run exactly these two commands (and no other shell command):",
        "- \(vettedImport)   (does app.py import cleanly?)",
        "- \(vettedPytest)   (do your own tests pass?)",
        "Work in one concise pass: write each file exactly once, do not explore",
        "the workspace or re-read files you just wrote, and run those commands at",
        "most once each. The acceptance suite checks user-visible behavior,",
        "not file layout — write the files named above directly.",
    ]).joined(separator: "\n")

    return PhasePacketBuilder.build(
        phaseText: phaseText,
        writableNote: writableNote,
        preamble: preamble,
        sharedContext: sharedContext,
        writableFiles: writableFiles,
        validationCommand: vettedImport,
        selfTestCommand: vettedPytest,
        toolCallBudget: Int(env["AGENTTEST_TOOL_BUDGET"] ?? "30") ?? 30,
        redacts: redacts,
        // The packet records the sampling the run actually used, so a capture is
        // self-describing rather than needing the invocation to interpret it.
        sampling: SamplingPolicy(
            think: env["AGENTTEST_THINK"] == "1" ? .bounded : .off,
            maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192))
}

// Validate every phase packet up front — before the model loads. The packets are
// worktree-independent, so a malformed one (an absolute path, an empty manifest,
// or a withheld fix leaked through the appended shared context) is caught in
// microseconds instead of after a 45–65 GiB load and three phases of generation.
for (i, phaseText) in phases.enumerated() {
    if case .invalid(let reasons) = HandoffPacketValidator.validate(phasePacket(phaseText)) {
        FileHandle.standardError.write(Data(
            ("swiftstar-agenttest: packet rejected for phase \(i + 1):\n"
             + reasons.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8))
        exit(2)
    }
}

func git(_ dir: URL, _ a: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir.path] + a
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    try? p.run()
    p.waitUntilExit()
}

// MARK: - one run

/// How one run finished. `completed` = the transaction committed a candidate and
/// was graded; `stopped` = the transaction stopped early (phase receipt, session
/// exhaustion, or an orchestrator error) and there is nothing to grade.
struct RunOutcome {
    enum Finish: String { case completed, stopped }
    let finish: Finish
    let note: String              // why it stopped (empty when completed)
    let acceptanceExit: Int32?    // nil when stopped
    let verdict: GraderVerdict?   // nil when stopped
    let report: AgentTestReport?  // derived from the wire; nil when no capture
    let elapsed: Int
}

/// Run the whole transaction once: a fresh disposable repo, the phase loop, the
/// deterministic acceptance grade, the DeepSeek qualitative grade, and the wire
/// analysis. Throws only on setup/IO failure; early transaction stops return a
/// `.stopped` outcome rather than throwing.
func runOnce(_ index: Int) throws -> RunOutcome {
    let runStart = Date()

    // A fresh disposable repo per run (batching isolates runs; a single run may
    // honor --repo to pin the location).
    let repoURL: URL
    if batchCount == 1, let explicitRepo {
        repoURL = URL(fileURLWithPath: explicitRepo)
    } else {
        let label = batchCount > 1 ? "\(specName)-run\(index + 1)" : "agenttest"
        repoURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(label)-\(UUID().uuidString)")
    }
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
    git(repoURL, ["init", "-q"])
    git(repoURL, ["config", "user.email", "agenttest@local"])
    git(repoURL, ["config", "user.name", "AgentTest"])
    try "".write(to: repoURL.appendingPathComponent(".gitkeep"), atomically: true, encoding: .utf8)
    git(repoURL, ["add", ".gitkeep"])
    git(repoURL, ["commit", "-q", "-m", "seed"])

    let settings = AgentSettings(
        engineDir: engineDir, modelPath: URL(fileURLWithPath: gguf),
        contextSize: 32768, workspace: repoURL, shellAllowed: false,
        maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192,
        // The worker runs `--nothink` by default: with the contract facts
        // pinned in the spec, it acts directly instead of think-looping to the
        // context limit (the hard-spec failure mode). AGENTTEST_THINK=1 re-enables
        // the reasoning phase for comparison.
        noThink: env["AGENTTEST_THINK"] != "1")
    let orch = try PoolOrchestrator(settings: settings)
    defer { orch.stop() }
    let txn = WorktreeTransaction(repo: repoURL)
    defer { txn.abort() }

    // Capture the raw wire to a committed artifact so the analyzer can re-derive
    // everything without rerunning (D5).
    let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = batchCount > 1 ? "-run\(index + 1)" : ""
    let captureDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("captures/agenttest/\(df.string(from: Date()))-\(specName)\(suffix)")
    try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
    let wireFile = captureDir.appendingPathComponent("wire.ndjson")
    FileManager.default.createFile(atPath: wireFile.path, contents: nil)
    let captureHandle = FileHandle(forWritingAtPath: wireFile.path)

    print("[agenttest] spec=\(specName) run=\(index + 1)/\(batchCount) phases=\(phases.count) capture=\(captureDir.path)")

    for (i, phaseText) in phases.enumerated() {
        // Same builder the up-front validation gate ran against, so what was
        // validated is exactly what is dispatched.
        let seedPacket = phasePacket(phaseText)
        print("[agenttest] phase \(i + 1)/\(phases.count) …")
        let wt = try txn.preparePhase(packet: seedPacket)
        // The worktree path is only known now, so the absolute arm rebuilds
        // here and is re-validated — the up-front gate ran before the model
        // loaded, this one guarantees the dispatched packet is well-formed.
        let packet = absolutePathStyle
            ? phasePacket(phaseText, absoluteRoot: wt.url.path)
            : seedPacket
        if case .invalid(let reasons) = HandoffPacketValidator.validate(packet) {
            FileHandle.standardError.write(Data(
                ("[agenttest] dispatched packet rejected for phase \(i + 1):\n"
                 + reasons.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8))
            exit(2)
        }
        let outcome: TurnOutcome
        do {
            outcome = try orch.runPhase(worker: WorkerId(1), packet: packet, worktree: wt.url,
                                        capture: captureHandle)
        } catch {
            print("[agenttest]   phase \(i + 1): runPhase failed: \(error)")
            return RunOutcome(finish: .stopped,
                              note: "phase \(i + 1) orchestrator error (worker session unusable)",
                              acceptanceExit: nil, verdict: nil, report: nil,
                              elapsed: Int(Date().timeIntervalSince(runStart)))
        }
        let result = try txn.finalizePhase(wt, packet: packet, turnOutcome: outcome, validation: nil)
        switch result {
        case .candidate(let ref, let carried, _):
            let tools = carried.toolCalls.map { $0.name }.joined(separator: ",")
            // One "turn" = one worker prompt/response; the granular measure is the
            // tool-call count. ctx_used is the session position (which compacts at
            // a soft limit), NOT a per-phase total.
            print("[agenttest]   phase \(i + 1): candidate \(ref) — \(carried.toolCalls.count) tool calls, \(carried.mutations.count) mutations, \(carried.generatedTokens) generated tokens, ctx_pos=\(carried.ctxUsed) stop=\(carried.stopReason.rawValue)")
            print("[agenttest]   tools=[\(tools)]")
            // A context-exhausted turn (limit / context_full) leaves the pooled
            // worker session full and unable to compact — the next phase's prompt
            // cannot prefill (engine: "not enough context left to request
            // compaction summary"). Stop the transaction instead of reusing the
            // session and crashing the engine.
            if carried.stopReason == .limit || carried.stopReason == .contextFull {
                print("[agenttest] STOPPING (worker session exhausted: \(carried.stopReason.rawValue) at ctx_pos=\(carried.ctxUsed))")
                return RunOutcome(finish: .stopped,
                                  note: "phase \(i + 1) session exhausted (\(carried.stopReason.rawValue) at ctx_pos=\(carried.ctxUsed))",
                                  acceptanceExit: nil, verdict: nil, report: nil,
                                  elapsed: Int(Date().timeIntervalSince(runStart)))
            }
        case .receipt(let r):
            print("[agenttest]   phase \(i + 1): receipt \(r)")
            if case .noChanges = r, outcome.stopReason == .eos {
                // A clean-eos noChanges means the phase mutated nothing because a
                // prior phase front-loaded its work (the user-story phases bleed).
                // Grade the accumulated tree instead of stopping. A limit/contextFull
                // noChanges is session exhaustion, not "already done" — stop that.
                print("[agenttest]   (noChanges + eos: continuing to grade the accumulated tree)")
                continue
            }
            return RunOutcome(finish: .stopped,
                              note: "phase \(i + 1) receipt \(r) (\(outcome.stopReason.rawValue))",
                              acceptanceExit: nil, verdict: nil, report: nil,
                              elapsed: Int(Date().timeIntervalSince(runStart)))
        }
    }

    guard let ref = txn.commitBack() else {
        return RunOutcome(finish: .stopped, note: "no candidate ref",
                          acceptanceExit: nil, verdict: nil, report: nil,
                          elapsed: Int(Date().timeIntervalSince(runStart)))
    }
    print("[agenttest] final candidate: \(ref)")

    // MARK: - grade (deterministic acceptance suite)

    var acceptanceExit: Int32 = -1
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
        acceptanceExit = p.terminationStatus
        let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("[agenttest] acceptance exit=\(p.terminationStatus)")
        print(output)
    } else {
        return RunOutcome(finish: .stopped, note: "no final worktree to grade",
                          acceptanceExit: nil, verdict: nil, report: nil,
                          elapsed: Int(Date().timeIntervalSince(runStart)))
    }

    // MARK: - DeepSeek grader (qualitative read, D6)

    // Dump the final worktree's generated code + the fixed rubric into the capture
    // dir (the committed artifact the record cites), then grade with DeepSeek. This
    // runs BEFORE `discardFinal`, while the final worktree is still present.
    var verdict = GraderVerdict(verdict: .error, reasons: [])
    if let gradeWT = txn.finalWorktree {
        var codeDump = ""
        for file in writableFiles {
            let url = gradeWT.url.appendingPathComponent(file)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            codeDump += "=== \(file) ===\n\(text)\n\n"
        }
        let rubric = specText + "\n\n" + mission + "\n\n" + techStack
        try codeDump.write(to: captureDir.appendingPathComponent("code.md"), atomically: true, encoding: .utf8)
        try rubric.write(to: captureDir.appendingPathComponent("rubric.md"), atomically: true, encoding: .utf8)

        print("[agenttest] grader: calling \(DeepSeekGrader.model) …")
        verdict = DeepSeekGrader.grade(rubric: rubric, code: codeDump)
        print("[agenttest] grader verdict: \(verdict.verdict.rawValue)")
        for reason in verdict.reasons {
            print("[agenttest]   - \(reason)")
        }
        let verdictObj: [String: Any] = ["verdict": verdict.verdict.rawValue, "reasons": verdict.reasons]
        if let data = try? JSONSerialization.data(withJSONObject: verdictObj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: captureDir.appendingPathComponent("verdict.json"))
        }
    }

    txn.discardFinal()

    // Analyze the captured wire (D5) — deterministic, re-derivable without a rerun.
    var report: AgentTestReport?
    if let wireText = try? String(contentsOf: wireFile, encoding: .utf8) {
        var parser = PoolWireParser()
        var events: [PoolWireEvent] = []
        for line in wireText.split(separator: "\n") {
            if let ev = parser.feed(String(line)) { events.append(ev) }
        }
        report = AgentTestAnalyzer.analyze(events: events)
        if let report { print(report.summary()) }
    }

    let elapsed = Int(Date().timeIntervalSince(runStart))
    print("[agenttest] elapsed: \(elapsed)s")
    return RunOutcome(finish: .completed, note: "",
                      acceptanceExit: acceptanceExit, verdict: verdict, report: report,
                      elapsed: elapsed)
}

// MARK: - batch driver

var outcomes: [RunOutcome] = []
for i in 0..<batchCount {
    do {
        outcomes.append(try runOnce(i))
    } catch {
        print("[agenttest] run \(i + 1) failed: \(error)")
        outcomes.append(RunOutcome(finish: .stopped, note: "\(error)",
                                   acceptanceExit: nil, verdict: nil, report: nil, elapsed: 0))
    }
}

if batchCount > 1 {
    let completed = outcomes.filter { $0.finish == .completed }
    let passes = completed.filter { ($0.acceptanceExit ?? 1) == 0 }.count
    let verdicts = completed.compactMap { $0.verdict }
    let good = verdicts.filter { $0.verdict == .good }.count
    let bad = verdicts.filter { $0.verdict == .bad }.count
    let errors = verdicts.filter { $0.verdict == .error }.count
    let totalCalls = completed.compactMap { $0.report }.map(\.totalToolCalls).reduce(0, +)
    let totalGen = completed.compactMap { $0.report }
        .map { $0.phases.map(\.generatedTokens).reduce(0, +) }.reduce(0, +)
    let meanElapsed = completed.isEmpty ? 0 : completed.map(\.elapsed).reduce(0, +) / completed.count
    print("[agenttest] batch \(specName): \(completed.count)/\(batchCount) completed")
    print("[agenttest]   acceptance pass \(passes)/\(completed.count), grader good/bad/error \(good)/\(bad)/\(errors)")
    print("[agenttest]   total tool calls \(totalCalls), total generated tokens \(totalGen), mean elapsed \(meanElapsed)s")
    for (i, o) in outcomes.enumerated() where o.finish == .stopped {
        print("[agenttest]   run \(i + 1) stopped: \(o.note)")
    }
}

print("[agenttest] done")
