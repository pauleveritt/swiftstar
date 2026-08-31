import Foundation
import SwiftStarKit
import SwiftStarAppKit

// swiftstar-eval run — one ad-hoc prompt driven down the app's own spawn
// path (eval-cli task 5). Unlike `swiftstar-drive` (which spawns the raw
// engine binary directly, its own argv, its own wire parser) and
// `swiftstar-agenttest` (its own multi-phase harness), `run` goes through
// `AgentSession` — the exact type `AgentController` uses — so a divergence
// between what the app does and what an eval measures is a compile error,
// not a silent difference (BRIEF.md).
//
//   swiftstar-eval run --prompt <text|@file> [--mode bare|chat|quick|orchestrate]
//       [--variant ID] [--gguf PATH] [--ctx N] [--power 70|100] [--shell on|off]
//       [--workspace PATH] [--host-tools] [--per-turn-think] [--seed N]
//       [--tools a,b,c] [--dry-run]
//
// Every former `CAPTURE_*` env knob (`swiftstar-drive`/`swiftstar-agenttest`)
// is a named flag here — see `EvalArguments.captureEnvKnobFlags` — except
// `DS4_DIR`, which stays an env var (binding rule 4's one exception).

let runVerbHandlers: [String: @Sendable ([String]) -> Void] = [
    "run": { args in
        // Bridges this synchronous dispatch entry point into the async,
        // `@MainActor`-isolated world `AgentSession` lives in (see the type
        // doc: it needs an async host and must never block the main thread).
        // `dispatchMain()` runs this thread's main dispatch queue — the
        // queue `MainActor`'s default executor schedules onto — until
        // `exit(_:)` terminates the process from inside the task below; it
        // never returns on its own, which is fine, because every path
        // through `runMain` ends in `exit(_:)`.
        Task { @MainActor in
            await runMain(args)
        }
        dispatchMain()
    }
]

@MainActor
private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("swiftstar-eval run: \(message)\n".utf8))
    exit(2)
}

@MainActor
private func runMain(_ args: [String]) async {
    let invocation: EvalArguments.EvalInvocation
    switch EvalArguments.parse(["run"] + args) {
    case .failure(let message):
        fail(message)
    case .success(let parsed):
        invocation = parsed
    }
    let flags = invocation.flags

    // MARK: - --prompt (required; `@file` reads the prompt text from disk —
    // the flag that replaces `CAPTURE_PROMPTS_FILE`'s role for a single
    // ad-hoc prompt).
    guard let promptFlag = flags["--prompt"], !promptFlag.isEmpty else {
        fail("--prompt <text|@file> is required")
    }
    let prompt: String
    if promptFlag.hasPrefix("@") {
        let path = String(promptFlag.dropFirst())
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            fail("could not read prompt file '\(path)'")
        }
        prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        prompt = promptFlag
    }
    guard !prompt.isEmpty else { fail("--prompt resolved to an empty string") }

    // MARK: - --mode (decision 1: chat is refused here, before any spawn —
    // never routed to `AgentSession`)
    let modeName = flags["--mode"] ?? "bare"
    guard ["bare", "chat", "quick", "orchestrate"].contains(modeName) else {
        fail("--mode must be one of bare|chat|quick|orchestrate (got '\(modeName)')")
    }
    if modeName == "chat" {
        // `AgentSession.run(.chat)` sends a plain agent turn (it has to: the
        // real app `/chat` is `AgentController.consult()`, a pool-worker
        // dispatch over app-owned `poolState` this session does not hold —
        // see `AgentSession.run`'s doc comment). A `run --mode chat` that
        // quietly sent that plain turn anyway would claim a treatment
        // (app `/chat`, a read-only worker consult) it does not apply — the
        // exact defect this eval subsystem exists to prevent. So this CLI
        // refuses the whole invocation before `AgentSession` is even
        // constructed, rather than let `run(.chat)`'s existing (and correct,
        // for its own callers) behavior stand in for something it isn't.
        fail(
            "--mode chat is refused: the app's /chat is AgentController.consult(), " +
            "a pooled consult dispatch over app-owned pool state that AgentSession " +
            "does not hold — it is not yet reachable headlessly. Use --mode bare, " +
            "quick, or orchestrate.")
    }

    // MARK: - model resolution (--variant, else --gguf / SWIFTSTAR_MODEL —
    // mirrors swiftstar-agenttest's own escape hatch)
    let env = ProcessInfo.processInfo.environment
    let modelPath: URL
    var family: ModelFamily = .lagunaS
    if let variantID = flags["--variant"] {
        guard let variant = VariantRegistry.resolve(variantID) else {
            fail("unknown variant '\(variantID)'")
        }
        let contextSize = Int(flags["--ctx"] ?? "32768") ?? 32768
        switch VariantGate.admit(
            variant, contextSize: contextSize,
            availableBytes: VariantAdmissionSource.availableBytes(),
            wiredLimitAdvisoryBytes: VariantAdmissionSource.wiredLimitAdvisoryBytes()
        ) {
        case .admitted:
            break
        case .contractMismatch(let mismatches):
            fail("variant '\(variant.id)' refused:\n" + mismatches.map(\.message).joined(separator: "\n"))
        case .infeasible(let reason):
            fail("variant '\(variant.id)' infeasible: \(reason.message)")
        }
        modelPath = variant.modelFile
        family = variant.family
    } else if let gguf = flags["--gguf"] ?? env["SWIFTSTAR_MODEL"], !gguf.isEmpty {
        modelPath = URL(fileURLWithPath: gguf)
    } else {
        fail("--gguf <path> (or --variant <id>, or SWIFTSTAR_MODEL) is required")
    }

    // MARK: - the rest of the documented flag set
    let ctx = Int(flags["--ctx"] ?? "32768") ?? 32768
    let workspacePath = flags["--workspace"] ?? FileManager.default.currentDirectoryPath
    let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
    let shellAllowed = (flags["--shell"] ?? "off") == "on"
    // `--power` mirrors the app's own posture (`AgentSettings
    // .powerSavingEnabled`, D-something's fixed 70%/100 duty cycle), not
    // `swiftstar-drive`'s arbitrary 1-100 engine throttle — `run` goes down
    // the app's own spawn path, and the app only ever has these two states.
    var powerSavingEnabled = false
    if let powerFlag = flags["--power"] {
        switch powerFlag {
        case "70": powerSavingEnabled = true
        case "100": powerSavingEnabled = false
        default:
            fail("--power must be 70 or 100 (the app's own two power postures; got '\(powerFlag)')")
        }
    }
    let seed = UInt64(flags["--seed"] ?? "0") ?? 0
    let tools = (flags["--tools"] ?? "")
        .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    // `--host-tools`/`--per-turn-think` are accepted (binding rule 4 — every
    // former CAPTURE_* knob becomes a named flag) but are no-ops when `--bare`
    // is absent: a `run` spawn goes through `AgentCommand.argv`, which already
    // passes both unconditionally — the app never had a way to turn either
    // off, so neither does this CLI. `--bare` (eval-cli task 8) is the one
    // exception: it suppresses both, along with `--workspace`/`--shell`, to
    // reproduce `swiftstar-drive`'s retired P5 argv shape.
    let bare = flags["--bare"] != nil
    let engineDir = URL(fileURLWithPath: env["DS4_DIR"] ?? FileManager.default.currentDirectoryPath + "/external/ds4")

    // MARK: - capture directory (kind "live" — same root `captureDirs()`
    // scans for the app's own sessions, so `list`/`summary --latest` see a
    // `run` capture exactly like an app one). Computed before `settings` so
    // `--bare`'s `tracePath` can point into it.
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let captureDirectory = captureRoot()
        .appendingPathComponent("live", isDirectory: true)
        .appendingPathComponent("\(df.string(from: Date()))-run", isDirectory: true)

    let settings = AgentSettings(
        engineDir: engineDir, modelPath: modelPath, contextSize: ctx,
        workspace: workspace, shellAllowed: shellAllowed,
        powerSavingEnabled: powerSavingEnabled, seed: seed,
        // `--trace <path>` is part of `swiftstar-drive`'s P5 shape
        // (unconditional there); only `--bare` reproduces it here — a plain
        // `run` leaves `tracePath` nil, unchanged from before this flag
        // existed. `swiftstar-drive`'s own trace file was named
        // `wire.trace` inside the capture directory; matched here so a
        // `--bare` capture carries the file the recapture rule expects.
        tracePath: bare ? captureDirectory.appendingPathComponent("wire.trace") : nil,
        // `--tools` must reach argv (`AgentCommand.argv`'s own `--tools`
        // flag), not just the `SpawnRecord.tools` provenance field below —
        // otherwise the flag would look wired but never actually restrict
        // the engine's advertised schema.
        tools: tools.isEmpty ? nil : tools,
        bare: bare)

    let dryRun = flags["--dry-run"] != nil

    let session = AgentSession(
        settings: settings, tools: tools, captureDirectory: captureDirectory,
        family: family, captureEnabled: true)

    if dryRun {
        // Binding rule: dry-run prints the resolved record and creates no
        // capture tree, no process. `resolveSpawnRecord()` is the exact
        // resolution `start()` itself would use — split out for this purpose.
        let record = session.resolveSpawnRecord()
        for fact in record.provenanceFacts {
            print("\(fact.label): \(fact.value)")
        }
        print("Mode: \(modeName)")
        print("Prompt: \(prompt)")
        print("Argv: \(record.argv.joined(separator: " "))")
        exit(0)
    }

    let record: SpawnRecord
    do {
        record = try session.start()
    } catch {
        fail("failed to spawn: \(error)")
    }
    _ = record

    var sawHello = false
    var refusalReason: String?
    var exitedEarly: (Int32, [String])?
    session.onEvent = { event in
        if case .hello = event { sawHello = true }
    }
    session.onRefusal = { reason in refusalReason = reason }
    session.onExit = { status, tail in exitedEarly = (status, tail) }

    // A real engine's `hello` arrives unsolicited, essentially immediately
    // after spawn — well before the app (or this CLI) ever writes a prompt.
    // Give it a short grace window so `.quick`'s `advertisedCaps` gate (which
    // reads whatever `hello` already populated, synchronously, at the moment
    // `send`/`run` is called) sees the real handshake rather than racing it.
    // Deliberately bounded, not "wait until hello or refuse": some replay
    // fakes (and, in principle, an engine build that only replies once
    // spoken to) never emit anything unsolicited, and `bare`/`orchestrate`
    // don't need `hello` to have landed at all — a `send`/`run` timeout
    // below is still this invocation's real failure mode if the handshake
    // never happens at all.
    let helloGrace = Date().addingTimeInterval(2)
    while !sawHello, refusalReason == nil, exitedEarly == nil, Date() < helloGrace {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    if let refusalReason {
        session.stop()
        fail("engine refused the handshake: \(refusalReason)")
    }
    if let exitedEarly {
        fail("engine exited before handshake (status \(exitedEarly.0)): \(exitedEarly.1.joined(separator: "\n"))")
    }

    var outcomes: [TurnOutcome] = []
    session.onOutcome = { outcomes.append($0) }

    let sent: Bool
    switch modeName {
    case "bare":
        sent = session.send(prompt)
    case "quick":
        sent = session.run(.quick(task: prompt))
    case "orchestrate":
        sent = session.run(.orchestrate(task: prompt, writableFiles: []))
    default:
        // Unreachable: "chat" already refused above, and the flag set was
        // validated to one of these four names.
        sent = false
    }
    guard sent else {
        session.stop()
        fail("--mode \(modeName) was refused by AgentSession (engine did not advertise the capability it needs)")
    }

    let turnDeadline = Date().addingTimeInterval(900)
    while outcomes.isEmpty, exitedEarly == nil, Date() < turnDeadline {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    session.stop()

    if let outcome = outcomes.first {
        print("stop_reason: \(outcome.stopReason)")
        print("generated_tokens: \(outcome.generatedTokens)")
        if let rate = outcome.decodeTPS {
            print("decode_tps: \(rate)")
        }
        print("capture: \(captureDirectory.path)")
        exit(0)
    } else if let exitedEarly {
        fail("engine exited before the turn finished (status \(exitedEarly.0)): \(exitedEarly.1.joined(separator: "\n"))")
    } else {
        fail("timed out waiting for the turn to finish")
    }
}
