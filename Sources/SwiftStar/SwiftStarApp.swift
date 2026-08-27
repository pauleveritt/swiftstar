import AppKit
import SwiftUI
import SwiftStarKit

@main
struct SwiftStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `Window`, not `WindowGroup`: a second window would build a second
        // MainView, hence a second AgentController, which spawns another engine
        // loading the same multi-GB model — two processes contending for the
        // GPU and for /tmp/ds4-agent.lock — and would re-point
        // `AgentController.shared` (the quit handler and Settings' lifecycle
        // row) at the newest window. One engine, one window.
        Window("SwiftStar", id: "main") {
            MainView()
        }
        .commands {
            ToolbarCommands()
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Resource-bundle smoke test for the markdown renderer's dependency
        // (gated by env): fails loudly at launch, not on the first code block.
        MarkdownText.runResourceSelfTestIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop the agent on quit (Cmd-Q) so it is not orphaned to launchd.
        AgentController.shared?.stopAgent()
    }
}
