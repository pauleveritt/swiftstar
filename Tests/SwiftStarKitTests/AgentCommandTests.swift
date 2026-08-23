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

    @Test func argvCarriesConsentFlagsByDefault() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        // The app always passes both flags explicitly (D2), shell defaulting to off.
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
        ])
    }

    @Test func argvAllowsShell() {
        let ws = URL(fileURLWithPath: "/tmp/ws")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws, shellAllowed: true))
        #expect(argv.contains("--shell"))
        #expect(argv[argv.firstIndex(of: "--shell")! + 1] == "on")
    }

    @Test func argvAppendsSystemPromptAfterShell() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws, systemPrompt: "You have Superpowers."))
        // -sys + text arrive after --shell (D1); the default-order test pins the nil case.
        #expect(argv == [
            "-m", "/tmp/model.gguf",
            "-c", "16384",
            "--metal",
            "--non-interactive",
            "--json-events",
            "--workspace", "/Users/me/Work",
            "--shell", "off",
            "-sys", "You have Superpowers.",
        ])
    }

    @Test func argvOmitsSystemPromptWhenNil() {
        let ws = URL(fileURLWithPath: "/Users/me/Work")
        let argv = AgentCommand.argv(settings: makeSettings(workspace: ws))
        #expect(!argv.contains("-sys"))
    }

    @Test func binaryPathIsDs4Agent() {
        let settings = makeSettings(workspace: URL(fileURLWithPath: "/tmp/ws"))
        #expect(AgentCommand.binaryPath(settings: settings) == URL(fileURLWithPath: "/tmp/fake-engine/ds4-agent"))
    }
}
