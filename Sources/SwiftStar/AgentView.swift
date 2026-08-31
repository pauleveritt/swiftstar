import AppKit
import SwiftUI
import SwiftStarKit

struct AgentView: View {
    let controller: AgentController
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize
    @Environment(\.transcriptFontSize) private var envTranscriptFontSize: CGFloat

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
        .toolbar(id: "main") {
            ToolbarItem(id: "workspace", placement: .automatic) {
                workspaceButton
            }
            ToolbarItem(id: "model", placement: .automatic) {
                ModelMenu(
                    isGenerating: controller.isGenerating,
                    isConsulting: controller.isConsulting,
                    isUp: controller.isUp,
                    isFailed: controller.isFailed,
                    onApply: { controller.applyModelSelection() },
                    onStart: { controller.startAgent() })
            }
            ToolbarItem(id: "endSession", placement: .primaryAction) {
                Button {
                    switch controller.state {
                    case .stopped, .failed:
                        controller.startAgent()
                    case .starting, .ready, .generating:
                        controller.stopAgent()
                    case .stopping:
                        break
                    }
                } label: {
                    Label(sessionActionTitle, systemImage: sessionActionIcon)
                }
                .disabled(controller.state == .stopping)
                .help(sessionActionHelp)
            }
        }
        .task { controller.startIfNeeded() }
    }

    private var workspaceButton: some View {
        Button(action: pickWorkspace) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(PathAbbreviation.leafName(controller.settings.workspace))
            }
            .font(.system(size: envTranscriptFontSize))
            // Keep the toolbar item at its natural width as the transcript
            // font grows, then add breathing room around the label.
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.borderless)
        .help("Workspace: the directory the agent may touch (applied at next start)")
    }

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = controller.settings.workspace
        panel.message = "Choose the workspace the agent may touch"
        if panel.runModal() == .OK, let url = panel.url {
            controller.settings.workspace = url
            UserDefaults.standard.set(url.path, forKey: "agentWorkspace")
        }
    }

    private var statusText: String {
        switch controller.state {
        case .stopped: return "Agent stopped"
        case .starting: return "Starting agent…"
        case .ready: return "Agent ready"
        case .generating: return "Working…"
        case .stopping: return "Stopping…"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Rows are keyed by offset — a stable-row-ID decision (P19.0):
                    // the transcript reducer is append-only (never inserts before
                    // or removes a row), so an offset is a stable identity for the
                    // row's whole lifetime. Pinned by
                    // `AgentTranscriptTests.reducerIsAppendOnly`; revisit if a
                    // reorder/insert/delete path ever lands (then stable IDs, not offsets).
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.transcript.rows) { _, _ in
                // The whole array, not `.count`: a streamed `text`/`think` event
                // mutates the trailing row in place, so `.count` never changes
                // mid-response and would freeze autoscroll for the whole answer
                // (the DS4 Control lesson). The array is Equatable over its
                // value-type rows, so comparing it fires on that in-place growth.
                let last = controller.transcript.rows.count - 1
                guard last >= 0 else { return }
                // Streamed rows change height many times per second. Starting
                // an animated scroll for each mutation continually interrupts
                // the previous animation, producing the visible up/down
                // oscillation. Follow the latest row in a transaction that
                // explicitly disables animation instead.
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
    private func rowView(_ row: AgentTranscriptRow) -> some View {
        switch row {
        case .user(let text, let stats):
            AgentPromptBubble(text: text, stats: stats)
        case .thinking(let text):
            ThinkingDisclosure(text: text)
        case .content(let text, let summary):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownText(text)
                if let summary {
                    // The frozen per-turn summary: decode average, tokens, ctx —
                    // styled small and secondary so engine telemetry never reads
                    // as part of the answer (the DS4 stats-line precedent).
                    Text(summary.line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .tool(let card):
            AgentToolCardView(card: card, workspace: controller.settings.workspace)
        case .consulted(let worker, let text, let stats):
            ConsultedAnswerView(worker: worker, text: text, stats: stats)
        case .system(let text, let stats):
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.system(size: envTranscriptFontSize)).foregroundStyle(.tertiary)
                if let stats {
                    Text(stats.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()
                }
            }
        case .compaction(let summary):
            CompactionRow(summary: summary)
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let error = errorText {
                HStack {
                    Text(error)
                        .font(.system(size: envTranscriptFontSize))
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
            // Item 2 (P22 cleanup): `state` stays `.ready` for the whole
            // consult worker turn (see AgentController.isConsulting's doc —
            // `.generating` is load-bearing elsewhere and must not be
            // reused), so without this the composer looks idle while a
            // worker actually runs. A small spinner + label, matching the
            // errorText row's shape, closes that gap without touching
            // canSend/isGenerating.
            if controller.isConsulting {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Consulting a worker…")
                        .font(.system(size: envTranscriptFontSize))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                // D8 attachment seam (reserved): a future clipboard-paste/attachment
                // chip renders directly above this field. No paste code this phase.
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
                        if controller.canSend && !controller.isConsulting {
                            send()
                        }
                        return .handled
                    }
                    // `canSend` alone stays true through a consult worker's
                    // turn (state never leaves `.ready`) — `isConsulting`
                    // closes that gap so the field visibly can't fire a
                    // conflicting turn while a worker is running.
                    .disabled(!controller.canSend || controller.isConsulting)
                Button {
                    if controller.isTurnActive {
                        controller.interrupt()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: controller.isTurnActive ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolEffect(.variableColor.iterative,
                                      isActive: controller.isTurnActive && !controller.interruptPending)
                        .foregroundStyle(controller.isTurnActive ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                // Icon-only, and the icon carries the whole meaning — the label
                // has to move with the state or VoiceOver announces nothing.
                .accessibilityLabel(controller.isTurnActive
                    ? (controller.interruptPending
                        ? (controller.isConsulting ? "Stopping consult" : "Stopping generation")
                        : (controller.isConsulting ? "Stop consult" : "Stop generating"))
                    : "Send message")
                .disabled(
                    controller.isTurnActive
                        ? controller.interruptPending
                        : (controller.state != .ready
                            || controller.isConsulting
                            || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: controller.isGenerating) { _, generating in
            if !generating { inputFocused = true }
        }
    }

    private var errorText: String? {
        if case .failed(let message) = controller.state { return message }
        return nil
    }

    private var sessionActionTitle: String {
        switch controller.state {
        case .stopped, .failed: return "Start session"
        case .stopping: return "Stopping…"
        case .starting, .ready, .generating: return "End session"
        }
    }

    private var sessionActionIcon: String {
        switch controller.state {
        case .stopped, .failed: return "play.circle"
        case .stopping: return "hourglass"
        case .starting, .ready, .generating: return "stop.circle"
        }
    }

    private var sessionActionHelp: String {
        switch controller.state {
        case .stopped, .failed: return "Start a new agent session"
        case .stopping: return "Waiting for the agent session to stop"
        case .starting, .ready, .generating: return "End the current agent session"
        }
    }

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Commands (P19.1 D10, glossary): `/chat` runs a read-only worker;
        // `/orchestrate` is the coordination loop (P20-forward). A bare prompt
        // is the default agent mode. Command names MUST agree with the glossary.
        switch CommandRouter.parse(message) {
        case .chat(let task):
            input = ""
            controller.consult(task: task, writableFiles: [])
        case .orchestrate(let task, let writableFiles):
            input = ""
            controller.orchestrate(task: task, writableFiles: writableFiles)
        case .quick(let task):
            input = ""
            controller.quick(task: task)
        case nil:
            guard controller.canSend, !message.isEmpty else { return }
            input = ""
            controller.send(message)
        }
        return
    }

    /// Bottom readout bar (ported from the DS4 Control agent window): left =
    /// fixed-width Prompt/Decode rates + activity, right = the context-fill
    /// ring. Hidden while the agent is down; the rates are ratcheted in the
    /// controller so a zero reading never blanks a live rate.
    private var bottomStatusBar: some View {
        HStack(spacing: 8) {
            // The engine's own per-worker error (StatusSnapshot.error, wire
            // field `status.error`) is a live, non-fatal report — distinct
            // from `AgentState.failed` (a process exit). Nothing consumed
            // this field before (a doc-comment on StatusSnapshot claimed
            // otherwise); it takes over the readout slot, in red, whenever
            // non-empty, matching the composer's existing red-error styling.
            if let engineError = controller.lastStatus?.error, !engineError.isEmpty {
                Text("Engine error: \(engineError)")
                    .font(.system(size: envTranscriptFontSize))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(engineError)
            } else {
                Text(bottomStatusText)
                    .font(.system(size: envTranscriptFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: bottomStatusText)
            }
            Spacer(minLength: 12)
            memoryStatusWidget
            if controller.isUp, let s = controller.lastStatus, s.ctxSize > 0 {
                ValueGaugeView(
                    fraction: Double(s.ctxUsed) / Double(s.ctxSize),
                    text: nil, textFontSize: 0,
                    trackColor: contextRingColor(ctxUsed: s.ctxUsed),
                    diameter: 15)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .help(contextRingTooltip(s))
                    .accessibilityElement()
                    .accessibilityLabel("Context window")
                    .accessibilityValue(contextRingTooltip(s))
                    .nativeTooltip(contextRingTooltip(s))
            }
        }
        .padding(.horizontal, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var memoryStatusWidget: some View {
        if controller.isUp,
           controller.lastPlannedModel == controller.settings.modelPath.lastPathComponent,
           let footprint = controller.lastFootprintBytes,
           let planned = controller.lastPlannedBytes, planned > 0 {
            // Keep the ring as a quick severity glance, but show the actual
            // resident/planned values beside it so memory use is discoverable
            // without requiring a hover or accessibility tooling.
            let tooltip = memoryRingTooltip(footprint: footprint, planned: planned)
            HStack(spacing: 4) {
                ValueGaugeView(
                    fraction: min(Double(footprint) / Double(planned), 1.0),
                    text: nil, textFontSize: 0,
                    trackColor: memoryRingColor(footprint: footprint, planned: planned),
                    diameter: 15)
                Text("\(memoryDisplay(footprint)) / \(memoryDisplay(planned))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .help(tooltip)
            .accessibilityElement()
            .accessibilityLabel("Agent memory")
            .accessibilityValue(tooltip)
            .nativeTooltip(tooltip)
        }
    }

    /// Rates + activity while the agent is up, else the same state text as
    /// the top bar (a readout, not a second control).
    private var bottomStatusText: String {
        if controller.state == .ready || controller.state == .generating {
            return AgentStatusText.promptDecodeLine(
                promptTPS: controller.lastPrefillTPS,
                decodeTPS: controller.lastGenTPS,
                message: AgentStatusText.stateMessage(controller.lastStatus?.state ?? ""))
        }
        return statusText
    }

    /// Absolute-token severity (DialLogic), not a fraction threshold: ctx_size
    /// varies 256k–1M by RAM/variant, so fraction-anchored colors fire at the
    /// wrong absolute usage (the P11 findings lesson).
    private func contextRingColor(ctxUsed: Int) -> Color {
        switch DialLogic.contextSeverity(ctxUsed: ctxUsed) {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    /// Generic 70/90 memory thresholds (DialLogic), unlike the context ring's
    /// telemetry-derived absolute anchors — memory stayed well under budget in
    /// every captured session, so there is no measured overshoot curve.
    private func memoryRingColor(footprint: Int64, planned: Int64) -> Color {
        switch DialLogic.memorySeverity(residentBytes: footprint, plannedBytes: planned) {
        case .healthy: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func memoryRingTooltip(footprint: Int64, planned: Int64) -> String {
        let percent = Double(footprint) / Double(planned) * 100
        var text = String(
            format: "Agent memory: %@ resident of %@ planned (%.0f%%).",
            memoryDisplay(footprint), memoryDisplay(planned), percent)
        if Double(footprint) > Double(planned) {
            // Resident includes the mapped model, so over-budget is normal for
            // a large model — say so rather than letting the critical color
            // stand unexplained.
            text += " Over budget (resident includes the mapped model)."
        }
        return text
    }

    private func memoryDisplay(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .memory))
    }

    /// Carries the mechanism, not just the numbers: prefill speed is the
    /// figure the investigation showed actually degrades as context grows.
    private func contextRingTooltip(_ s: StatusSnapshot) -> String {
        let percent = Double(s.ctxUsed) / Double(s.ctxSize) * 100
        var text =
            String(format: "Context window: %@ of %@ tokens (%.0f%% used).",
                   s.ctxUsed.formatted(), s.ctxSize.formatted(), percent)
            + " Once this fills, ds4-agent compacts the conversation to make room."
        if s.prefillTPS > 0 {
            text += String(format: " Current prefill: %.1f tok/s.", s.prefillTPS)
        }
        if s.genTPS > 0 {
            text += String(format: " Current decode: %.1f tok/s.", s.genTPS)
        }
        return text
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

/// The toolbar model menu (P19.1 D4): enumerates the effective model (Laguna S
/// default + registry variants + custom), disabled mid-generation. A selection
/// is a no-op for the same model; the actual switch behavior lands with P22.
struct ModelMenu: View {
    @AppStorage("selectedVariantID") private var selectedVariantID = ""
    @AppStorage("modelPath") private var modelPath = ""
    var isGenerating: Bool
    /// True while a `/chat` consult worker turn is running. `state` stays
    /// `.ready` for the whole turn (see `AgentController.isConsulting`), so
    /// this is checked separately from `isGenerating` to keep "Apply this
    /// model" from killing an in-flight consult with no refusal.
    var isConsulting: Bool
    /// The agent is up (ready or generating) — a live session exists to switch.
    var isUp: Bool
    /// A spawn refusal landed `.failed` — no process to switch away from, but
    /// picking a different model should still be startable from here.
    var isFailed: Bool
    /// Runs `AgentController.applyModelSelection()`: the pure decision gates
    /// the stop; refusals/no-ops surface as transcript system rows.
    var onApply: () -> Void
    /// Runs `AgentController.startAgent()` directly — the `.failed` recovery
    /// path, since `startIfNeeded()` only fires once for `.stopped`.
    var onStart: () -> Void

    var body: some View {
        Menu {
            ForEach(ModelChoice.list(variants: VariantRegistry.all)) { choice in
                Button(choice.label) {
                    switch choice.id {
                    case ModelChoice.defaultID:
                        // The default is the *empty* state, not a persisted id:
                        // "" + empty modelPath is the Laguna S fallback. Persisting
                        // "default" was unrepresentable in Settings/VariantResolver.
                        selectedVariantID = ""
                        modelPath = ""
                    case ModelChoice.customID:
                        selectedVariantID = ""
                    default:
                        selectedVariantID = choice.id
                    }
                }
            }
            if isUp {
                Divider()
                Button("Apply this model") { onApply() }
            } else if isFailed {
                Divider()
                Button("Start with this model") { onStart() }
            }
        } label: {
            Label(currentLabel, systemImage: "cpu")
        }
        .disabled(isGenerating || isConsulting)
        .help(isGenerating
            ? "Model switching is disabled while generating"
            : isConsulting
                ? "Model switching is disabled while a /chat consult is running"
                : "Pick a model for the next session, or choose Apply this model to switch the running session now.")
    }

    /// The model the next spawn will actually load. Resolved through
    /// `VariantResolver` — the same resolver `AgentController.defaultSettings()`
    /// uses — rather than re-deriving it here: a stale `selectedVariantID` (a
    /// variant id left in defaults after the registry changed) used to fall to a
    /// hardcoded "Laguna S" while the session launched something else entirely.
    private var currentLabel: String {
        if !selectedVariantID.isEmpty,
           let variant = VariantRegistry.resolve(selectedVariantID) {
            return variant.displayName
        }
        let resolved = VariantResolver.resolveModelFile(
            selectedVariantID: selectedVariantID.isEmpty ? nil : selectedVariantID,
            modelPath: modelPath.isEmpty ? nil : modelPath,
            envModel: ProcessInfo.processInfo.environment["SWIFTSTAR_MODEL"],
            fallback: AgentController.defaultModelFallback)
        return resolved.url.lastPathComponent
    }
}
