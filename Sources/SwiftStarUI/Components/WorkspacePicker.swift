import AppKit

/// The folder panel, shared by the toolbar's "Choose Folder…" and the
/// no-usable-workspace start (SU.6c, D1).
enum WorkspacePicker {
    static func run(from directory: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        panel.message = "Choose a folder in the git repository the engine should work on"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
