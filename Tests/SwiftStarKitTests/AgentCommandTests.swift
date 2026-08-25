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
}
