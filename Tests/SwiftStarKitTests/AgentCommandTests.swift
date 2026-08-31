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
        // defaulting to off, plus `--host-tools` (P9: the app owns execution)
        // and `--per-turn-think` (P23: the app pins the engine).
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
            "--host-tools",
            "--per-turn-think",
        ])
    }

    @Test func argvAddsThePowerSavingDutyCycleWhenEnabled() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        var settings = makeSettings(workspace: ws)
        settings.powerSavingEnabled = true
        let argv = AgentCommand.argv(settings: settings)
        let index = argv.firstIndex(of: "--power")
        #expect(index != nil)
        #expect(index.map { argv[argv.index(after: $0)] } == String(AgentSettings.powerSavingPercent))
    }

    @Test func argvOmitsPowerSavingWhenDisabled() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        #expect(!AgentCommand.argv(settings: makeSettings(workspace: ws)).contains("--power"))
    }

    /// ds4.c's Laguna load path refuses to start at all when
    /// `power_percent < 100` ("Laguna S 2.1 currently supports the standard
    /// local graph path only"), so `--power` must never reach argv for a
    /// variant that streams via SSD (Laguna S/XS's own signal) even when
    /// power-saving is otherwise enabled.
    @Test func argvOmitsPowerSavingForAnSsdStreamingVariantEvenWhenEnabled() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        var settings = makeSettings(workspace: ws)
        settings.powerSavingEnabled = true
        settings.runtime = EngineRuntimeConfig(ssdStreaming: true, ssdStreamingCacheExperts: 3200)
        let argv = AgentCommand.argv(settings: settings)
        #expect(!argv.contains("--power"))
        #expect(AgentCommand.powerRecord(settings: settings) == "100 (engine default; no `--power`)")
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
        // -sys + text arrive after --host-tools/--per-turn-think (P9/P23);
        // the default-order test pins the nil case.
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
            "--host-tools",
            "--per-turn-think",
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

    @Test func argvAppendsVariantRuntimeFlags() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        var settings = makeSettings(workspace: ws)
        settings.runtime = EngineRuntimeConfig(ssdStreaming: true, ssdStreamingCacheExperts: 3200, prefillChunk: 4096)
        let argv = AgentCommand.argv(settings: settings)
        #expect(Array(argv.suffix(5)) == ["--ssd-streaming", "--ssd-streaming-cache-experts", "3200", "--prefill-chunk", "4096"])
    }

    @Test func argvOmitsRuntimeFlagsWhenNil() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        #expect(!AgentCommand.argv(settings: makeSettings(workspace: ws)).contains("--ssd-streaming"))
    }
}

/// The live capture's `provenance.md` recorded `Sampler: think=default` as a
/// literal, and recorded the engine's throttle not at all. Both are spawn facts
/// the argv already carries, and both changed how a session was read:
///
/// - `captures/live/20260830-180004` ran `--power 70` (the app's power-saving
///   default) while a `swiftstar-drive` re-run took the engine default of 100.
///   Prefill and decode were ~1.7x faster in the drive run on ~the same work,
///   and with the throttle unrecorded that gap was first read as an engine
///   improvement. It is visible only by grepping `power` out of the wire.
/// - `think=default` reads as "engine defaults", but the same spawn passes
///   `--nothink` and `--think-budget` whenever those settings are set.
struct AgentProvenanceRecordTests {
    private func settings(power: Bool, noThink: Bool = false,
                          thinkBudget: Int = 0, maxTokens: Int = 0) -> AgentSettings {
        AgentSettings(engineDir: URL(fileURLWithPath: "/e"),
                      modelPath: URL(fileURLWithPath: "/m.gguf"),
                      contextSize: 51_200,
                      workspace: URL(fileURLWithPath: "/ws"),
                      powerSavingEnabled: power,
                      maxTokens: maxTokens,
                      noThink: noThink,
                      thinkBudget: thinkBudget)
    }

    @Test func powerRecordNamesTheThrottleAndItsSource() {
        #expect(AgentCommand.powerRecord(settings: settings(power: true)) == "70 (`--power 70`)")
        #expect(AgentCommand.powerRecord(settings: settings(power: false))
                == "100 (engine default; no `--power`)")
    }

    /// The recorded throttle must be whatever argv actually passes — the two
    /// cannot be allowed to drift.
    @Test func powerRecordAgreesWithArgv() {
        let on = AgentCommand.argv(settings: settings(power: true))
        #expect(on.contains("--power"))
        #expect(on[on.firstIndex(of: "--power")! + 1] == "70")
        #expect(AgentCommand.powerRecord(settings: settings(power: true)).hasPrefix("70"))

        let off = AgentCommand.argv(settings: settings(power: false))
        #expect(!off.contains("--power"))
        #expect(AgentCommand.powerRecord(settings: settings(power: false)).hasPrefix("100"))
    }

    @Test func samplerRecordReportsTheSpawnThinkConfiguration() {
        #expect(AgentCommand.samplerRecord(settings: settings(power: true)) == "think=default")
        #expect(AgentCommand.samplerRecord(settings: settings(power: true, noThink: true))
                == "think=none (`--nothink`)")
        #expect(AgentCommand.samplerRecord(settings: settings(power: true, thinkBudget: 512))
                == "think=default, budget=512")
        #expect(AgentCommand.samplerRecord(
            settings: settings(power: true, noThink: true, thinkBudget: 512))
                == "think=none (`--nothink`), budget=512")
    }

    /// `clampThinkBudget` halves the budget against `maxTokens`; the record must
    /// report the clamped value that argv actually passes, not the raw setting.
    @Test func samplerRecordReportsTheClampedBudget() {
        let s = settings(power: true, thinkBudget: 512, maxTokens: 400)
        let argv = AgentCommand.argv(settings: s)
        #expect(argv[argv.firstIndex(of: "--think-budget")! + 1] == "200")
        #expect(AgentCommand.samplerRecord(settings: s) == "think=default, budget=200")
    }
}
