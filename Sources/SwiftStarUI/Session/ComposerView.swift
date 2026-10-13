import SwiftUI
import SwiftStarKit

/// The prompt field and its send/stop button, plus the engine-not-found
/// notice above them.
struct ComposerView: View {
    @Environment(EngineController.self) private var controller
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @AppStorage(DefaultsKey.transcriptFontSize.rawValue) private var transcriptFontSize = TranscriptFontScale.defaultSize
    @Environment(\.transcriptFontSize) private var envTranscriptFontSize: CGFloat

    private var composerState: EngineComposer { controller.composer }

    var body: some View {
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
        .task { inputFocused = true }
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

    private var trimmedInput: String {
        input.trimmedOrNil ?? ""
    }

    private func send() {
        let message = trimmedInput
        guard composerState.canSend, !message.isEmpty else { return }
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
