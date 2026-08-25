import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-agenttest: the canonical agent test (P11 addendum).
//
// Decompose a roadmap into phases, run each phase as a subagent in a
// chained-worktree transaction, then grade the result with the deterministic
// acceptance suite and the DeepSeek qualitative read (D6).
//
// Usage: swift run swiftstar-agenttest --spec <roadmap|roadmap-user-story> [--repo DIR] [--batch N] [--variant mellum-2.1]
// Env:   SWIFTSTAR_MODEL (gguf, custom-path escape hatch), SWIFTSTAR_VARIANT,
//        DS4_DIR (engine), AGENTTEST_PY_PROJECT (the uv project with the
//        acceptance deps; default ~/projects/pauleveritt/local-ai-pi)

let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let specName = argValue("--spec") ?? "roadmap"
let batchCount = Int(argValue("--batch") ?? "1") ?? 1
let explicitRepo = argValue("--repo")
let fixtureName = argValue("--fixture")
let pyProject = env["AGENTTEST_PY_PROJECT"] ?? NSHomeDirectory() + "/projects/pauleveritt/local-ai-pi"

// P13: resolve the model. A selected variant (--variant / SWIFTSTAR_VARIANT) is
// verified + memory-gated once up front — before any engine is spawned —
// covering every spawn site (roadmap, fixture, repair) (C1). SWIFTSTAR_MODEL
// remains the custom-path escape hatch, recorded as unverified.
let variantID = argValue("--variant") ?? env["SWIFTSTAR_VARIANT"]
let resolvedVariant = variantID.flatMap { VariantRegistry.resolve($0) }
let gguf: String
if let v = resolvedVariant {
    switch VariantGate.admit(v, contextSize: 32_768, availableBytes: MemorySnapshot.availableBytes()) {
    case .admitted:
        break
    case .contractMismatch(let mismatches):
        FileHandle.standardError.write(Data(
            ("swiftstar-agenttest: variant '\(v.id)' refused:\n"
             + mismatches.map(\.message).joined(separator: "\n") + "\n").utf8))
        exit(2)
    case .infeasible(let reason):
        FileHandle.standardError.write(Data(
            "swiftstar-agenttest: variant '\(v.id)' infeasible: \(reason.message)\n".utf8))
        exit(2)
    }
    gguf = v.modelFile.path
} else if variantID != nil {
    FileHandle.standardError.write(Data("swiftstar-agenttest: unknown variant '\(variantID!)'\n".utf8))
    exit(2)
} else {
    guard let m = env["SWIFTSTAR_MODEL"], !m.isEmpty else {
        FileHandle.standardError.write(Data(
            "swiftstar-agenttest: SWIFTSTAR_MODEL is required (or pass --variant <id>)\n".utf8))
        exit(2)
    }
    gguf = m
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
    // C13: one phase-2 failure burned 44.7k characters of reasoning on whether
    // the vetted command changes the working directory ("working directory" x49,
    // "temp directory" x73). It does not -- SubprocessRunner runs it with cwd set
    // to the worktree, and `--project` selects only the uv environment. Verified
    // empirically, not assumed. The fact states the consequence the model
    // actually agonized over, not just the mechanism, and names the directory
    // literally in the absolute arm so nothing is left to infer.
    let cwdDescription = absoluteRoot.map { "`\($0)`" } ?? "the workspace root, the same directory the file paths above refer to"
    let facts = [
        "The vetted commands run with the working directory set to \(cwdDescription). "
        + "`--project` selects the Python environment only; it does not change the working directory. "
        + "So `import app` imports the `app.py` you wrote, and `tests/test_app.py` is the file you wrote.",
    ]

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
        facts: facts,
        redacts: redacts,
        // The packet records the sampling the run actually used, so a capture is
        // self-describing rather than needing the invocation to interpret it.
        sampling: SamplingPolicy(
            think: env["AGENTTEST_THINK"] == "1" ? .bounded : .off,
            maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192))
}

/// Build the authored repair packet (D3/D6): the directive names the failure;
/// the actual failure output + file contents are appended by `RepairLoop` as
/// `MachineEvidence`. Role `.repair`, thinking off (or bounded via
/// `AGENTTEST_REPAIR_THINK=1`), same contract/writableFiles/redacts as implement.
func repairPacket(_ ctx: RepairContext) -> HandoffPacket {
    let vettedImport = "uv run --project \(pyProject) python -c 'import app'"
    let vettedPytest = "uv run --project \(pyProject) python -m pytest tests/test_app.py -q"
    let renderedFiles = writableFiles.map { "- \($0)" }.joined(separator: "\n")
    let pathRule = ["All tool paths are relative to the workspace root (e.g. `app.py`,",
                    "`templates/base.html`) — never absolute paths."]
    let facts = [
        "The vetted commands run with the working directory set to the workspace root. "
        + "`--project` selects the Python environment only; it does not change the working directory. "
        + "So `import app` imports the `app.py` in this workspace, and `tests/test_app.py` is the file in this workspace.",
    ]
    let directive = ([
        "The acceptance suite failed against the code written by a prior phase.",
        "Diagnose the defect from the failure output and the current file contents",
        "appended below under \"Failure evidence (machine output)\", then fix exactly",
        "the file(s) that are wrong. Edit the code — do not rewrite working files,",
        "and do not add new files or routes.",
    ]).joined(separator: " ")
    let writableNote = ([
        "You may write or edit only these files:",
        renderedFiles,
    ] + pathRule + [
        "You may run exactly these two commands (and no other shell command):",
        "- \(vettedImport)   (does app.py import cleanly?)",
        "- \(vettedPytest)   (do your own tests pass?)",
        "Work in one concise pass: make the minimal edit that fixes the failure,",
        "then run those commands at most once each.",
    ]).joined(separator: "\n")
    // The packet records the sampling the run actually used (same invariant as
    // phasePacket, above): thinking is a property of the whole pooled engine
    // process, set once at spawn time via AgentSettings.noThink (AGENTTEST_THINK),
    // not something dispatch can override per-packet. AGENTTEST_REPAIR_THINK is
    // reserved for a per-worker think override — not yet wired; see P12.6 — and
    // has no effect today, so deriving from it here would make the capture claim
    // a sampling mode the engine did not actually run under.
    if env["AGENTTEST_REPAIR_THINK"] != nil {
        let warning = "[agenttest] note: AGENTTEST_REPAIR_THINK is currently inert (deferred to "
            + "P12.6); repair think mode mirrors AGENTTEST_THINK\n"
        FileHandle.standardError.write(Data(warning.utf8))
    }
    let think: ThinkMode = env["AGENTTEST_THINK"] == "1" ? .bounded : .off
    return PhasePacketBuilder.build(
        phaseText: directive,
        writableNote: writableNote,
        preamble: preamble,
        sharedContext: sharedContext,
        writableFiles: writableFiles,
        validationCommand: vettedImport,
        selfTestCommand: vettedPytest,
        toolCallBudget: Int(env["AGENTTEST_TOOL_BUDGET"] ?? "30") ?? 30,
        facts: facts,
        redacts: redacts,
        sampling: SamplingPolicy(think: think,
                                 maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192),
        role: .repair)
}

// Validate every phase packet up front — before the model loads. The packets are
// worktree-independent, so a malformed one (an absolute path, an empty manifest,
// or a withheld fix leaked through the appended shared context) is caught in
// microseconds instead of after a 45–65 GiB load and three phases of generation.
// Fixture mode (D10) never builds `phases`/`phasePacket` at all — it grades a
// pre-seeded fixture and drives `repairPacket` directly — so this loop is
// skipped entirely when `--fixture` is active; guarding it here rather than
// deferring `phases`/`decompose` themselves keeps the non-fixture path unchanged.
if fixtureName == nil {
    for (i, phaseText) in phases.enumerated() {
        if case .invalid(let reasons) = HandoffPacketValidator.validate(phasePacket(phaseText)) {
            FileHandle.standardError.write(Data(
                ("swiftstar-agenttest: packet rejected for phase \(i + 1):\n"
                 + reasons.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8))
            exit(2)
        }
    }
}

// Validate the repair packet up front too (both fixture and live paths dispatch
// one), using a synthetic/representative RepairContext — repairPacket does not
// read the context's fields when assembling the directive/contract, only the
// shared spec/redacts state closed over above, so a placeholder context is
// sufficient to catch the same class of defect (an absolute path, an empty
// manifest, a withheld fix leaked through) before a model loads. Without this,
// a malformed repairPacket only surfaces as RepairLoopError.packetInvalid from
// inside RepairLoop.run, at repair-round time — after a full model load and all
// implement phases have already run.
let syntheticRepairContext = RepairContext(failedRef: "", grade: GradeResult(exit: 1, output: ""), round: 1)
if case .invalid(let reasons) = HandoffPacketValidator.validate(repairPacket(syntheticRepairContext)) {
    FileHandle.standardError.write(Data(
        ("swiftstar-agenttest: repair packet rejected:\n"
         + reasons.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8))
    exit(2)
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

func gitOutput(_ dir: URL, _ a: [String]) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = ["-C", dir.path] + a
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    try p.run(); p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func copyTree(_ from: URL, into to: URL) throws {
    let items = try FileManager.default.contentsOfDirectory(at: from, includingPropertiesForKeys: nil)
    for src in items {
        let dst = to.appendingPathComponent(src.lastPathComponent)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
            try copyTree(src, into: dst)
        } else {
            try FileManager.default.copyItem(at: src, to: dst)
        }
    }
}

/// D10: seed a repo with `reference/*` + a fixture's buggy `app.py`, commit it
/// as the failed candidate ref, grade (12/13), run RepairLoop, and assert 13/13.
func runFixtureOnce(_ name: String) throws {
    let fixtureBug = fixtureDir.appendingPathComponent("repair/\(name)/app.py")
    let referenceRoot = fixtureDir.appendingPathComponent("reference")
    let acceptanceSource = try String(
        contentsOf: fixtureDir.appendingPathComponent("acceptance/test_acceptance.py"),
        encoding: .utf8)

    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("agenttest-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    git(repo, ["init", "-q"])
    git(repo, ["config", "user.email", "agenttest@local"])
    git(repo, ["config", "user.name", "AgentTest"])

    // Overlay reference/* then the fixture's buggy app.py.
    try copyTree(referenceRoot, into: repo)
    try FileManager.default.removeItem(at: repo.appendingPathComponent("app.py"))
    try String(contentsOf: fixtureBug, encoding: .utf8)
        .write(to: repo.appendingPathComponent("app.py"), atomically: true, encoding: .utf8)
    git(repo, ["add", "-A"])
    git(repo, ["commit", "-q", "-m", "fixture baseline"])

    let failedRef = try gitOutput(repo, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    let initial = try AcceptanceGrader.grade(worktree: repo, acceptanceSource: acceptanceSource, pyProject: pyProject)
    print("[agenttest] fixture \(name): baseline exit=\(initial.exit)")
    guard initial.exit != 0 else {
        print("[agenttest] fixture \(name): expected a failing baseline, got 13/13 — overlay is wrong")
        exit(2)
    }

    let orch = try PoolOrchestrator(settings: AgentSettings(
        engineDir: engineDir, modelPath: URL(fileURLWithPath: gguf),
        contextSize: 32768, workspace: repo, shellAllowed: false,
        maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192,
        noThink: env["AGENTTEST_THINK"] != "1",
        thinkBudget: Int(env["AGENTTEST_THINK_BUDGET"] ?? "0") ?? 0,
        seed: UInt64(env["AGENTTEST_SEED"] ?? "0") ?? 0))
    defer { orch.stop() }

    // Give the fixture tier the same capture trail runOnce gets (D5/D9). D10's
    // own caveat is that this tier — a single fixed repair scenario, not a
    // guaranteed-pass smoke test — is the one most likely to fail on a first
    // attempt, so it is exactly the tier that most needs an evidence trail
    // (repair-packet-N.json / repair-round-N.json / wire.ndjson) when it does.
    let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
    let captureDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("captures/agenttest/\(df.string(from: Date()))-fixture-\(name)")
    try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
    let wireFile = captureDir.appendingPathComponent("wire.ndjson")
    FileManager.default.createFile(atPath: wireFile.path, contents: nil)
    let captureHandle = FileHandle(forWritingAtPath: wireFile.path)
    print("[agenttest] fixture \(name): capture=\(captureDir.path)")

    let result = try RepairLoop.run(
        repo: repo, failedRef: failedRef, initialGrade: initial,
        packetBuilder: repairPacket,
        runPhase: { pkt, wt, cap in try orch.runPhase(worker: WorkerId(1), packet: pkt, worktree: wt, capture: cap) },
        grade: { wt in try AcceptanceGrader.grade(worktree: wt, acceptanceSource: acceptanceSource, pyProject: pyProject) },
        capture: captureHandle,
        captureDir: captureDir)

    switch result {
    case .passed(_, let grade, let wt):
        print("[agenttest] fixture \(name): repaired — exit=\(grade.exit)")
        WorktreeDispatcher.discard(wt, in: repo)
        if grade.exit == 0 { print("[agenttest] fixture \(name): 13/13 ✓"); return }
        print("[agenttest] fixture \(name): repaired but still failing — \(grade.exit)")
        exit(1)
    case .exhausted(_, let receipt):
        print("[agenttest] fixture \(name): repair exhausted — \(receipt)")
        exit(1)
    }
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
        noThink: env["AGENTTEST_THINK"] != "1",
        // AGENTTEST_THINK_BUDGET bounds a round's thinking while leaving the
        // rest of maxTokens for action. C14 run 3 spent 2,343 think events and
        // 8,192 generated tokens to produce one mutation before dying of
        // context; a ceiling well under the total cap is the point.
        thinkBudget: Int(env["AGENTTEST_THINK_BUDGET"] ?? "0") ?? 0,
        seed: UInt64(env["AGENTTEST_SEED"] ?? "0") ?? 0)
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

    // D3: make the capture self-describing. `wire.ndjson` carries no model name
    // and no config, so distinguishing two same-morning batches previously meant
    // reading engine memory-plan lines and guessing.
    let runConfig: [String: String] = [
        "model": gguf,
        "spec": specName,
        "think": env["AGENTTEST_THINK"] == "1" ? "on" : "nothink",
        "thinkBudget": env["AGENTTEST_THINK_BUDGET"] ?? "0",
        "maxTokens": env["AGENTTEST_MAX_TOKENS"] ?? "8192",
        "toolBudget": env["AGENTTEST_TOOL_BUDGET"] ?? "30",
        "pathStyle": absolutePathStyle ? "absolute" : "relative",
        "redacts": redacts.joined(separator: ","),
        // D9: run-config gains the repair fields too. repairThink mirrors what
        // repairPacket's think mode actually derives from (AGENTTEST_THINK, per
        // the fix above) rather than the unwired AGENTTEST_REPAIR_THINK, so the
        // capture stays honest about what the engine ran under. repairMaxRounds
        // is RepairLoop.run's default bound (not currently env-configurable).
        "repairThink": env["AGENTTEST_THINK"] == "1" ? "on" : "nothink",
        "repairMaxRounds": "2",
        // P13: record the variant + sampler source + available memory so the
        // capture is self-describing (I2/I7).
        "variant": resolvedVariant?.id ?? "custom-unverified",
        "sampler": (resolvedVariant?.sampler?.description ?? "").isEmpty
            ? "engine-family-default"
            : (resolvedVariant?.sampler?.description ?? ""),
        "availableBytesGiB": String(format: "%.1f", Double(MemorySnapshot.availableBytes()) / 1_073_741_824),
        "seed": env["AGENTTEST_SEED"] ?? "0",
    ]
    if let cfg = try? JSONSerialization.data(withJSONObject: runConfig, options: [.prettyPrinted, .sortedKeys]) {
        try? cfg.write(to: captureDir.appendingPathComponent("run-config.json"))
    }
    if let pkt = try? JSONEncoder().encode(phasePacket(phases[0])) {
        try? pkt.write(to: captureDir.appendingPathComponent("packet.json"))
    }

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
        // Run the packet's own vetted import check before the phase may report
        // a candidate. C17: two runs completed every phase, wrote every file,
        // and died in acceptance *collection* on one wrong import line
        // (`fastapi.templates`, and RedirectResponse from the wrong module) --
        // while this exact command sat in the packet, unused. A phase whose code
        // cannot be imported is not a candidate, and the verdict already knows
        // how to say so (`.validationFailed`). Catching it here also stops a
        // broken tree from being chained into the next phase.
        let validation = try WorktreeDispatcher.runValidation(packet.validationCommand, in: wt.url)
        if let validation, !validation.passed {
            print("[agenttest]   phase \(i + 1): import check failed (exit \(validation.exit))")
        }
        let result = try txn.finalizePhase(wt, packet: packet, turnOutcome: outcome,
                                           validation: validation)
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

    // MARK: - grade (deterministic acceptance suite) + repair on failure

    guard let failedWT = txn.finalWorktree else {
        return RunOutcome(finish: .stopped, note: "no final worktree to grade",
                          acceptanceExit: nil, verdict: nil, report: nil,
                          elapsed: Int(Date().timeIntervalSince(runStart)))
    }
    let acceptanceSource = try String(
        contentsOf: fixtureDir.appendingPathComponent("acceptance/test_acceptance.py"),
        encoding: .utf8)
    var grade = try AcceptanceGrader.grade(
        worktree: failedWT.url, acceptanceSource: acceptanceSource, pyProject: pyProject)
    var acceptanceExit = grade.exit
    print("[agenttest] acceptance exit=\(grade.exit)")
    print(grade.output)
    try? "exit=\(grade.exit)\n\n\(grade.output)"
        .write(to: captureDir.appendingPathComponent("acceptance.txt"),
               atomically: true, encoding: .utf8)

    var gradeWorktree = failedWT
    var gradeWorktreeOwnedByTxn = true
    var repairNote = ""

    if !grade.passed {
        do {
            let repair = try RepairLoop.run(
                repo: repoURL,
                failedRef: ref,          // txn.candidateRef (the failed implement chain)
                initialGrade: grade,
                packetBuilder: repairPacket,
                runPhase: { pkt, wt, cap in
                    try orch.runPhase(worker: WorkerId(2), packet: pkt, worktree: wt, capture: cap)
                },
                grade: { wt in try AcceptanceGrader.grade(
                    worktree: wt, acceptanceSource: acceptanceSource, pyProject: pyProject) },
                capture: captureHandle,
                captureDir: captureDir)
            switch repair {
            case .passed(let repairedRef, let g, let wt):
                grade = g
                acceptanceExit = g.exit
                gradeWorktree = wt
                gradeWorktreeOwnedByTxn = false
                repairNote = "repaired \(repairedRef)"
                print("[agenttest] repair: passed — \(repairedRef) (exit \(g.exit))")
                try? "exit=\(g.exit)\n\n\(g.output)\n\nrepaired: \(repairedRef)"
                    .write(to: captureDir.appendingPathComponent("acceptance.txt"),
                           atomically: true, encoding: .utf8)
            case .exhausted(_, let receipt):
                repairNote = "repair exhausted (\(receipt))"
                print("[agenttest] repair: exhausted — \(receipt)")
            }
        } catch RepairLoopError.sessionExhausted(let reason) {
            txn.discardFinal()
            return RunOutcome(finish: .stopped,
                              note: "repair session exhausted (\(reason.rawValue))",
                              acceptanceExit: nil, verdict: nil, report: nil,
                              elapsed: Int(Date().timeIntervalSince(runStart)))
        }
    }

    // MARK: - DeepSeek grader (qualitative read, D6) against the graded tree

    var verdict = GraderVerdict(verdict: .error, reasons: [])
    var codeDump = ""
    for file in writableFiles {
        let url = gradeWorktree.url.appendingPathComponent(file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
        codeDump += "=== \(file) ===\n\(text)\n\n"
    }
    let rubric = specText + "\n\n" + mission + "\n\n" + techStack
    try codeDump.write(to: captureDir.appendingPathComponent("code.md"), atomically: true, encoding: .utf8)
    try rubric.write(to: captureDir.appendingPathComponent("rubric.md"), atomically: true, encoding: .utf8)

    print("[agenttest] grader: calling \(DeepSeekGrader.model) …")
    verdict = DeepSeekGrader.grade(rubric: rubric, code: codeDump)
    print("[agenttest] grader verdict: \(verdict.verdict.rawValue)")
    for reason in verdict.reasons { print("[agenttest]   - \(reason)") }
    let verdictObj: [String: Any] = ["verdict": verdict.verdict.rawValue, "reasons": verdict.reasons]
    if let data = try? JSONSerialization.data(withJSONObject: verdictObj, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: captureDir.appendingPathComponent("verdict.json"))
    }

    // Discard the graded worktree: txn-owned via discardFinal, repair-owned via WorktreeDispatcher.
    if gradeWorktreeOwnedByTxn {
        txn.discardFinal()
    } else {
        WorktreeDispatcher.discard(gradeWorktree, in: repoURL)
        txn.discardFinal()
    }

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
    return RunOutcome(finish: .completed, note: repairNote,
                      acceptanceExit: acceptanceExit, verdict: verdict, report: report,
                      elapsed: elapsed)
}

// MARK: - fixture driver (D10)

if let fixtureName {
    do { try runFixtureOnce(fixtureName) }
    catch { print("[agenttest] fixture run failed: \(error)"); exit(1) }
    print("[agenttest] done")
    exit(0)
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
