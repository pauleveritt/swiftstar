import AppKit
import SwiftUI
import SwiftStarKit

/// The session window's toolbar: folder, model and context menus, the
/// start/end button and the inspector toggle. The "Other…" and "Custom…"
/// alerts live on `SessionView`; this toolbar only raises their flags.
struct SessionToolbar: ToolbarContent {
    @Binding var askingModel: Bool
    @Binding var askingContext: Bool
    @Binding var entry: String
    @Binding var inspectorPresented: Bool
    @Environment(EngineController.self) private var controller
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) { menuButton(folderMenu) }
        ToolbarSpacer(.fixed, placement: .automatic)
        ToolbarItem(placement: .automatic) { menuButton(modelMenu) }
        ToolbarSpacer(.fixed, placement: .automatic)
        ToolbarItem(placement: .automatic) { menuButton(contextMenu) }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if controller.isActive {
                    Task { await controller.quit() }
                } else {
                    Task { await controller.start() }
                }
            } label: {
                Label(sessionActionTitle, systemImage: sessionActionIcon)
            }
            .help(sessionActionHelp)
            .disabled(controller.phase == .quitting)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorPresented.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help(inspectorPresented ? "Hide Inspector" : "Show Inspector")
        }
    }

    /// Each menu is its own toolbar item (its own glass capsule); choosing a
    /// different value restarts a running session, so all are disabled while
    /// one starts or quits.
    private func menuButton(_ menu: some View) -> some View {
        menu
            .font(.system(size: transcriptFontSize))
            .disabled(!controller.canChoose)
    }

    private func menuLabel(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        // Keep the item at its natural width as the transcript font grows.
        .fixedSize(horizontal: true, vertical: false)
        // `.borderlessButton` menus draw no content inset of their own inside the
        // glass capsule, so give the label the inset the icon buttons have.
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func choiceRow(
        title: String, checked: Bool, disabledReason: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            let text = disabledReason.map { "\(title) — \($0)" } ?? title
            if checked {
                Label(text, systemImage: "checkmark")
            } else {
                Text(text)
            }
        }
        .disabled(disabledReason != nil)
    }

    private var folderMenu: some View {
        let current = controller.workspace?.path
        return Menu {
            ForEach(
                RecentWorkspaces.items(
                    controller.recentWorkspaces, current: current,
                    exists: { FileManager.default.fileExists(atPath: $0) }),
                id: \.value
            ) { item in
                choiceRow(title: item.title, checked: item.isChecked, disabledReason: item.disabledReason) {
                    controller.select(workspace: URL(fileURLWithPath: item.value))
                }
            }
            if !controller.recentWorkspaces.isEmpty { Divider() }
            Button("Choose Folder…", action: pickWorkspace)
        } label: {
            menuLabel(controller.workspace.map(PathAbbreviation.leafName) ?? "Choose folder", icon: "folder")
        }
        .menuStyle(.borderlessButton)
        .help("Workspace: its git repository is the engine's source. Choosing another restarts a running session.")
    }

    private var modelMenu: some View {
        let loaded = controller.transcript.session?.modelID
        let items = ModelMenu.items(list: controller.catalog, settingsID: controller.modelID, loadedID: loaded)
        let label = ModelMenu.label(loaded: loaded, chosen: controller.modelID)
        return Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                choiceRow(title: item.title, checked: item.isChecked, disabledReason: item.disabledReason) {
                    controller.select(modelID: item.value)
                }
                if index == 0 { Divider() }
            }
            Divider()
            Button("Other…") { entry = ""; askingModel = true }
        } label: {
            menuLabel(label)
        }
        .menuStyle(.borderlessButton)
        .help("Model: choosing another restarts a running session")
    }

    private var contextMenu: some View {
        let session = controller.transcript.session
        let items = ContextMenu.items(
            list: controller.catalog, modelID: session?.modelID ?? controller.modelID,
            settingsContext: controller.contextSize, loaded: session?.contextSize)
        let label = ContextMenu.label(loaded: session?.contextSize, chosen: controller.contextSize)
        return Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                choiceRow(title: item.title, checked: item.isChecked, disabledReason: item.disabledReason) {
                    controller.select(contextSize: item.value)
                }
                if index == 0 { Divider() }
            }
            Divider()
            Button("Custom…") { entry = ""; askingContext = true }
        } label: {
            menuLabel(label)
        }
        .menuStyle(.borderlessButton)
        .help("Context size: choosing another restarts a running session")
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = controller.workspace
        panel.message = "Choose a folder in the git repository the engine should work on"
        if panel.runModal() == .OK, let url = panel.url {
            controller.select(workspace: url)
        }
    }

    private var sessionActionTitle: String {
        controller.isActive ? "End session" : "Start session"
    }

    private var sessionActionIcon: String {
        controller.isActive ? "stop.circle" : "play.circle"
    }

    private var sessionActionHelp: String {
        controller.isActive ? "End the current agent session" : "Start a new agent session"
    }
}

#Preview("Running", traits: .runningSession) {
    @Previewable @State var flag = false
    @Previewable @State var entry = ""
    Color.clear
        .frame(width: 900, height: 120)
        .toolbar {
            SessionToolbar(
                askingModel: $flag, askingContext: $flag, entry: $entry, inspectorPresented: $flag)
        }
}
