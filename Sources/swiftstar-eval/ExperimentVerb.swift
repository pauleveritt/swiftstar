import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-eval experiment / verdict — the paired, interleaved A/B (eval-cli
// task 7). `experiment` pre-registers the question and the falsifier, runs
// `EvalExperiment.runOrder()` down `AgentSession` (each run in its own fresh
// `RunWorkspace`), refuses when the arms differ by anything undeclared
// (`ArmDiff`), and reports paired deltas (`PairBill`/`EvalReport`) without a
// verdict — `verdict` is a SEPARATE invocation (decision 1): a verdict cannot
// be recorded before the data it verdicts on exists.
//
//   swiftstar-eval experiment evals/<name>.json [--exploratory] [--dry-run]
//   swiftstar-eval verdict <results-dir> --record claimSurvives|claimFalsified
//       --evidence <path|line>
//
// Results land in
// captures/eval/<name>/<timestamp>/{experiment.json, preregistration.md,
// arm-diff.txt, pair-N/<armID>/, report.md}.

let experimentVerbHandlers: [String: @Sendable ([String]) -> Void] = [
    "experiment": { args in
        // Same synchronous-dispatch-to-@MainActor-async bridge as `run` —
        // see RunVerb.swift's doc comment on this exact pattern.
        Task { @MainActor in
            await experimentMain(args)
        }
        dispatchMain()
    },
    "verdict": { args in
        verdictMain(args)
    },
]

// MARK: - shared helpers

private func experimentCaptureRoot() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("captures")
}

/// `yyyyMMdd-HHmmss` plus a short random suffix: two `experiment` invocations
/// against the same fake engine (an integration test's own back-to-back
/// runs) can land in the same wall-clock second, and a bare second-precision
/// stamp would silently merge their two results directories into one —
/// exactly the kind of thing that would make `attemptNumberComesFromSiblingDirectories`
/// flake instead of fail. The suffix sorts after the timestamp lexically, so
/// chronological order is preserved for attempt counting.
private func resultsTimestamp() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = UUID().uuidString.prefix(6).lowercased()
    return "\(df.string(from: Date()))-\(suffix)"
}

// MARK: - `experiment`

@MainActor
private func experimentFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swiftstar-eval experiment: \(message)\n".utf8))
    exit(2)
}

/// Apply one `EvalValue` override, keyed by the `SpawnRecord` property name
/// it names (`EvalExperiment.spawnRecordProperties`'s vocabulary — the same
/// names a `variable:` declaration uses), onto `settings`. Not every declared
/// property is a settable spawn input (`sampler`, `thinkPolicy`'s rendered
/// form, every SHA/hash, `captureDirectory`/`startedAt`/`runIndex`) — those
/// are outputs of a spawn, not inputs to one, and are silently ignored here;
/// an experiment that declares one of them as `variable` was already refused
/// by `EvalExperiment.parse`'s own gate... except `thinkPolicy` and `power`,
/// which DO have a settable input side (`noThink`, `powerSavingEnabled`) and
/// are handled below. `workspace`/`hostTools`/`gitRef` are handled by the
/// caller instead: `workspace` is `RunWorkspace`-managed (never an
/// `overrides` value), `hostTools` is always on (`AgentCommand.argv` passes
/// it unconditionally), and `gitRef` selects the engine build the caller
/// resolves once per arm, not a per-field `AgentSettings` write.
private func applyOverride(_ settings: inout AgentSettings, key: String, value: EvalValue) {
    switch key {
    case "tools":
        if case .list(let l) = value { settings.tools = l }
    case "power":
        switch value {
        case .bool(let b): settings.powerSavingEnabled = b
        case .string(let s): settings.powerSavingEnabled = (s == "70")
        case .int(let i): settings.powerSavingEnabled = (i == 70)
        case .list: break
        }
    case "maxTokens":
        if case .int(let i) = value { settings.maxTokens = i }
    case "thinkBudget":
        if case .int(let i) = value { settings.thinkBudget = i }
    case "contextSize":
        if case .int(let i) = value { settings.contextSize = i }
    case "modelPath":
        if case .string(let s) = value { settings.modelPath = URL(fileURLWithPath: s) }
    case "shellAllowed":
        if case .bool(let b) = value { settings.shellAllowed = b }
        if case .string(let s) = value { settings.shellAllowed = (s == "on") }
    case "thinkPolicy":
        if case .string(let s) = value { settings.noThink = (s == "none") }
    default:
        break
    }
}

/// `common` merged with `arm.overrides` — the arm's own keys win, per the
/// design's own documented precedence ("`common` applies to every arm; an
/// arm's own keys override it").
private func mergedFields(experiment: EvalExperiment, arm: Arm) -> [String: EvalValue] {
    experiment.common.merging(arm.overrides) { _, armValue in armValue }
}

private func buildSettings(
    experiment: EvalExperiment, arm: Arm, engineDir: URL, defaultModelPath: URL,
    workspace: URL, seed: UInt64, tracePath: URL
) -> AgentSettings {
    var settings = AgentSettings(
        engineDir: engineDir, modelPath: defaultModelPath, contextSize: 32768,
        workspace: workspace, shellAllowed: false, seed: seed, tracePath: tracePath)
    for (key, value) in mergedFields(experiment: experiment, arm: arm) {
        applyOverride(&settings, key: key, value: value)
    }
    return settings
}

/// The arm's declared tool set (merged `common` + `overrides`), if any — the
/// set decision 6 verifies against the wire after the handshake. nil means
/// the experiment never declared one, so there is nothing to verify.
private func declaredTools(experiment: EvalExperiment, arm: Arm) -> [String]? {
    guard case .list(let tools)? = mergedFields(experiment: experiment, arm: arm)["tools"] else { return nil }
    return tools
}

/// Resolve one arm's `SpawnRecord` WITHOUT spawning a process — the same
/// `resolveSpawnRecord()` `swiftstar-eval run --dry-run` uses. This is what
/// lets `ArmDiff.admit` run, and refuse, before anything is spawned (Step 1's
/// `refusesArmsThatDifferUndeclared`: "spawns nothing").
@MainActor
private func dryResolve(
    experiment: EvalExperiment, arm: Arm, engineDir: URL, defaultModelPath: URL, workspace: URL
) -> SpawnRecord {
    let settings = buildSettings(
        experiment: experiment, arm: arm, engineDir: engineDir, defaultModelPath: defaultModelPath,
        workspace: workspace, seed: 0, tracePath: workspace.appendingPathComponent("dry-\(arm.id).trace"))
    let session = AgentSession(
        settings: settings, tools: declaredTools(experiment: experiment, arm: arm) ?? [],
        captureDirectory: workspace.appendingPathComponent("dry-\(arm.id)"), captureEnabled: false)
    return session.resolveSpawnRecord()
}

@MainActor
private func experimentMain(_ args: [String]) async {
    let invocation: EvalArguments.EvalInvocation
    switch EvalArguments.parse(["experiment"] + args) {
    case .failure(let message):
        experimentFail(message)
    case .success(let parsed):
        invocation = parsed
    }
    guard let pathArg = invocation.positional.first, !pathArg.isEmpty else {
        experimentFail("evals/<name>.json is required")
    }
    let exploratory = invocation.flags["--exploratory"] != nil
    let dryRun = invocation.flags["--dry-run"] != nil

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let repoRoot = ProjectRoot.locate(anchor: cwd) ?? cwd
    let experimentPath = URL(fileURLWithPath: pathArg, relativeTo: cwd)

    // Decision 5: the committed-file gate. `git status --porcelain -- <path>`
    // reports both an untracked file ("?? path") and a modified tracked one
    // ("M path" / " M path") as non-empty output — one check covers both
    // halves of "pre-registered is a fact, not a habit".
    guard let statusResult = try? GitProcess.run(
        ["status", "--porcelain", "--", experimentPath.path], in: repoRoot),
        statusResult.exit == 0, !statusResult.timedOut
    else {
        experimentFail("could not check git status for '\(pathArg)'")
    }
    guard statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        experimentFail(
            "'\(pathArg)' is not committed and clean — an experiment must be pre-registered " +
            "before it runs. git status: \(statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    guard let data = FileManager.default.contents(atPath: experimentPath.path) else {
        experimentFail("could not read '\(pathArg)'")
    }
    let experiment: EvalExperiment
    do {
        experiment = try EvalExperiment.parse(data, exploratory: exploratory)
    } catch {
        experimentFail("invalid experiment file: \(error)")
    }
    guard experiment.arms.count == 2 else {
        experimentFail("experiment must declare exactly two arms (got \(experiment.arms.count))")
    }
    // Decision 7: parity with `run` — chat is never reachable headlessly.
    guard experiment.mode != .chat else {
        experimentFail(
            "mode \"chat\" is refused, the same as `swiftstar-eval run --mode chat` — " +
            "use bare, quick, or orchestrate.")
    }

    let armA = experiment.arms[0]
    let armB = experiment.arms[1]

    let env = ProcessInfo.processInfo.environment
    let engineDir = URL(fileURLWithPath: env["DS4_DIR"] ?? repoRoot.appendingPathComponent("external/ds4").path)
    guard let defaultModelPath = (env["SWIFTSTAR_MODEL"]).map({ URL(fileURLWithPath: $0) }) else {
        experimentFail("SWIFTSTAR_MODEL (or a 'modelPath' key in the experiment's common/overrides) is required")
    }

    // MARK: - results directory + attempt number

    let resultsRoot = experimentCaptureRoot()
        .appendingPathComponent("eval", isDirectory: true)
        .appendingPathComponent(experiment.name, isDirectory: true)
    let existingAttempts = (try? FileManager.default.contentsOfDirectory(
        at: resultsRoot, includingPropertiesForKeys: nil))?.count ?? 0
    let attempt = existingAttempts + 1
    let resultsDir = resultsRoot.appendingPathComponent(resultsTimestamp(), isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
    } catch {
        experimentFail("could not create results directory: \(error)")
    }

    // Binding rule 5 / Step 1's `writesPreregistrationBeforeTheFirstSpawn`:
    // both files below exist before anything is spawned — nothing past this
    // point that could fail leaves the reader without at least these two.
    try? data.write(to: resultsDir.appendingPathComponent("experiment.json"))
    try? experiment.preregistration.write(
        to: resultsDir.appendingPathComponent("preregistration.md"), atomically: true, encoding: .utf8)

    // MARK: - the arm diff, BEFORE any spawn

    let dryRecordA = dryResolve(
        experiment: experiment, arm: armA, engineDir: engineDir,
        defaultModelPath: defaultModelPath, workspace: resultsDir)
    let dryRecordB = dryResolve(
        experiment: experiment, arm: armB, engineDir: engineDir,
        defaultModelPath: defaultModelPath, workspace: resultsDir)
    let declaredRefs: (String, String)? = experiment.variable == "gitRef"
        ? (dryRecordA.engineSHA, dryRecordB.engineSHA) : nil
    let admission = ArmDiff.admit(dryRecordA, dryRecordB, variable: experiment.variable, declaredRefs: declaredRefs)

    let armDiffText: String
    switch admission {
    case .success(let allowed):
        armDiffText =
            "Admitted. Declared variable \"\(experiment.variable)\" — " +
            "differing keys: \(allowed.sorted().joined(separator: ", "))."
    case .failure(let refusal):
        armDiffText = refusal.message
    }
    try? armDiffText.write(to: resultsDir.appendingPathComponent("arm-diff.txt"), atomically: true, encoding: .utf8)

    guard case .success = admission else {
        FileHandle.standardError.write(Data("swiftstar-eval experiment: \(armDiffText)\n".utf8))
        exit(2)
    }

    if dryRun {
        print(experiment.preregistration)
        print("")
        print(armDiffText)
        print("")
        print("Run order: " + experiment.runOrder().map { "\($0.pair):\($0.armID)" }.joined(separator: ", "))
        print("results: \(resultsDir.path)")
        exit(0)
    }

    // MARK: - the prompt

    let promptPath = URL(fileURLWithPath: experiment.promptFile, relativeTo: repoRoot)
    guard let promptText = try? String(contentsOf: promptPath, encoding: .utf8) else {
        experimentFail("could not read promptFile '\(experiment.promptFile)'")
    }
    let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)

    // MARK: - the interleaved run loop, one fresh `RunWorkspace` per run

    var capturesByPair: [Int: [String: CaptureTree]] = [:]
    var pairResults: [PairResult] = []
    var drops: [PairDrop] = []

    for step in experiment.runOrder() {
        let arm = step.armID == armA.id ? armA : armB
        let armDir = resultsDir
            .appendingPathComponent("pair-\(step.pair)", isDirectory: true)
            .appendingPathComponent(arm.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: armDir, withIntermediateDirectories: true)

        let workspace: RunWorkspace
        do {
            workspace = try RunWorkspace.create(repoRoot: repoRoot)
        } catch {
            drops.append(.unusable(arm: arm.id, reason: "could not create a fresh workspace: \(error)"))
            continue
        }
        defer { workspace.remove() }

        let tracePath = armDir.appendingPathComponent("agent.trace")
        let settings = buildSettings(
            experiment: experiment, arm: arm, engineDir: engineDir, defaultModelPath: defaultModelPath,
            workspace: workspace.path, seed: step.seed, tracePath: tracePath)
        let tools = declaredTools(experiment: experiment, arm: arm) ?? []

        let session = AgentSession(settings: settings, tools: tools, captureDirectory: armDir, captureEnabled: true)

        var record: SpawnRecord
        do {
            record = try session.start()
        } catch {
            drops.append(.unusable(arm: arm.id, reason: "failed to spawn: \(error)"))
            continue
        }
        record = record.withWorkspaceRef(workspace.ref)

        var sawHello = false
        var refusalReason: String?
        var exitedEarly: (Int32, [String])?
        session.onEvent = { event in
            if case .hello = event { sawHello = true }
        }
        session.onRefusal = { reason in refusalReason = reason }
        session.onExit = { status, tail in exitedEarly = (status, tail) }

        let helloGrace = Date().addingTimeInterval(2)
        while !sawHello, refusalReason == nil, exitedEarly == nil, Date() < helloGrace {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if refusalReason != nil || exitedEarly != nil {
            session.stop()
            drops.append(.unusable(arm: arm.id, reason: "engine did not complete the handshake"))
            continue
        }

        // Decision 6: verify the advertised tools against the wire — a
        // record that merely repeats what the arm asked for is the defect
        // this project keeps rediscovering.
        if !tools.isEmpty {
            let traceText = (try? String(contentsOf: tracePath, encoding: .utf8)) ?? ""
            let advertised = AdvertisedToolNames.names(fromTrace: traceText)
            guard advertised == Set(tools) else {
                session.stop()
                let message =
                    "swiftstar-eval experiment: pair \(step.pair) arm \(arm.id) aborted — " +
                    "declared tools \(tools.sorted()) but the engine advertised " +
                    "\(advertised.sorted()) after the handshake.\n"
                FileHandle.standardError.write(Data(message.utf8))
                drops.append(.unusable(
                    arm: arm.id,
                    reason: "advertised tools \(advertised.sorted()) != declared \(tools.sorted())"))
                continue
            }
        }

        var outcomes: [TurnOutcome] = []
        session.onOutcome = { outcomes.append($0) }

        let sent: Bool
        switch experiment.mode {
        case .bare: sent = session.send(prompt)
        case .quick: sent = session.run(.quick(task: prompt))
        case .orchestrate: sent = session.run(.orchestrate(task: prompt, writableFiles: []))
        case .chat: sent = false  // unreachable: refused above
        }
        guard sent else {
            session.stop()
            drops.append(.unusable(arm: arm.id, reason: "mode \(experiment.mode.rawValue) was refused by AgentSession"))
            continue
        }

        let turnDeadline = Date().addingTimeInterval(900)
        while outcomes.isEmpty, exitedEarly == nil, Date() < turnDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        session.stop()

        let wireText = (try? String(contentsOf: armDir.appendingPathComponent("wire.ndjson"), encoding: .utf8)) ?? ""
        let traceText = (try? String(contentsOf: tracePath, encoding: .utf8)) ?? ""
        capturesByPair[step.pair, default: [:]][arm.id] = CaptureTree(
            armID: arm.id, traceText: traceText, wireText: wireText)

        if let pairCaptures = capturesByPair[step.pair],
           let control = pairCaptures[armA.id], let treatment = pairCaptures[armB.id]
        {
            switch PairBill.reduce(pair: step.pair, control: control, treatment: treatment) {
            case .success(let result): pairResults.append(result)
            case .failure(let drop): drops.append(drop)
            }
        }
    }

    let report = EvalReport.render(
        experiment, pairs: pairResults.sorted { $0.pair < $1.pair }, drops: drops,
        verdict: .unrecorded, attempt: attempt, exploratory: exploratory)
    try? report.write(to: resultsDir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
    print(report)
    print("")
    print("results: \(resultsDir.path)")
    // Deliberately always exits the `.unrecorded` code (2): `experiment`
    // never records a verdict itself (decision 1) — see `swiftstar-eval
    // verdict`, the separate invocation.
    exit(EvalReport.exitCode(for: .unrecorded))
}

// MARK: - `verdict`

private func verdictFail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swiftstar-eval verdict: \(message)\n".utf8))
    exit(2)
}

/// `swiftstar-eval verdict <results-dir> --record claimSurvives|claimFalsified
/// --evidence <path|line>` — a SEPARATE invocation from `experiment`
/// (decision 1): recording a verdict is a human act over a results directory
/// that already exists, never a side effect of the run that produced it.
/// Writes `verdict.txt` alongside the already-written `report.md` rather than
/// re-deriving `pairs`/`drops` — this command records an outcome, it does not
/// recompute one.
private func verdictMain(_ args: [String]) {
    let invocation: EvalArguments.EvalInvocation
    switch EvalArguments.parse(["verdict"] + args) {
    case .failure(let message):
        verdictFail(message)
    case .success(let parsed):
        invocation = parsed
    }
    guard let dirArg = invocation.positional.first, !dirArg.isEmpty else {
        verdictFail("<results-dir> is required")
    }
    let resultsDir = URL(fileURLWithPath: dirArg, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resultsDir.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        verdictFail("results directory not found: '\(dirArg)'")
    }
    guard let recordFlag = invocation.flags["--record"] else {
        verdictFail("--record claimSurvives|claimFalsified is required")
    }
    guard let verdict = FalsifierVerdict(rawValue: recordFlag), verdict != .unrecorded else {
        verdictFail("--record must be claimSurvives or claimFalsified (got '\(recordFlag)')")
    }
    guard let evidence = invocation.flags["--evidence"], !evidence.isEmpty else {
        verdictFail("--evidence <path|line> is required")
    }

    let text = """
    Recorded: \(verdict.rawValue)
    Evidence: \(evidence)
    Recorded at: \(ISO8601DateFormatter().string(from: Date()))
    """
    do {
        try text.write(to: resultsDir.appendingPathComponent("verdict.txt"), atomically: true, encoding: .utf8)
    } catch {
        verdictFail("could not write verdict.txt: \(error)")
    }
    print(text)
    exit(EvalReport.exitCode(for: verdict))
}
