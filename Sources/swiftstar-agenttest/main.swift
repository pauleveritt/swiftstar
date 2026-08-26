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
// D11: the text-contract build is gated behind an env flag so the default
// remains agentic (the forcing-gate experiment must run agentic too).
let textContractBuild = env["AGENTTEST_TEXT_CONTRACT"] == "1"
// P12.5: dispatch one model-authored decompose packet on its own pool worker
// before the phase loop, instead of the naive host string split. Off by
// default, matching every other P12.1-era lever. See
// docs/superpowers/specs/2026-08-25-p12-5-model-authored-packets-design.md.
let modelDecompose = env["AGENTTEST_MODEL_DECOMPOSE"] == "1"

// P16: the repair round budget, env-configurable as of 2026-08-26. The n=4
// measure batch showed the 2-round default was the binding constraint on what
// could be observed, not the model: in 2 of 3 valid cells Mellum reached an
// actionable failure surface on the SAME round the budget expired (one cleared
// the precondition gate at round 2 and was never shown the assertions it had
// just unlocked). Recorded in run-config.json so a capture stays self-describing.
let repairMaxRounds = max(1, Int(env["AGENTTEST_REPAIR_ROUNDS"] ?? "2") ?? 2)

/// The temperature the engine actually samples at.
///
/// `AgentSettings` carries no temperature field and `PoolOrchestrator` records
/// every turn's sampler as `"engine-defaults"` — the harness never transmits one,
/// so the engine samples at its own family defaults, which for a resolved variant
/// are exactly the values that variant declares. Meanwhile
/// `SamplingPolicy.temperature` defaults to 0, so every stored packet claimed
/// *greedy* decoding for runs that were not greedy: found 2026-08-25, when
/// `run-config.json` said `temp 0.6` and `repair-packet-1.json` said
/// `temperature: 0` for the same run. Same class of defect as the
/// `AGENTTEST_REPAIR_THINK` note below — a packet must not assert a sampling mode
/// the engine did not run under — so record what the engine really uses.
let engineTemperature = resolvedVariant?.sampler?.temperature ?? 0


/// Strings this run's spec is supposed to withhold, comma-separated
/// (`AGENTTEST_REDACT="default_factory,fastapi.responses"`). An experiment cell
/// that claims the worker must *diagnose* a fix declares the fix here, and the
/// harness refuses to dispatch a packet that states it anywhere — the check
/// that would have caught the near-miss cell shipping its own answer.
let redacts = (env["AGENTTEST_REDACT"] ?? "")
    .split(separator: ",")
    .map { $0.trimmingCharacters(in: .whitespaces) }
    .filter { !$0.isEmpty }

// `decompose(_:)` (the host's naive `## Phase` splitter) moved to
// SwiftStarKit/Decompose.swift (P12.5, D2) so it is unit-testable on its own
// and reusable for both the host split (here) and a model's decompose reply
// (inside runOnce, gated behind AGENTTEST_MODEL_DECOMPOSE — see below).
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
func phasePacket(_ phaseText: String, absoluteRoot: String? = nil, textContract: Bool = false) -> HandoffPacket {
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

    // The text-contract directive ("Do not call tools …") only belongs on
    // text-contract phase packets; the forcing re-prompt and default agentic
    // builds pass textContract: false and must stay clean of it.
    let contractPrefix: [String] = textContract ? [TextContract.directive, ""] : []
    let writableNote = (contractPrefix + [
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
        textContract: textContract,
        turnBudget: textContract ? max(100_000, renderedFiles.utf8.count * 4) : 100_000,
        facts: facts,
        redacts: redacts,
        // The packet records the sampling the run actually used, so a capture is
        // self-describing rather than needing the invocation to interpret it.
        // `temperature` is the engine's, not the harness's — see engineTemperature.
        sampling: SamplingPolicy(
            think: env["AGENTTEST_THINK"] == "1" ? .bounded : .off,
            maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192,
            temperature: engineTemperature))
}

/// Build the authored repair packet (D3/D6): the directive names the failure;
/// the actual failure output + file contents are appended by `RepairLoop` as
/// `MachineEvidence`. Role `.repair`, thinking off (or bounded via
/// `AGENTTEST_REPAIR_THINK=1`), same contract/writableFiles/redacts as implement.
/// Turn 2 of the two-turn emission protocol (see the seam in `RepairLoop`). Turn
/// 1 is allowed to reason and reliably stops at eos the moment the file should
/// begin; this is the short continuation that only has to emit. It names no new
/// facts on purpose — everything it needs is the model's own prior assistant
/// turn, still in the pooled worker's session.
let repairEmissionFollowUp = ([
    "Now emit it. Your entire response must be the heading line for the file you",
    "just diagnosed, followed by one fenced code block containing that file's",
    "complete corrected contents with the correction you just described already",
    "applied. Nothing before the heading line and nothing after the closing fence.",
    "Do not explain anything further and do not restate the diagnosis.",
]).joined(separator: " ")

/// The build arm's half of the two-turn emission protocol. Same shape as
/// `repairEmissionFollowUp`, but a build phase writes a set of files rather than
/// the one file it just diagnosed.
let buildEmissionFollowUp = ([
    "Now emit the files. Your entire response must be, for each file, the heading",
    "line followed immediately by one fenced code block containing that file's",
    "complete contents. Nothing before the first heading line and nothing after",
    "the last closing fence. Do not explain anything and do not restate the plan.",
]).joined(separator: " ")

func repairPacket(_ ctx: RepairContext, phaseScoped: Bool = false) -> HandoffPacket {
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
    // The repair *ask*, not the parser, was the P15 repair blocker. Measured
    // 2026-08-25 (capture 20260825-160310): Mellum diagnosed the 307/303 bug
    // correctly, emitted a diff block and a snippet, then closed with "Now I'll
    // create the exact file content with this change:" and stopped at eos with
    // 510 of 8192 tokens used. It treated *explaining* the fix as the whole
    // turn. Constraining the response to start at the heading fixed emission
    // completely (capture 20260825-163139: two conforming turns, both harvested
    // to candidates) but the file returned was a byte-identical re-emission of
    // the broken original — the correct diagnosis the narrating run produced had
    // vanished. The narration was carrying the reasoning, so this variant keeps
    // the reasoning and moves the file to the END of the response rather than
    // suppressing the prose. First-complete-block-wins makes "do not reproduce
    // the current broken file" load-bearing: a quoted original under the same
    // heading would be harvested in preference to the fix.
    // Which flavor of "how many files are wrong" to assert depends on what the
    // evidence RepairLoop is about to append actually shows (D-fix, 2026-08-26):
    // the fixed "exactly one file is wrong" text below is well-calibrated for
    // a build phase that wrote most of the app and left one real bug (P12.4's
    // original design target, and still true whenever count <= 1) but was
    // false, unconditionally, whenever 2+ writable files are missing or wrong
    // -- the overnight matrix's dominant Mellum defect (39/40 cells): the
    // model derived the correct multi-file fix and then cited this exact text
    // back three times to justify not making it (verbatim in
    // captures/agenttest/20260826-060458-roadmap's worker-2 transcript).
    let missingCount = ctx.missingWritableFiles.count
    let scope = phaseScoped
        ? "The import check failed against the code written by this phase."
        : "The acceptance suite failed against the code written by a prior phase."
    let reRun = phaseScoped ? "re-runs the import check itself" : "re-runs the suite itself"
    let directive = (missingCount >= 2 ? [
        scope,
        "The failure output and the current file contents are appended below",
        "under \"Failure evidence (machine output)\".",
        "\(missingCount) of the files you may edit are missing or wrong — not",
        "one. First, in a few sentences, work out from the failure output and",
        "the current file contents which of them need to change. Then, for",
        "each file that needs to change, emit its heading line followed by one",
        "fenced code block holding that file's complete corrected contents —",
        "one heading-plus-block pair per file, in any order. Nothing before",
        "the first heading line and nothing after the last closing fence.",
        "Do not emit a diff or a partial snippet for any file, and do not",
        "reproduce a file that is already correct. The host applies every",
        "file you return exactly as written and \(reRun).",
        "Do not rewrite files not listed above and do not add new routes.",
    ] : [
        scope,
        "The failure output and the current file contents are appended below",
        "under \"Failure evidence (machine output)\".",
        "Exactly one file is wrong. First, in a few sentences, work out what the",
        "failure output tells you and what the corrected line must be. Then emit",
        "the heading line for that file followed by one fenced code block holding",
        "that file's complete corrected contents. The heading line and its fenced",
        "block must be the LAST thing in your response — end with the closing",
        "fence and write nothing after it.",
        "Do not emit a diff or a partial snippet, and do not reproduce the current",
        "broken file: emit the corrected file exactly once. The host applies the",
        "file you return exactly as written and \(reRun).",
        "Do not rewrite working files and do not add new files or routes.",
    ]).joined(separator: " ")
    let writableNote = ([
        TextContract.directive,
        "",
        "You may write or edit only these files:",
        renderedFiles,
    ] + pathRule + [
        // A text-contract turn is told "Do not call tools" by TextContract.directive
        // above; listing runnable commands here contradicted that in the same
        // packet. The host owns execution in this mode, so it says so instead.
        "Do not run any command. After you return the file, the host runs the",
        phaseScoped
            ? "import check itself and re-validates the result."
            : "import check and the acceptance suite itself and re-grades the result.",
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
        textContract: true,
        facts: facts,
        redacts: redacts,
        sampling: SamplingPolicy(think: think,
                                 maxTokens: Int(env["AGENTTEST_MAX_TOKENS"] ?? "8192") ?? 8192,
                                 temperature: engineTemperature),
        role: .repair)
}

// P12.5 (D1): the `role: .decompose` packet itself — `DecomposePacket.build`/
// `.followUp()` — lives in SwiftStarKit (Sources/SwiftStarKit/Decompose.swift)
// rather than here alongside `repairPacket`, specifically so its shape
// (`writableFiles: []`, no validation command, `role: .decompose`) is
// unit-testable from `SwiftStarKitTests` — this file's top-level `main.swift`
// code cannot be `@testable import`ed. See that file's doc comments for why
// it is exempt from `HandoffPacketValidator.validate` by construction.

// Validate every phase packet up front — before the model loads. The packets are
// worktree-independent, so a malformed one (an absolute path, an empty manifest,
// or a withheld fix leaked through the appended shared context) is caught in
// microseconds instead of after a 45–65 GiB load and three phases of generation.
// Fixture mode (D10) never builds `phases`/`phasePacket` at all — it grades a
// pre-seeded fixture and drives `repairPacket` directly — so this loop is
// skipped entirely when `--fixture` is active; guarding it here rather than
// deferring `phases`/`decompose` themselves keeps the non-fixture path unchanged.
//
// P12.5 (D1): the model-decompose arm skips this gate too, and deliberately
// so, not by accident. The packets it would validate here are built from the
// HOST's split of the spec text — but in that arm those phase texts are never
// what gets dispatched; `runOnce` replaces `phases` with the model's own
// decompose output before the dispatch loop runs, and the model hasn't been
// asked yet at this point in the program (no engine has even spawned). There
// is no way to validate "the phases that will actually be dispatched" this
// early in that arm — decomposition itself needs a loaded model. Skipping
// this gate does not silently validate a stale/empty `phases` against nothing
// downstream cares about; it is skipped outright. The real gate for that arm
// is the per-phase check inside the dispatch loop (~line 613 in the original
// layout), which validates every phase's packet — host-split or
// model-authored — right before it is dispatched, unchanged by this design.
if fixtureName == nil, !modelDecompose {
    for (i, phaseText) in phases.enumerated() {
        if case .invalid(let reasons) = HandoffPacketValidator.validate(phasePacket(phaseText, textContract: textContractBuild)) {
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
        writableFiles: writableFiles,
        packetBuilder: { repairPacket($0) },
        runPhase: { pkt, wt, cap in try orch.runPhase(worker: WorkerId(1), packet: pkt, worktree: wt, capture: cap) },
        grade: { wt in try AcceptanceGrader.grade(worktree: wt, acceptanceSource: acceptanceSource, pyProject: pyProject) },
        capture: captureHandle,
        captureDir: captureDir,
        maxCandidateRounds: repairMaxRounds,
        emissionFollowUp: repairEmissionFollowUp)

    switch result {
    case .passed(_, let grade, let wt):
        print("[agenttest] fixture \(name): repaired — exit=\(grade.exit)")
        WorktreeDispatcher.discard(wt, in: repo)
        if grade.exit == 0 { print("[agenttest] fixture \(name): 13/13 ✓"); return }
        print("[agenttest] fixture \(name): repaired but still failing — \(grade.exit)")
        exit(1)
    case .exhausted(_, let receipt, let best):
        if let best { WorktreeDispatcher.discard(best.worktree, in: repo) }
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

    // Capture the raw wire to a committed artifact so the analyzer can re-derive
    // everything without rerunning (D5). Computed before `settings` so the
    // trace path (P12.7 piece 1) can point at this same directory.
    let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = batchCount > 1 ? "-run\(index + 1)" : ""
    let captureDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("captures/agenttest/\(df.string(from: Date()))-\(specName)\(suffix)")
    try FileManager.default.createDirectory(at: captureDir, withIntermediateDirectories: true)
    let wireFile = captureDir.appendingPathComponent("wire.ndjson")
    FileManager.default.createFile(atPath: wireFile.path, contents: nil)
    let captureHandle = FileHandle(forWritingAtPath: wireFile.path)
    // P12.7 piece 1: every capture dir gets a `wire.trace` file the same way it
    // already gets `wire.ndjson` — unconditional, matching swiftstar-drive's
    // own naming (Sources/swiftstar-drive/main.swift). The engine writes to
    // this path directly and independently of stdin/stdout/stderr; it is read
    // back from disk after the run completes (below), not streamed live.
    let tracePath = captureDir.appendingPathComponent("wire.trace")

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
        seed: UInt64(env["AGENTTEST_SEED"] ?? "0") ?? 0,
        tracePath: tracePath)
    // P12.5 (D1): the model-decompose arm bumps the pool from 3 to 4 so
    // decompose gets its own independent KV-cache session (WorkerId(3)) that
    // cannot collide with the engine's untagged startup handshake (which
    // parses to WorkerId.orchestrator / id 0 by the wire parser's
    // absent-field default) or with the implement/repair sessions (1/2).
    let orch = try PoolOrchestrator(settings: settings, workers: modelDecompose ? 4 : 3)
    defer { orch.stop() }
    let txn = WorktreeTransaction(repo: repoURL)
    defer { txn.abort() }

    // P12.5 (D1): dispatch one model-authored decompose packet, before the
    // phase loop, on WorkerId(3) — a fresh fourth pool session, never
    // WorkerId.orchestrator/WorkerId(0) (collides with the engine's untagged
    // startup handshake — round 2 of the design's review) and never
    // WorkerId(1)/WorkerId(2) (implement/repair — dispatching decompose there
    // would pollute those sessions and confound the very build-vs-repair
    // comparison this project measures). `phases` is shadowed as a local
    // `var` here so the model's output can replace it for this run only; the
    // global `let (preamble, phases)` computed from the host split above is
    // untouched, and `preamble` is never replaced regardless of arm (D1) — the
    // shared spec context every packet gets stays host-computed.
    var phases = phases
    if modelDecompose {
        // Same rule as every other packet (comment at phasePacket's own
        // `sampling:` argument): the packet records the sampling the run
        // actually used, so a capture is self-describing. `SamplingPolicy()`'s
        // bare default is `.bounded`, which would misdescribe a nothink run.
        let decomposeThink: ThinkMode = env["AGENTTEST_THINK"] == "1" ? .bounded : .off
        print("[agenttest] decompose: dispatching model-authored decompose packet on worker 3 …")
        let firstOutcome = try orch.runPhase(
            worker: WorkerId(3), packet: DecomposePacket.build(specText: specText, think: decomposeThink),
            worktree: repoURL, capture: captureHandle)
        var finalText = firstOutcome.text
        var decision = DecomposeDispatch.decide(
            text: firstOutcome.text, stopReason: firstOutcome.stopReason, isFollowUp: false)
        // D3: one emission follow-up, on the same worker/session, before
        // calling it model failure #1 — the same reason-then-stop protection
        // P15 needed for repair/build, scaled to decompose's prose shape.
        if case .needsFollowUp = decision {
            print("[agenttest] decompose: 0 phases parsed, turn reasoned without emitting — sending emission follow-up")
            let followUpOutcome = try orch.runPhase(
                worker: WorkerId(3), packet: DecomposePacket.followUp(think: decomposeThink),
                worktree: repoURL, capture: captureHandle)
            finalText = followUpOutcome.text
            decision = DecomposeDispatch.decide(
                text: followUpOutcome.text, stopReason: followUpOutcome.stopReason, isFollowUp: true)
        }
        // D4: persist the raw decompose text (the turn that was actually
        // parsed — the follow-up's if one ran) so the parse is independently
        // reproducible later — "no number without its capture."
        try? finalText.write(to: captureDir.appendingPathComponent("decompose-output.txt"),
                              atomically: true, encoding: .utf8)
        switch decision {
        case .parsed(let modelPhases):
            print("[agenttest] decompose: model produced \(modelPhases.count) phase(s)")
            phases = modelPhases
        case .needsFollowUp, .failedClosed:
            // `.needsFollowUp` cannot actually recur here (`decide(isFollowUp:
            // true)` never returns it) but the switch must stay exhaustive;
            // both arms of this case mean the same thing at this point in the
            // control flow — zero phases parsed, nothing left to try. D2: no
            // fallback to the host split — that would silently substitute the
            // untested path for the tested one and defeat the point of P12.5.
            FileHandle.standardError.write(Data(
                ("swiftstar-agenttest: model decompose failed closed — 0 phases parsed even "
                 + "after the emission follow-up; not falling back to the host split\n").utf8))
            return RunOutcome(finish: .stopped,
                              note: "model decompose failed closed (0 phases parsed)",
                              acceptanceExit: nil, verdict: nil, report: nil,
                              elapsed: Int(Date().timeIntervalSince(runStart)))
        }
    }

    print("[agenttest] spec=\(specName) run=\(index + 1)/\(batchCount) phases=\(phases.count) capture=\(captureDir.path)")

    // D3: make the capture self-describing. `wire.ndjson` carries no model name
    // and no config, so distinguishing two same-morning batches previously meant
    // reading engine memory-plan lines and guessing.
    let seedEnv = UInt64(env["AGENTTEST_SEED"] ?? "0") ?? 0
    let seedRecord = seedEnv > 0
        ? String(seedEnv)
        : "unseeded (--seed omitted; engine picks a time-derived seed — runs are not reproducible)"
    let runConfig: [String: String] = [
        "model": gguf,
        "spec": specName,
        "think": env["AGENTTEST_THINK"] == "1" ? "on" : "nothink",
        "thinkBudget": env["AGENTTEST_THINK_BUDGET"] ?? "0",
        "maxTokens": env["AGENTTEST_MAX_TOKENS"] ?? "8192",
        "toolBudget": env["AGENTTEST_TOOL_BUDGET"] ?? "30",
        "pathStyle": absolutePathStyle ? "absolute" : "relative",
        "redacts": redacts.joined(separator: ","),
        // P12.5 (D4): the two arms are otherwise distinguishable only by the
        // presence of decompose-output.txt in the capture dir — say so
        // in-band instead of leaving it to be inferred from a file's absence.
        "modelDecompose": modelDecompose ? "on" : "off",
        "poolWorkers": modelDecompose ? "4" : "3",
        // D9: run-config gains the repair fields too. repairThink mirrors what
        // repairPacket's think mode actually derives from (AGENTTEST_THINK, per
        // the fix above) rather than the unwired AGENTTEST_REPAIR_THINK, so the
        // capture stays honest about what the engine ran under. repairMaxRounds
        // is the bound this run actually used (AGENTTEST_REPAIR_ROUNDS).
        "repairThink": env["AGENTTEST_THINK"] == "1" ? "on" : "nothink",
        "repairMaxRounds": String(repairMaxRounds),
        // P13: record the variant + sampler source + available memory so the
        // capture is self-describing (I2/I7).
        "variant": resolvedVariant?.id ?? "custom-unverified",
        "sampler": (resolvedVariant?.sampler?.description ?? "").isEmpty
            ? "engine-family-default"
            : (resolvedVariant?.sampler?.description ?? ""),
        "availableBytesGiB": String(format: "%.1f", Double(MemorySnapshot.availableBytes()) / 1_073_741_824),
        // A seed of 0 does NOT mean "seeded with 0": `AgentCommand` omits --seed
        // entirely when seed == 0, so the engine picks a time-derived seed and the
        // run is not reproducible. Recording a bare "0" read as a pinned seed and
        // made four runs that differed look like an unexplained nondeterminism
        // (2026-08-25); say which it is instead.
        "seed": seedRecord,
        "phases": String(phases.count),
        "textContract": textContractBuild ? "on" : "off",
        // D11 measurement hygiene: a text-contract run's files are written by the
        // host from the model's prose, with zero tool calls. Every such capture
        // says so in-band, so a later reader cannot mistake a passing grade for
        // agency.
        "resultClass": textContractBuild
            ? "drafting quality + host orchestration, not agency"
            : "native agent competence",
    ]
    if let cfg = try? JSONSerialization.data(withJSONObject: runConfig, options: [.prettyPrinted, .sortedKeys]) {
        try? cfg.write(to: captureDir.appendingPathComponent("run-config.json"))
    }
    // packet.json is phase 1's packet as built BEFORE dispatch, and under
    // `AGENTTEST_PATH_STYLE=absolute` it is not what was dispatched (the
    // dispatched one carries `absoluteRoot: wt.url.path`, unknowable here).
    // Kept for compatibility with existing captures and tooling. **V4 must read
    // `phase-packet-N.json`, written at dispatch inside the phase loop** — see
    // the 2026-08-26 fix that made V4 auditable at all.
    if let pkt = try? JSONEncoder().encode(phasePacket(phases[0], textContract: textContractBuild)) {
        try? pkt.write(to: captureDir.appendingPathComponent("packet.json"))
    }
    // P12.7 piece 2: Σprompt/Σcached/Σsuffix across the whole run (every phase,
    // every tool round), read back from the `wire.trace` file piece 1 wired
    // into `AgentSettings.tracePath`. A `defer`, not a call at the end of the
    // happy path, because `runOnce` has ~10 early `return RunOutcome(.stopped,
    // …)` paths (budgetExceeded, contractNotFollowed, orchestrator errors) —
    // exactly the runs this accounting matters most for — and a plain
    // end-of-function call would have silently skipped all of them (Opus
    // checkpoint review, 2026-08-25). The pure summation lives in SwiftStarKit
    // (`TraceSummary.sum`, unit tested against golden.trace and synthetic
    // input); this is just the read + report + record. A missing or empty
    // trace (short run, or the file never materialized) reads as "" and sums
    // to all-zero rather than throwing — this must never fail a run that
    // would otherwise have succeeded. "Stateful tokens" (Σprompt - final
    // ctx_used) is a separate, out-of-scope metric — see TraceTokenTotals'
    // doc comment.
    defer {
        let traceText = (try? String(contentsOf: tracePath, encoding: .utf8)) ?? ""
        let traceTotals = TraceSummary.sum(traceText: traceText)
        print("[agenttest] trace: Σprompt=\(traceTotals.sumPrompt) Σcached=\(traceTotals.sumCached) Σsuffix=\(traceTotals.sumSuffix)")
        var runConfigWithTrace = runConfig
        runConfigWithTrace["sumPrompt"] = String(traceTotals.sumPrompt)
        runConfigWithTrace["sumCached"] = String(traceTotals.sumCached)
        runConfigWithTrace["sumSuffix"] = String(traceTotals.sumSuffix)
        if let cfg = try? JSONSerialization.data(withJSONObject: runConfigWithTrace, options: [.prettyPrinted, .sortedKeys]) {
            try? cfg.write(to: captureDir.appendingPathComponent("run-config.json"))
        }
    }

    for (i, phaseText) in phases.enumerated() {
        // Same builder the up-front validation gate ran against (host-split
        // arm), so what was validated is exactly what is dispatched. The
        // model-decompose arm has no up-front equivalent to have run against
        // (that gate is skipped for it — see the comment at its `if` above),
        // so this is the *first* validation these phase packets see; either
        // way, this per-phase gate — unchanged by P12.5 — is what actually
        // gates every dispatched phase, either arm.
        let seedPacket = phasePacket(phaseText, textContract: textContractBuild)
        print("[agenttest] phase \(i + 1)/\(phases.count) …")
        let wt = try txn.preparePhase(packet: seedPacket)
        // The worktree path is only known now, so the absolute arm rebuilds
        // here and is re-validated — the up-front gate ran before the model
        // loaded, this one guarantees the dispatched packet is well-formed.
        let packet = absolutePathStyle
            ? phasePacket(phaseText, absoluteRoot: wt.url.path, textContract: textContractBuild)
            : seedPacket
        if case .invalid(let reasons) = HandoffPacketValidator.validate(packet) {
            FileHandle.standardError.write(Data(
                ("[agenttest] dispatched packet rejected for phase \(i + 1):\n"
                 + reasons.map { "  - \($0)" }.joined(separator: "\n") + "\n").utf8))
            exit(2)
        }
        // V4: capture what was ACTUALLY dispatched, for every phase. Before
        // this only `phases[0]` reached the capture, so no reason in
        // verdict.json could be traced to a phase 2/3 brief and V4 reported
        // UNAUDITABLE for the whole of v1-v3. Written before the turn runs, so
        // a crash mid-phase still leaves the evidence behind.
        if let dispatched = try? JSONEncoder().encode(packet) {
            try? dispatched.write(
                to: captureDir.appendingPathComponent("phase-packet-\(i + 1).json"))
        }
        var outcome: TurnOutcome
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
        // Step-0 forcing gate (experiment, agentic builds only — a text-contract
        // turn has 0 tool calls by design and must never be re-prompted, or the
        // forced turn discards the valid harvest).
        if !packet.textContract {
            var forced = 0
            var forcingOutcome = outcome
            let maxForces = Int(env["AGENTTEST_FORCE"] ?? "0") ?? 0
            while forcingOutcome.toolCalls.isEmpty, forced < maxForces {
                forced += 1
                print("[agenttest]   forcing re-prompt \(forced)/\(maxForces) (0 tool calls)")
                let forcingPacket = phasePacket(
                    "The previous turn produced no tool calls. Do not narrate a plan: emit a tool call now and keep working.")
                forcingOutcome = try orch.runPhase(worker: WorkerId(1), packet: forcingPacket, worktree: wt.url,
                                                   capture: captureHandle)
            }
            outcome = forcingOutcome
        }
        // Text-contract harvest: a zero-tool-call eos turn's labeled blocks become the
        // phase's mutations (spec Section 2 step 3).
        if packet.textContract, outcome.toolCalls.isEmpty, outcome.stopReason == .eos {
            // Same protocol as the repair arm, same implementation: harvest, and
            // if the turn reasoned instead of emitting, ask once more before
            // calling it a contract failure.
            let attempt = try TextContractHarvest.run(
                firstTurn: outcome, packet: packet, worktree: wt.url,
                emissionFollowUp: buildEmissionFollowUp, capture: captureHandle,
                runPhase: { pkt, tree, cap in
                    try orch.runPhase(worker: WorkerId(1), packet: pkt, worktree: tree, capture: cap)
                })
            if attempt.usedFollowUp {
                print("[agenttest]   phase \(i + 1): emission follow-up (first turn harvested 0 blocks)")
                outcome = attempt.turn
            }
            let harvest = attempt.result
            if harvest.degenerateRepetition {
                print("[agenttest]   phase \(i + 1): repeated heading — harvest stopped after \(harvest.files.count) file(s)")
            }
            if harvest.files.isEmpty {
                FileHandle.standardError.write(Data("[agenttest] harvest: 0 labeled blocks from text:\n\(outcome.text)\n".utf8))
                return RunOutcome(finish: .stopped,
                                  note: "phase \(i + 1) contractNotFollowed (0 labeled blocks)",
                                  acceptanceExit: nil, verdict: nil, report: nil,
                                  elapsed: Int(Date().timeIntervalSince(runStart)))
            }
            for (path, content) in harvest.files {
                try WorktreeDispatcher.writeFile(content, to: path, in: wt.url)
            }
            outcome.mutations = harvest.files.map(\.path)
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
            // P12.8 (D4): repair the phase instead of aborting. Surface the cause
            // first — the repair's evidence is this same output, but the capture
            // stays even if repair is exhausted.
            print("[agenttest]   phase \(i + 1): import check failed (exit \(validation.exit)) — repairing")
            if !validation.output.isEmpty {
                print(validation.output)
                try? "phase \(i + 1) validation exit=\(validation.exit)\n\n\(validation.output)"
                    .write(to: captureDir.appendingPathComponent("validation-phase\(i + 1).txt"),
                           atomically: true, encoding: .utf8)
            }
            let repairCaptureDir = captureDir.appendingPathComponent("repair-phase\(i + 1)")
            try? FileManager.default.createDirectory(at: repairCaptureDir, withIntermediateDirectories: true)
            do {
                let repair = try PhaseRepair.run(
                    repo: repoURL,
                    failedWorktree: wt,
                    packet: packet,
                    validation: validation,
                    packetBuilder: { repairPacket($0, phaseScoped: true) },
                    runPhase: { pkt, tree, cap in
                        try orch.runPhase(worker: WorkerId(2), packet: pkt, worktree: tree, capture: cap)
                    },
                    capture: captureHandle,
                    captureDir: repairCaptureDir,
                    maxCandidateRounds: repairMaxRounds,
                    emissionFollowUp: repairEmissionFollowUp)
                switch repair {
                case .repaired(let repairedRef, let repairedWT):
                    try txn.adoptRepairedPhase(failedWorktree: wt,
                                               repairedWorktree: repairedWT,
                                               repairedRef: repairedRef)
                    print("[agenttest]   phase \(i + 1): repaired \(repairedRef)")
                    continue
                case .exhausted(let receipt):
                    return RunOutcome(finish: .stopped,
                                      note: "phase \(i + 1) repair exhausted (\(receipt))",
                                      acceptanceExit: nil, verdict: nil, report: nil,
                                      elapsed: Int(Date().timeIntervalSince(runStart)))
                }
            } catch RepairLoopError.sessionExhausted(let reason) {
                return RunOutcome(finish: .stopped,
                                  note: "phase \(i + 1) repair session exhausted (\(reason.rawValue))",
                                  acceptanceExit: nil, verdict: nil, report: nil,
                                  elapsed: Int(Date().timeIntervalSince(runStart)))
            }
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
                writableFiles: writableFiles,
                packetBuilder: { repairPacket($0) },
                runPhase: { pkt, wt, cap in
                    try orch.runPhase(worker: WorkerId(2), packet: pkt, worktree: wt, capture: cap)
                },
                grade: { wt in try AcceptanceGrader.grade(
                    worktree: wt, acceptanceSource: acceptanceSource, pyProject: pyProject) },
                capture: captureHandle,
                captureDir: captureDir,
                maxCandidateRounds: repairMaxRounds,
                emissionFollowUp: repairEmissionFollowUp)
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
            case .exhausted(_, let receipt, let best):
                repairNote = "repair exhausted (\(receipt))"
                print("[agenttest] repair: exhausted — \(receipt)")
                // Grade the best tree repair reached, not the tree that entered
                // repair (decision 2026-08-26). Rounds are cumulative, so the
                // last candidate holds every round's work. Previously this
                // branch updated nothing, leaving `gradeWorktree` on the
                // pre-repair tree -- so `code.md`, the qualitative verdict and
                // the reported acceptance exit all described a tree that
                // predated every repair round. Measured across the 2026-08-26
                // matrix: 21 of 21 cells that exhausted acceptance repair were
                // graded that way, one of them faulted for what was missing
                // from a `models.py` repair had itself written. The run still
                // *fails* either way -- `g.passed` short-circuits to `.passed`,
                // so an exhausted repair never carries a passing grade -- but
                // what gets reported is now what the model actually produced.
                if let best {
                    grade = best.grade
                    acceptanceExit = best.grade.exit
                    gradeWorktree = best.worktree
                    gradeWorktreeOwnedByTxn = false
                    repairNote = "repair exhausted (\(receipt)); graded best reached \(best.ref)"
                    print("[agenttest] repair: grading best tree reached — \(best.ref) (exit \(best.grade.exit))")
                    try? "exit=\(best.grade.exit)\n\n\(best.grade.output)\n\nbest reached: \(best.ref) (repair exhausted)"
                        .write(to: captureDir.appendingPathComponent("acceptance.txt"),
                               atomically: true, encoding: .utf8)
                }
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
