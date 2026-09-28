import SwiftUI
import SwiftStarAppKit
import SwiftStarKit

struct SettingsView: View {
    @AppStorage("engineExecutable") private var engineExecutable = ""
    @AppStorage("transcriptFontSize") private var transcriptFontSize = TranscriptFontScale.defaultSize

    // Download section
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
        let base = URL.applicationSupportDirectory
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
                TextField("ds4-dogfood path", text: $engineExecutable, prompt: Text("Search PATH and ~/.local/bin"))
                Text("Leave empty to search PATH and ~/.local/bin. Applies when a session next starts.")
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
        .frame(width: 520, height: 420)
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
            Label("Downloaded to \(url.path)", systemImage: "checkmark.circle")
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
