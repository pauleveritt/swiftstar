import AppKit
import SwiftUI
import SwiftStarKit
import SwiftStarUI

@main
struct SwiftStarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var engine = EngineController()

    var body: some Scene {
        // `Window`, not `WindowGroup`: a second window would spawn a second
        // engine loading the same multi-GB model, two processes contending for
        // the GPU. One engine, one window.
        Window("SwiftStar", id: "main") {
            MainView()
                .environment(engine)
                .onAppear { appDelegate.engine = engine }
        }
        .commands { SwiftStarCommands(engine: engine) }
        .defaultSize(width: 1000, height: 640)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the main window; the quit handler waits on it.
    var engine: EngineController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // Resource-bundle smoke test for the markdown renderer's dependency
        // (gated by env): fails loudly at launch, not on the first code block.
        MarkdownSelfTest.runIfRequested()
    }

    /// One engine, one window (see `SwiftStarApp.body`): closing it should
    /// end the app, not leave it running with no window and a menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// SU.7b: the Recent projects, each with its resume item indented under
    /// it. Choosing one brings the window forward first, so a mid-turn
    /// confirmation shows on it.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let engine else { return nil }
        let projects = engine.recentProjects
        guard !projects.isEmpty else { return nil }
        let menu = NSMenu()
        for project in projects {
            let folder = URL(fileURLWithPath: project.path)
            let row = NSMenuItem(title: project.menuTitle, action: nil, keyEquivalent: "")
            row.state = project.isCurrent ? .on : .off
            if !project.isCurrent, project.disabledReason == nil {
                row.target = self
                row.action = #selector(openRecent(_:))
                row.representedObject = ProjectSwitch(folder: folder, resuming: nil)
            }
            menu.addItem(row)
            if let conversation = project.latest, let title = project.resumeTitle {
                let resume = NSMenuItem(title: title, action: #selector(openRecent(_:)), keyEquivalent: "")
                resume.target = self
                resume.indentationLevel = 1
                resume.representedObject = ProjectSwitch(folder: folder, resuming: conversation)
                menu.addItem(resume)
            }
        }
        return menu
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? ProjectSwitch else { return }
        NSApp.activate()
        engine?.requestSwitch(to: request.folder, resuming: request.resuming)
    }

    /// A terminate reply is owed and not yet sent.
    private var terminationPending = false

    /// Quit waits for the engine to exit, so it is not orphaned to launchd.
    /// While the engine is active (including mid-quit) this answers
    /// `.terminateLater`, joins any quit in flight, and replies exactly once.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine, engine.isActive else { return .terminateNow }
        guard !terminationPending else { return .terminateLater }
        terminationPending = true
        engine.beginTerminating()
        Task {
            await engine.quit()
            terminationPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
