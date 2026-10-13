import SwiftUI
import SwiftStarKit

public struct SettingsView: View {
    @AppStorage(DefaultsKey.executable.rawValue) private var engineExecutable = ""
    @AppStorage(DefaultsKey.transcriptFontSize.rawValue) private var transcriptFontSize = TranscriptFontScale.defaultSize

    public init() {}

    public var body: some View {
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
                Slider(value: fontSliderValue, in: 0...Double(TranscriptFontScale.sizes.count - 1), step: 1) {
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

    /// The slider's slot, mapped through `TranscriptFontScale` so the stored
    /// value is always a defined size.
    private var fontSizeIndex: Int { TranscriptFontScale.slot(for: transcriptFontSize) }

    private var fontSliderValue: Binding<Double> {
        Binding(
            get: { Double(fontSizeIndex) },
            set: { transcriptFontSize = TranscriptFontScale.size(forSlot: Int($0.rounded())) }
        )
    }
}

#Preview("Settings") {
    SettingsView()
}
