import SwiftUI
import SwiftStarKit

public struct SettingsView: View {
    @AppStorage(DefaultsKey.executable.rawValue) private var engineExecutable = ""
    @AppStorage(DefaultsKey.fontSize.rawValue) private var fontSize = TranscriptFontScale.defaultSize
    @AppStorage(DefaultsKey.allowBash.rawValue) private var allowBash = false

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
            Section("Shell") {
                // SU.18, D1: ds4-engine's `--allow-bash`, an experiment.
                Toggle("Let the model run shell commands (experimental)", isOn: $allowBash)
                Text("""
                    A command the model runs that isn't a plain cat, ls or grep runs as bash in a sandbox: \
                    in the engine's copy of the project, network off, for up to 120 s. It can still read \
                    files outside the project. Applies when a session next starts. If the engine's \
                    config.toml sets run_bash = true, it's on whatever this says.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Text") {
                Slider(value: fontSliderValue, in: 0...Double(TranscriptFontScale.sizes.count - 1), step: 1) {
                    Text("Font size")
                }
                HStack {
                    Text("Font size: \(TranscriptFontScale.sizes[fontSizeIndex]) pt")
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
        .frame(width: 520, height: 480)
    }

    /// The slider's slot, mapped through `TranscriptFontScale` so the stored
    /// value is always a defined size.
    private var fontSizeIndex: Int { TranscriptFontScale.slot(for: fontSize) }

    private var fontSliderValue: Binding<Double> {
        Binding(
            get: { Double(fontSizeIndex) },
            set: { fontSize = TranscriptFontScale.size(forSlot: Int($0.rounded())) }
        )
    }
}

#Preview("Settings") {
    SettingsView()
}
