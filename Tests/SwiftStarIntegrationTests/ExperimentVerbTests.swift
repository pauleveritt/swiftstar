import Testing
import Foundation
import SwiftStarKit
import SwiftStarAppKit

/// Task 7: `swiftstar-eval experiment` / `verdict` — the paired, interleaved
/// A/B, pre-registered before it runs. Spawns the real built
/// `.build/debug/swiftstar-eval` binary against a compiled fake `ds4-agent`
/// (same harness `RunVerbTests` uses) inside a disposable git repo
/// (`GitFixtureRepo`), since the experiment file must itself be committed
/// (decision 5) and `RunWorkspace` needs a real repo to make worktrees of.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ExperimentVerbTests {

    static var binary: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/swiftstar-eval")
    }

    /// hello -> one generating segment -> turn-end ready, same minimal shape
    /// `RunVerbTests.plainTurn`/`AgentSessionTests.plainTurn` use.
    private static let plainTurn = """
    {"t":"hello","v":1,"caps":["status","ready","text","think","tool","queued","ts","think_override"],"ts":1}
    {"t":"status","state":"generating","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":4,"gen_tps":10.0,"ctx_used":10,"ctx_size":32768,"power":100,"error":"","ts":4}
    {"t":"text","s":"hi there","ts":5}
    {"t":"status","state":"idle","prefill_done":1,"prefill_total":1,"prefill_tps":0.0,"generated":8,"gen_tps":10.0,"ctx_used":20,"ctx_size":32768,"power":100,"error":"","ts":6}
    {"t":"ready","kv_bytes":1,"scratch_bytes":1,"model_bytes":1,"planned_bytes":1,"stop_reason":"eos","generated":8,"ctx_used":20,"ts":7}
    """

    private func tempDir(_ label: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("expverb-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The argv `AgentCommand.argv` renders for a given `tools` set —
    /// `workspace`/`trace`/`seed` are placeholders: `FakeAgentSource`'s
    /// generated `matches()` wildcards their VALUES (only the flags'
    /// presence and position matter), so any value here reproduces the same
    /// shape `swiftstar-eval experiment` actually spawns with.
    private func expectedArgv(engineDir: URL, modelPath: URL, tools: [String]?) -> [String] {
        let settings = AgentSettings(
            engineDir: engineDir, modelPath: modelPath, contextSize: 32768,
            workspace: URL(fileURLWithPath: "/placeholder-workspace"), shellAllowed: false,
            seed: 1, tracePath: URL(fileURLWithPath: "/placeholder-trace"), tools: tools)
        return AgentCommand.argv(settings: settings)
    }

    /// Compiles a fake `ds4-agent` that answers to every `tools` variant in
    /// `toolVariants` (each producing its own argv shape) and, when
    /// `simulateToolAdvertisement` is set, writes a `--trace` token dump that
    /// mirrors whatever `--tools` it was actually spawned with (or
    /// `FAKE_ADVERTISE_TOOLS_OVERRIDE`, for the mismatch test).
    private func buildFakeEngine(
        engineDir: URL, modelPath: URL, toolVariants: [[String]], simulateToolAdvertisement: Bool = true
    ) throws {
        let variantArgvs = toolVariants.map { expectedArgv(engineDir: engineDir, modelPath: modelPath, tools: $0) }
        let source = try FakeAgentSource.generate(
            capture: Data(Self.plainTurn.utf8), engineArgv: variantArgvs[0], hostTools: true,
            simulateToolAdvertisement: simulateToolAdvertisement,
            alsoAcceptArgv: Array(variantArgvs.dropFirst()))
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("expverb-fake-\(UUID().uuidString)", isDirectory: true)
        let binary = try FakeAgentHarness.compileFake(source: source, into: work)
        try FileManager.default.createDirectory(at: engineDir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: binary, to: engineDir.appendingPathComponent("ds4-agent"))
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

    /// Builds a disposable git repo with one seed commit (`GitFixtureRepo`),
    /// writes `evals/<name>.json` + `prompts/<name>.md` into it, and commits
    /// them — decision 5's gate requires the experiment file to be committed
    /// and clean BEFORE `experiment` will run it.
    private func makeRepo(experimentName: String, experimentJSON: String, commit: Bool = true) throws -> URL {
        let repo = try GitFixtureRepo.make(prefix: "expverb")
        let evalsDir = repo.appendingPathComponent("evals", isDirectory: true)
        let promptsDir = repo.appendingPathComponent("prompts", isDirectory: true)
        try FileManager.default.createDirectory(at: evalsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: promptsDir, withIntermediateDirectories: true)
        try experimentJSON.write(
            to: evalsDir.appendingPathComponent("\(experimentName).json"), atomically: true, encoding: .utf8)
        try "say hi\n".write(
            to: promptsDir.appendingPathComponent("\(experimentName).md"), atomically: true, encoding: .utf8)
        if commit {
            try GitFixtureRepo.git(repo, ["add", "evals", "prompts"])
            try GitFixtureRepo.git(repo, ["commit", "-m", "add \(experimentName)"])
        }
        return repo
    }

    private func experimentJSON(
        name: String, variable: String,
        controlOverrides: String, treatmentOverrides: String, common: String = "{}"
    ) -> String {
        """
        {
          "name": "\(name)",
          "question": "Does the declared variable change anything?",
          "falsifier": "no pair moves in the predicted direction",
          "variable": "\(variable)",
          "pairs": 1,
          "mode": "bare",
          "promptFile": "prompts/\(name).md",
          "captureSelection": "recordsWork",
          "arms": [
            { "id": "control", "overrides": \(controlOverrides) },
            { "id": "treatment", "overrides": \(treatmentOverrides) }
          ],
          "common": \(common)
        }
        """
    }

    private func resultsRoot(repo: URL, name: String) -> URL {
        repo.appendingPathComponent("captures/eval/\(name)", isDirectory: true)
    }

    private func onlyResultsDir(repo: URL, name: String) throws -> URL {
        let root = resultsRoot(repo: repo, name: name)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try #require(entries.first)
    }

    // MARK: - writesPreregistrationBeforeTheFirstSpawn / the admitted-run success path

    /// `admitsTheDeclaredVariable` doubles as `writesPreregistrationBeforeTheFirstSpawn`'s
    /// success path: an admitted run writes `preregistration.md` and
    /// `arm-diff.txt` (checked here), then goes on to spawn both arms and
    /// write their capture trees — proving the two files are not only
    /// present but written independently of whether any spawn later
    /// succeeds.
    @Test func admitsTheDeclaredVariableAndWritesPreregistrationBeforeAnySpawn() throws {
        let name = "admits-tools"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let engineDir = try tempDir("engine")
        let modelPath = URL(fileURLWithPath: "/tmp/expverb-model.gguf")
        try buildFakeEngine(engineDir: engineDir, modelPath: modelPath, toolVariants: [["read"], ["read", "write"]])

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": engineDir.path, "SWIFTSTAR_MODEL": modelPath.path])

        #expect(result.status == 2, "an admitted-but-unrecorded run always exits 2: stderr=\(result.stderr) stdout=\(result.stdout)")

        let resultsDir = try onlyResultsDir(repo: repo, name: name)
        let preregistration = try String(contentsOf: resultsDir.appendingPathComponent("preregistration.md"), encoding: .utf8)
        #expect(preregistration.contains(name))
        let armDiff = try String(contentsOf: resultsDir.appendingPathComponent("arm-diff.txt"), encoding: .utf8)
        #expect(armDiff.contains("Admitted"), "arm-diff.txt: \(armDiff)")

        let controlWire = resultsDir.appendingPathComponent("pair-1/control/wire.ndjson")
        let treatmentWire = resultsDir.appendingPathComponent("pair-1/treatment/wire.ndjson")
        #expect(FileManager.default.fileExists(atPath: controlWire.path))
        #expect(FileManager.default.fileExists(atPath: treatmentWire.path))

        let report = try String(contentsOf: resultsDir.appendingPathComponent("report.md"), encoding: .utf8)
        #expect(report.contains("attempt 1"))
        #expect(report.contains("VERDICT: unrecorded"))
    }

    // MARK: - refusesArmsThatDifferUndeclared

    @Test func refusesArmsThatDifferUndeclared() throws {
        let name = "undeclared-diff"
        // Declares "tools" but the treatment arm ALSO flips `power` — an
        // undeclared second axis, the exact shape of the 2026-08-30 incident.
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"], "power": "70"}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)
        // Deliberately no fake engine built: a pre-spawn refusal must spawn nothing.

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": repo.appendingPathComponent("no-such-engine").path,
                       "SWIFTSTAR_MODEL": "/tmp/expverb-model-unused.gguf"])

        #expect(result.status != 0)

        let resultsDir = try onlyResultsDir(repo: repo, name: name)
        let armDiff = try String(contentsOf: resultsDir.appendingPathComponent("arm-diff.txt"), encoding: .utf8)
        #expect(armDiff.contains("power"), "refusal must name the undeclared key: \(armDiff)")
        #expect(!FileManager.default.fileExists(atPath: resultsDir.appendingPathComponent("pair-1").path),
                "a refused arm diff must spawn nothing")
    }

    // MARK: - writesTheResolvedSpawnRecordPerRun (F6)

    /// Fable-fixes review, F6: `record.withWorkspaceRef(...)` was the last
    /// use of the resolved `SpawnRecord` — computed, then discarded. Pins
    /// that each run's arm directory now carries a `spawn-record.json` with
    /// the workspace ref actually filled in (the one fact `provenance.md`,
    /// rendered earlier inside `AgentSession.start()`, could not yet have).
    @Test func writesTheResolvedSpawnRecordPerRun() throws {
        let name = "spawn-record"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let engineDir = try tempDir("engine-record")
        let modelPath = URL(fileURLWithPath: "/tmp/expverb-model-record.gguf")
        try buildFakeEngine(engineDir: engineDir, modelPath: modelPath, toolVariants: [["read"], ["read", "write"]])

        try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": engineDir.path, "SWIFTSTAR_MODEL": modelPath.path])

        let resultsDir = try onlyResultsDir(repo: repo, name: name)
        for armID in ["control", "treatment"] {
            let recordURL = resultsDir
                .appendingPathComponent("pair-1", isDirectory: true)
                .appendingPathComponent(armID, isDirectory: true)
                .appendingPathComponent("spawn-record.json")
            let data = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(SpawnRecord.self, from: data)
            #expect(!record.workspaceRef.isEmpty,
                    "\(armID)'s spawn-record.json must carry the workspace ref RunWorkspace resolved")
            #expect(record.tools == (armID == "control" ? ["read"] : ["read", "write"]))
        }
    }

    // MARK: - refusesArmsWhoseDeclaredVariableNeverActuallyDiffered (F1)

    /// Fable-fixes review, F1's second hole: the experiment declares
    /// `variable: "tools"`, but both arms resolve to the SAME tools list —
    /// the treatment never applied. `differingKeys` has nothing undeclared to
    /// complain about (nothing else moved either), so before this fix the
    /// run was silently admitted. Sibling of
    /// `admitsTheDeclaredVariableAndWritesPreregistrationBeforeAnySpawn`,
    /// where the two arms genuinely differ on "tools".
    @Test func refusesArmsWhoseDeclaredVariableNeverActuallyDiffered() throws {
        let name = "no-op-treatment"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)
        // Deliberately no fake engine built: a pre-spawn refusal must spawn nothing.

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": repo.appendingPathComponent("no-such-engine").path,
                       "SWIFTSTAR_MODEL": "/tmp/expverb-model-unused.gguf"])

        #expect(result.status != 0)

        let resultsDir = try onlyResultsDir(repo: repo, name: name)
        let armDiff = try String(contentsOf: resultsDir.appendingPathComponent("arm-diff.txt"), encoding: .utf8)
        #expect(armDiff.contains("tools"), "refusal must name the variable that never applied: \(armDiff)")
        #expect(!FileManager.default.fileExists(atPath: resultsDir.appendingPathComponent("pair-1").path),
                "a refused arm diff must spawn nothing")
    }

    // MARK: - refusesAnUncommittedExperimentFile

    @Test func refusesAnUncommittedExperimentFile() throws {
        let name = "uncommitted"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        // commit: false — the file is written but never `git add`/`commit`ed,
        // so `git status --porcelain` reports it untracked.
        let repo = try makeRepo(experimentName: name, experimentJSON: json, commit: false)

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": repo.appendingPathComponent("no-such-engine").path,
                       "SWIFTSTAR_MODEL": "/tmp/expverb-model-unused.gguf"])

        #expect(result.status != 0)
        #expect(result.stderr.lowercased().contains("committed"), "stderr: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("captures").path),
                "an uncommitted experiment file must be refused before any results directory is created")
    }

    // MARK: - eachRunGetsAFreshWorkspace

    /// Direct test of `RunWorkspace` (Step 5's break/restore target): two
    /// `create(repoRoot:)` calls against the same repo, with a file written
    /// into the first workspace in between, prove the second workspace
    /// starts at the same ref but in a private directory that never sees the
    /// first workspace's edit.
    @Test func eachRunGetsAFreshWorkspace() throws {
        let repo = try GitFixtureRepo.make(prefix: "runworkspace")

        let workspace1 = try RunWorkspace.create(repoRoot: repo)
        try "run-1-was-here\n".write(
            to: workspace1.path.appendingPathComponent("run1-edit.txt"), atomically: true, encoding: .utf8)
        workspace1.remove()

        let workspace2 = try RunWorkspace.create(repoRoot: repo)
        defer { workspace2.remove() }

        #expect(workspace2.ref == workspace1.ref, "both start from the same repo HEAD")
        #expect(workspace2.path != workspace1.path, "each run gets its own directory")
        #expect(!FileManager.default.fileExists(atPath: workspace2.path.appendingPathComponent("run1-edit.txt").path),
                "run 2's workspace must not see run 1's own edit")
    }

    // MARK: - advertisedToolsAreVerifiedAgainstTheWire

    @Test func advertisedToolsAreVerifiedAgainstTheWire() throws {
        let name = "advertised-mismatch"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let engineDir = try tempDir("engine-mismatch")
        let modelPath = URL(fileURLWithPath: "/tmp/expverb-model-mismatch.gguf")
        try buildFakeEngine(engineDir: engineDir, modelPath: modelPath, toolVariants: [["read"], ["read", "write"]])

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: [
                "DS4_DIR": engineDir.path, "SWIFTSTAR_MODEL": modelPath.path,
                // Forces the fake to advertise something OTHER than what
                // either arm declared — the handshake mismatch decision 6
                // exists to catch.
                "FAKE_ADVERTISE_TOOLS_OVERRIDE": "bogus",
            ])

        #expect(result.status != 0)
        #expect(result.stderr.contains("advertised"), "stderr: \(result.stderr)")

        let resultsDir = try onlyResultsDir(repo: repo, name: name)
        let report = try String(contentsOf: resultsDir.appendingPathComponent("report.md"), encoding: .utf8)
        #expect(report.contains("advertised"), "the dropped-pair reason must name the mismatch: \(report)")
    }

    // MARK: - verdictCannotBeRecordedOnTheRunInvocation, and its sibling

    @Test func verdictCannotBeRecordedOnTheRunInvocation() throws {
        let name = "record-refused"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let result = try run(
            ["experiment", "evals/\(name).json", "--exploratory", "--record", "claimSurvives"], cwd: repo,
            extraEnv: ["DS4_DIR": repo.appendingPathComponent("no-such-engine").path,
                       "SWIFTSTAR_MODEL": "/tmp/expverb-model-unused.gguf"])

        #expect(result.status != 0)
        #expect(result.stderr.contains("--record"), "stderr: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: repo.appendingPathComponent("captures").path),
                "--record on the run invocation must be refused before anything is written")
    }

    /// Sibling (binding rule 4): `verdict` — a SEPARATE invocation, over an
    /// already-written results directory — records successfully and exits 0.
    @Test func verdictRecordsAfterwardAndExitsZero() throws {
        let name = "record-sibling"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let engineDir = try tempDir("engine-verdict")
        let modelPath = URL(fileURLWithPath: "/tmp/expverb-model-verdict.gguf")
        try buildFakeEngine(engineDir: engineDir, modelPath: modelPath, toolVariants: [["read"], ["read", "write"]])

        try run(
            ["experiment", "evals/\(name).json", "--exploratory"], cwd: repo,
            extraEnv: ["DS4_DIR": engineDir.path, "SWIFTSTAR_MODEL": modelPath.path])
        let resultsDir = try onlyResultsDir(repo: repo, name: name)

        let verdictResult = try run(
            ["verdict", resultsDir.path, "--record", "claimSurvives", "--evidence", "report.md:1"],
            cwd: repo, extraEnv: [:])

        #expect(verdictResult.status == 0, "stderr: \(verdictResult.stderr)")
        let verdictText = try String(contentsOf: resultsDir.appendingPathComponent("verdict.txt"), encoding: .utf8)
        #expect(verdictText.contains("claimSurvives"))
    }

    // MARK: - attemptNumberComesFromSiblingDirectories

    @Test func attemptNumberComesFromSiblingDirectories() throws {
        let name = "attempt-count"
        let json = experimentJSON(
            name: name, variable: "tools",
            controlOverrides: #"{"tools": ["read"]}"#,
            treatmentOverrides: #"{"tools": ["read", "write"]}"#)
        let repo = try makeRepo(experimentName: name, experimentJSON: json)

        let engineDir = try tempDir("engine-attempt")
        let modelPath = URL(fileURLWithPath: "/tmp/expverb-model-attempt.gguf")
        try buildFakeEngine(engineDir: engineDir, modelPath: modelPath, toolVariants: [["read"], ["read", "write"]])

        let env = ["DS4_DIR": engineDir.path, "SWIFTSTAR_MODEL": modelPath.path]
        try run(["experiment", "evals/\(name).json", "--exploratory"], cwd: repo, extraEnv: env)
        try run(["experiment", "evals/\(name).json", "--exploratory"], cwd: repo, extraEnv: env)

        let root = resultsRoot(repo: repo, name: name)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(entries.count == 2)
        let firstReport = try String(contentsOf: entries[0].appendingPathComponent("report.md"), encoding: .utf8)
        let secondReport = try String(contentsOf: entries[1].appendingPathComponent("report.md"), encoding: .utf8)
        #expect(firstReport.contains("attempt 1"), "\(firstReport)")
        #expect(secondReport.contains("attempt 2"), "\(secondReport)")
    }
}
