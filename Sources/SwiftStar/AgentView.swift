import AppKit
import SwiftUI
import SwiftStarKit

struct AgentView: View {
    let controller: EngineController
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("appShellInspectorPresented") private var inspectorPresented = false
    @State private var askingModel = false
    @State private var askingContext = false
    @State private var entry = ""
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize
    @Environment(\.transcriptFontSize) private var envTranscriptFontSize: CGFloat

    private var composerState: EngineComposer { controller.composer }

    var body: some View {
        VStack(spacing: 0) {
            transcriptView
            Divider()
            composer
            Divider()
            bottomStatusBar
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

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Rows are keyed by offset: the transcript only appends
                    // rows (a tool card fills in place), so an offset is a
                    // stable identity for a row's whole lifetime.
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { index, row in
                        rowView(row, queued: controller.transcript.isPending(rowAt: index))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.transcript.rows) { _, _ in
                // Compare the whole array, not `.count`: a tool card fills in
                // place, so the count alone would miss it.
                let last = controller.transcript.rows.count - 1
                guard last >= 0 else { return }
                // Follow the latest row without animating; an animated scroll
                // per mutation keeps interrupting the previous one.
                var transaction = Transaction()
                transaction.animation = nil
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TranscriptRow, queued: Bool) -> some View {
        switch row {
        case .user(let text):
            AgentPromptBubble(text: text, queued: queued)
        case .thinking(let text):
            ThinkingDisclosure(text: text)
        case .narration(let text):
            MarkdownText(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .answer(let answer):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(answer.text)
                if let line = Self.answerSummary(answer) {
                    // Engine telemetry, styled small and secondary so it never
                    // reads as part of the answer.
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let card):
            AgentToolCardView(card: card, workspace: controller.workspace)
        case .system(let text):
            Text(text)
                .font(.system(size: envTranscriptFontSize))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
        case .error(let text):
            Text(text)
                .font(.system(size: envTranscriptFontSize))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private static func answerSummary(_ answer: EngineAnswer) -> String? {
        var parts: [String] = []
        if let ms = answer.durationMs, ms.isFinite, ms >= 0 {
            parts.append(String(format: "%.1fs", ms / 1000))
        }
        if let used = answer.contextUsed, let size = answer.contextSize {
            parts.append("ctx \(used.formatted()) / \(size.formatted())")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
                    .onKeyPress(keys: [.return], phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            input += "\n"
                            return .handled
                        }
                        send()
                        return .handled
                    }
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

    /// Bottom readout bar: left = fixed-width prefill/generation rates and the
    /// phase, right = memory and the context-fill ring.
    private var bottomStatusBar: some View {
        HStack(spacing: 8) {
            Text(bottomStatusText)
                .font(.system(size: envTranscriptFontSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: bottomStatusText)
            Spacer(minLength: 12)
            memoryStatusWidget
            if let used = controller.metrics.contextUsed,
               let size = controller.metrics.contextSize, size > 0 {
                let tooltip = contextRingTooltip(used: used, size: size)
                ValueGaugeView(
                    fraction: Double(used) / Double(size),
                    trackColor: Severity.ofContext(used: used, size: size).color,
                    diameter: 15)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .help(tooltip)
                    .accessibilityElement()
                    .accessibilityLabel("Context window")
                    .accessibilityValue(tooltip)
                    .nativeTooltip(tooltip)
            }
        }
        .padding(.horizontal, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var memoryStatusWidget: some View {
        if let allocated = controller.metrics.gpuAllocatedBytes,
           let budget = controller.metrics.gpuBudgetBytes, budget > 0 {
            let tooltip = "GPU memory: \(memoryDisplay(allocated)) allocated of \(memoryDisplay(budget)) budget."
            HStack(spacing: 4) {
                ValueGaugeView(
                    fraction: min(Double(allocated) / Double(budget), 1.0),
                    trackColor: .green,
                    diameter: 15)
                Text("\(memoryDisplay(allocated)) / \(memoryDisplay(budget))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .help(tooltip)
            .accessibilityElement()
            .accessibilityLabel("GPU memory")
            .accessibilityValue(tooltip)
            .nativeTooltip(tooltip)
        }
    }

    /// Rates and activity while the session is up, else the composer's
    /// status label (which carries the exit message once it has ended).
    private var bottomStatusText: String {
        guard controller.phase == .running else { return composerState.label }
        let activity = composerState.label
        return "Prefill avg \(rateText(controller.metrics.prefillTPS)) tok/s · "
            + "Generation avg \(rateText(controller.metrics.generationTPS)) tok/s · \(activity)"
    }

    private func rateText(_ value: Double?) -> String {
        value.map { String(format: "%.1f", $0) } ?? "—"
    }

    private func memoryDisplay(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .memory))
    }

    private func contextRingTooltip(used: Int, size: Int) -> String {
        let percent = Double(used) / Double(size) * 100
        return String(format: "Context window: %@ of %@ tokens (%.0f%% used).",
                      used.formatted(), size.formatted(), percent)
    }
}

/// SwiftUI's `.help` does not reliably create a hover target for a small,
/// custom-drawn view. Keep a transparent AppKit view over each status widget so
/// macOS can provide its native tooltip while the gauge remains non-interactive.
private struct NativeTooltipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.toolTip = text
    }
}

private struct NativeTooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content.overlay {
            NativeTooltipView(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
        }
    }
}

private extension View {
    func nativeTooltip(_ text: String) -> some View {
        modifier(NativeTooltipModifier(text: text))
    }
}
