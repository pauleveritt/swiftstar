import AppKit
import SwiftUI
import SwiftStarKit

struct SessionView: View {
    @Environment(EngineController.self) private var controller
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage(DefaultsKey.inspectorPresented.rawValue) private var inspectorPresented = false
    @State private var askingModel = false
    @State private var askingContext = false
    @State private var entry = ""
    @AppStorage(DefaultsKey.transcriptFontSize.rawValue) private var transcriptFontSize = TranscriptFontScale.defaultSize
    @Environment(\.transcriptFontSize) private var envTranscriptFontSize: CGFloat

    private var composerState: EngineComposer { controller.composer }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(transcript: controller.transcript, workspace: controller.workspace)
            Divider()
            composer
            Divider()
            StatusBarView(phase: controller.phase, composerLabel: composerState.label, metrics: controller.metrics)
        }
        .navigationTitle("Agent")
        .environment(\.transcriptFontSize, CGFloat(TranscriptFontScale.clamp(transcriptFontSize)))
        .toolbar {
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
                        controller.start()
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
        .task { if controller.phase == .idle { controller.start() } }
        .task { inputFocused = true }
        .task { await controller.loadCatalogIfNeeded() }
        .alert("Other model", isPresented: $askingModel) {
            TextField("Model id", text: $entry)
            Button("Use") { controller.select(modelID: entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type an engine model id, e.g. laguna-xs-2.1. A running session restarts.")
        }
        .alert("Custom context size", isPresented: $askingContext) {
            TextField("Tokens", text: $entry)
            Button("Use") {
                if let n = Int(entry.trimmingCharacters(in: .whitespaces)), n > 0 {
                    controller.select(contextSize: n)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Type a context size in tokens. A running session restarts.")
        }
    }

    /// Each menu is its own toolbar item (its own glass capsule); choosing a
    /// different value restarts a running session, so all are disabled while
    /// one starts or quits.
    private func menuButton(_ menu: some View) -> some View {
        menu
            .font(.system(size: envTranscriptFontSize))
            .disabled(controller.phase == .starting || controller.phase == .quitting)
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
        var label = loaded ?? (controller.modelID.isEmpty ? "Engine default" : controller.modelID)
        // A skipped restart leaves Settings ahead of the loaded model.
        if let loaded, !controller.modelID.isEmpty, controller.modelID != loaded {
            label = "\(loaded) → \(controller.modelID)"
        }
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
        let size = session?.contextSize ?? (controller.contextSize > 0 ? controller.contextSize : nil)
        var label = size.map { "\($0.formatted(.number.grouping(.never))) ctx" } ?? "Default ctx"
        if let loadedSize = session?.contextSize, controller.contextSize > 0,
           controller.contextSize != loadedSize {
            label = "\(loadedSize.formatted(.number.grouping(.never))) → \(controller.contextSize.formatted(.number.grouping(.never))) ctx"
        }
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

    private var composer: some View {
        VStack(spacing: 4) {
            if let notice = noticeText {
                HStack {
                    Text(notice)
                        .font(.system(size: envTranscriptFontSize))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the agent…", text: $input, axis: .vertical)
                    .font(.system(size: CGFloat(TranscriptFontScale.clamp(transcriptFontSize))))
                    .textFieldStyle(.plain)
                    .lineLimit(1...15)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .focused($inputFocused)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                    )
                    .onSubmit { send() }
                    .disabled(!composerState.canType)
                // Busy with text typed: the button sends (the engine queues it);
                // busy with an empty field it stops.
                let showsStop = composerState.canStop && trimmedInput.isEmpty
                Button {
                    if showsStop {
                        controller.stop()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: showsStop ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolEffect(.variableColor.iterative, isActive: showsStop)
                        .foregroundStyle(showsStop ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // Icon-only, and the icon carries the whole meaning — the label
                // has to move with the state or VoiceOver announces nothing.
                .accessibilityLabel(showsStop ? "Stop generating" : "Send message")
                .disabled(showsStop ? false : (!composerState.canSend || trimmedInput.isEmpty))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: composerState.canStop) { _, stoppable in
            if !stoppable { inputFocused = true }
        }
    }

    /// Shown above the prompt field when the engine could not be found.
    private var noticeText: String? {
        if case .notFound(let searched) = controller.phase {
            return "ds4-dogfood was not found. Searched:\n" + searched.joined(separator: "\n")
        }
        return nil
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

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let message = trimmedInput
        guard composerState.canSend, !message.isEmpty else { return }
        input = ""
        controller.send(message)
    }
}

#Preview("Running", traits: .runningSession) {
    SessionView()
}

#Preview("Idle", traits: .idleSession) {
    SessionView()
}
