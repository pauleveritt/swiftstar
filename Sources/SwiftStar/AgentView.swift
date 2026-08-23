import SwiftUI
import SwiftStarKit

/// One tool card: name, params, bash output, and a status line when the block
/// did not close cleanly (interrupt / parse error / hard failure).
struct ToolCardView: View {
    let card: ToolCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                Text(card.name).font(.callout).bold()
                Spacer()
            }
            ForEach(Array(card.params.enumerated()), id: \.offset) { _, param in
                Text("\(param.name): \(param.value)")
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let output = card.output {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if let status = card.status {
                Text(status).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct AgentView: View {
    @Bindable var controller: AgentController
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcriptView
            Divider()
            consentControls
            Divider()
            composer
        }
        .navigationTitle("Agent")
        .task { controller.startIfNeeded() }
    }

    private var statusBar: some View {
        HStack {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(statusText).font(.caption)
            Spacer()
            if controller.isGenerating {
                Button("Interrupt") { controller.interrupt() }
            } else {
                agentButton
            }
        }
        .padding(8)
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
            .onChange(of: controller.transcript.rows.count) { _, _ in
                let last = controller.transcript.rows.count - 1
                guard last >= 0 else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: AgentTranscriptRow) -> some View {
        switch row {
        case .thinking(let text):
            Text(text).font(.callout).foregroundStyle(.secondary).italic()
        case .content(let text):
            Text(text).font(.body).textSelection(.enabled)
        case .tool(let card):
            ToolCardView(card: card)
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// Spawn-time consent (D2): the workspace grant and the shell toggle apply
    /// when the agent next starts; changing them never mutates a live child.
    private var consentControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Workspace").font(.caption).foregroundStyle(.secondary)
                TextField("Workspace directory", text: Binding(
                    get: { controller.settings.workspace.path },
                    set: { controller.settings.workspace = URL(fileURLWithPath: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
            Toggle("Allow shell commands", isOn: Binding(
                get: { controller.settings.shellAllowed },
                set: { controller.settings.shellAllowed = $0 }
            ))
            .font(.caption)
            Text("Applied when the agent starts.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(8)
    }

    private var composer: some View {
        HStack {
            TextField("Message the agent", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .disabled(!controller.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
    }

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard controller.canSend, !message.isEmpty else { return }
        input = ""
        controller.send(message)
    }
}
