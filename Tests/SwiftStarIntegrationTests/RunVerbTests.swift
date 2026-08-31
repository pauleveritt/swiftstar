import Testing
import Foundation
import SwiftStarKit

/// Task 5: `swiftstar-eval run` — one ad-hoc prompt driven down the app's own
/// spawn path (`AgentSession`). This spawns the real built
/// `.build/debug/swiftstar-eval` binary (real process; `run`'s own dispatch
/// entry bridges into `AgentSession`'s `@MainActor` async world via
/// `dispatchMain()` — not `@testable import`able the way a plain executable's
/// top-level code would auto-run, same gotcha `AnalyzeVerbsDispatchTests`
/// documents) against a compiled fake `ds4-agent` (`FakeAgentSource`, the
/// same harness `AgentSessionTests` uses) — no real engine, no real model.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct RunVerbTests {

    /// `.build/debug/swiftstar-eval` — SwiftPM's stable symlink to whichever
    /// arch/config subdirectory `swift test` (run from the repo root) just
    /// built into.
    static var binary: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/swiftstar-eval")
    }

    /// hello → one generating segment → turn-end ready. Same minimal shape
    /// `AgentSessionTests.plainTurn` uses (see that file's doc comment for
    /// why there is no separate startup `ready`).
    private static let plainTurn = """
    {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","think_override"],"ts":1}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":4,"gen_tps":10.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":4}
    {"t":"text","s":"hi there","ts":5}
    {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":8,"gen_tps":10.0,"ctx_used":20,"ctx_size":32768,"power":100,"error":"","ts":6}
    {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":8,"ctx_used":20,"ts":7}
    """

    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("runverb-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds the exact `AgentSettings` `run` will resolve from the flags
    /// below, so the fake's baked-in `engineArgv` matches what `run` actually
    /// spawns with — the same "settings the CLI would build" contract
    /// `AgentSessionTests.buildFakeEngine` uses for `AgentSession` directly.
    private func makeSettings(engineDir: URL, modelPath: URL, workspace: URL, power: String?) -> AgentSettings {
        AgentSettings(
            engineDir: engineDir, modelPath: modelPath, contextSize: 8192,
            workspace: workspace, shellAllowed: false,
            powerSavingEnabled: power == "70")
    }

    /// Compile `capture` into a fake `ds4-agent` and place it where
    /// `AgentCommand.binaryPath(settings:)` resolves — mirrors
    /// `AgentSessionTests.buildFakeEngine`. `hostTools` defaults `true` (every
    /// existing caller here spawns through the app's own unconditional
    /// `--host-tools` path); Task 8's `--bare` tests pass `false` — a bare
    /// spawn never advertises or exercises the tool-request wire, so the fake
    /// must replay the capture observation-only, unmodified.
    private func buildFakeEngine(capture: String, settings: AgentSettings, hostTools: Bool = true) throws {
        let argv = AgentCommand.argv(settings: settings)
        let source = try FakeAgentSource.generate(
            capture: Data(capture.utf8), engineArgv: argv, hostTools: hostTools)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("runverb-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        try FileManager.default.moveItem(
            at: binary, to: settings.engineDir.appendingPathComponent("ds4-agent"))
    }

    @discardableResult
    private func run(_ args: [String], cwd: URL, extraEnv: [String: String]) throws
        -> (status: Int32, stdout: String, stderr: String)
    {
        let process = Process()
        process.executableURL = Self.binary
        process.arguments = args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extraEnv { env[k] = v }
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    // MARK: - the behavioral test (brief Step 1/5)

    /// The capture `run` writes passes `CaptureValidity` and `provenance.md`
    /// carries the `power` line — the fact a `--power 70` vs `100` mismatch
    /// used to lose (`AgentCommand.powerRecord`'s doc comment: a 2026-08-30
    /// A/B misread an unrecorded throttle difference as an engine speedup).
    @Test func runWritesACaptureTreeAndProvenance() throws {
        let engineDir = try tempDir("engine")
        let workspace = try tempDir("ws")
        let cwd = try tempDir("cwd")
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-model.gguf")
        let settings = makeSettings(engineDir: engineDir, modelPath: modelPath, workspace: workspace, power: "70")
        try buildFakeEngine(capture: Self.plainTurn, settings: settings)

        let result = try run(
            ["run", "--prompt", "hi there", "--gguf", modelPath.path,
             "--workspace", workspace.path, "--ctx", "8192", "--power", "70"],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])

        #expect(result.status == 0, "stderr: \(result.stderr)")

        let liveDir = cwd.appendingPathComponent("captures/live", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
        let captureDir = try #require(entries.first { $0.lastPathComponent.hasSuffix("-run") })

        let wire = try String(contentsOf: captureDir.appendingPathComponent("wire.ndjson"), encoding: .utf8)
        let validity = CaptureValidity.audit(wire: wire)
        #expect(validity.v5.status == .pass, "\(validity.v5)")
        #expect(validity.v6.status == .pass, "\(validity.v6)")

        let provenance = try String(contentsOf: captureDir.appendingPathComponent("provenance.md"), encoding: .utf8)
        #expect(provenance.contains("- Power: 70 (`--power 70`)"),
                "provenance.md must carry the resolved --power, not silently drop it:\n\(provenance)")
    }

    // MARK: - --mode chat refusal (decision 1) and its success sibling (binding rule 4)

    @Test func modeChatIsRefused() throws {
        let engineDir = try tempDir("engine-chat")
        let workspace = try tempDir("ws-chat")
        let cwd = try tempDir("cwd-chat")
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-model.gguf")
        // No fake engine built: a refusal must happen before any spawn.

        let result = try run(
            ["run", "--prompt", "hello", "--mode", "chat", "--gguf", modelPath.path,
             "--workspace", workspace.path],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])

        #expect(result.status != 0)
        #expect(result.stderr.contains("chat"))
        #expect(result.stderr.lowercased().contains("consult"),
                "the refusal must name AgentController.consult() as what app /chat actually is")
        #expect(!FileManager.default.fileExists(atPath: cwd.appendingPathComponent("captures").path),
                "a refused --mode chat must spawn nothing and write no capture tree")
    }

    /// Sibling of `modeChatIsRefused` (binding rule 4): a mode that DOES work
    /// completes normally — proves the chat refusal is mode-specific, not a
    /// blanket failure.
    @Test func modeBareSucceeds() throws {
        let engineDir = try tempDir("engine-bare")
        let workspace = try tempDir("ws-bare")
        let cwd = try tempDir("cwd-bare")
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-model.gguf")
        let settings = makeSettings(engineDir: engineDir, modelPath: modelPath, workspace: workspace, power: nil)
        try buildFakeEngine(capture: Self.plainTurn, settings: settings)

        let result = try run(
            ["run", "--prompt", "hi there", "--mode", "bare", "--gguf", modelPath.path,
             "--workspace", workspace.path, "--ctx", "8192"],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])

        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("stop_reason"))
    }

    // MARK: - --dry-run (brief Step 1)

    @Test func dryRunSpawnsNothing() throws {
        let engineDir = try tempDir("engine-dry")
        let workspace = try tempDir("ws-dry")
        let cwd = try tempDir("cwd-dry")
        // Deliberately no fake engine binary at all — a dry-run must never
        // try to spawn anything, so a missing `ds4-agent` must not matter.
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-model.gguf")

        let result = try run(
            ["run", "--prompt", "hi there", "--gguf", modelPath.path,
             "--workspace", workspace.path, "--ctx", "8192", "--power", "70", "--dry-run"],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])

        #expect(result.status == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("Power: 70"))
        #expect(result.stdout.contains("Argv:"))
        #expect(!FileManager.default.fileExists(atPath: cwd.appendingPathComponent("captures").path),
                "--dry-run must create no capture tree")
    }

    // MARK: - Task 8: `--bare` reproduces `swiftstar-drive`'s retired P5 shape
    //
    // `swiftstar-drive` is deleted; this is the proof its replacement,
    // `swiftstar-eval run --bare`, produces a shape-identical wire — the
    // acceptance criterion for retiring it and re-pointing `just capture`.
    // Two things are proven, per the ruling: the resolved argv (explicit
    // comparison against the exact P5 shape
    // `Sources/swiftstar-drive/main.swift` used to build), and the
    // `fixtures/agent/provenance.md`-named invariants on the wire a real
    // spawn produces — a "caps/`tool_request`-free bare wire" — using
    // `golden.ndjson` itself as the fake engine's replay script (behavior,
    // not source text: binding rule 3).

    /// `fixtures/agent/golden.ndjson` — the committed capture whose shape
    /// this proves `--bare` reproduces. Read from the repo tree the same way
    /// `FixtureReplayTests.bundledFixtureMatchesRepoFixture` locates it.
    private static var goldenNDJSON: String {
        get throws {
            let repo = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("fixtures/agent/golden.ndjson")
            return try String(contentsOf: repo, encoding: .utf8)
        }
    }

    /// Explicit argv comparison (Step 1/acceptance criterion, part 1):
    /// `--dry-run --bare`'s printed `Argv:` line must be exactly the P5
    /// shape above, and must carry none of the four flags `--bare`
    /// suppresses.
    @Test func bareDryRunArgvMatchesDriveSP5Shape() throws {
        let engineDir = try tempDir("engine-bare-dry")
        let cwd = try tempDir("cwd-bare-dry")
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-bare-model.gguf")

        let result = try run(
            ["run", "--prompt", "hi there", "--bare", "--dry-run",
             "--gguf", modelPath.path, "--ctx", "8192"],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])
        #expect(result.status == 0, "stderr: \(result.stderr)")

        let argvLine = result.stdout.split(separator: "\n").first { $0.hasPrefix("Argv: ") }
        let argvLineText = try #require(argvLine, "no Argv: line in:\n\(result.stdout)")
        let actual = argvLineText.dropFirst("Argv: ".count).split(separator: " ").map(String.init)

        // 9 tokens: -m <path> -c <ctx> --metal --non-interactive
        // --json-events --trace <path> — the exact P5 shape
        // `swiftstar-drive` built (its now-deleted `main.swift`), with
        // `--trace`'s value a wildcard (a fresh timestamped capture
        // directory every invocation, same rule `FakeAgentSource` applies).
        #expect(actual.count == 9, "expected the 9-token P5 shape: \(actual)")
        #expect(Array(actual.prefix(7)) == [
            "-m", modelPath.path, "-c", "8192", "--metal", "--non-interactive", "--json-events",
        ])
        #expect(actual[7] == "--trace")
        #expect(actual[8].hasSuffix("/wire.trace"), "the --trace path must be <captureDirectory>/wire.trace: \(actual[8])")
        for suppressed in ["--workspace", "--shell", "--host-tools", "--per-turn-think"] {
            #expect(!actual.contains(suppressed), "--bare must suppress \(suppressed): \(actual)")
        }
    }

    /// The wire-shape invariants (Step 1/acceptance criterion, part 2):
    /// spawn a fake engine that replays `golden.ndjson` verbatim
    /// (`hostTools: false` — observation-only, exactly what a bare capture
    /// is), drive it through `run --bare`, and assert the produced tree
    /// passes `CaptureValidity` and carries the invariants
    /// `fixtures/agent/provenance.md` names for this fixture: no
    /// `tool_request` events, and the `hello` `caps` array unchanged from
    /// what the fixture itself advertises (no `pool`/`tool_request` caps
    /// added). This is also this task's Step 1 test — `just capture`
    /// calling a deleted `swiftstar-drive` is exactly what running this
    /// against the pre-Task-8 tree failed on (see the task report).
    @Test func bareProducesTheBareWireShapeCaptureValidityPasses() throws {
        let engineDir = try tempDir("engine-bare-real")
        let cwd = try tempDir("cwd-bare-real")
        let modelPath = URL(fileURLWithPath: "/tmp/runverb-bare-model.gguf")
        let golden = try Self.goldenNDJSON

        // The settings this spawn resolves to, built the same way `run`
        // itself builds them (bare: true, a trace path set) — matches
        // `makeSettings`'s role in the non-bare tests above. The trace
        // path's VALUE is a wildcard (`FakeAgentSource`'s own rule); only
        // its presence/position needs to match the real spawn's.
        let settings = AgentSettings(
            engineDir: engineDir, modelPath: modelPath, contextSize: 8192,
            workspace: URL(fileURLWithPath: "/unused-in-bare-argv"),
            tracePath: URL(fileURLWithPath: "/placeholder/wire.trace"),
            bare: true)
        try buildFakeEngine(capture: golden, settings: settings, hostTools: false)

        let result = try run(
            ["run", "--prompt", "hi there", "--bare",
             "--gguf", modelPath.path, "--ctx", "8192"],
            cwd: cwd, extraEnv: ["DS4_DIR": engineDir.path])
        #expect(result.status == 0, "stderr: \(result.stderr)")

        let liveDir = cwd.appendingPathComponent("captures/live", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
        let captureDir = try #require(entries.first { $0.lastPathComponent.hasSuffix("-run") })

        let wire = try String(contentsOf: captureDir.appendingPathComponent("wire.ndjson"), encoding: .utf8)

        // CaptureValidity: the acceptance criterion names this explicitly.
        let validity = CaptureValidity.audit(wire: wire)
        #expect(validity.v5.status == .pass, "\(validity.v5)")
        #expect(validity.v6.status == .pass, "\(validity.v6)")

        // fixtures/agent/provenance.md's named invariants for this fixture
        // (behavior, not source text — binding rule 3): "caps/`tool_request`-
        // free bare wire" — no tool_request events, hello caps unchanged.
        #expect(!wire.contains("\"t\":\"tool_request\""),
                "a --bare capture must stay observation-only, no tool_request events")
        let helloLine = try #require(wire.split(separator: "\n").first, "empty wire")
        #expect(helloLine.contains(#""caps":["status","ready","text","think","tool","queued","ts"]"#),
                "the hello caps must be unchanged from the fixture's own — no pool/tool_request cap added: \(helloLine)")

        // `--trace` reached argv, not just `--dry-run`'s printed line: the
        // fake's `validateArgv` (`FakeAgentSource`) refuses (exit 1, no
        // wire.ndjson) on any argv shape other than the one baked into it —
        // including the `--trace` flag's presence/position — so this spawn
        // succeeding at all (`result.status == 0` above) already proves the
        // real argv carried `--trace`. (The fake doesn't write a real
        // `--trace` file by default — that's `simulateToolAdvertisement`'s
        // job, unrelated to this test — so this doesn't re-assert a
        // `wire.trace` file's existence on disk.)
    }

    // MARK: - EvalArguments.parse's own flag rejection, exercised through the real CLI

    @Test func unknownFlagIsRejected() throws {
        let cwd = try tempDir("cwd-badflag")
        let result = try run(["run", "--prompt", "hi", "--bogus"], cwd: cwd, extraEnv: [:])
        #expect(result.status == 2)
        #expect(result.stderr.contains("--bogus"))
    }
}
