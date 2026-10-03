import SwiftUI
import SwiftStarKit

struct SettingsView: View {
    @AppStorage(DefaultsKey.executable.rawValue) private var engineExecutable = ""
    @AppStorage(DefaultsKey.transcriptFontSize.rawValue) private var transcriptFontSize = TranscriptFontScale.defaultSize

    var body: some View {
        Form {
            Section("Engine") {
                TextField("ds4-dogfood path", text: $engineExecutable, prompt: Text("Search PATH and ~/.local/bin"))
                Text("Leave empty to search PATH and ~/.local/bin. Applies when a session next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Model and context size are chosen from the Agent toolbar menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Transcript") {
                Slider(value: fontSliderValue, in: 0...3, step: 1) {
                    Text("Transcript font size")
                }
                HStack {
                    Text("Transcript font size: \(TranscriptFontScale.sizes[fontSizeIndex]) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Applies immediately")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 300)
    }

    /// The slider's 0…3 slot index, mapped through `TranscriptFontScale.sizes`
    /// so the stored value is always a defined size (clamped on read).
    private var fontSizeIndex: Int {
        TranscriptFontScale.sizes.firstIndex(of: transcriptFontSize)
            ?? TranscriptFontScale.sizes.firstIndex(of: TranscriptFontScale.clamp(transcriptFontSize))!
    }

    private var fontSliderValue: Binding<Double> {
        Binding(
            get: { Double(fontSizeIndex) },
            set: { transcriptFontSize = TranscriptFontScale.sizes[max(0, min(3, Int($0.rounded())))] }
        )
    }
}
