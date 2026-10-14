import SwiftUI
import SwiftStarUI

/// The real window and menus over the preview fixtures, with no engine
/// (SU.12): for checking what the canvas can't, such as the toolbar and the
/// menus. Its settings are its own defaults domain, by process name.
@main
struct GalleryApp: App {
    @State private var engine = EngineController.gallery()

    var body: some Scene {
        Window("SwiftStar Gallery", id: "main") {
            MainView()
                .environment(engine)
        }
        .commands { SwiftStarCommands(engine: engine) }
        .defaultSize(width: 900, height: 640)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
        }
    }
}
