import SwiftUI
import SwiftStarKit

/// The main window's menus, shared by the app and the gallery (SU.12, D2),
/// so the gallery shows the same File, View and Session menus as the app.
public struct SwiftStarCommands: Commands {
    let engine: EngineController
    @AppStorage(DefaultsKey.fontSize.rawValue) private var fontSize = TranscriptFontScale.defaultSize

    public init(engine: EngineController) { self.engine = engine }

    public var body: some Commands {
        ToolbarCommands()
        // SU.11, D3: New Conversation, from the list's first row.
        CommandGroup(replacing: .newItem) {
            Button("New Conversation") { Task { await engine.newConversation() } }
                .keyboardShortcut("n")
        }
        // SU.7b: the Recent projects, as in the toolbar's folder menu.
        CommandGroup(after: .newItem) {
            Menu("Open Recent") {
                RecentProjectRows(controller: engine)
                Divider()
                Button("Clear Menu") { engine.clearRecents() }
                    .disabled(!engine.hasRecents)
            }
        }
        // SU.6f: the font size, a slot at a time, as in Settings.
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Bigger") { fontSize = TranscriptFontScale.bigger(fontSize) ?? fontSize }
                .keyboardShortcut("+")
                .disabled(TranscriptFontScale.bigger(fontSize) == nil)
            Button("Smaller") { fontSize = TranscriptFontScale.smaller(fontSize) ?? fontSize }
                .keyboardShortcut("-")
                .disabled(TranscriptFontScale.smaller(fontSize) == nil)
            Button("Actual Size") { fontSize = TranscriptFontScale.defaultSize }
                .keyboardShortcut("0")
                .disabled(TranscriptFontScale.clamp(fontSize) == TranscriptFontScale.defaultSize)
        }
        // SU.6c, D2: the last session's apply command, one click away.
        CommandMenu("Session") {
            Button("Copy Apply Command") { engine.copyApplyCommand() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!engine.canCopyApplyCommand)
        }
    }
}
