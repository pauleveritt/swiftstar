import AppKit
import SwiftUI
import SwiftStarKit

struct AgentView: View {
    let controller: EngineController
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("engineModelID") private var engineModelID = ""
    @AppStorage("engineContextSize") private var engineContextSize = 0
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
            ToolbarItem(placement: .automatic) {
                workspaceButton
            }
            ToolbarItem(placement: .automatic) {
                modelStatus
            }
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
            }
        }
        .task { if controller.phase == .idle { controller.start() } }
    }

    /// Loaded model label plus, when Settings differ, the restart button.
    /// One toolbar item, so nothing renders as a blank slot.
    private var modelStatus: some View {
        HStack(spacing: 8) {
            modelLabel
            if controller.restartNeeded(modelID: engineModelID, contextSize: engineContextSize) {
                Button {
                    Task { await controller.restart() }
                } label: {
                    Label(restartTitle, systemImage: "arrow.clockwise")
                }
                .help("Settings changed the model or context size; restart the session to apply")
            }
        }
    }

    private var restartTitle: String {
        let id = engineModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let loaded = controller.transcript.session?.modelID
        if !id.isEmpty, let loaded, id != loaded { return "Restart to use \(id)" }
        if !id.isEmpty, loaded == nil, engineContextSize <= 0 { return "Restart to use \(id)" }
        return "Restart with context \(engineContextSize.formatted(.number.grouping(.never)))"
    }

    /// The loaded model and context size; empty for an older engine that
    /// sends no `session` event.
    @ViewBuilder private var modelLabel: some View {
        if let info = controller.transcript.session, info.modelID != nil || info.contextSize != nil {
            let context = info.contextSize.map { " · \($0.formatted(.number.grouping(.never))) ctx" } ?? ""
            Text((info.modelID ?? "model") + context)
                .font(.system(size: envTranscriptFontSize))
                .foregroundStyle(.secondary)
                .help("Model and context size loaded in the running session")
        }
    }

    private var workspaceButton: some View {
        Button(action: pickWorkspace) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(controller.workspace.map(PathAbbreviation.leafName) ?? "Choose folder")
            }
            .font(.system(size: envTranscriptFontSize))
            // Keep the toolbar item at its natural width as the transcript
            // font grows, then add breathing room around the label.
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderless)
        .help("Workspace: its git repository is the engine's source (applied at next start)")
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = controller.workspace
        panel.message = "Choose a folder in the git repository the engine should work on"
        if panel.runModal() == .OK, let url = panel.url {
            controller.workspace = url
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
                Button {
                    if composerState.canStop {
                        controller.stop()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: composerState.canStop ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolEffect(.variableColor.iterative, isActive: composerState.canStop)
                        .foregroundStyle(composerState.canStop ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // Icon-only, and the icon carries the whole meaning — the label
                // has to move with the state or VoiceOver announces nothing.
                .accessibilityLabel(composerState.canStop ? "Stop generating" : "Send message")
                .disabled(composerState.canStop
                    ? false
                    : (!composerState.canSend || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard composerState.canType, !message.isEmpty else { return }
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
                    text: nil, textFontSize: 0,
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
                    text: nil, textFontSize: 0,
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
        let activity = controller.transcript.isGenerating ? "Generating…" : composerState.label
        return "Prefill \(rateText(controller.metrics.prefillTPS)) tok/s · "
            + "Generation \(rateText(controller.metrics.generationTPS)) tok/s · \(activity)"
    }

    private func rateText(_ value: Double?) -> String {
        fixedWidth(value.map { String(format: "%.1f", $0) } ?? "—", width: 6)
    }

    /// Right-aligns `text` in a field of `width` characters so a changing
    /// value does not shift the text around it.
    private func fixedWidth(_ text: String, width: Int) -> String {
        if text.count >= width { return text }
        return String(repeating: " ", count: width - text.count) + text
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
