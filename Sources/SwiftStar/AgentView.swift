import SwiftUI
import SwiftStarKit

struct AgentView: View {
    @Bindable var controller: AgentController
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize
    @AppStorage("dispatchDumb") private var dispatchDumb = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcriptView
            Divider()
            composer
            Divider()
            bottomStatusBar
        }
        .navigationTitle("Agent")
        .environment(\.transcriptFontSize, CGFloat(TranscriptFontScale.clamp(transcriptFontSize)))
        .task { controller.startIfNeeded() }
    }

    private var statusBar: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.caption)
            Spacer()
            workspaceButton
            // The dumb/smart handoff-packet lever (P12.7 DumbImplementer, built
            // 2026-08-26 as the demo/eval control): Smart = the engineered
            // packet with the architecture's context help; Dumb = the minimal
            // "here's the spec, build it" brief. Applies to the next dispatch.
            Picker("Dispatch mode", selection: $dispatchDumb) {
                Text("Smart").tag(false)
                Text("Dumb").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            .help("Handoff packets: Smart carries the architecture's context help; Dumb is the minimal brief (eval/demo lever).")
            agentButton
        }
        .padding(8)
    }

    private var workspaceButton: some View {
        Button(action: pickWorkspace) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(PathAbbreviation.abbreviate(
                    controller.settings.workspace,
                    home: FileManager.default.homeDirectoryForCurrentUser))
            }
            .font(.caption)
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

    @ViewBuilder
    private var agentButton: some View {
        switch controller.state {
        case .ready, .generating, .starting:
            Button("Stop Agent") { controller.stopAgent() }
        case .stopped, .failed:
            Button("Start Agent") { controller.startAgent() }
        case .stopping:
            Button("Start Agent") { controller.startAgent() }.disabled(true)
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

    private var statusColor: Color {
        switch controller.state {
        case .stopped: return .gray
        case .starting, .stopping: return .yellow
        case .ready: return .green
        case .generating: return .blue
        case .failed: return .red
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
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
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: AgentTranscriptRow) -> some View {
        switch row {
        case .user(let text):
            AgentPromptBubble(text: text)
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
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if let error = errorText {
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
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
                        if controller.canSend {
                            send()
                        }
                        return .handled
                    }
                    .disabled(!controller.canSend)
                Button {
                    if controller.isGenerating {
                        controller.interrupt()
                    } else {
                        send()
                    }
                } label: {
                    Image(systemName: controller.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .symbolEffect(.variableColor.iterative, isActive: controller.isGenerating)
                        .foregroundStyle(controller.isGenerating ? .red : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(
                    !controller.isGenerating
                        && (controller.state != .ready
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

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // `/orchestrate <text>` — optionally `--files a.swift, b.swift`:
        // dispatch as a subagent task in place (fresh context, worktree), the
        // named files writable (worktree-relative), else read-only. Stays in
        // the chat; the main context is untouched. Manual, so it stays
        // available in dumb mode (the user's own hand).
        if let request = OrchestrateCommand.parse(message) {
            input = ""
            controller.orchestrate(task: request.task, writableFiles: request.writableFiles)
            return
        }
        guard controller.canSend, !message.isEmpty else { return }
        input = ""
        controller.send(message)
    }

    /// Bottom readout bar (ported from the DS4 Control agent window): left =
    /// fixed-width Prompt/Decode rates + activity, right = the context-fill
    /// ring. Hidden while the agent is down; the rates are ratcheted in the
    /// controller so a zero reading never blanks a live rate.
    private var bottomStatusBar: some View {
        HStack(spacing: 8) {
            Text(bottomStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: bottomStatusText)
            Spacer(minLength: 12)
            if controller.isUp,
               controller.lastPlannedModel == controller.settings.modelPath.lastPathComponent,
               let footprint = controller.lastFootprintBytes,
               let planned = controller.lastPlannedBytes, planned > 0 {
                // Clamped at 1.0 for the ring: footprint is resident (includes
                // the mapped model), so it can exceed the planned budget and
                // the ring must read "full," not overflow. The color still uses
                // the true fraction (over-budget = critical, via DialLogic).
                ValueGaugeView(
                    fraction: min(Double(footprint) / Double(planned), 1.0),
                    text: nil, textFontSize: 0,
                    trackColor: memoryRingColor(footprint: footprint, planned: planned),
                    diameter: 15)
                    .contentShape(Rectangle())
                    .help(memoryRingTooltip(footprint: footprint, planned: planned))
            }
            if controller.isUp, let s = controller.lastStatus, s.ctxSize > 0 {
                ValueGaugeView(
                    fraction: Double(s.ctxUsed) / Double(s.ctxSize),
                    text: nil, textFontSize: 0,
                    trackColor: contextRingColor(ctxUsed: s.ctxUsed),
                    diameter: 15)
                    .contentShape(Rectangle())
                    .help(contextRingTooltip(s))
            }
            Button("End session") { controller.stopAgent() }
                .disabled(controller.state == .stopped || controller.state == .stopping)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
        func gb(_ b: Int64) -> String { String(format: "%.1f GB", Double(b) / 1_073_741_824) }
        var text = "Agent memory footprint: \(gb(footprint)) of a \(gb(planned)) budget."
        if Double(footprint) > Double(planned) {
            // Resident includes the mapped model, so over-budget is normal for
            // a large model — say so rather than letting the critical color
            // stand unexplained.
            text += " Over budget (resident includes the mapped model)."
        }
        return text
    }

    /// Carries the mechanism, not just the numbers: prefill speed is the
    /// figure the investigation showed actually degrades as context grows.
    private func contextRingTooltip(_ s: StatusSnapshot) -> String {
        var text =
            "Context window used / total: \(s.ctxUsed.formatted()) / \(s.ctxSize.formatted()). "
            + "Once this fills, ds4-agent compacts the conversation to make room."
        if s.prefillTPS > 0 {
            text += String(format: " Current prefill speed: %.1f tok/s.", s.prefillTPS)
        }
        return text
    }
}
