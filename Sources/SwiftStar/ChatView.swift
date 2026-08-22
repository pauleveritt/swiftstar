import SwiftUI
import SwiftStarKit

struct ChatView: View {
    @State private var controller = EngineController()
    @State private var input = ""

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            transcriptView
            Divider()
            composer
        }
        .navigationTitle("Chat")
        .task { controller.startIfNeeded() }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText).font(.caption)
            Spacer()
            engineButton
        }
        .padding(8)
    }

    @ViewBuilder
    private var engineButton: some View {
        switch controller.state {
        case .ready, .generating, .starting:
            // .starting shows Stop so a cold start can be cancelled.
            Button("Stop Engine") { controller.stopEngine() }
        case .stopped, .failed:
            Button("Start Engine") { controller.startEngine() }
        case .stopping:
            Button("Start Engine") { controller.startEngine() }
                .disabled(true)
        }
    }

    private var statusText: String {
        switch controller.state {
        case .stopped: return "Engine stopped"
        case .starting: return "Starting engine…"
        case .ready: return "Engine ready"
        case .generating: return "Generating…"
        case .stopping: return "Stopping…"
        case .failed(let failure): return "Failed: \(failureDescription(failure))"
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

    private func failureDescription(_ failure: EngineFailure) -> String {
        switch failure {
        case .engineMissing(let url): return "engine binary missing at \(url.path)"
        case .portInUse(let port): return "port \(port) is already in use"
        case .instanceLocked: return "another ds4 process is already running"
        case .exited(let code, let tail): return "engine exited (\(code)): \(tail)"
        case .timeout: return "engine start timed out"
        }
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { index, row in
                        rowView(row)
                            .id(index)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: controller.transcript.rows.count) { _, _ in
                // Append-only transcript: keep the newest row in view as it streams.
                let lastIndex = controller.transcript.rows.count - 1
                guard lastIndex >= 0 else { return }
                withAnimation {
                    proxy.scrollTo(lastIndex, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TranscriptRow) -> some View {
        switch row {
        case .reasoning(let text):
            Text(text).font(.callout).foregroundStyle(.secondary).italic()
        case .content(let text):
            Text(text).font(.body).textSelection(.enabled)
        case .finished:
            EmptyView()
        case .system(let text):
            Text(text).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var composer: some View {
        HStack {
            TextField("Message the engine", text: $input)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .disabled(!controller.canSend || input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(8)
    }

    private func send() {
        let message = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Both the button and onSubmit go through this guard; the input is
        // preserved (not cleared) when the engine is not ready to take a turn.
        guard controller.canSend, !message.isEmpty else { return }
        input = ""
        controller.send(message)
    }
}
