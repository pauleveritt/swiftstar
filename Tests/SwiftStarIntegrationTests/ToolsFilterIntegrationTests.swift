import Testing
import Foundation
import Darwin
import SwiftStarKit

/// eval-cli task 1 (fork divergence #19): `--tools` is the flagship
/// experiment's declared variable (`variable: "tools"`), so the app's own
/// `AgentCommand.argv` wiring must actually reach the real engine's
/// advertised schema set, not just the argv array. Every other integration
/// test in this target drives a *fake* `ds4-agent` compiled from a captured
/// fixture (`FakeAgentHarness`); this suite is the one exception — it spawns
/// the REAL binary built by `just engine` against a real model, because the
/// thing under test is exactly what the fake cannot fake: whether the engine
/// itself honors the flag. Skips (rather than fails) when the binary or
/// model isn't staged on this machine, the same pattern
/// `DeepSeekV4FlashMetadataIntegrationTests` uses for its real artifact.
// .serialized: both tests spawn the real ~46 GiB Laguna S 2.1 engine
// process; running them concurrently (swift-testing's default) doubles the
// Metal/memory footprint and risks the two engines racing on the same GPU
// device, unrelated to what either test is actually checking.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTSTAR_INTEGRATION"] == "1"))
struct ToolsFilterIntegrationTests {
    private var engineDir: URL { FakeAgentHarness.repoRoot.appendingPathComponent("external/ds4") }
    private var engineBinary: URL { engineDir.appendingPathComponent("ds4-agent") }

    /// Spawn the real engine with `settings`, wait for the startup `ready`
    /// event (worker init — including the system-prompt prefill the trace
    /// dumps — is complete by then), then return the tool names the
    /// `--trace` file's `initial_system_prompt` token dump advertised.
    /// Real spawn, real model load — this is the one place in the suite
    /// that is genuinely slow (tens of seconds), which is why it is scoped
    /// to exactly the two tests that need it.
    private func advertisedToolNames(settings: AgentSettings, tracePath: URL) throws -> Set<String> {
        var settings = settings
        settings.tracePath = tracePath
        let process = Process()
        process.executableURL = engineBinary
        process.arguments = AgentCommand.argv(settings: settings)
        process.currentDirectoryURL = engineDir
        process.environment = AgentCommand.engineEnvironment(
            engineDir: engineDir,
            lockFile: "/tmp/ds4-tools-filter-test-\(UUID().uuidString).lock",
            base: ProcessInfo.processInfo.environment)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = Pipe()
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
        }

        let reader = PollingLineReader(fd: out.fileHandleForReading.fileDescriptor)
        var parser = AgentWireParser()
        let deadline = Date().addingTimeInterval(180)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                Issue.record("timed out waiting for startup ready")
                return []
            }
            let line = try reader.nextLine(timeout: remaining)
            if let event = parser.feed(line), case .ready = event {
                break
            }
        }

        let trace = try String(contentsOf: tracePath, encoding: .utf8)
        return Self.toolNames(fromTrace: trace)
    }

    /// Decode every token's `text="..."` payload from the trace's
    /// `initial_system_prompt` dump (`agent_trace_tokens`/`agent_trace_token`
    /// in `ds4_agent.c`), concatenate the decoded text, and extract the
    /// `"name"` key's string value from every schema object — the Swift
    /// mirror of the engine test suite's own `agent_test_tool_names` helper
    /// (`ds4_agent.c`), so both sides agree on what "the advertised tool
    /// names" means. Tolerates both schema spellings: compact
    /// (`"name":"x"`) and DSML's pretty-printed (`"name": "x"`).
    static func toolNames(fromTrace trace: String) -> Set<String> {
        var decoded = ""
        var scan = trace.startIndex
        let needle = "text=\""
        while let range = trace.range(of: needle, range: scan..<trace.endIndex) {
            var i = range.upperBound
            var token = ""
            while i < trace.endIndex, trace[i] != "\"" {
                if trace[i] == "\\", trace.index(after: i) < trace.endIndex {
                    let next = trace[trace.index(after: i)]
                    switch next {
                    case "n": token.append("\n")
                    case "r": token.append("\r")
                    case "t": token.append("\t")
                    case "\"": token.append("\"")
                    case "\\": token.append("\\")
                    default: token.append(next)
                    }
                    i = trace.index(i, offsetBy: 2)
                } else {
                    token.append(trace[i])
                    i = trace.index(after: i)
                }
            }
            decoded += token
            scan = i < trace.endIndex ? trace.index(after: i) : trace.endIndex
        }

        var names: Set<String> = []
        var i = decoded.startIndex
        let key = "\"name\""
        while let range = decoded.range(of: key, range: i..<decoded.endIndex) {
            var j = range.upperBound
            while j < decoded.endIndex, decoded[j] == " " { j = decoded.index(after: j) }
            guard j < decoded.endIndex, decoded[j] == ":" else { i = range.upperBound; continue }
            j = decoded.index(after: j)
            while j < decoded.endIndex, decoded[j] == " " { j = decoded.index(after: j) }
            guard j < decoded.endIndex, decoded[j] == "\"" else { i = range.upperBound; continue }
            let start = decoded.index(after: j)
            var k = start
            while k < decoded.endIndex, decoded[k] != "\"" { k = decoded.index(after: k) }
            names.insert(String(decoded[start..<k]))
            i = k < decoded.endIndex ? decoded.index(after: k) : decoded.endIndex
        }
        return names
    }

    private func realSettings(tools: [String]?) throws -> AgentSettings {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftstar-tools-filter-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return AgentSettings(
            engineDir: engineDir,
            modelPath: VariantRegistry.lagunaS.modelFile,
            contextSize: 4096,
            workspace: workspace,
            shellAllowed: true,
            tools: tools)
    }

    private func skipIfUnstaged() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: engineBinary.path) else {
            Issue.record("ds4-agent not built at \(engineBinary.path) — run `just engine`; skip on a machine without it")
            return true
        }
        guard FileManager.default.isReadableFile(atPath: VariantRegistry.lagunaS.modelFile.path) else {
            Issue.record("Laguna S 2.1 model not found at \(VariantRegistry.lagunaS.modelFile.path) — skip on a machine without it staged")
            return true
        }
        return false
    }

    /// `advertisedSchemasHonorTheToolsFilter`: spawning with
    /// `--tools read,write,list` yields a handshake whose advertised schema
    /// names are exactly those three.
    @Test func advertisedSchemasHonorTheToolsFilter() throws {
        if skipIfUnstaged() { return }
        let trace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools-filter-\(UUID().uuidString).trace")
        let settings = try realSettings(tools: ["read", "write", "list"])
        let names = try advertisedToolNames(settings: settings, tracePath: trace)
        #expect(names == ["read", "write", "list"])
    }

    /// Sibling of the above (binding rule 4): the unfiltered set is
    /// unchanged when `--tools` is absent — the decision this task is built
    /// around ("absent `--tools` preserves today's advertisement") verified
    /// against the real binary, not assumed.
    @Test func absentToolsFlagAdvertisesEverything() throws {
        if skipIfUnstaged() { return }
        let trace = FileManager.default.temporaryDirectory
            .appendingPathComponent("tools-filter-\(UUID().uuidString).trace")
        let settings = try realSettings(tools: nil)
        let names = try advertisedToolNames(settings: settings, tracePath: trace)
        // shellAllowed: true, host_tools always on (AgentCommand always
        // passes --host-tools) -- the full Laguna/GLM-syntax surface,
        // unfiltered: the 11-tool base zoo plus the three host-tool schemas
        // (dispatch/test/lint), all advertised under --host-tools.
        #expect(names == [
            "google_search", "visit_page", "bash", "bash_status", "bash_stop",
            "read", "more", "write", "edit", "search", "list",
            "dispatch", "test", "lint",
        ])
    }
}
