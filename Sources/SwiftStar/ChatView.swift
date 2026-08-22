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
            if controller.state == .ready || controller.state == .generating {
                Button("Stop Engine") { controller.stopEngine() }
            } else {
                Button("Start Engine") { controller.startEngine() }
            }
        }
        .padding(8)
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
                    ForEach(Array(controller.transcript.rows.enumerated()), id: \.offset) { _, row in
                        rowView(row)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
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
        let message = input
        input = ""
        controller.send(message)
    }
}
