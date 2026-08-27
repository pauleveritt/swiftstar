import AppKit
import SwiftUI
import SwiftStarKit

@main
struct SwiftStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("SwiftStar") {
            MainView()
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
