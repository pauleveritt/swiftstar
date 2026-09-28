import SwiftUI
import SwiftStarKit

struct SettingsView: View {
    @AppStorage("engineExecutable") private var engineExecutable = ""
    @AppStorage("engineModelID") private var engineModelID = ""
    @AppStorage("engineContextSize") private var engineContextSize = 0
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize

    var body: some View {
        Form {
            Section("Engine") {
                TextField("ds4-dogfood path", text: $engineExecutable, prompt: Text("Search PATH and ~/.local/bin"))
                Text("Leave empty to search PATH and ~/.local/bin. Applies when a session next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Model id", text: $engineModelID, prompt: Text("Engine default"))
                TextField("Context size", text: contextText, prompt: Text("Engine default"))
                Text("Model id, e.g. laguna-xs-2.1 or qwen3.8-flash-next. Empty = engine default. A running session keeps its model; use Restart in the Agent toolbar.")
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
        .frame(width: 520, height: 380)
    }

    /// Empty or non-numeric text stores 0 (engine default), so the field shows
    /// its prompt instead of "0".
    private var contextText: Binding<String> {
        Binding(
            get: { engineContextSize > 0 ? String(engineContextSize) : "" },
            set: { engineContextSize = max(0, Int($0.trimmingCharacters(in: .whitespaces)) ?? 0) }
        )
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
