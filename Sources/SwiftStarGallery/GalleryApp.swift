import AppKit
import SwiftUI
import SwiftStarUI

/// The real window and menus over the preview fixtures, with no engine
/// (SU.12): for checking what the canvas can't, such as the toolbar and the
/// menus. Its settings are its own defaults domain, by process name.
@main
struct GalleryApp: App {
    @NSApplicationDelegateAdaptor(GalleryDelegate.self) private var delegate
    @State private var engine = EngineController.gallery()

    var body: some Scene {
        Window("SwiftStar Gallery", id: "main") {
            MainView()
                .environment(engine)
                // `defaults write SwiftStarGallery galleryFlipGPU -int 6`: flip
                // GPU metrics that many times at launch (SU.13).
                .task {
                    let flips = UserDefaults.standard.integer(forKey: "galleryFlipGPU")
                    if flips > 0 { await engine.galleryFlipGPU(times: flips) }
                }
        }
        .commands { SwiftStarCommands(engine: engine) }
        .defaultSize(width: 1000, height: 640)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}

/// A bare executable starts as a background app: no Dock icon, and its
/// window stays behind Xcode. Like the app's delegate, come forward.
final class GalleryDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
