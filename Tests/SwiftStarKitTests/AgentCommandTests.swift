import Testing
import Foundation
@testable import SwiftStarKit

struct AgentCommandTests {
    private func makeSettings(workspace: URL, shellAllowed: Bool = false, systemPrompt: String? = nil) -> AgentSettings {
        AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            contextSize: 16384,
            workspace: workspace,
            shellAllowed: shellAllowed,
            systemPrompt: systemPrompt
        )
    }

    @Test func argvCarriesConsentFlagsAndHostToolsByDefault() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        // The app always passes both consent flags explicitly (D2), shell
        // defaulting to off, plus `--host-tools` (P9: the app owns execution).
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
            "--host-tools",
        ])
    }

    @Test func argvAllowsShell() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws, shellAllowed: true))
        #expect(argv.contains("--shell"))
        #expect(argv[argv.firstIndex(of: "--shell")! + 1] == "on")
    }

    @Test func argvAppendsSystemPromptAfterHostTools() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws, systemPrompt: "You have Superpowers."))
        // -sys + text arrive after --host-tools (P9); the default-order test
        // pins the nil case.
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
            "--host-tools",
            "-sys", "You have Superpowers.",
        ])
    }

    @Test func argvOmitsSystemPromptWhenNil() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        #expect(!argv.contains("-sys"))
    }

    @Test func argvEmitsTokenCapWhenSet() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let settings = AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            workspace: ws, maxTokens: 8192)
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("-n"))
        #expect(argv[argv.firstIndex(of: "-n")! + 1] == "8192")
    }

    @Test func argvOmitsTokenCapWhenZero() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        #expect(!argv.contains("-n"))
    }

    @Test func argvEmitsNothinkWhenSet() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let settings = AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            workspace: ws, noThink: true)
        #expect(AgentCommand.argv(settings: settings).contains("--nothink"))
        #expect(!AgentCommand.argv(settings: makeSettings(workspace: ws)).contains("--nothink"))
    }

    /// `--think-budget` bounds a single round's *thinking* separately from
    /// `-n`, which caps the round's total generation. Forcing `</think>` when
    /// the total cap is already exhausted would end the round with no room to
    /// act, so the two must stay distinct.
    @Test func argvEmitsThinkBudgetWhenSet() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let settings = AgentSettings(
            engineDir: URL(fileURLWithPath: "/tmp/fake-engine"),
            modelPath: URL(fileURLWithPath: "/tmp/model.gguf"),
            workspace: ws, maxTokens: 8192, thinkBudget: 2048)
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("--think-budget"))
        #expect(argv[argv.firstIndex(of: "--think-budget")! + 1] == "2048")
        // The total cap must still be emitted and must not be overwritten.
        #expect(argv[argv.firstIndex(of: "-n")! + 1] == "8192")
    }

    @Test func argvOmitsThinkBudgetWhenZero() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        #expect(!AgentCommand.argv(settings: makeSettings(workspace: ws)).contains("--think-budget"))
    }

    /// P12.7 piece 1: `--trace <path>` is appended only when `tracePath` is
    /// set — every existing call site that doesn't set it (the default `nil`)
    /// must produce byte-identical argv to before this field existed.
    @Test func argvOmitsTraceWhenNotSet() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        #expect(!argv.contains("--trace"))
    }

    @Test func argvAppendsTraceWhenSet() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        var settings = makeSettings(workspace: ws)
        settings.tracePath = URL(fileURLWithPath: "/tmp/captures/run1/wire.trace")
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("--trace"))
        #expect(argv[argv.firstIndex(of: "--trace")! + 1] == "/tmp/captures/run1/wire.trace")
    }

    @Test func binaryPathIsDs4Agent() {
        let settings = makeSettings(workspace: URL(fileURLWithPath: "/tmp/ws"))
        #expect(AgentCommand.binaryPath(settings: settings) == URL(fileURLWithPath: "/tmp/fake-engine/ds4-agent"))
    }

    @Test func argvPassesSeedWhenNonZero() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        var settings = makeSettings(workspace: ws)
        settings.seed = 7
        let argv = AgentCommand.argv(settings: settings)
        #expect(argv.contains("--seed"))
        #expect(argv[argv.firstIndex(of: "--seed")! + 1] == "7")
    }

    @Test func argvOmitsSeedWhenZero() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        #expect(!AgentCommand.argv(settings: makeSettings(workspace: ws)).contains("--seed"))
    }

    /// The engine chdir's to `--workspace` and loads `metal/*.metal`
    /// cwd-relative, so the spawner must point each at its absolute path via
    /// `DS4_METAL_*_SOURCE` (the same override PoolOrchestrator/swiftstar-drive
    /// use). Regression: the app's Agent tab omitted this, so the agent aborted
    /// startup ("metal backend unavailable") before emitting `hello`. Also sets
    /// the per-mode `DS4_LOCK_FILE` so Chat and Agent don't collide on the
    /// engine's single-instance lock.
    @Test func engineEnvironmentPointsShadersAtAbsolutePathsAndSetsLock() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metal-env-\(UUID().uuidString)")
        let metal = dir.appendingPathComponent("metal", isDirectory: true)
        try FileManager.default.createDirectory(at: metal, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: metal.appendingPathComponent("flash_attn.metal"), atomically: true, encoding: .utf8)
        try "y".write(to: metal.appendingPathComponent("moe.metal"), atomically: true, encoding: .utf8)
        try "z".write(to: metal.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        let env = AgentCommand.engineEnvironment(engineDir: dir, lockFile: "/tmp/ds4-test.lock", base: ["KEEP": "me"])

        #expect(env["DS4_METAL_FLASH_ATTN_SOURCE"] == metal.appendingPathComponent("flash_attn.metal").path)
        #expect(env["DS4_METAL_MOE_SOURCE"] == metal.appendingPathComponent("moe.metal").path)
        #expect(env["DS4_METAL_README_SOURCE"] == nil, "non-.metal files must not get an override")
        #expect(env["DS4_LOCK_FILE"] == "/tmp/ds4-test.lock", "the per-mode lock file must be set")
        #expect(env["KEEP"] == "me", "the base environment must be preserved")
    }
}
