import SwiftUI
import SwiftStarAppKit

struct SettingsView: View {
    @AppStorage("engineDir") private var engineDir = ""
    @AppStorage("modelPath") private var modelPath = ""
    @AppStorage("contextSize") private var contextSize = 32768
    @AppStorage("port") private var port = 0

    // Download section (P3)
    @State private var downloadRunner = DownloadRunner()
    @State private var downloadTask: Task<Void, Never>?
    @State private var selectedTarget = 0

    struct DownloadTarget {
        let name: String
        let repo: String
        let revision: String
        let file: String
        var url: URL {
            URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file)")!
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

    private var selectedDestination: URL {
        downloadsDir.appendingPathComponent(Self.targets[selectedTarget].file)
    }

    var body: some View {
        Form {
            Section("Engine") {
                TextField("Engine directory (DS4_DIR)", text: $engineDir)
                TextField("Model file", text: $modelPath)
                Stepper("Context size: \(contextSize)", value: $contextSize, in: 1024...262144, step: 1024)
                Stepper("Port (0 = auto): \(port)", value: $port, in: 0...65535, step: 1)
                Text("Settings apply when the engine next starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Download model") {
                Picker("Model", selection: $selectedTarget) {
                    ForEach(Self.targets.indices, id: \.self) { i in
                        Text(Self.targets[i].name).tag(i)
                    }
                }
                if case .downloading(let fraction) = downloadRunner.state {
                    ProgressView(value: fraction) {
                        Text("Downloading… \(Int(fraction * 100))%")
                    }
                    Button("Cancel") { cancelDownload() }
                } else if case .done(let url) = downloadRunner.state {
                    Label("Downloaded to \(url.path)", systemImage: "checkmark.circle")
                } else if case .failed(let message) = downloadRunner.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                } else {
                    Button("Download") { startDownload() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
    }

    private func startDownload() {
        let spec = DownloadSpec(
            url: Self.targets[selectedTarget].url,
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
        downloadTask?.cancel()
        downloadTask = nil
    }
}
