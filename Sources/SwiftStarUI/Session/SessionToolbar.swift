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
        // No `.font` here: these menus ignored it (a 30 pt probe rendered
        // unchanged in SU.4, under the `.borderlessButton` style since dropped).
        menu.disabled(!controller.canChoose)
    }

    private func menuLabel(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        // Keep the item at its natural width as the font size grows.
        .fixedSize(horizontal: true, vertical: false)
        // No padding and no menu style: the toolbar's own pop-up style gives
        // even insets, chevron included, as in Xcode. `.borderlessButton`
        // drew none and dropped the label's padding (SU.6f).
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
        Menu {
            RecentProjectRows(controller: controller)
            if !controller.recentWorkspaces.isEmpty { Divider() }
            Button("Choose Folder…", action: pickWorkspace)
        } label: {
            menuLabel(controller.workspace?.leafName ?? "Choose folder", icon: "folder")
        }
        .help("Workspace: its git repository is the engine's source. Choosing another ends a running session; mid-turn, it asks first.")
    }

    private var modelMenu: some View {
        let loaded = controller.transcript.session?.modelID
        let items = ModelMenu.items(list: controller.catalog, settingsID: controller.modelID, loadedID: loaded)
        let label = ModelMenu.label(loaded: loaded, chosen: controller.modelID)
        return choiceMenu(items, label: label, more: "Other…", select: { controller.select(modelID: $0) }) {
            entry = ""; askingModel = true
        }
        .help("Model: choosing another switches a running session with /model, keeping its files")
    }

    private var contextMenu: some View {
        let session = controller.transcript.session
        let items = ContextMenu.items(
            list: controller.catalog, modelID: session?.modelID ?? controller.modelID,
            settingsContext: controller.contextSize, loaded: session?.contextSize)
        let label = ContextMenu.label(loaded: session?.contextSize, chosen: controller.contextSize)
        return choiceMenu(items, label: label, more: "Custom…", select: { controller.select(contextSize: $0) }) {
            entry = ""; askingContext = true
        }
        .help("Context size: choosing another restarts a running session")
    }

    /// A menu of choices: the first (the engine default) set off by a
    /// divider, then the rest, then an entry for a value typed by hand.
    private func choiceMenu<Value: Equatable & Sendable>(
        _ items: [MenuChoice<Value>], label: String, more: String,
        select: @escaping (Value) -> Void, onMore: @escaping () -> Void
    ) -> some View {
        Menu {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                choiceRow(title: item.title, checked: item.isChecked, disabledReason: item.disabledReason) {
                    select(item.value)
                }
                if index == 0 { Divider() }
            }
            Divider()
            Button(more, action: onMore)
        } label: {
            menuLabel(label)
        }
    }

    private func pickWorkspace() {
        if let url = WorkspacePicker.run(from: controller.workspace) {
            controller.requestSwitch(to: url)
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
