import SwiftUI
import SwiftStarKit

/// The prompt field and its send/stop button, plus the engine-not-found
/// notice above them.
struct ComposerView: View {
    @Environment(EngineController.self) private var controller
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.transcriptFontSize) private var transcriptFontSize: CGFloat

    private var composerState: EngineComposer { controller.composer }

    var body: some View {
        VStack(spacing: 4) {
            if let notice = controller.phase.notFoundNotice {
                HStack {
                    Text(notice)
                        .font(.system(size: transcriptFontSize))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask the agent…", text: $input, axis: .vertical)
                    .font(.system(size: transcriptFontSize))
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
                    .disabled(!composerState.canSend)
                let button = composerState.button(forInput: input)
                let showsStop = button == .stop
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
                .disabled(button == .send(enabled: false))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task { inputFocused = true }
        .onChange(of: composerState.canStop) { _, stoppable in
            if !stoppable { inputFocused = true }
        }
    }

    private func send() {
        guard composerState.canSend, let message = input.trimmedOrNil else { return }
        input = ""
        controller.send(message)
    }
}

#Preview("Ready", traits: .runningSession) {
    ComposerView()
        .frame(width: 600)
}

#Preview("Idle", traits: .idleSession) {
    ComposerView()
        .frame(width: 600)
}

#Preview("Engine not found") {
    // Its own fixture, not a shared trait: built fresh for this preview.
    var model = EngineSessionModel()
    model.didNotFind(searched: ["/opt/homebrew/bin/ds4-dogfood", "~/.local/bin/ds4-dogfood"])
    return ComposerView()
        .environment(EngineController(model: model))
        .frame(width: 600)
}
