import AppKit
import SwiftUI
import SwiftStarKit

@main
struct SwiftStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = EngineController()

    var body: some Scene {
        // `Window`, not `WindowGroup`: a second window would spawn a second
        // engine loading the same multi-GB model, two processes contending for
        // the GPU. One engine, one window.
        Window("SwiftStar", id: "main") {
            MainView(engine: engine)
                .onAppear { appDelegate.engine = engine }
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
    /// Set by the main window; the quit handler waits on it.
    var engine: EngineController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Resource-bundle smoke test for the markdown renderer's dependency
        // (gated by env): fails loudly at launch, not on the first code block.
        MarkdownText.runResourceSelfTestIfRequested()
    }

    /// Quit waits for the engine to exit, so it is not orphaned to launchd.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine, engine.isActive else { return .terminateNow }
        Task { @MainActor in
            await engine.quit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
