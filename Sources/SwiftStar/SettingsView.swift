import SwiftUI
import SwiftStarAppKit
import SwiftStarKit

struct SettingsView: View {
    @AppStorage("engineDir") private var engineDir = ""
    @AppStorage("modelPath") private var modelPath = ""
    @AppStorage("selectedVariantID") private var selectedVariantID = ""
    @AppStorage("contextSize") private var contextSize = 51_200
    @AppStorage("port") private var port = 0
    // Agent pane (2026-08-26): the shell toggle moved here from the Agent tab;
    // the transcript font size applies immediately.
    @AppStorage("agentShellAllowed") private var shellAllowed = false
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize

    // Download section (P3)
    @State private var downloadRunner = DownloadRunner()
    @State private var downloadTask: Task<Void, Never>?
    @State private var selectedTarget: String = Self.targets[0].file

    struct DownloadTarget {
        let name: String
        let repo: String
        let revision: String
        let file: String
        var url: URL {
            // Percent-encode the file name; the repo/revision are path-safe.
            var components = URLComponents()
            components.scheme = "https"
            components.host = "huggingface.co"
            components.path = "/\(repo)/resolve/\(revision)/\(file)"
            guard let url = components.url else {
                fatalError("misconfigured download target: \(name)")
            }
            return url
        }
    }
    // The P1 model first; more targets arrive with P12. Source of the URL
    // pattern: external/ds4/download_model.sh (laguna-q2-q3 target).
    static let targets: [DownloadTarget] = [
        DownloadTarget(
            name: "Laguna S 2.1 — Routed Q2/Q3 (48 GB)",
            repo: "antirez/Laguna-S-2.1-GGUF",
            revision: "706fa69799926b6afde1af9e24ca2a4923f110a1",
            file: "laguna-s-2.1-RoutedQ2_K-Last27Q3_K.gguf"
        ),
    ]

    private var downloadsDir: URL {
        if let dir = ProcessInfo.processInfo.environment["SWIFTSTAR_DOWNLOAD_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("SwiftStar/Downloads")
    }

    private var selectedTargetEntry: DownloadTarget {
        Self.targets.first { $0.file == selectedTarget } ?? Self.targets[0]
    }

    private var selectedDestination: URL {
        downloadsDir.appendingPathComponent(selectedTargetEntry.file)
    }

    var body: some View {
        Form {
            Section("Engine") {
                TextField("Engine directory (DS4_DIR)", text: $engineDir)
                Picker("Variant", selection: $selectedVariantID) {
                    Text("Custom file…").tag("")
                    ForEach(VariantRegistry.all) { variant in
                        Text(variant.displayName).tag(variant.id)
                    }
                }
                if selectedVariantID.isEmpty {
                    TextField("Model file", text: $modelPath)
                } else if let variant = VariantRegistry.resolve(selectedVariantID) {
                    Text(variant.modelFile.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Stepper("Context size: \(contextSize)", value: $contextSize, in: 1024...262144, step: 1024)
                Stepper("Port (0 = auto): \(port)", value: $port, in: 0...65535, step: 1)
                Text("A selected variant is verified before launch; a custom file is not. Settings apply when the engine next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Download model") {
                Picker("Model", selection: $selectedTarget) {
                    ForEach(Self.targets, id: \.file) { target in
                        Text(target.name).tag(target.file)
                    }
                }
                downloadStatus
            }
            Section("Agent") {
                Toggle("Allow shell commands", isOn: $shellAllowed)
                Text("Applies when the agent next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 520, height: 440)
        .onDisappear { downloadTask?.cancel() }
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

    @ViewBuilder
    private var downloadStatus: some View {
        switch downloadRunner.state {
        case .idle:
            Button("Download") { startDownload() }
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading… \(Int(fraction * 100))%")
            }
            Button("Cancel") { cancelDownload() }
        case .done(let url):
            VStack(alignment: .leading, spacing: 6) {
                Label("Downloaded to \(url.path)", systemImage: "checkmark.circle")
                Button("Use this model") {
                    modelPath = url.path
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }

    private func startDownload() {
        let spec = DownloadSpec(
            url: selectedTargetEntry.url,
            destination: selectedDestination,
            chunkSize: 16 * 1024 * 1024,
            maxConcurrency: 4
        )
        downloadTask?.cancel()
        downloadTask = Task {
            await downloadRunner.start(spec: spec)
        }
    }

    private func cancelDownload() {
        downloadRunner.cancel()
        downloadTask?.cancel()
        downloadTask = nil
    }
}
